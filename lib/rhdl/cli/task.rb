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
        FileUtils.mkdir_p(path)
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
