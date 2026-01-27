# frozen_string_literal: true

require 'fileutils'

module RHDL
  module CLI
    # Base class for all CLI tasks
    # Provides common functionality for task execution
    class Task
      attr_reader :options

      def initialize(options = {})
        @options = options
        @dry_run_output = []
      end

      # Execute the task - must be implemented by subclasses
      def run
        raise NotImplementedError, "#{self.class} must implement #run"
      end

      # Execute the task and handle errors
      def execute
        run
      rescue => e
        handle_error(e)
        false
      end

      # Check if running in dry_run mode
      def dry_run?
        !!options[:dry_run]
      end

      # Get dry run output (for testing)
      def dry_run_output
        @dry_run_output
      end

      # Record an action that would be performed in dry_run mode
      # Returns the description for chaining
      def would(action, details = {})
        entry = { action: action }.merge(details)
        @dry_run_output << entry
        entry
      end

      # Describe what this task does (for dry_run output)
      # Subclasses should override this
      def describe
        { task: self.class.name, options: options.reject { |k, _| k == :dry_run } }
      end

      protected

      # Print a status message
      def puts_status(status, message)
        puts "  [#{status}] #{message}"
      end

      # Print a success message
      def puts_ok(message)
        puts_status('OK', message)
      end

      # Print an error message
      def puts_error(message)
        puts_status('ERROR', message)
      end

      # Print a header
      def puts_header(title)
        puts title
        puts '=' * 50
        puts
      end

      # Print a separator line
      def puts_separator
        puts '-' * 50
      end

      # Ensure a directory exists
      def ensure_dir(path)
        FileUtils.mkdir_p(path) unless dry_run?
      end

      # Handle an error during task execution
      def handle_error(error)
        warn "ERROR: #{error.message}"
        warn error.backtrace.first(5).join("\n") if options[:debug]
      end

      # Check if a system command is available
      def command_available?(cmd)
        system("which #{cmd} > /dev/null 2>&1")
      end
    end
  end
end
