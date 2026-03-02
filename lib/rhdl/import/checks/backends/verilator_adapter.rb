# frozen_string_literal: true

require "open3"
require "shellwords"

module RHDL
  module Import
    module Checks
      module Backends
        class VerilatorAdapter
          def initialize(runner: nil)
            @runner = runner || method(:default_runner)
          end

          def call(command:, work_dir:, env: {})
            normalized_command = Array(command).map(&:to_s)
            expanded_work_dir = File.expand_path(work_dir)
            normalized_env = normalize_env(env)

            stdout, stderr, status = @runner.call(
              normalized_command,
              chdir: expanded_work_dir,
              env: normalized_env
            )

            exit_code = extract_exit_code(status)
            {
              backend: :verilator,
              status: exit_code.zero? ? :ok : :tool_failure,
              available: true,
              error: nil,
              command: command_metadata(
                command: normalized_command,
                stdout: stdout,
                stderr: stderr,
                exit_code: exit_code,
                chdir: expanded_work_dir,
                env: normalized_env
              )
            }
          rescue Errno::ENOENT => e
            {
              backend: :verilator,
              status: :unavailable,
              available: false,
              error: {
                class: e.class.name,
                message: e.message.to_s
              },
              command: command_metadata(
                command: normalized_command,
                stdout: nil,
                stderr: nil,
                exit_code: nil,
                chdir: expanded_work_dir,
                env: normalized_env
              )
            }
          end

          private

          def default_runner(command, chdir:, env:)
            Open3.capture3(env, *command, chdir: chdir)
          end

          def normalize_env(env)
            return {} unless env.is_a?(Hash)

            env.each_with_object({}) do |(key, value), memo|
              memo[key.to_s] = value.to_s
            end
          end

          def extract_exit_code(status)
            return status if status.is_a?(Integer)
            return status.exitstatus if status.respond_to?(:exitstatus)

            1
          end

          def command_metadata(command:, stdout:, stderr:, exit_code:, chdir:, env:)
            {
              argv: command,
              shell: Shellwords.join(command),
              stdout: stdout.to_s,
              stderr: stderr.to_s,
              exit_code: exit_code,
              chdir: chdir,
              env: env
            }
          end
        end
      end
    end
  end
end
