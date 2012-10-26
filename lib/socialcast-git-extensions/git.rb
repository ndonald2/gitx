require 'grit'

module Socialcast
  module Gitx
    module Git
      AGGREGATE_BRANCHES = %w{ staging prototype }
      RESERVED_BRANCHES = %w{ HEAD master next_release } + AGGREGATE_BRANCHES

      private
      def assert_not_protected_branch!(branch, action)
        raise "Cannot #{action} reserved branch" if RESERVED_BRANCHES.include?(branch) || aggregate_branch?(branch)
      end

      # lookup the current branch of the PWD
      def current_branch
        repo = Grit::Repo.new(Dir.pwd)
        Grit::Head.current(repo).name
      end

      # lookup the current repository of the PWD
      # ex: git@github.com:socialcast/socialcast-git-extensions.git OR https://github.com/socialcast/socialcast-git-extensions.git
      def current_repo
        repo = `git config -z --get remote.origin.url`.strip
        repo.gsub(/\.git$/,'').split(/[:\/]/).last(2).join('/')
      end

      # lookup the current github.user
      # ex: 'wireframe'
      def current_user
        `git config -z --global --get github.user`.strip
      end

      # retrieve a list of branches
      def branches(options = {})
        branches = []
        args = []
        args << '-r' if options[:remote]
        args << "--merged #{options[:merged].is_a?(String) ? options[:merged] : ''}" if options[:merged]
        output = `git branch #{args.join(' ')}`.split("\n")
        output.each do |branch|
          branch = branch.gsub(/\*/, '').strip.split(' ').first
          branch = branch.split('/').last if options[:remote]
          branches << branch unless RESERVED_BRANCHES.include?(branch)
        end
        branches.uniq
      end

      # reset the specified branch to the same set of commits as the destination branch
      # reverts commits on aggregate branches back to a known good state
      # returns list of branches that were removed
      def nuke_branch(branch, head_branch)
        return [] if branch == head_branch
        raise "Only aggregate branches are allowed to be reset: #{AGGREGATE_BRANCHES}" unless aggregate_branch?(branch)
        say "Resetting "
        say "#{branch} ", :green
        say "branch to "
        say head_branch, :green

        run_cmd "git checkout #{Socialcast::Gitx::BASE_BRANCH}"
        refresh_branch_from_remote head_branch
        removed_branches = branches(:remote => true, :merged => "origin/#{branch}") - branches(:remote => true, :merged => "origin/#{head_branch}")
        run_cmd "git branch -D #{branch}" rescue nil
        run_cmd "git push origin --delete #{branch}" rescue nil
        run_cmd "git checkout -b #{branch}"
        share_branch branch
        run_cmd "git checkout #{Socialcast::Gitx::BASE_BRANCH}"

        removed_branches
      end

      # share the local branch in the remote repo
      def share_branch(branch)
        run_cmd "git push origin #{branch}"
        track_branch branch
      end

      def track_branch(branch)
        run_cmd "git branch --set-upstream #{branch} origin/#{branch}"
      end

      # integrate a branch into a destination aggregate branch
      # blow away the local aggregate branch to ensure pulling into most recent "clean" branch
      def integrate_branch(branch, destination_branch)
        assert_not_protected_branch!(branch, 'integrate') unless aggregate_branch?(destination_branch)
        raise "Only aggregate branches are allowed for integration: #{AGGREGATE_BRANCHES}" unless aggregate_branch?(destination_branch) || destination_branch == Socialcast::Gitx::BASE_BRANCH
        say "Integrating "
        say "#{branch} ", :green
        say "into "
        say destination_branch, :green

        refresh_branch_from_remote destination_branch
        run_cmd "git pull . #{branch}"
        run_cmd "git push origin HEAD"
        run_cmd "git checkout #{branch}"
      end

      # nuke local branch and pull fresh version from remote repo
      def refresh_branch_from_remote(destination_branch)
        run_cmd "git branch -D #{destination_branch}" rescue nil
        run_cmd "git fetch origin"
        run_cmd "git checkout #{destination_branch}"
      end

      def aggregate_branch?(branch)
        AGGREGATE_BRANCHES.include?(branch) || branch.starts_with?('last_known_good')
      end

      # build a summary of changes
      def changelog_summary(branch)
        changes = `git diff --stat origin/#{Socialcast::Gitx::BASE_BRANCH}...#{branch}`.split("\n")
        stats = changes.pop
        if changes.length > 5
          dirs = changes.map do |file_change|
            filename = "#{file_change.split.first}"
            dir = filename.gsub(/\/[^\/]+$/, '')
            dir
          end
          dir_counts = Hash.new(0)
          dirs.each {|dir| dir_counts[dir] += 1 }
          changes = dir_counts.to_a.sort_by {|k,v| v}.reverse.first(5).map {|k,v| "#{k} (#{v} file#{'s' if v > 1})"}
        end
        (changes + [stats]).join("\n")
      end

      # launch configured editor to retreive message/string
      def editor_input(initial_text = '')
        require 'tempfile'
        Tempfile.open('reviewrequest.md') do |f|
          f << initial_text
          f.flush

          editor = ENV['EDITOR'] || 'vi'
          flags = case editor
          when 'mate', 'emacs'
            '-w'
          when 'mvim'
            '-f'
          else
            ''
          end
          pid = fork { exec "#{editor} #{flags} #{f.path}" }
          Process.waitpid(pid)
          description = File.read(f.path)
          description.gsub(/^\#.*/, '').chomp.strip
        end
      end

      # load Git review buddies YAML
      # Ex: ENV['SCGITX_REVIEW_BUDDIES_PATH'] or default $PWD/config/scgitx_review_buddies.yml
      def load_review_buddies
        if ENV.has_key?('SCGITX_REVIEW_BUDDIES_PATH')
          YAML.load_file(ENV['SCGITX_REVIEW_BUDDIES_PATH'])
        else
          default_location = Pathname(([Dir.pwd, '/config/scgitx_review_buddies.yml']).join)
          default_location.exist? ? YAML.load_file(default_location) : nil
        end
      end
    end
  end
end
