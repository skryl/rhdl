# frozen_string_literal: true

require_relative "backends/icarus_adapter"
require_relative "backends/verilator_adapter"

module RHDL
  module Import
    module Checks
      class Runner
        FALLBACK_STATUSES = %i[unavailable tool_failure].freeze

        def initialize(icarus_adapter: nil, verilator_adapter: nil)
          @icarus_adapter = icarus_adapter || Backends::IcarusAdapter.new
          @verilator_adapter = verilator_adapter || Backends::VerilatorAdapter.new
        end

        def call(work_dir:, icarus_command:, verilator_command:, env: {})
          attempts = []

          icarus_result = call_backend(@icarus_adapter, icarus_command, work_dir: work_dir, env: env)
          attempts << attempt_metadata(icarus_result) if icarus_result

          selected_result = if icarus_result
            if FALLBACK_STATUSES.include?(icarus_result[:status].to_sym) && command_present?(verilator_command)
              verilator_result = call_backend(@verilator_adapter, verilator_command, work_dir: work_dir, env: env)
              attempts << attempt_metadata(verilator_result)
              verilator_result
            else
              icarus_result
            end
          elsif command_present?(verilator_command)
            verilator_result = call_backend(@verilator_adapter, verilator_command, work_dir: work_dir, env: env)
            attempts << attempt_metadata(verilator_result)
            verilator_result
          else
            unavailable_result
          end

          {
            status: selected_result[:status].to_sym,
            selected_backend: selected_result[:backend].to_sym,
            selected_result: selected_result,
            selected_command: normalize_command(selected_result[:command]),
            attempts: attempts
          }
        end

        private

        def call_backend(adapter, command, work_dir:, env:)
          return nil unless command_present?(command)

          adapter.call(command: command, work_dir: work_dir, env: env)
        end

        def command_present?(command)
          Array(command).any?
        end

        def unavailable_result
          {
            backend: :none,
            status: :unavailable,
            available: false,
            error: { class: "RuntimeError", message: "no backend command configured" },
            command: {
              argv: [],
              shell: "",
              stdout: "",
              stderr: "",
              exit_code: nil,
              chdir: "",
              env: {}
            }
          }
        end

        def attempt_metadata(result)
          normalized = result.is_a?(Hash) ? result : {}
          command = normalize_command(normalized[:command])
          error = normalize_error(normalized[:error])

          {
            backend: normalized[:backend]&.to_sym,
            status: normalized[:status]&.to_sym,
            available: !!normalized[:available],
            exit_code: command[:exit_code],
            shell: command[:shell],
            error_class: error[:class],
            error_message: error[:message]
          }
        end

        def normalize_command(command)
          hash = command.is_a?(Hash) ? command : {}
          {
            argv: Array(hash[:argv]),
            shell: hash[:shell].to_s,
            stdout: hash[:stdout].to_s,
            stderr: hash[:stderr].to_s,
            exit_code: hash[:exit_code],
            chdir: hash[:chdir].to_s,
            env: hash[:env].is_a?(Hash) ? hash[:env] : {}
          }
        end

        def normalize_error(error)
          hash = error.is_a?(Hash) ? error : {}
          {
            class: hash[:class],
            message: hash[:message]
          }
        end
      end
    end
  end
end
