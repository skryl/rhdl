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
        DEFAULT_CIRCT_VERILOG_IMPORT_PASSES = ['--detect-memories'].freeze
        DEFAULT_VERILOG_EXPORT_TOOL = 'firtool'
        DEFAULT_FIRTOOL_LOWERING_OPTIONS = 'disallowMuxInlining,disallowPortDeclSharing,disallowLocalVariables,locationInfoStyle=none,omitVersionComment'
        DEFAULT_VHDL_IMPORT_TOOL = 'ghdl'
        DEFAULT_ARC_FLATTEN_PIPELINE = 'builtin.module(hw-flatten-modules{hw-inline-public hw-inline-with-state})'
        DEFAULT_ARC_CLEANUP_PASSES = ['--canonicalize', '--cse'].freeze
        DEFAULT_ARC_PREP_INCLUDE_STEPS = %i[strip_dbg strip_llhd flatten canonicalize to_arc].freeze
        DEFAULT_ARCILATOR_SPLIT_FUNCS_THRESHOLD = 100
        DEFAULT_ARC_INPUT_SYNTAX_CLEANUP_PASSES = [
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
          '--canonicalize'
        ].freeze
        VALID_ARC_INPUT_CLEANUP_MODES = %i[semantic llhd_only syntax_only].freeze
        VALID_ARC_PREP_INCLUDE_STEPS = (DEFAULT_ARC_PREP_INCLUDE_STEPS + [:cannonicalize]).freeze

        def circt_verilog_import_args(extra_args: [])
          args = Array(extra_args).dup
          unless args.any? { |arg| arg.to_s.start_with?('--ir-') }
            args.unshift(DEFAULT_CIRCT_VERILOG_IMPORT_MODE)
          end
          DEFAULT_CIRCT_VERILOG_IMPORT_PASSES.reverse_each do |default_arg|
            args.unshift(default_arg) unless args.include?(default_arg)
          end
          args
        end

        def circt_verilog_import_command(verilog_path:, tool: DEFAULT_VERILOG_IMPORT_TOOL, extra_args: [])
          [tool] + circt_verilog_import_args(extra_args: extra_args) + [verilog_path.to_s]
        end

        def circt_verilog_import_command_string(verilog_path:, tool: DEFAULT_VERILOG_IMPORT_TOOL, extra_args: [])
          shell_join(circt_verilog_import_command(verilog_path: verilog_path, tool: tool, extra_args: extra_args))
        end

        def arcilator_command(mlir_path:, state_file:, out_path:, extra_args: [])
          args = Array(extra_args).dup
          split_arg = "--split-funcs-threshold=#{DEFAULT_ARCILATOR_SPLIT_FUNCS_THRESHOLD}"
          unless args.any? { |arg| arg.to_s.start_with?('--split-funcs-threshold=') }
            args.unshift(split_arg)
          end
          ['arcilator', mlir_path.to_s] + args + ["--state-file=#{state_file}", '-o', out_path.to_s]
        end

        def arcilator_command_string(mlir_path:, state_file:, out_path:, extra_args: [])
          shell_join(arcilator_command(mlir_path: mlir_path, state_file: state_file, out_path: out_path, extra_args: extra_args))
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

        def prepare_arc_mlir_from_verilog(verilog_path:, work_dir:, tool: DEFAULT_VERILOG_IMPORT_TOOL, stub_modules: [],
                                          cleanup_mode: :semantic)
          FileUtils.mkdir_p(work_dir)

          moore_mlir_path = stage_artifact_path(work_dir: work_dir, base_name: 'import', step: 1, suffix: 'core.mlir')
          stripped_moore_mlir_path = stage_artifact_path(work_dir: work_dir, base_name: 'import', step: 2, suffix: 'dbg_stripped.core.mlir')

          import = verilog_to_circt_mlir(
            verilog_path: verilog_path,
            out_path: moore_mlir_path,
            tool: tool
          )
          return prepare_arc_failure(import: import, work_dir: work_dir) unless import[:success]

          FileUtils.cp(moore_mlir_path, stripped_moore_mlir_path)
          strip_dbg_ops!(stripped_moore_mlir_path)
          imported_text = File.read(stripped_moore_mlir_path)

          unless imported_text.include?('moore.module')
            prepared = prepare_arc_mlir_from_circt_mlir(
              mlir_path: stripped_moore_mlir_path,
              work_dir: work_dir,
              base_name: 'import',
              stub_modules: stub_modules,
              cleanup_mode: cleanup_mode,
              stage_index_offset: 2
            )

            return {
              success: prepared[:success],
              import: import,
              normalize: prepared[:normalize],
              transform: prepared[:transform],
              flatten: prepared[:flatten],
              arc: prepared[:arc],
              moore_mlir_path: moore_mlir_path,
              source_mlir_path: prepared[:source_mlir_path],
              dbg_stripped_mlir_path: prepared[:dbg_stripped_mlir_path],
              normalized_llhd_mlir_path: prepared[:normalized_llhd_mlir_path],
              hwseq_mlir_path: prepared[:hwseq_mlir_path],
              flattened_hwseq_mlir_path: prepared[:flattened_hwseq_mlir_path],
              flattened_cleaned_hwseq_mlir_path: prepared[:flattened_cleaned_hwseq_mlir_path],
              arc_mlir_path: prepared[:arc_mlir_path],
              transformed_modules: prepared[:transformed_modules],
              unsupported_modules: prepared[:unsupported_modules]
            }
          end

          normalized_llhd_mlir_path = stage_artifact_path(
            work_dir: work_dir,
            base_name: 'import',
            step: 3,
            suffix: 'normalized.llhd.mlir'
          )

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
            stripped_moore_mlir_path,
            '-o',
            normalized_llhd_mlir_path
          ]
          normalize = run_external_command(tool: 'circt-opt', cmd: normalize_cmd, out_path: normalized_llhd_mlir_path)
          return prepare_arc_failure(import: import, normalize: normalize, work_dir: work_dir) unless normalize[:success]

          prepared = prepare_arc_mlir_from_circt_mlir(
            mlir_path: normalized_llhd_mlir_path,
            work_dir: work_dir,
            base_name: 'import',
            stub_modules: stub_modules,
            cleanup_mode: cleanup_mode,
            stage_index_offset: 3
          )
          prepared.merge(
            import: import,
            normalize: normalize,
            moore_mlir_path: moore_mlir_path
          )
        end

        def prepare_arc_mlir_from_circt_mlir(mlir_path:, work_dir:, base_name: 'import', top: nil, strict: false,
                                             extern_modules: [], stub_modules: [], cleanup_mode: :semantic,
                                             stage_index_offset: 0, include: DEFAULT_ARC_PREP_INCLUDE_STEPS)
          FileUtils.mkdir_p(work_dir)

          cleanup_mode = normalize_arc_input_cleanup_mode(cleanup_mode)
          include_steps = normalize_arc_prep_include_steps(include)
          source_mlir_path = stage_artifact_path(work_dir: work_dir, base_name: base_name, step: stage_index_offset + 1, suffix: 'input.core.mlir')
          dbg_stripped_mlir_path = stage_artifact_path(work_dir: work_dir, base_name: base_name, step: stage_index_offset + 2, suffix: 'dbg_stripped.core.mlir')
          normalized_llhd_mlir_path = stage_artifact_path(work_dir: work_dir, base_name: base_name, step: stage_index_offset + 3, suffix: 'prepared.normalized.llhd.mlir')
          hwseq_mlir_path = stage_artifact_path(work_dir: work_dir, base_name: base_name, step: stage_index_offset + 4, suffix: 'hwseq.mlir')
          flattened_hwseq_mlir_path = stage_artifact_path(work_dir: work_dir, base_name: base_name, step: stage_index_offset + 5, suffix: 'flattened.hwseq.mlir')
          flattened_cleaned_hwseq_mlir_path = stage_artifact_path(work_dir: work_dir, base_name: base_name, step: stage_index_offset + 6, suffix: 'flattened.cleaned.hwseq.mlir')
          arc_mlir_path = stage_artifact_path(work_dir: work_dir, base_name: base_name, step: stage_index_offset + 7, suffix: 'arc.mlir')
          syntax_cleanup_path = stage_artifact_path(work_dir: work_dir, base_name: base_name, step: stage_index_offset + 2, suffix: 'syntax.cleaned.core.mlir')

          text = File.read(mlir_path)
          File.write(source_mlir_path, text)
          current_path = source_mlir_path
          current_text = text

          normalize = skipped_stage_result(tool: 'ruby-import-cleanup', out_path: normalized_llhd_mlir_path)
          transform = skipped_transform_result(current_text)
          flatten = skipped_stage_result(tool: 'circt-opt', out_path: flattened_hwseq_mlir_path)
          flatten_cleanup = skipped_stage_result(tool: 'circt-opt', out_path: flattened_cleaned_hwseq_mlir_path)
          arc = skipped_stage_result(tool: 'circt-opt', out_path: arc_mlir_path)

          if include_steps.include?(:strip_dbg)
            File.write(dbg_stripped_mlir_path, current_text)
            strip_dbg_ops!(dbg_stripped_mlir_path)
            current_path = dbg_stripped_mlir_path
            current_text = File.read(current_path)
          else
            dbg_stripped_mlir_path = nil
          end

          if include_steps.include?(:strip_llhd)
            normalize =
              case cleanup_mode
              when :semantic, :llhd_only
                cleaned_text = cleanup_imported_core_mlir_text(
                  current_text,
                  top: top,
                  strict: strict,
                  extern_modules: extern_modules,
                  stub_modules: stub_modules,
                  llhd_only: cleanup_mode == :llhd_only
                )
                File.write(normalized_llhd_mlir_path, cleaned_text)
                {
                  success: true,
                  command: nil,
                  stdout: '',
                  stderr: '',
                  output_path: normalized_llhd_mlir_path,
                  tool: cleanup_mode == :llhd_only ? 'ruby-import-cleanup-llhd-only' : 'ruby-import-cleanup'
                }
              when :syntax_only
                syntax_only_arc_input_cleanup!(
                  input_path: current_path,
                  output_path: syntax_cleanup_path,
                  stub_modules: stub_modules
                )
              end
            return prepare_arc_failure(normalize: normalize, work_dir: work_dir) unless normalize[:success]

            current_path = normalize.fetch(:output_path)
            current_text = File.read(current_path)

            transform =
              if cleanup_mode == :syntax_only
                {
                  success: true,
                  output_text: current_text,
                  transformed_modules: module_names_from_core_mlir(current_text),
                  unsupported_modules: []
                }
              else
                prepare_hwseq_from_circt_mlir_text(current_text)
              end
            File.write(hwseq_mlir_path, transform.fetch(:output_text))
            current_path = hwseq_mlir_path
            current_text = transform.fetch(:output_text)
          else
            normalized_llhd_mlir_path = nil
            hwseq_mlir_path = nil
          end

          if include_steps.include?(:flatten)
            flatten = if transform.fetch(:unsupported_modules).empty?
                        flatten_hwseq_for_arc(
                          hwseq_mlir_path: current_path,
                          output_path: flattened_hwseq_mlir_path,
                          work_dir: work_dir,
                          base_name: base_name
                        )
                      else
                        failed_result(
                          tool: 'circt-opt',
                          out_path: flattened_hwseq_mlir_path,
                          cmd: arc_flatten_command(
                            input_path: current_path,
                            output_path: flattened_hwseq_mlir_path,
                            work_dir: work_dir,
                            base_name: base_name
                          ),
                          stderr: format_unsupported_modules(transform.fetch(:unsupported_modules))
                        )
                      end
            current_path = flattened_hwseq_mlir_path if flatten[:success]
          else
            flattened_hwseq_mlir_path = nil
          end

          if include_steps.include?(:canonicalize)
            flatten_cleanup = if transform.fetch(:unsupported_modules).empty? && flatten[:success]
                                cleanup_flattened_hwseq_for_arc(
                                  flattened_hwseq_mlir_path: current_path,
                                  output_path: flattened_cleaned_hwseq_mlir_path,
                                  work_dir: work_dir,
                                  base_name: base_name
                                )
                              else
                                failed_result(
                                  tool: 'circt-opt',
                                  out_path: flattened_cleaned_hwseq_mlir_path,
                                  cmd: arc_cleanup_command(
                                    input_path: current_path,
                                    output_path: flattened_cleaned_hwseq_mlir_path,
                                    work_dir: work_dir,
                                    base_name: base_name
                                  ),
                                  stderr: flatten[:stderr]
                                )
                              end
            current_path = flattened_cleaned_hwseq_mlir_path if flatten_cleanup[:success]
          else
            flattened_cleaned_hwseq_mlir_path = nil
          end

          if include_steps.include?(:to_arc)
            arc_command = arc_convert_command(input_path: current_path, output_path: arc_mlir_path)
            arc = if transform.fetch(:unsupported_modules).empty?
                    run_external_command(
                      tool: 'circt-opt',
                      cmd: arc_command,
                      out_path: arc_mlir_path
                    )
                  else
                    failed_result(
                      tool: 'circt-opt',
                      out_path: arc_mlir_path,
                      cmd: arc_command,
                      stderr: format_unsupported_modules(transform.fetch(:unsupported_modules))
                    )
                  end
          else
            arc_mlir_path = nil
          end

          {
            success: [normalize, flatten, flatten_cleanup, arc].all? { |stage| stage[:success] },
            import: nil,
            normalize: normalize,
            transform: transform,
            flatten: flatten,
            flatten_cleanup: flatten_cleanup,
            canonicalize: flatten_cleanup,
            arc: arc,
            moore_mlir_path: nil,
            source_mlir_path: source_mlir_path,
            dbg_stripped_mlir_path: dbg_stripped_mlir_path && File.file?(dbg_stripped_mlir_path) ? dbg_stripped_mlir_path : nil,
            normalized_llhd_mlir_path: normalized_llhd_mlir_path && File.file?(normalized_llhd_mlir_path) ? normalized_llhd_mlir_path : nil,
            hwseq_mlir_path: hwseq_mlir_path && File.file?(hwseq_mlir_path) ? hwseq_mlir_path : nil,
            flattened_hwseq_mlir_path: flattened_hwseq_mlir_path && File.file?(flattened_hwseq_mlir_path) ? flattened_hwseq_mlir_path : nil,
            flattened_cleaned_hwseq_mlir_path: flattened_cleaned_hwseq_mlir_path && File.file?(flattened_cleaned_hwseq_mlir_path) ? flattened_cleaned_hwseq_mlir_path : nil,
            arc_mlir_path: arc_mlir_path && File.file?(arc_mlir_path) ? arc_mlir_path : nil,
            transformed_modules: transform.fetch(:transformed_modules),
            unsupported_modules: transform.fetch(:unsupported_modules),
            include_steps: include_steps
          }
        end

        def prepare_arcilator_input_from_circt_mlir(mlir_path:, work_dir:, base_name: 'import', top: nil, strict: false,
                                                    extern_modules: [], stub_modules: [], cleanup_mode: :semantic)
          prepared = prepare_arc_mlir_from_circt_mlir(
            mlir_path: mlir_path,
            work_dir: work_dir,
            base_name: base_name,
            top: top,
            strict: strict,
            extern_modules: extern_modules,
            stub_modules: stub_modules,
            cleanup_mode: cleanup_mode
          )

          prepared.merge(arcilator_input_mlir_path: preferred_arcilator_input_mlir_path(prepared))
        end

        def preferred_arcilator_input_mlir_path(prepared)
          return nil unless prepared.is_a?(Hash)

          [
            prepared[:flattened_cleaned_hwseq_mlir_path],
            prepared[:flattened_hwseq_mlir_path],
            prepared[:hwseq_mlir_path],
            prepared[:arc_mlir_path]
          ].find { |path| path && File.file?(path) } ||
            prepared[:flattened_cleaned_hwseq_mlir_path] ||
            prepared[:arc_mlir_path] ||
            prepared[:flattened_hwseq_mlir_path] ||
            prepared[:hwseq_mlir_path]
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
            flatten: nil,
            arc: nil,
            moore_mlir_path: import && import[:output_path],
            source_mlir_path: stage_artifact_path(work_dir: work_dir, base_name: 'import', step: 1, suffix: 'input.core.mlir'),
            dbg_stripped_mlir_path: nil,
            normalized_llhd_mlir_path: normalize && normalize[:output_path],
            hwseq_mlir_path: stage_artifact_path(work_dir: work_dir, base_name: 'import', step: 4, suffix: 'hwseq.mlir'),
            flattened_hwseq_mlir_path: nil,
            flattened_cleaned_hwseq_mlir_path: nil,
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

        def cleanup_imported_core_mlir_text(text, top:, strict:, extern_modules:, stub_modules:, llhd_only: false)
          needs_cleanup = text.include?('llhd.') || Array(stub_modules).any?
          return text unless needs_cleanup

          cleanup = RHDL::Codegen::CIRCT::ImportCleanup.cleanup_imported_core_mlir(
            text,
            strict: strict,
            top: top,
            extern_modules: Array(extern_modules).map(&:to_s),
            stub_modules: stub_modules,
            llhd_only: llhd_only
          )
          raise RuntimeError, 'Imported CIRCT core cleanup failed during ARC preparation' unless cleanup.success?

          cleanup.cleaned_text
        end

        def finalize_arc_mlir_for_arcilator!(arc_mlir_path:, check_paths: [], output_path: nil)
          Array(check_paths).compact.each do |path|
            next unless File.file?(path)

            text = File.read(path)
            next unless text.include?('llhd.')

            raise RuntimeError, "ARC preparation left LLHD operations in #{path}"
          end

          finalized_path = output_path || finalized_arc_mlir_path(arc_mlir_path)
          FileUtils.mkdir_p(File.dirname(finalized_path))
          FileUtils.cp(arc_mlir_path, finalized_path) unless File.expand_path(finalized_path) == File.expand_path(arc_mlir_path)
          strip_dbg_ops!(finalized_path)
          finalized_path
        end

        def normalize_arc_input_cleanup_mode(mode)
          normalized = (mode || :semantic).to_sym
          return normalized if VALID_ARC_INPUT_CLEANUP_MODES.include?(normalized)

          raise ArgumentError,
                "Unsupported ARC input cleanup mode #{mode.inspect}. Use :semantic, :llhd_only, or :syntax_only."
        end

        def normalize_arc_prep_include_steps(include_steps)
          steps = Array(include_steps).map(&:to_sym).map { |step| step == :cannonicalize ? :canonicalize : step }
          invalid = steps - DEFAULT_ARC_PREP_INCLUDE_STEPS
          return steps.freeze if invalid.empty?

          raise ArgumentError,
                "Unsupported ARC prep include step(s) #{invalid.inspect}. Use any of: #{DEFAULT_ARC_PREP_INCLUDE_STEPS.join(', ')}"
        end

        def skipped_stage_result(tool:, out_path:)
          {
            success: true,
            skipped: true,
            command: nil,
            stdout: '',
            stderr: '',
            output_path: out_path.to_s,
            tool: tool
          }
        end

        def skipped_transform_result(text)
          {
            success: true,
            skipped: true,
            output_text: text,
            transformed_modules: module_names_from_core_mlir(text),
            unsupported_modules: []
          }
        end

        def syntax_only_arc_input_cleanup!(input_path:, output_path:, stub_modules:)
          if Array(stub_modules).any?
            return failed_result(
              tool: 'circt-opt',
              out_path: output_path,
              cmd: arc_input_syntax_cleanup_command(input_path: input_path, output_path: output_path),
              stderr: 'ARC syntax-only cleanup does not support stub_modules'
            )
          end

          text = File.read(input_path)
          unless text.include?('llhd.')
            FileUtils.mkdir_p(File.dirname(output_path.to_s))
            FileUtils.cp(input_path, output_path)
            return {
              success: true,
              command: nil,
              stdout: '',
              stderr: '',
              output_path: output_path.to_s,
              tool: 'circt-opt'
            }
          end

          run_external_command(
            tool: 'circt-opt',
            cmd: arc_input_syntax_cleanup_command(input_path: input_path, output_path: output_path),
            out_path: output_path
          )
        end

        def arc_input_syntax_cleanup_command(input_path:, output_path:)
          ['circt-opt'] + DEFAULT_ARC_INPUT_SYNTAX_CLEANUP_PASSES + [input_path.to_s, '-o', output_path.to_s]
        end

        def cleanup_flattened_hwseq_for_arc(flattened_hwseq_mlir_path:, output_path:, work_dir:, base_name:)
          cleanup = run_external_command(
            tool: 'circt-opt',
            cmd: arc_cleanup_command(
              input_path: flattened_hwseq_mlir_path,
              output_path: output_path,
              work_dir: work_dir,
              base_name: base_name
            ),
            out_path: output_path
          )
          cleanup
        end

        def flatten_hwseq_for_arc(hwseq_mlir_path:, output_path:, work_dir:, base_name:)
          run_external_command(
            tool: 'circt-opt',
            cmd: arc_flatten_command(
              input_path: hwseq_mlir_path,
              output_path: output_path,
              work_dir: work_dir,
              base_name: base_name
            ),
            out_path: output_path
          )
        end

        def arc_flatten_command(input_path:, output_path:, work_dir:, base_name:)
          raise ArgumentError, 'flatten output path must stay inside the ARC prep work dir' unless output_path.to_s.start_with?(work_dir.to_s)
          basename = File.basename(output_path.to_s)
          expected_suffix = ".#{base_name}.flattened.hwseq.mlir"
          valid_flatten_name = basename == "#{base_name}.flattened.hwseq.mlir" || basename.end_with?(expected_suffix)
          raise ArgumentError, 'flatten output file must use the flattened hwseq naming convention' unless valid_flatten_name

          ['circt-opt', input_path, "--pass-pipeline=#{DEFAULT_ARC_FLATTEN_PIPELINE}", '-o', output_path]
        end

        def arc_cleanup_command(input_path:, output_path:, work_dir:, base_name:)
          raise ArgumentError, 'cleanup output path must stay inside the ARC prep work dir' unless output_path.to_s.start_with?(work_dir.to_s)
          basename = File.basename(output_path.to_s)
          expected_suffix = ".#{base_name}.flattened.cleaned.hwseq.mlir"
          valid_cleanup_name = basename == "#{base_name}.flattened.cleaned.hwseq.mlir" || basename.end_with?(expected_suffix)
          raise ArgumentError, 'cleanup output file must use the flattened cleanup naming convention' unless valid_cleanup_name || output_path.to_s == input_path.to_s

          ['circt-opt', input_path] + DEFAULT_ARC_CLEANUP_PASSES + ['-o', output_path]
        end

        def arc_convert_command(input_path:, output_path:)
          ['circt-opt', input_path, '--convert-to-arcs', '--arc-split-loops', '--arc-canonicalizer', '-o', output_path]
        end

        def format_unsupported_modules(entries)
          return 'Unsupported ARC preparation patterns' if entries.nil? || entries.empty?

          details = entries.first(12).map do |entry|
            "#{entry.fetch('module')}: #{entry.fetch('reason')}"
          end
          extra = entries.length > 12 ? "\n... #{entries.length - 12} more module(s)" : ''
          "Unsupported ARC preparation patterns:\n#{details.join("\n")}#{extra}"
        end

        def stage_artifact_path(work_dir:, base_name:, step:, suffix:)
          File.join(work_dir, format('%02d.%s.%s', step, base_name, suffix))
        end

        def finalized_arc_mlir_path(arc_mlir_path)
          path = arc_mlir_path.to_s
          dir = File.dirname(path)
          name = File.basename(path)
          if (match = /\A(\d+)\.(.+)\.arc\.mlir\z/.match(name))
            return stage_artifact_path(
              work_dir: dir,
              base_name: match[2],
              step: match[1].to_i + 1,
              suffix: 'final.arc.mlir'
            )
          end

          File.join(dir, name.sub(/\.arc\.mlir\z/, '.final.arc.mlir'))
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
