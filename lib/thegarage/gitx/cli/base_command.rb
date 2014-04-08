require 'thor'
require 'pathname'
require 'rugged'
require 'English'
require 'thegarage/gitx'

module Thegarage
  module Gitx
    module Cli
      class BaseCommand < Thor
        include Thor::Actions

        AGGREGATE_BRANCHES = %w( staging prototype )
        RESERVED_BRANCHES = %w( HEAD master next_release ) + AGGREGATE_BRANCHES
        add_runtime_options!

        method_option :trace, :type => :boolean, :aliases => '-v'
        def initialize(*args)
          super(*args)
          RestClient.proxy = ENV['HTTPS_PROXY'] if ENV.has_key?('HTTPS_PROXY')
          RestClient.log = Logger.new(STDOUT) if options[:trace]
        end

        private

        def repo
          @repo ||= begin
            path = Dir.pwd
            root_path = Rugged::Repository.discover(path)
            Rugged::Repository.new(root_path)
          end
        end

        # lookup the current branch of the repo
        def current_branch
          repo.branches.find(&:head?)
        end

        # execute a shell command and raise an error if non-zero exit code is returned
        # return the string output from the command
        def run_cmd(cmd, options = {})
          say "$ #{cmd}"
          output = `#{cmd}`
          success = $CHILD_STATUS.to_i == 0
          fail "#{cmd} failed" unless success || options[:allow_failure]
          output
        end

        def aggregate_branch?(branch)
          AGGREGATE_BRANCHES.include?(branch)
        end

        def assert_not_protected_branch!(branch, action)
          raise "Cannot #{action} reserved branch" if RESERVED_BRANCHES.include?(branch) || aggregate_branch?(branch)
        end
      end
    end
  end
end