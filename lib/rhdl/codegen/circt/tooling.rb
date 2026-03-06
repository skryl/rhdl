# frozen_string_literal: true

require 'open3'
require 'shellwords'
require 'fileutils'
require_relative 'import_cleanup'

module RHDL
  module Codegen
    module CIRCT
      module Tooling
        module_function

        DEFAULT_VERILOG_IMPORT_TOOL = 'circt-verilog'
        DEFAULT_CIRCT_VERILOG_IMPORT_MODE = '--ir-hw'
        DEFAULT_VERILOG_EXPORT_TOOL = 'firtool'
        DEFAULT_FIRTOOL_LOWERING_OPTIONS = 'disallowMuxInlining,disallowPortDeclSharing,disallowLocalVariables,locationInfoStyle=none,omitVersionComment'
        DEFAULT_VHDL_IMPORT_TOOL = 'ghdl'

        def circt_verilog_import_args(extra_args: [])
          args = Array(extra_args).dup
          unless args.any? { |arg| arg.to_s.start_with?('--ir-') }
            args.unshift(DEFAULT_CIRCT_VERILOG_IMPORT_MODE)
          end
          args
        end

        def circt_verilog_import_command(verilog_path:, tool: DEFAULT_VERILOG_IMPORT_TOOL, extra_args: [])
          [tool] + circt_verilog_import_args(extra_args: extra_args) + [verilog_path.to_s]
        end

        def circt_verilog_import_command_string(verilog_path:, tool: DEFAULT_VERILOG_IMPORT_TOOL, extra_args: [])
          shell_join(circt_verilog_import_command(verilog_path: verilog_path, tool: tool, extra_args: extra_args))
        end

        def verilog_to_circt_mlir(verilog_path:, out_path:, tool: DEFAULT_VERILOG_IMPORT_TOOL, extra_args: [])
          cmd, preflight_error = verilog_import_command(
            tool: tool,
            verilog_path: verilog_path,
            out_path: out_path,
            extra_args: extra_args
          )
          return failed_result(tool: tool, out_path: out_path, cmd: cmd, stderr: preflight_error) if preflight_error

          stdout, stderr, status = Open3.capture3(*cmd)
          if status.success?
            FileUtils.mkdir_p(File.dirname(out_path.to_s))
            File.write(out_path, stdout)
          end

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

        def prepare_arc_mlir_from_verilog(verilog_path:, work_dir:, tool: DEFAULT_VERILOG_IMPORT_TOOL)
          FileUtils.mkdir_p(work_dir)

          moore_mlir_path = File.join(work_dir, 'import.core.mlir')

          import = verilog_to_circt_mlir(
            verilog_path: verilog_path,
            out_path: moore_mlir_path,
            tool: tool
          )
          return prepare_arc_failure(import: import, work_dir: work_dir) unless import[:success]

          strip_dbg_ops!(moore_mlir_path)
          imported_text = File.read(moore_mlir_path)

          unless imported_text.include?('moore.module')
            prepared = prepare_arc_mlir_from_circt_mlir(
              mlir_path: moore_mlir_path,
              work_dir: work_dir,
              base_name: 'import'
            )

            return {
              success: prepared[:success],
              import: import,
              normalize: prepared[:normalize],
              transform: prepared[:transform],
              arc: prepared[:arc],
              moore_mlir_path: moore_mlir_path,
              normalized_llhd_mlir_path: prepared[:normalized_llhd_mlir_path],
              hwseq_mlir_path: prepared[:hwseq_mlir_path],
              arc_mlir_path: prepared[:arc_mlir_path],
              transformed_modules: prepared[:transformed_modules],
              unsupported_modules: prepared[:unsupported_modules]
            }
          end

          normalized_llhd_mlir_path = File.join(work_dir, 'import.normalized.llhd.mlir')

          normalize_cmd = [
            'circt-opt',
            '--moore-lower-concatref',
            '--canonicalize',
            '--moore-lower-concatref',
            '--convert-moore-to-core',
            '--llhd-sig2reg',
            '--canonicalize',
            '--llhd-lower-processes',
            '--llhd-wrap-procedural-ops',
            '--llhd-inline-calls',
            '--llhd-hoist-signals',
            '--llhd-remove-control-flow',
            '--llhd-mem2reg',
            '--llhd-deseq',
            '--llhd-sig2reg',
            '--canonicalize',
            moore_mlir_path,
            '-o',
            normalized_llhd_mlir_path
          ]
          normalize = run_external_command(tool: 'circt-opt', cmd: normalize_cmd, out_path: normalized_llhd_mlir_path)
          return prepare_arc_failure(import: import, normalize: normalize, work_dir: work_dir) unless normalize[:success]

          prepared = prepare_arc_mlir_from_circt_mlir(
            mlir_path: normalized_llhd_mlir_path,
            work_dir: work_dir,
            base_name: 'import'
          )
          prepared.merge(
            import: import,
            normalize: normalize,
            moore_mlir_path: moore_mlir_path,
            normalized_llhd_mlir_path: normalized_llhd_mlir_path
          )
        end

        def prepare_arc_mlir_from_circt_mlir(mlir_path:, work_dir:, base_name: 'import', top: nil, strict: false, extern_modules: [])
          FileUtils.mkdir_p(work_dir)

          input_copy_path = File.join(work_dir, "#{base_name}.normalized.llhd.mlir")
          hwseq_mlir_path = File.join(work_dir, "#{base_name}.hwseq.mlir")
          arc_mlir_path = File.join(work_dir, "#{base_name}.arc.mlir")

          text = File.read(mlir_path)
          File.write(input_copy_path, text)
          strip_dbg_ops!(input_copy_path)
          cleaned_text = cleanup_imported_core_mlir_text(
            File.read(input_copy_path),
            top: top,
            strict: strict,
            extern_modules: extern_modules
          )
          File.write(input_copy_path, cleaned_text)

          transform = prepare_hwseq_from_circt_mlir_text(cleaned_text)
          File.write(hwseq_mlir_path, transform.fetch(:output_text))

          arc = if transform.fetch(:unsupported_modules).empty?
                  run_external_command(
                    tool: 'circt-opt',
                    cmd: ['circt-opt', '--convert-to-arcs', hwseq_mlir_path, '-o', arc_mlir_path],
                    out_path: arc_mlir_path
                  )
                else
                  failed_result(
                    tool: 'circt-opt',
                    out_path: arc_mlir_path,
                    cmd: ['circt-opt', '--convert-to-arcs', hwseq_mlir_path, '-o', arc_mlir_path],
                    stderr: format_unsupported_modules(transform.fetch(:unsupported_modules))
                  )
                end

          {
            success: arc[:success],
            import: nil,
            normalize: nil,
            transform: transform,
            arc: arc,
            moore_mlir_path: nil,
            normalized_llhd_mlir_path: input_copy_path,
            hwseq_mlir_path: hwseq_mlir_path,
            arc_mlir_path: arc[:success] ? arc_mlir_path : nil,
            transformed_modules: transform.fetch(:transformed_modules),
            unsupported_modules: transform.fetch(:unsupported_modules)
          }
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

        def ghdl_analyze(vhdl_path:, workdir:, std: '08', work: 'work', tool: DEFAULT_VHDL_IMPORT_TOOL, extra_args: [])
          cmd = [
            tool,
            '-a',
            "--std=#{std}",
            "--workdir=#{workdir}",
            "--work=#{work}",
            "-P#{workdir}"
          ] + Array(extra_args) + [vhdl_path.to_s]
          run_external_command(tool: tool, cmd: cmd, out_path: vhdl_path.to_s)
        end

        def ghdl_synth_to_verilog(entity:, out_path:, workdir:, std: '08', work: 'work', tool: DEFAULT_VHDL_IMPORT_TOOL, extra_args: [])
          cmd = [
            tool,
            '--synth',
            "--std=#{std}",
            "--workdir=#{workdir}",
            "--work=#{work}",
            "-P#{workdir}"
          ] + Array(extra_args) + ['--out=verilog', entity.to_s]
          stdout, stderr, status = Open3.capture3(*cmd)
          File.write(out_path, stdout) if status.success?
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
          when 'circt-verilog'
            [circt_verilog_import_command(verilog_path: verilog_path, tool: tool, extra_args: extra_args), nil]
          else
            cmd = [tool] + Array(extra_args) + [verilog_path.to_s]
            [cmd, "Tool '#{tool}' is not supported for Verilog import in this flow. Verilog import requires circt-verilog."]
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

        def strip_dbg_ops!(path)
          return unless File.file?(path)

          text = File.read(path)
          stripped = text.each_line.reject { |line| line.strip.start_with?('dbg.') }.join
          File.write(path, stripped) unless stripped == text
        end

        def prepare_arc_failure(import: nil, normalize: nil, work_dir:)
          {
            success: false,
            import: import,
            normalize: normalize,
            transform: {
              success: false,
              output_text: nil,
              transformed_modules: [],
              unsupported_modules: []
            },
            arc: nil,
            moore_mlir_path: import && import[:output_path],
            normalized_llhd_mlir_path: normalize && normalize[:output_path],
            hwseq_mlir_path: File.join(work_dir, 'import.hwseq.mlir'),
            arc_mlir_path: nil,
            transformed_modules: [],
            unsupported_modules: []
          }
        end

        def prepare_hwseq_from_circt_mlir_text(text)
          return {
            success: true,
            output_text: text,
            transformed_modules: module_names_from_core_mlir(text),
            unsupported_modules: []
          } unless text.include?('llhd.')

          ArcPrepare.transform_normalized_llhd(text)
        end

        def cleanup_imported_core_mlir_text(text, top:, strict:, extern_modules:)
          needs_cleanup = text.include?('llhd.')
          return text unless needs_cleanup

          cleanup = RHDL::Codegen::CIRCT::ImportCleanup.cleanup_imported_core_mlir(
            text,
            strict: strict,
            top: top,
            extern_modules: Array(extern_modules).map(&:to_s)
          )
          raise RuntimeError, 'Imported CIRCT core cleanup failed during ARC preparation' unless cleanup.success?

          cleanup.cleaned_text
        end

        def format_unsupported_modules(entries)
          return 'Unsupported ARC preparation patterns' if entries.nil? || entries.empty?

          details = entries.first(12).map do |entry|
            "#{entry.fetch('module')}: #{entry.fetch('reason')}"
          end
          extra = entries.length > 12 ? "\n... #{entries.length - 12} more module(s)" : ''
          "Unsupported ARC preparation patterns:\n#{details.join("\n")}#{extra}"
        end

        def module_names_from_core_mlir(text)
          text.to_s.scan(/^\s*(?:hw|sv)\.module\s+@([A-Za-z_$][A-Za-z0-9_$.]*)/).flatten.uniq
        end

        def run_external_command(tool:, cmd:, out_path:)
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
