# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "shellwords"
require_relative "command_builder"

module RHDL
  module Import
    module Frontend
      class VerilatorAdapter
        class ExecutionError < StandardError
          attr_reader :exit_code, :stderr, :command, :metadata

          def initialize(message, exit_code:, stderr:, command:, metadata:)
            super(message)
            @exit_code = exit_code
            @stderr = stderr
            @command = command
            @metadata = metadata
          end
        end

        def initialize(verilator_bin: "verilator", command_builder: nil, runner: nil)
          @command_builder = command_builder || CommandBuilder.new(verilator_bin: verilator_bin)
          @runner = runner || method(:default_runner)
        end

        def call(resolved_input:, work_dir:, env: {})
          expanded_work_dir = File.expand_path(work_dir)
          FileUtils.mkdir_p(expanded_work_dir)

          output_paths = default_output_paths(expanded_work_dir)
          command = @command_builder.build(
            resolved_input: resolved_input,
            frontend_json_path: output_paths[:frontend_json_path],
            frontend_meta_path: output_paths[:frontend_meta_path]
          )

          stdout, stderr, status = @runner.call(command, chdir: expanded_work_dir, env: env)
          exit_code = extract_exit_code(status)
          command_metadata = {
            argv: command,
            shell: Shellwords.join(command),
            stdout: stdout.to_s,
            stderr: stderr.to_s,
            exit_code: exit_code,
            chdir: expanded_work_dir,
            env: env
          }

          metadata = { command: command_metadata }
          raise_execution_error!("Verilator frontend failed (exit #{exit_code})", exit_code: exit_code, stderr: stderr, command: command, metadata: metadata) unless exit_code.zero?

          unless File.exist?(output_paths[:frontend_json_path])
            raise_execution_error!(
              "Verilator did not write frontend JSON artifact: #{output_paths[:frontend_json_path]}",
              exit_code: exit_code,
              stderr: stderr,
              command: command,
              metadata: metadata
            )
          end

          payload = read_json(output_paths[:frontend_json_path])
          frontend_meta = File.exist?(output_paths[:frontend_meta_path]) ? read_json(output_paths[:frontend_meta_path]) : {}

          {
            payload: payload,
            metadata: {
              frontend_meta: frontend_meta,
              command: command_metadata
            }
          }
        end

        private

        def default_output_paths(work_dir)
          {
            frontend_json_path: File.join(work_dir, "verilator_frontend.json"),
            frontend_meta_path: File.join(work_dir, "verilator_frontend.meta.json")
          }
        end

        def default_runner(command, chdir:, env:)
          Open3.capture3(env, *command, chdir: chdir)
        end

        def extract_exit_code(status)
          return status if status.is_a?(Integer)
          return status.exitstatus if status.respond_to?(:exitstatus)

          1
        end

        def read_json(path)
          JSON.parse(File.read(path), max_nesting: false)
        rescue JSON::ParserError => e
          raise ExecutionError.new(
            "Failed to parse JSON artifact #{path}: #{e.message}",
            exit_code: 1,
            stderr: e.message,
            command: [],
            metadata: {}
          )
        end

        def raise_execution_error!(message, exit_code:, stderr:, command:, metadata:)
          raise ExecutionError.new(
            message,
            exit_code: exit_code,
            stderr: stderr.to_s,
            command: command,
            metadata: metadata
          )
        end
      end
    end
  end
end
