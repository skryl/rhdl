# frozen_string_literal: true

require 'open3'
require 'shellwords'

module RHDL
  module Codegen
    module CIRCT
      module Tooling
        module_function

        DEFAULT_VERILOG_IMPORT_TOOL = 'circt-translate'
        DEFAULT_VERILOG_EXPORT_TOOL = 'firtool'
        DEFAULT_FIRTOOL_LOWERING_OPTIONS = 'disallowPackedArrays,disallowMuxInlining,disallowPortDeclSharing,disallowLocalVariables,locationInfoStyle=none,omitVersionComment'

        def verilog_to_circt_mlir(verilog_path:, out_path:, tool: DEFAULT_VERILOG_IMPORT_TOOL, extra_args: [])
          cmd, preflight_error = verilog_import_command(
            tool: tool,
            verilog_path: verilog_path,
            out_path: out_path,
            extra_args: extra_args
          )
          return failed_result(tool: tool, out_path: out_path, cmd: cmd, stderr: preflight_error) if preflight_error

          stdout, stderr, status = Open3.capture3(*cmd)

          {
            success: status.success?,
            command: shell_join(cmd),
            stdout: stdout,
            stderr: stderr,
            output_path: out_path.to_s,
            tool: tool
          }
        rescue Errno::ENOENT
          failed_result(tool: tool, out_path: out_path, cmd: cmd, stderr: "Tool not found: #{tool}")
        end

        def circt_mlir_to_verilog(mlir_path:, out_path:, tool: DEFAULT_VERILOG_EXPORT_TOOL, extra_args: [], input_format: nil)
          cmd = mlir_export_command(
            tool: tool,
            mlir_path: mlir_path,
            out_path: out_path,
            extra_args: extra_args,
            input_format: input_format
          )
          stdout, stderr, status = Open3.capture3(*cmd)

          {
            success: status.success?,
            command: shell_join(cmd),
            stdout: stdout,
            stderr: stderr,
            output_path: out_path.to_s,
            tool: tool
          }
        rescue Errno::ENOENT
          failed_result(tool: tool, out_path: out_path, cmd: cmd, stderr: "Tool not found: #{tool}")
        end

        def verilog_import_command(tool:, verilog_path:, out_path:, extra_args:)
          case tool_basename(tool)
          when 'firtool'
            cmd = [tool] + Array(extra_args)
            [cmd, "Tool '#{tool}' does not support direct Verilog import in this flow. Use circt-translate (or another importer) for Verilog -> CIRCT MLIR."]
          else
            [[tool, '--import-verilog', verilog_path.to_s, '-o', out_path.to_s] + Array(extra_args), nil]
          end
        end

        def mlir_export_command(tool:, mlir_path:, out_path:, extra_args:, input_format:)
          case tool_basename(tool)
          when 'firtool'
            args = Array(extra_args)
            unless args.any? { |arg| arg.to_s.start_with?('--format=') }
              args = ["--format=#{input_format || 'mlir'}"] + args
            end
            unless args.any? { |arg| arg.to_s.start_with?('--lowering-options=') }
              args = ["--lowering-options=#{DEFAULT_FIRTOOL_LOWERING_OPTIONS}"] + args
            end
            [tool, mlir_path.to_s, '--verilog', '-o', out_path.to_s] + args
          else
            [tool, '--export-verilog', mlir_path.to_s, '-o', out_path.to_s] + Array(extra_args)
          end
        end

        def tool_basename(tool)
          File.basename(tool.to_s.strip)
        end

        def failed_result(tool:, out_path:, cmd:, stderr:)
          {
            success: false,
            command: shell_join(cmd),
            stdout: '',
            stderr: stderr,
            output_path: out_path.to_s,
            tool: tool
          }
        end

        def shell_join(cmd)
          cmd.map { |arg| Shellwords.escape(arg.to_s) }.join(' ')
        end
      end
    end
  end
end
