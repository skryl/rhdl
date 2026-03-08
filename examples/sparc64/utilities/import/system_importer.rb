# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'yaml'
require 'json'
require 'set'

module RHDL
  module Examples
    module SPARC64
      module Import
        class SystemImporter
          DEFAULT_REFERENCE_ROOT = File.expand_path('../../reference', __dir__)
          DEFAULT_TOP = 'W1'
          DEFAULT_TOP_FILE = File.join(DEFAULT_REFERENCE_ROOT, 'Top', 'W1.v')
          DEFAULT_OUTPUT_DIR = File.expand_path('../../import', __dir__)
          DEFAULT_IMPORT_STRATEGY = :mixed
          VALID_IMPORT_STRATEGIES = %i[mixed].freeze
          DEFAULT_HEADER_SEARCH_DIRS = [
            File.join(DEFAULT_REFERENCE_ROOT, 'T1-common', 'include')
          ].freeze
          EXCLUDED_SOURCE_PATHS = [
            File.join(DEFAULT_REFERENCE_ROOT, 'T1-common', 'srams', 'bw_r_tlb.v'),
            File.join(DEFAULT_REFERENCE_ROOT, 'T1-common', 'u1', 'u1.V')
          ].freeze
          FORCE_STUB_SOURCE_PREFIXES = [
            File.join(DEFAULT_REFERENCE_ROOT, 'WB2ALTDDR3'),
            File.join(DEFAULT_REFERENCE_ROOT, 'NOR-flash'),
            File.join(DEFAULT_REFERENCE_ROOT, 'OC-UART'),
            File.join(DEFAULT_REFERENCE_ROOT, 'OC-Ethernet')
          ].freeze
          FORCE_STUB_SOURCE_PATHS = [
            File.join(DEFAULT_REFERENCE_ROOT, 'T1-common', 'srams', 'bw_r_tlb_fpga.v'),
            File.join(DEFAULT_REFERENCE_ROOT, 'T1-common', 'srams', 'bw_r_dcd.v'),
            File.join(DEFAULT_REFERENCE_ROOT, 'T1-common', 'srams', 'bw_r_frf.v'),
            File.join(DEFAULT_REFERENCE_ROOT, 'T1-common', 'srams', 'bw_r_icd.v'),
            File.join(DEFAULT_REFERENCE_ROOT, 'T1-common', 'srams', 'bw_r_idct.v'),
            File.join(DEFAULT_REFERENCE_ROOT, 'T1-common', 'srams', 'bw_r_irf_register.v'),
            File.join(DEFAULT_REFERENCE_ROOT, 'T1-common', 'srams', 'bw_r_rf16x32.v'),
            File.join(DEFAULT_REFERENCE_ROOT, 'T1-common', 'srams', 'bw_r_rf16x160.v'),
            File.join(DEFAULT_REFERENCE_ROOT, 'T1-common', 'srams', 'bw_r_rf32x152b.v')
          ].freeze
          INSTANCE_KEYWORDS = %w[
            module if else for case while begin end always always_ff always_comb
            assign wire reg logic input output inout localparam parameter generate
            endgenerate function endfunction task endtask initial package import
            typedef enum struct
          ].freeze

          Result = Struct.new(
            :success,
            :output_dir,
            :workspace,
            :staged_root,
            :staged_top_file,
            :include_dirs,
            :staged_include_dirs,
            :files_written,
            :manifest_path,
            :mlir_path,
            :report_path,
            :diagnostics,
            :raise_diagnostics,
            :closure_modules,
            :module_files_by_name,
            :module_source_relpaths,
            :staged_source_paths_by_module,
            :strategy_requested,
            :strategy_used,
            :fallback_used,
            :attempted_strategies,
            keyword_init: true
          ) do
            def success?
              !!success
            end
          end

          attr_reader :reference_root, :top, :top_file, :output_dir, :workspace_dir, :keep_workspace,
                      :clean_output, :maintain_directory_structure, :strict, :progress_callback,
                      :import_task_class, :import_strategy, :emit_runtime_json

          def initialize(reference_root: DEFAULT_REFERENCE_ROOT,
                         top: DEFAULT_TOP,
                         top_file: DEFAULT_TOP_FILE,
                         output_dir: DEFAULT_OUTPUT_DIR,
                         workspace_dir: nil,
                         keep_workspace: false,
                         clean_output: true,
                         maintain_directory_structure: true,
                         strict: true,
                         progress: nil,
                         import_task_class: nil,
                         import_strategy: DEFAULT_IMPORT_STRATEGY,
                         emit_runtime_json: true)
            @reference_root = File.expand_path(reference_root)
            @top = top.to_s
            @top_file = File.expand_path(top_file)
            @output_dir = File.expand_path(output_dir)
            @workspace_dir = workspace_dir && File.expand_path(workspace_dir)
            @keep_workspace = keep_workspace
            @clean_output = clean_output
            @maintain_directory_structure = maintain_directory_structure
            @strict = strict
            @progress_callback = progress
            @import_task_class = import_task_class
            @import_strategy = normalize_strategy(import_strategy)
            @emit_runtime_json = !!emit_runtime_json
            @resolved_include_cache = {}
          end

          def run
            diagnostics = []
            raise_diagnostics = []
            workspace = workspace_dir || Dir.mktmpdir('rhdl_sparc64_import')
            temp_workspace = workspace if workspace_dir.nil?

            emit_progress('resolve mixed sources from reference tree')
            resolved = resolve_sources
            module_source_relpaths = resolved.fetch(:module_source_relpaths)
            module_files_by_name = resolved.fetch(:module_files_by_name)
            closure_modules = resolved.fetch(:closure_modules)

            emit_progress("prepare output directory: #{output_dir}")
            prepare_output_dir!

            emit_progress('write staged import source')
            source_bundle = write_import_source_bundle(workspace: workspace, resolved: resolved)
            report_path = File.join(output_dir, 'import_report.json')
            requested_mlir_path = File.join(output_dir, '.mixed_import', "#{top}.core.mlir")

            emit_progress('run import strategy: verilog')
            import_result = run_import_task(
              mode: :verilog,
              mlir_path: requested_mlir_path,
              report_path: report_path,
              input_path: source_bundle.fetch(:input_path),
              extra_tool_args: source_bundle.fetch(:tool_args)
            )

            diagnostics.concat(Array(import_result[:diagnostics]))
            raise_diagnostics.concat(Array(import_result[:raise_diagnostics]))

            if import_result[:success]
              files_written = import_result[:files_written]
              if maintain_directory_structure
                emit_progress('remap output to source directory layout')
                files_written = remap_output_layout(
                  files_written: files_written,
                  module_source_relpaths: module_source_relpaths,
                  diagnostics: diagnostics
                )
              end

              report = read_report(report_path)
              artifacts = report.fetch('artifacts', {})
              return Result.new(
                success: true,
                output_dir: output_dir,
                workspace: workspace,
                staged_root: source_bundle.fetch(:staged_root),
                staged_top_file: source_bundle.fetch(:staged_top_file),
                include_dirs: resolved.fetch(:include_dirs),
                staged_include_dirs: source_bundle.fetch(:staged_include_dirs),
                files_written: files_written,
                manifest_path: source_bundle.fetch(:input_path),
                mlir_path: artifacts['core_mlir_path'] || requested_mlir_path,
                report_path: report_path,
                diagnostics: diagnostics,
                raise_diagnostics: raise_diagnostics,
                closure_modules: closure_modules,
                module_files_by_name: module_files_by_name,
                module_source_relpaths: module_source_relpaths,
                staged_source_paths_by_module: source_bundle.fetch(:staged_source_paths_by_module),
                strategy_requested: import_strategy,
                strategy_used: :mixed,
                fallback_used: false,
                attempted_strategies: [:mixed]
              )
            end

            Result.new(
              success: false,
              output_dir: output_dir,
              workspace: workspace,
              staged_root: source_bundle[:staged_root],
              staged_top_file: source_bundle[:staged_top_file],
              include_dirs: resolved.fetch(:include_dirs),
              staged_include_dirs: source_bundle.fetch(:staged_include_dirs, []),
              files_written: [],
              manifest_path: source_bundle.fetch(:input_path),
              mlir_path: nil,
              report_path: report_path,
              diagnostics: diagnostics,
              raise_diagnostics: raise_diagnostics,
              closure_modules: closure_modules,
              module_files_by_name: module_files_by_name,
              module_source_relpaths: module_source_relpaths,
              staged_source_paths_by_module: source_bundle.fetch(:staged_source_paths_by_module, {}),
              strategy_requested: import_strategy,
              strategy_used: nil,
              fallback_used: false,
              attempted_strategies: [:mixed]
            )
          rescue StandardError, SystemStackError => e
            diagnostics << e.message
            Result.new(
              success: false,
              output_dir: output_dir,
              workspace: workspace_dir,
              staged_root: nil,
              staged_top_file: nil,
              include_dirs: [],
              staged_include_dirs: [],
              files_written: [],
              manifest_path: nil,
              mlir_path: nil,
              report_path: nil,
              diagnostics: diagnostics,
              raise_diagnostics: raise_diagnostics,
              closure_modules: [],
              module_files_by_name: {},
              module_source_relpaths: {},
              staged_source_paths_by_module: {},
              strategy_requested: import_strategy,
              strategy_used: nil,
              fallback_used: false,
              attempted_strategies: [:mixed]
            )
          ensure
            FileUtils.rm_rf(temp_workspace) if defined?(temp_workspace) && temp_workspace && !keep_workspace
          end

          def resolve_sources
            validate_source_inputs!

            all_module_files = candidate_verilog_files.select { |path| module_defining_verilog_file?(path) }
            duplicate_modules = duplicate_module_definitions(all_module_files)
            unless duplicate_modules.empty?
              details = duplicate_modules.sort.map { |name, paths| "#{name}=#{paths.map { |p| source_relative_path(p) }.join(',')}" }
              raise ArgumentError, "Duplicate SPARC64 module definitions: #{details.join(' | ')}"
            end

            module_paths = module_index(all_module_files)
            raise ArgumentError, "Top module '#{top}' not found under #{reference_root}" unless module_paths.key?(top)

            graph = module_reference_graph(all_module_files)
            module_files = ordered_module_paths(top, graph, module_paths)
            closure_modules = module_closure(top, graph).select { |name| module_paths.key?(name) }
            top_path = File.expand_path(top_file)
            module_files.reject! do |path|
              File.expand_path(path) != top_path && force_stubbed_hierarchy_source?(path)
            end
            module_files << top_path if File.file?(top_path)
            module_files.uniq!
            active_module_files_by_name = module_index(module_files)
            layout_module_paths = full_reference_module_index_for_layout.merge(module_paths)

            {
              top: {
                name: top,
                file: File.expand_path(top_file),
                language: 'verilog'
              },
              files: module_files.map { |path| { path: path, language: 'verilog', library: nil } },
              module_files: module_files,
              closure_modules: active_module_files_by_name.keys.sort,
              module_files_by_name: active_module_files_by_name,
              module_source_relpaths: layout_module_paths.transform_values { |path| source_relative_path(path) },
              include_dirs: include_dirs_for_files(module_files)
            }
          end

          def write_import_source_bundle(workspace:, resolved: nil)
            resolved ||= resolve_sources
            staged = stage_sources(workspace: workspace, resolved: resolved)
            support_stub_path = write_hierarchy_support_stubs(
              staged_root: staged.fetch(:staged_root),
              staged_module_files: staged.fetch(:files).map { |entry| entry.fetch(:path) },
              top_file: staged.fetch(:top_file)
            )
            staged_module_files = staged.fetch(:files).map { |entry| entry.fetch(:path) }
            extra_source_files = staged_module_files.reject { |path| File.expand_path(path) == File.expand_path(staged.fetch(:top_file)) }

            {
              input_path: staged.fetch(:top_file),
              staged_root: staged.fetch(:staged_root),
              staged_top_file: staged.fetch(:top_file),
              include_dirs: resolved.fetch(:include_dirs),
              staged_include_dirs: staged.fetch(:include_dirs),
              staged_source_paths_by_module: resolved.fetch(:module_source_relpaths).each_with_object({}) do |(name, relpath), acc|
                next unless resolved.fetch(:module_files_by_name).key?(name)

                acc[name] = File.join(staged.fetch(:staged_root), relpath)
              end,
              tool_args: staged.fetch(:include_dirs).map { |dir| "-I#{dir}" } + ['-DFPGA_SYN', support_stub_path, *extra_source_files]
            }
          end

          private

          def normalize_strategy(value)
            strategy = value.to_sym
            return strategy if VALID_IMPORT_STRATEGIES.include?(strategy)

            raise ArgumentError,
                  "Unknown import_strategy #{value.inspect}. Expected one of: #{VALID_IMPORT_STRATEGIES.join(', ')}"
          end

          def emit_progress(message)
            if progress_callback.respond_to?(:call)
              progress_callback.call(message)
            else
              puts "SPARC64 import step: #{message}"
            end
          end

          def validate_source_inputs!
            raise ArgumentError, "SPARC64 reference tree not found: #{reference_root}" unless Dir.exist?(reference_root)
            raise ArgumentError, "SPARC64 top source file not found: #{top_file}" unless File.file?(top_file)
          end

          def candidate_verilog_files
            Dir.glob(File.join(reference_root, '**', '*')).sort.filter_map do |path|
              next unless File.file?(path)
              next unless verilog_source_file?(path)
              next if EXCLUDED_SOURCE_PATHS.include?(File.expand_path(path))

              File.expand_path(path)
            end
          end

          def full_reference_module_index_for_layout
            files = Dir.glob(File.join(reference_root, '**', '*')).sort.select do |path|
              File.file?(path) && verilog_source_file?(path) && module_defining_verilog_file?(path)
            end
            module_index(files)
          end

          def verilog_source_file?(path)
            %w[.v .sv .vh].include?(File.extname(path).downcase)
          end

          def force_stubbed_hierarchy_source?(path)
            absolute = File.expand_path(path)
            return true if FORCE_STUB_SOURCE_PATHS.include?(absolute)

            FORCE_STUB_SOURCE_PREFIXES.any? do |prefix|
              absolute.start_with?("#{File.expand_path(prefix)}/")
            end
          end

          def module_defining_verilog_file?(path)
            strip_comments(File.read(path)).match?(/\bmodule\s+[A-Za-z_][A-Za-z0-9_$]*\b/)
          end

          def duplicate_module_definitions(files)
            defs = Hash.new { |h, k| h[k] = [] }
            files.each do |path|
              strip_comments(File.read(path)).scan(/\bmodule\s+([A-Za-z_][A-Za-z0-9_$]*)\b/).flatten.each do |name|
                defs[name] << path
              end
            end
            defs.each_with_object({}) do |(name, paths), out|
              unique_paths = paths.uniq
              out[name] = unique_paths if unique_paths.length > 1
            end
          end

          def include_dirs_for_files(files)
            include_dirs = Set.new(DEFAULT_HEADER_SEARCH_DIRS.map { |dir| File.expand_path(dir) })

            files.each do |path|
              source_dir = File.dirname(path)
              include_names(path).each do |include_name|
                if File.file?(File.join(source_dir, include_name))
                  include_dirs << source_dir
                  next
                end

                include_path = resolve_include_path(include_name)
                raise ArgumentError, "Unable to resolve include '#{include_name}' for #{source_relative_path(path)}" unless include_path

                include_dirs << File.dirname(include_path)
              end
            end

            include_dirs.to_a.sort
          end

          def stage_sources(workspace:, resolved:)
            staged_root = File.join(workspace, 'mixed_sources')
            FileUtils.mkdir_p(staged_root)

            paths_to_stage = resolved.fetch(:module_files)
              .concat(header_dependency_paths(resolved.fetch(:module_files)))
              .push(File.expand_path(top_file))
              .uniq

            paths_to_stage.each do |path|
              staged_path = staged_path_for_source(path, staged_root: staged_root)
              FileUtils.mkdir_p(File.dirname(staged_path))
              File.write(staged_path, normalize_verilog_for_import(File.read(path), source_path: path))
            end

            {
              staged_root: staged_root,
              top_file: staged_path_for_source(top_file, staged_root: staged_root),
              files: resolved.fetch(:files).map do |entry|
                {
                  path: staged_path_for_source(entry.fetch(:path), staged_root: staged_root),
                  language: entry.fetch(:language),
                  library: entry[:library]
                }
              end,
              include_dirs: resolved.fetch(:include_dirs).map { |dir| staged_path_for_source(dir, staged_root: staged_root) }.uniq.sort
            }
          end

          def write_hierarchy_support_stubs(staged_root:, staged_module_files:, top_file:)
            path = File.join(staged_root, '__rhdl_sparc64_hierarchy_stubs.v')
            ordered_names = module_index(staged_module_files).keys.to_set
            module_ports = Hash.new { |h, k| h[k] = [] }

            Array(staged_module_files).each do |source_path|
              text = strip_comments(File.read(source_path))
              text.scan(/^\s*([A-Za-z_][A-Za-z0-9_$]*)\s*(?:#\s*(?:\([^;]*?\)|\d+))?\s+([A-Za-z_][A-Za-z0-9_$]*)\s*\((.*?)\)\s*;/m) do |target, _instance_name, connection_text|
                next if target == top
                next if INSTANCE_KEYWORDS.include?(target)
                next if target == 'endcase'
                next if ordered_names.include?(target)

                named_ports = connection_text.scan(/\.\s*([A-Za-z_][A-Za-z0-9_$]*)\s*\(/).flatten.uniq
                ports = if named_ports.empty?
                          positional = connection_text.split(',').map(&:strip).reject(&:empty?)
                          positional.each_index.map { |idx| "p#{idx}" }
                        else
                          named_ports
                        end
                module_ports[target].concat(ports)
              end
            end

            body = +"`timescale 1ns / 1ps\n\n"
            module_ports.keys.sort.each do |mod_name|
              ports = module_ports.fetch(mod_name).uniq
              body << "module #{mod_name}(#{ports.join(', ')});\n"
              ports.each { |port| body << "  input #{port};\n" }
              body << "endmodule\n\n"
            end

            File.write(path, body)
            path
          end

          def header_dependency_paths(files)
            queue = Array(files).map { |path| File.expand_path(path) }
            visited = Set.new
            headers = Set.new

            until queue.empty?
              path = queue.shift
              next if visited.include?(path) || !File.file?(path)

              visited << path
              source_dir = File.dirname(path)
              include_names(path).each do |include_name|
                include_path = if File.file?(File.join(source_dir, include_name))
                                 File.expand_path(File.join(source_dir, include_name))
                               else
                                 resolve_include_path(include_name)
                               end
                next unless include_path
                next if headers.include?(include_path)

                headers << include_path
                queue << include_path
              end
            end

            headers.to_a.sort
          end

          def staged_path_for_source(path, staged_root:)
            File.join(staged_root, source_relative_path(path))
          end

          def normalize_verilog_for_import(content, source_path:)
            text = content.dup
            text.gsub!(/\bassign\s+#\s*\d+\s+/, 'assign ')
            text.gsub!(/<=\s*#\s*\d+\s*/, '<= ')
            text.gsub!(/=\s*#\s*\d+\s*/, '= ')
            text.gsub!(/\b([A-Za-z_][A-Za-z0-9_$]*)\s+#\s*(\d+)\s+([A-Za-z_][A-Za-z0-9_$]*)\s*\(/, '\1 #(\2) \3(')
            text.gsub!(/^\s*\$constraint\b.*$/, '')
            text.gsub!(%r{//\s*synopsys translate_off.*?//\s*synopsys translate_on\s*}m, '')
            text.gsub!(/\bdo\b/, 'dout')
            text.gsub!(/,\s*\);\s*$/, "\n);")

            case File.basename(source_path).downcase
            when 'w1.v'
              text.gsub!(/\binout\b/, 'input')
              text.sub!(/reg \[223:0\] ILA_DATA;.*?endmodule/m, "endmodule\n")
            when 'os2wb.v'
              declarations = <<~DECL
                reg fifo_rd;
                wire [123:0] pcx_packet;
                assign pcx_packet=pcx_data_fifo[123:0];

              DECL
              text.sub!(/reg fifo_rd;\s*wire \[123:0\] pcx_packet;\s*assign pcx_packet=pcx_data_fifo\[123:0\];\s*/m, '')
              text.sub!(/pcx_fifo pcx_fifo_inst\(/, "#{declarations}pcx_fifo pcx_fifo_inst(")
            when 'os2wb_dual.v'
              text.gsub!(/\.ready\(ready\),(\s*\/\/[^\n]*\n\s*)\);/, '.ready(ready)\1);')
              declarations = <<~DECL
                reg fifo_rd;
                reg fifo_rd1;
                reg cpu;
                reg cpu2;
                wire [123:0] pcx_packet;
                assign pcx_packet=cpu ? pcx1_data_fifo[123:0]:pcx_data_fifo[123:0];

              DECL
              text.sub!(/reg fifo_rd;\s*reg fifo_rd1;\s*reg cpu;\s*reg cpu2;\s*wire \[123:0\] pcx_packet;\s*assign pcx_packet=cpu \? pcx1_data_fifo\[123:0\]:pcx_data_fifo\[123:0\];\s*/m, '')
              text.sub!(/reg fifo_rd;\s*reg fifo_rd1;\s*wire \[123:0\] pcx_packet;\s*assign pcx_packet=cpu \? pcx1_data_fifo\[123:0\]:pcx_data_fifo\[123:0\];\s*reg cpu;\s*reg cpu2;\s*/m, '')
              text.sub!(/pcx_fifo pcx_fifo_inst\(/, "#{declarations}pcx_fifo pcx_fifo_inst(")
            when 'sparc_ifu_milfsm.v'
              text.gsub!(/`CMP_CLK_PERIOD/, '1333')
            when 'sparc_exu_alu.v'
              text.gsub!(/\bsparc_exu_alulogic\s+logic\s*\(/, 'sparc_exu_alulogic logic_inst(')
            when 'sparc_ffu_ctl_visctl.v'
              text.gsub!(/\blogic\b/, 'logic_op')
            when 'spu_mactl.v'
              text.sub!(
                /wire spu_lsu_unc_error_w = (.*?);\s*$/m,
                "assign spu_lsu_unc_error_w = \\1;\n"
              )
            when 'tlu.h'
              text.sub!(
                /`define INT_THR_HI\s+12\s*?\n`define INT_VEC_HI 5\s*?\n`define INT_VEC_LO 0\s*?\n`define INT_THR_HI\s+12\s*?\n`define INT_THR_LO\s+8\s*?\n/,
                <<~DEFS
                  `ifndef INT_VEC_HI
                  `define INT_VEC_HI 5
                  `endif
                  `ifndef INT_VEC_LO
                  `define INT_VEC_LO 0
                  `endif
                  `ifndef INT_THR_HI
                  `define INT_THR_HI 12
                  `endif
                  `ifndef INT_THR_LO
                  `define INT_THR_LO 8
                  `endif
                DEFS
              )
            end

            text
          end

          def include_names(path)
            strip_comments(File.read(path)).scan(/^\s*`include\s+"([^"]+)"/).flatten.uniq
          end

          def resolve_include_path(include_name)
            return @resolved_include_cache[include_name] if @resolved_include_cache.key?(include_name)

            matches = Dir.glob(File.join(reference_root, '**', include_name)).sort.select { |path| File.file?(path) }
            @resolved_include_cache[include_name] = case matches.length
                                                    when 0 then nil
                                                    when 1 then File.expand_path(matches.first)
                                                    else
                                                      raise ArgumentError,
                                                            "Ambiguous include '#{include_name}' under #{reference_root}: #{matches.map { |path| source_relative_path(path) }.join(', ')}"
                                                    end
          end

          def prepare_output_dir!
            FileUtils.mkdir_p(output_dir)
            return unless clean_output

            Dir.glob(File.join(output_dir, '*'), File::FNM_DOTMATCH).each do |entry|
              next if %w[. ..].include?(File.basename(entry))
              next if File.basename(entry) == '.gitignore'

              FileUtils.rm_rf(entry)
            end
          end

          def run_import_task(mode:, mlir_path:, report_path:, manifest_path: nil, input_path: nil, extra_tool_args: [])
            task_class = import_task_class
            unless task_class
              require 'rhdl'
              require_relative '../../../../lib/rhdl/cli/tasks/import_task'
              task_class = RHDL::CLI::Tasks::ImportTask
            end

            options = {
              mode: mode,
              out: output_dir,
              mlir_out: mlir_path,
              report: report_path,
              top: top,
              strict: strict,
              raise_to_dsl: true,
              format_output: false,
              emit_runtime_json: emit_runtime_json,
              tool_args: [
                '--allow-use-before-declare',
                '--ignore-unknown-modules',
                '--timescale=1ns/1ps',
                "--top=#{top}"
              ] + Array(extra_tool_args)
            }
            options[:manifest] = manifest_path if manifest_path
            options[:input] = input_path if input_path

            task = task_class.new(options)
            task.run

            report_diags, report_raise_diags = diagnostics_from_report(report_path)
            files_written = Dir.glob(File.join(output_dir, '**', '*.rb')).sort
            {
              success: true,
              diagnostics: report_diags,
              raise_diagnostics: report_raise_diags,
              files_written: files_written
            }
          rescue StandardError, SystemStackError => e
            {
              success: false,
              diagnostics: [e.message],
              raise_diagnostics: [],
              files_written: []
            }
          end

          def diagnostics_from_report(report_path)
            return [[], []] unless File.file?(report_path)

            report = JSON.parse(File.read(report_path))
            import_diags = Array(report['import_diagnostics']).map { |diag| diag['message'] }.compact
            raise_diags = Array(report['raise_diagnostics']).map { |diag| diag['message'] }.compact
            [import_diags, raise_diags]
          rescue JSON::ParserError
            [[], []]
          end

          def read_report(report_path)
            return {} unless File.file?(report_path)

            JSON.parse(File.read(report_path))
          rescue JSON::ParserError
            {}
          end

          def remap_output_layout(files_written:, module_source_relpaths:, diagnostics:)
            target_dirs_by_basename = Hash.new { |h, k| h[k] = [] }
            module_source_relpaths.each do |module_name, rel_source_path|
              rel_dir = File.dirname(rel_source_path.to_s)
              next if rel_dir.nil? || rel_dir == '.'

              basename = "#{underscore_module_name(module_name)}.rb"
              target_dirs_by_basename[basename] << rel_dir
            end

            files_written.map do |source_path|
              basename = File.basename(source_path)
              dirs = target_dirs_by_basename[basename].uniq
              if dirs.empty?
                inferred_basename = infer_layout_basename(basename, target_dirs_by_basename.keys)
                if inferred_basename
                  dirs = target_dirs_by_basename[inferred_basename].uniq
                end
              end
              if dirs.empty?
                source_path
              else
                rel_dir = dirs.sort.first
                if dirs.length > 1
                  diagnostics << "SPARC64 layout ambiguous for #{basename}: #{dirs.sort.join(', ')}; using #{rel_dir}"
                end

                destination_dir = File.join(output_dir, rel_dir)
                FileUtils.mkdir_p(destination_dir)
                destination_path = File.join(destination_dir, basename)
                next destination_path if File.expand_path(source_path) == File.expand_path(destination_path)

                FileUtils.rm_f(destination_path)
                FileUtils.mv(source_path, destination_path)
                destination_path
              end
            end
          end

          def infer_layout_basename(basename, known_basenames)
            stem = File.basename(basename, '.rb')
            Array(known_basenames)
              .select do |candidate|
                candidate_stem = File.basename(candidate, '.rb')
                stem.start_with?("#{candidate_stem}_")
              end
              .max_by { |candidate| File.basename(candidate, '.rb').length }
          end

          def source_relative_path(path)
            root = File.expand_path(reference_root)
            absolute = File.expand_path(path)
            prefix = "#{root}/"
            return absolute.delete_prefix(prefix) if absolute.start_with?(prefix)

            File.basename(absolute)
          end

          def underscore_module_name(name)
            name.to_s
                .gsub('::', '_')
                .gsub(/([A-Z]+)([A-Z][a-z])/, '\\1_\\2')
                .gsub(/([a-z\d])([A-Z])/, '\\1_\\2')
                .tr('.', '_')
                .downcase
                .gsub(/[^a-z0-9_]/, '_')
          end

          def module_index(files)
            files.each_with_object({}) do |path, acc|
              text = strip_comments(File.read(path))
              text.scan(/\bmodule\s+([A-Za-z_][A-Za-z0-9_$]*)\b/).flatten.each do |name|
                acc[name] ||= path
              end
            end
          end

          def module_reference_graph(files)
            files.each_with_object(Hash.new { |h, k| h[k] = [] }) do |path, acc|
              text = strip_comments(File.read(path))
              text.scan(/\bmodule\s+([A-Za-z_][A-Za-z0-9_$]*)\b(.*?)\bendmodule\b/m) do |mod_name, body|
                body.scan(/\b([A-Za-z_][A-Za-z0-9_$]*)\s*(?:#\s*(?:\([^;]*?\)|\d+))?\s+([A-Za-z_][A-Za-z0-9_$]*)\s*\(/m) do |target, _inst_name|
                  next if INSTANCE_KEYWORDS.include?(target)
                  next if target == 'endcase'

                  acc[mod_name] << target unless acc[mod_name].include?(target)
                end
              end
            end
          end

          def module_closure(start, graph)
            seen = {}
            queue = [start.to_s]
            until queue.empty?
              current = queue.shift
              next if seen[current]

              seen[current] = true
              Array(graph[current]).each { |child| queue << child }
            end
            seen.keys
          end

          def ordered_module_paths(start, graph, module_paths)
            visited = {}
            ordered = []

            visit = lambda do |mod_name|
              return if visited[mod_name]

              visited[mod_name] = true
              Array(graph[mod_name]).each { |child| visit.call(child) if module_paths.key?(child) }
              ordered << module_paths.fetch(mod_name) if module_paths.key?(mod_name)
            end

            visit.call(start.to_s)
            ordered.uniq
          end

          def strip_comments(text)
            text
              .gsub(%r{//.*$}, '')
              .gsub(%r{/\*.*?\*/}m, '')
          end
        end
      end
    end
  end
end
