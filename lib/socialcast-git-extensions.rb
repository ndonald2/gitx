require 'jira4r'
require 'activesupport'
require 'grit'

module Socialcast
  GIT_BRANCH_FIELD = 'customfield_10010'
  IN_STAGING_FIELD = 'customfield_10020'
  JIRA_CREDENTIALS_FILE = File.expand_path('~/.jira_key')

  def current_branch
    repo = Grit::Repo.new(Dir.pwd)
    Grit::Head.current(repo).name
  end
  def jira_credentials
    @credentials ||= YAML.load_file(JIRA_CREDENTIALS_FILE).symbolize_keys!
    @credentials
  end
  def jira_server
    #make sure soap4r is installed
    require 'jira4r'
    require "highline/import.rb"

    return @jira if @jira
    if !File.exists?(JIRA_CREDENTIALS_FILE)
      input = {}
      input[:username] = HighLine.ask("JIRA username: ")
      input[:password] = HighLine.ask("JIRA password: ") { |q| q.echo = "*" }

      File.open(JIRA_CREDENTIALS_FILE, "w") do |f|
        f.write input.to_yaml
      end
    end
    File.chmod 0600, JIRA_CREDENTIALS_FILE
    credentials = jira_credentials

    begin
      @jira = Jira4R::JiraTool.new 2, "https://issues.socialcast.com"
      @jira.login credentials[:username], credentials[:password]
      return @jira
    rescue => e
      puts "Error: #{e.message}"
      File.delete config_file
      raise e
    end
  end

  def update_ticket(ticket, options = {})
    fields = []
    fields << Jira4R::V2::RemoteFieldValue.new(GIT_BRANCH_FIELD, [options[:branch]]) if options[:branch]
    fields << Jira4R::V2::RemoteFieldValue.new(IN_STAGING_FIELD, ['true']) if options[:in_staging]
    jira_server.updateIssue ticket, fields
  end
  def start_ticket(ticket)
    transition_ticket_if_has_status ticket, 1, 11
  end
  def resolve_ticket(ticket)
    transition_ticket_if_has_status ticket, 3, 21
  end
  def release_ticket(ticket)
    transition_ticket_if_has_status ticket, 5, 101
  end
  def transition_ticket_if_has_status(ticket, status, action)
    issue = jira_server.getIssue ticket
    if issue.status == status.to_s
      jira_server.progressWorkflowAction ticket, action.to_s, []
    end
  end

  def run_cmd(cmd)
    puts "\nRunning: #{cmd}"
    raise "#{cmd} failed" unless system cmd
  end

  def reset_branch(branch)
    run_cmd "git branch -D #{branch}"
    run_cmd "git push origin :#{branch}"
    run_cmd "git checkout master"
    run_cmd "git checkout -b #{branch}"
    run_cmd "grb publish #{branch}"
  end

  def integrate(branch, destination_branch = 'staging')
    puts "integrating #{branch} into #{destination_branch}"
    run_cmd "git remote prune origin"
    unless destination_branch == 'master'
      run_cmd "git branch -D #{destination_branch}" rescue nil
      run_cmd "grb track #{destination_branch}"
    end
    run_cmd "git checkout #{destination_branch}"
    run_cmd "git pull . #{branch}"
    run_cmd "git push origin HEAD"

    run_cmd "git checkout #{branch}"
  end
end