# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'shellwords'
require 'tmpdir'
require 'rhdl'

module RHDL
  module Examples
    module AO486
      module Import
        # Imports the AO486 system-level top (system.v) into CIRCT and raises to RHDL DSL.
        # This importer intentionally uses blackbox stubs for child modules to establish a
        # deterministic top-level import baseline.
        class SystemImporter
          DEFAULT_REFERENCE_ROOT = File.expand_path('../../reference', __dir__)
          DEFAULT_PATCHES_ROOT = File.expand_path('../../patches', __dir__)
          DEFAULT_SOURCE_PATH = File.join(DEFAULT_REFERENCE_ROOT, 'rtl', 'system.v')
          DEFAULT_TOP = 'system'
          DEFAULT_IMPORT_STRATEGY = :stubbed
          VALID_IMPORT_STRATEGIES = %i[stubbed tree].freeze

          LATE_REG_DECLARATIONS = %w[ide0_wait ide1_wait].freeze
          TREE_FORCE_STUB_MODULES = %w[dma floppy ide pit pit_counter ps2 rtc].freeze
          TREE_MAX_AUTO_STUB_RETRIES = 16
          INSTANCE_KEYWORDS = %w[
            module if else for case while begin end always always_ff always_comb
            assign wire reg logic input output inout localparam parameter generate
            endgenerate function endfunction task endtask
          ].freeze

          Result = Struct.new(
            :success,
            :output_dir,
            :files_written,
            :workspace,
            :moore_mlir_path,
            :core_mlir_path,
            :normalized_core_mlir_path,
            :command_log,
            :diagnostics,
            :raise_diagnostics,
            :strategy_requested,
            :strategy_used,
            :fallback_used,
            :attempted_strategies,
            :stub_modules,
            :closure_modules,
            :module_files_by_name,
            :staged_module_files_by_name,
            :module_source_relpaths,
            :include_dirs,
            :staged_include_dirs,
            keyword_init: true
          ) do
            def success?
              !!success
            end
          end
          FormatResult = Struct.new(:success, :diagnostics, keyword_init: true) do
            def success?
              !!success
            end
          end

          attr_reader :source_path, :output_dir, :top, :keep_workspace, :workspace_dir, :clean_output,
                      :import_strategy, :fallback_to_stubbed, :maintain_directory_structure, :strict,
                      :format_output, :patches_dir, :patch_profiles,
                      :progress_callback

          def initialize(source_path: DEFAULT_SOURCE_PATH,
                         output_dir:,
                         top: DEFAULT_TOP,
                         keep_workspace: false,
                         workspace_dir: nil,
                         clean_output: true,
                         import_strategy: DEFAULT_IMPORT_STRATEGY,
                         fallback_to_stubbed: true,
                         maintain_directory_structure: true,
                         patch_profile: nil,
                         patch_profiles: nil,
                         patches_dir: nil,
                         format_output: false,
                         strict: true,
                         progress: nil)
            @source_path = File.expand_path(source_path)
            raise ArgumentError, 'output_dir is required' if output_dir.to_s.strip.empty?

            @output_dir = File.expand_path(output_dir)
            @top = top.to_s
            @keep_workspace = keep_workspace
            @workspace_dir = workspace_dir && File.expand_path(workspace_dir)
            @clean_output = clean_output
            @import_strategy = normalize_import_strategy(import_strategy)
            @fallback_to_stubbed = fallback_to_stubbed
            @maintain_directory_structure = maintain_directory_structure
            @patch_profiles = normalize_patch_profiles(
              patch_profile: patch_profile,
              patch_profiles: patch_profiles
            )
            @patches_dir = normalize_patches_dir(patches_dir)
            @format_output = format_output
            @strict = strict
            @progress_callback = progress
          end

          def run
            diagnostics = []
            command_log = []
            temp_workspace = nil
            prepared = nil

            emit_progress('validate source and toolchain')
            unless File.exist?(source_path)
              diagnostics << "Source file not found: #{source_path}"
              return failed_result(diagnostics: diagnostics, command_log: command_log)
            end

            [RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL, 'circt-opt'].each do |tool|
              next if tool_available?(tool)

              diagnostics << "Required tool not found: #{tool}"
            end
            return failed_result(diagnostics: diagnostics, command_log: command_log) unless diagnostics.empty?

            workspace = workspace_dir || Dir.mktmpdir('rhdl_ao486_import')
            temp_workspace = workspace if workspace_dir.nil?
            emit_progress("workspace ready: #{workspace}")

            source_prep = prepare_import_source_tree(
              workspace,
              diagnostics: diagnostics,
              command_log: command_log
            )
            unless source_prep[:success]
              return failed_result(
                diagnostics: diagnostics,
                command_log: command_log,
                workspace: workspace
              )
            end

            attempts = strategy_attempts
            strategy_used = nil
            attempts.each_with_index do |strategy, idx|
              emit_progress("strategy '#{strategy}': prepare + import")
              if strategy == :tree
                tree_attempt = run_tree_strategy_attempt(workspace, diagnostics: diagnostics, command_log: command_log)
                prepared = tree_attempt[:prepared]
                pipeline = tree_attempt[:pipeline]
              else
                prepared = prepare_workspace(workspace, strategy: strategy)
                pipeline = run_import_pipeline(prepared, diagnostics: diagnostics, command_log: command_log)
              end

              if pipeline[:success]
                strategy_used = strategy
                break
              end

              next_strategy = attempts[idx + 1]
              if next_strategy
                diagnostics << "AO486 import strategy '#{strategy}' failed; retrying with '#{next_strategy}'"
                emit_progress("strategy '#{strategy}' failed; retry '#{next_strategy}'")
                next
              end

              return failed_result(
                diagnostics: diagnostics,
                command_log: command_log,
                workspace: workspace,
                moore_mlir_path: prepared[:moore_mlir_path],
                core_mlir_path: prepared[:core_mlir_path],
                normalized_core_mlir_path: prepared[:normalized_core_mlir_path],
                strategy_requested: import_strategy,
                strategy_used: strategy,
                attempted_strategies: attempts,
                fallback_used: strategy != import_strategy,
                stub_modules: prepared[:stub_modules],
                closure_modules: prepared[:closure_modules],
                module_files_by_name: prepared[:module_files_by_name],
                staged_module_files_by_name: prepared[:staged_module_files_by_name],
                module_source_relpaths: prepared[:module_source_relpaths],
                include_dirs: prepared[:include_dirs],
                staged_include_dirs: prepared[:staged_include_dirs]
              )
            end

            raise "AO486 import strategy loop failed unexpectedly" unless strategy_used

            emit_progress("strategy '#{strategy_used}': normalize core MLIR")
            normalized_core_mlir = normalize_core_mlir_text(
              File.read(prepared[:core_mlir_path]),
              diagnostics: diagnostics
            )
            File.write(prepared[:normalized_core_mlir_path], normalized_core_mlir)
            emit_artifact_size_progress('normalized core MLIR', prepared[:normalized_core_mlir_path])

            FileUtils.mkdir_p(output_dir)
            emit_progress("clean output directory: #{output_dir}") if clean_output
            clean_output_dir! if clean_output

            emit_progress("raise CIRCT -> RHDL: #{output_dir}")
            raise_result = RHDL::Codegen.raise_circt(
              normalized_core_mlir,
              out_dir: output_dir,
              top: top,
              strict: strict,
              format: false
            )
            format_result = if format_output
                              emit_progress("format RHDL output directory: #{output_dir}")
                              RHDL::Codegen.format_raised_dsl(output_dir)
                            else
                              emit_progress('skip formatting raised RHDL output')
                              FormatResult.new(success: true, diagnostics: [])
                            end

            files_written = raise_result.files_written
            if maintain_directory_structure
              emit_progress('remap output to source directory layout')
              files_written = remap_output_layout(
                files_written: files_written,
                module_source_relpaths: prepared[:module_source_relpaths],
                diagnostics: diagnostics
              )
            end
            emit_output_package_progress(files_written)

            raise_diagnostics = Array(raise_result.diagnostics) + Array(format_result.diagnostics)
            success = raise_result.success? && format_result.success?
            Result.new(
              success: success,
              output_dir: output_dir,
              files_written: files_written,
              workspace: workspace,
              moore_mlir_path: prepared[:moore_mlir_path],
              core_mlir_path: prepared[:core_mlir_path],
              normalized_core_mlir_path: prepared[:normalized_core_mlir_path],
              command_log: command_log,
              diagnostics: diagnostics,
              raise_diagnostics: raise_diagnostics,
              strategy_requested: import_strategy,
              strategy_used: strategy_used,
              fallback_used: strategy_used != import_strategy,
              attempted_strategies: attempts,
              stub_modules: prepared[:stub_modules],
              closure_modules: prepared[:closure_modules],
              module_files_by_name: prepared[:module_files_by_name],
              staged_module_files_by_name: prepared[:staged_module_files_by_name],
              module_source_relpaths: prepared[:module_source_relpaths],
              include_dirs: prepared[:include_dirs],
              staged_include_dirs: prepared[:staged_include_dirs]
            )
          ensure
            FileUtils.rm_rf(temp_workspace) if temp_workspace && !keep_workspace
          end

          private

          def failed_result(diagnostics:, command_log:, workspace: nil, moore_mlir_path: nil, core_mlir_path: nil,
                            normalized_core_mlir_path: nil, strategy_requested: import_strategy, strategy_used: nil,
                            fallback_used: false, attempted_strategies: strategy_attempts, stub_modules: [],
                            closure_modules: [], module_files_by_name: {}, staged_module_files_by_name: {},
                            module_source_relpaths: {}, include_dirs: [], staged_include_dirs: [])
            Result.new(
              success: false,
              output_dir: output_dir,
              files_written: [],
              workspace: workspace,
              moore_mlir_path: moore_mlir_path,
              core_mlir_path: core_mlir_path,
              normalized_core_mlir_path: normalized_core_mlir_path,
              command_log: command_log,
              diagnostics: diagnostics,
              raise_diagnostics: [],
              strategy_requested: strategy_requested,
              strategy_used: strategy_used,
              fallback_used: fallback_used,
              attempted_strategies: attempted_strategies,
              stub_modules: stub_modules,
              closure_modules: closure_modules,
              module_files_by_name: module_files_by_name,
              staged_module_files_by_name: staged_module_files_by_name,
              module_source_relpaths: module_source_relpaths,
              include_dirs: include_dirs,
              staged_include_dirs: staged_include_dirs
            )
          end

          def strategy_attempts
            attempts = [import_strategy]
            if import_strategy == :tree && fallback_to_stubbed
              attempts << :stubbed
            end
            attempts.uniq
          end

          def run_tree_strategy_attempt(workspace, diagnostics:, command_log:)
            forced_stub_modules = TREE_FORCE_STUB_MODULES.dup
            retries = 0
            prepared = nil
            pipeline = nil

            loop do
              emit_progress("tree attempt #{retries + 1}: stage tree inputs")
              prepared = prepare_workspace(
                workspace,
                strategy: :tree,
                force_stub_modules: forced_stub_modules
              )
              pipeline = run_import_pipeline(prepared, diagnostics: diagnostics, command_log: command_log)
              break if pipeline[:success]

              break unless pipeline[:stage] == :import

              if retries >= TREE_MAX_AUTO_STUB_RETRIES
                diagnostics << "AO486 tree import retry limit reached (#{TREE_MAX_AUTO_STUB_RETRIES})"
                break
              end

              inferred = infer_tree_stub_modules_from_errors(
                stderr: pipeline[:stderr],
                workspace: workspace,
                current_stub_modules: forced_stub_modules
              )
              break if inferred.empty?

              retries += 1
              forced_stub_modules.concat(inferred).uniq!
              diagnostics << "AO486 tree import retry #{retries}: forcing stubs for #{inferred.sort.join(', ')}"
              emit_progress("tree retry #{retries}: force stubs #{inferred.sort.join(', ')}")
            end

            {
              prepared: prepared,
              pipeline: pipeline
            }
          end

          def infer_tree_stub_modules_from_errors(stderr:, workspace:, current_stub_modules:)
            error_files = stderr.to_s.lines.filter_map do |line|
              match = line.match(/^([^:\s][^:]*\.(?:v|sv)):\d+:\d+:\s+error:/)
              next unless match

              raw = match[1]
              candidate = if raw.start_with?('/')
                            raw
                          else
                            File.expand_path(raw, workspace)
                          end
              next unless File.file?(candidate)

              candidate
            end

            error_files.uniq.flat_map do |path|
              extract_defined_modules(File.read(path))
            end.reject do |module_name|
              module_name == top || current_stub_modules.include?(module_name)
            end.uniq
          end

          def prepare_workspace(workspace, strategy:, force_stub_modules: TREE_FORCE_STUB_MODULES)
            FileUtils.mkdir_p(workspace)
            force_stub_modules = Array(force_stub_modules).map(&:to_s).uniq
            current_source_root = import_source_search_root
            current_source_path = import_source_path

            basename = artifact_basename
            staged_system_path = File.join(workspace, "#{basename}.v")
            stub_path = File.join(workspace, "stubs.#{strategy}.v")
            wrapper_path = File.join(workspace, "import_all.#{strategy}.sv")
            moore_mlir_path = File.join(workspace, "#{basename}.#{strategy}.moore.mlir")
            core_mlir_path = File.join(workspace, "#{basename}.#{strategy}.core.mlir")
            normalized_core_mlir_path = File.join(workspace, "#{basename}.#{strategy}.normalized.core.mlir")

            FileUtils.cp(current_source_path, staged_system_path)
            normalize_staged_source!(staged_system_path)

            include_paths = [staged_system_path]
            stub_ports = {}
            module_to_file, = build_module_index(current_source_root)
            module_source_relpaths = module_to_file.transform_values { |path| source_relative_path(path) }

            if strategy == :tree
              tree_module_files = stage_tree_module_files(workspace, force_stub_modules: force_stub_modules)
              include_paths.concat(tree_module_files)
            end

            include_paths.each do |path|
              merge_stub_ports!(stub_ports, extract_stub_ports(File.read(path)))
            end

            if strategy == :tree
              include_paths.reject! do |path|
                modules_in_file = extract_defined_modules(File.read(path))
                !(modules_in_file & force_stub_modules).empty?
              end
              force_stub_modules.each { |name| stub_ports[name] ||= { ports: [], params: [] } }
            end

            defined = include_paths.flat_map { |file| extract_defined_modules(File.read(file)) }.uniq
            stub_ports = stub_ports.reject { |module_name, _ports| defined.include?(module_name) }

            metadata = prepared_metadata(
              source_root: current_source_root,
              staged_source_path: staged_system_path,
              workspace: workspace,
              include_paths: include_paths,
              module_source_relpaths: module_source_relpaths
            )

            write_stub_file(stub_path, stub_ports)
            write_wrapper_file(wrapper_path, include_paths: include_paths, stub_path: stub_path)

            {
              strategy: strategy,
              staged_system_path: staged_system_path,
              stub_path: stub_path,
              wrapper_path: wrapper_path,
              include_paths: include_paths.freeze,
              moore_mlir_path: moore_mlir_path,
              core_mlir_path: core_mlir_path,
              normalized_core_mlir_path: normalized_core_mlir_path,
              stub_modules: stub_ports.keys.sort,
              module_source_relpaths: module_source_relpaths,
              command_chdir: (strategy == :tree ? workspace : nil)
            }.merge(metadata).tap do |prepared|
              emit_prepared_package_progress(prepared)
            end
          end

          def prepared_metadata(source_root:, staged_source_path:, workspace:, include_paths:, module_source_relpaths:)
            original_module_to_file, = build_module_index(source_root)
            original_module_to_file = original_module_to_file.dup
            original_module_to_file[top] ||= source_path if File.file?(source_path)

            staged_module_to_file = {}
            stage_root = File.join(workspace, 'tree')
            if Dir.exist?(stage_root)
              staged_module_to_file, = build_module_index(stage_root)
            end
            staged_module_to_file[top] = staged_source_path if File.file?(staged_source_path)

            closure_modules = include_paths.flat_map { |path| extract_defined_modules(File.read(path)) }.uniq.sort.freeze

            {
              closure_modules: closure_modules,
              module_files_by_name: closure_modules.each_with_object({}) do |module_name, acc|
                path = original_module_to_file[module_name]
                acc[module_name] = path if path
              end.freeze,
              staged_module_files_by_name: closure_modules.each_with_object({}) do |module_name, acc|
                path = staged_module_to_file[module_name]
                acc[module_name] = path if path
              end.freeze,
              include_dirs: import_include_dirs_for_source_root(source_root),
              staged_include_dirs: staged_import_include_dirs(workspace)
            }
          end

          def import_include_dirs_for_source_root(source_root)
            dirs = [source_root]
            helper_root = helper_include_source_root(source_root)
            dirs << helper_root if Dir.exist?(helper_root)
            dirs.map { |dir| File.expand_path(dir) }.uniq.select { |dir| Dir.exist?(dir) }.freeze
          end

          def staged_import_include_dirs(workspace)
            stage_root = File.join(workspace, 'tree')
            dirs = [workspace]
            dirs << stage_root if Dir.exist?(stage_root)
            helper_root = helper_include_source_root(stage_root)
            dirs << helper_root if Dir.exist?(helper_root)
            dirs.map { |dir| File.expand_path(dir) }.uniq.select { |dir| Dir.exist?(dir) }.freeze
          end

          def run_import_pipeline(prepared, diagnostics:, command_log:)
            emit_progress("run #{circt_verilog_import_command_string(prepared[:wrapper_path])} -> #{File.basename(prepared[:moore_mlir_path])}")
            import_result = RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
              verilog_path: prepared[:wrapper_path],
              out_path: prepared[:moore_mlir_path],
              tool: RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL,
              extra_args: circt_verilog_import_extra_args
            )
            command_log << import_result[:command]
            append_diagnostics(diagnostics, import_result[:stderr], max_lines: 60)
            return { success: false, stage: :import, stderr: import_result[:stderr] } unless import_result[:success]
            emit_artifact_size_progress('moore MLIR', prepared[:moore_mlir_path])

            imported_text = File.read(prepared[:moore_mlir_path])
            if imported_text.include?('moore.module')
              lower_cmd = [
                'circt-opt',
                '--moore-lower-concatref',
                '--canonicalize',
                '--moore-lower-concatref',
                '--convert-moore-to-core',
                '--llhd-sig2reg',
                '--canonicalize',
                prepared[:moore_mlir_path],
                '-o',
                prepared[:core_mlir_path]
              ]
              emit_progress("run circt-opt -> #{File.basename(prepared[:core_mlir_path])}")
              lower_result = run_command(lower_cmd, chdir: prepared[:command_chdir])
              command_log << lower_result[:command]
              append_diagnostics(diagnostics, lower_result[:stderr], max_lines: 60)
              return { success: false, stage: :lower, stderr: lower_result[:stderr] } unless lower_result[:success]
              emit_artifact_size_progress('core MLIR', prepared[:core_mlir_path])
            else
              FileUtils.cp(prepared[:moore_mlir_path], prepared[:core_mlir_path])
              emit_artifact_size_progress('core MLIR', prepared[:core_mlir_path])
            end

            emit_progress('import pipeline complete')
            { success: true, stage: :done }
          end

          def circt_verilog_import_command_string(verilog_path)
            RHDL::Codegen::CIRCT::Tooling.circt_verilog_import_command_string(
              verilog_path: verilog_path,
              extra_args: circt_verilog_import_extra_args
            )
          end

          def circt_verilog_import_extra_args
            current_top = top.to_s.strip
            raise ArgumentError, 'AO486 SystemImporter requires a non-empty top for circt-verilog import' if current_top.empty?

            ["--top=#{current_top}"]
          end

          def normalize_system_source!(path)
            lines = File.readlines(path)

            unless lines.any? { |line| line.match?(/^\s*`timescale\b/) }
              lines.unshift("`timescale 1ns/1ps\n")
            end

            moved = []
            remaining = []
            lines.each do |line|
              if LATE_REG_DECLARATIONS.any? { |name| line.match?(/^\s*reg\s+#{Regexp.escape(name)}\s*=\s*0\s*;\s*$/) }
                moved << line
              else
                remaining << line
              end
            end

            return if moved.empty?

            insert_idx = remaining.index { |line| line.match?(/^\s*reg\s+sysctl_cs\s*;\s*$/) }
            insert_idx ||= remaining.index { |line| line.match?(/^\s*reg\b/) }
            insert_idx = insert_idx ? insert_idx + 1 : 0
            remaining.insert(insert_idx, *moved)

            File.write(path, remaining.join)
          end

          def normalize_staged_source!(path)
            normalize_system_source!(path)
          end

          def extract_stub_ports(source)
            stub_ports = Hash.new { |h, k| h[k] = { ports: [], params: [] } }
            each_instance(source) do |module_name, ports_body, params_body|
              ports = ports_body.scan(/\.([A-Za-z_][A-Za-z0-9_$]*)\s*\(/).flatten
              params = params_body ? params_body.scan(/\.([A-Za-z_][A-Za-z0-9_$]*)\s*\(/).flatten : []
              stub_ports[module_name][:ports].concat(ports)
              stub_ports[module_name][:params].concat(params)
            end

            stub_ports.transform_values! do |entry|
              {
                ports: entry[:ports].uniq,
                params: entry[:params].uniq
              }
            end
            stub_ports
          end

          def extract_defined_modules(source)
            source.scan(/(^|\n)\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)\b/m).map { |m| m[1] }.uniq
          end

          def discover_tree_module_files(force_stub_modules:)
            root = import_source_search_root
            module_to_file, module_to_body = build_module_index(root)
            force_stub_modules = Array(force_stub_modules).map(&:to_s).uniq

            needed_files = []
            seen_modules = {}
            queue = [top]

            until queue.empty?
              module_name = queue.shift
              next if seen_modules[module_name]

              seen_modules[module_name] = true
              next if force_stub_modules.include?(module_name) && module_name != top

              file = module_to_file[module_name]
              body = module_to_body[module_name]
              needed_files << file if file
              next unless body

              extract_instantiated_modules(body).each do |child|
                queue << child if module_to_body.key?(child) && !seen_modules[child]
              end
            end

            source_expanded = File.expand_path(import_source_path)
            needed_files.compact.uniq.sort.reject { |path| File.expand_path(path) == source_expanded }
          end

          def build_module_index(root)
            module_to_file = {}
            module_to_body = {}

            Dir.glob(File.join(root, '**', '*.{v,sv}')).sort.each do |path|
              source = File.read(path)
              source.scan(/(^|\n)\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)\b(.*?)^\s*endmodule\b/m) do |_prefix, mod, body|
                module_to_file[mod] ||= path
                module_to_body[mod] ||= body
              end
            end

            [module_to_file, module_to_body]
          end

          def extract_instantiated_modules(source)
            modules = []
            each_instance(source) do |module_name, _ports_body, _params_body|
              modules << module_name
            end

            modules.uniq
          end

          def each_instance(source)
            pattern = /(^|\n)\s*([A-Za-z_][A-Za-z0-9_$]*)\b/m
            idx = 0

            while (match = pattern.match(source, idx))
              module_name = match[2]
              idx = match.end(0)
              next if INSTANCE_KEYWORDS.include?(module_name)

              cursor = skip_whitespace(source, idx)
              params_body = nil
              if source[cursor] == '#'
                cursor += 1
                cursor = skip_whitespace(source, cursor)
                next unless source[cursor] == '('

                param_close = find_matching_paren(source, cursor)
                next unless param_close

                params_body = source[(cursor + 1)...param_close]
                cursor = skip_whitespace(source, param_close + 1)
              end

              inst_name, inst_end = read_identifier(source, cursor)
              next unless inst_name

              cursor = skip_whitespace(source, inst_end)
              next unless source[cursor] == '('

              open_idx = cursor
              close_idx = find_instance_close(source, open_idx)
              next unless close_idx

              ports_body = source[(open_idx + 1)...close_idx]
              yield module_name, ports_body, params_body

              idx = close_idx + 2
            end
          end

          def skip_whitespace(source, idx)
            i = idx
            i += 1 while i < source.length && source[i].match?(/\s/)
            i
          end

          def read_identifier(source, idx)
            return [nil, idx] unless idx < source.length && source[idx].match?(/[A-Za-z_]/)

            i = idx + 1
            i += 1 while i < source.length && source[i].match?(/[A-Za-z0-9_$]/)
            [source[idx...i], i]
          end

          def find_matching_paren(source, open_idx)
            depth = 0
            idx = open_idx

            while idx < source.length
              char = source[idx]
              depth += 1 if char == '('
              depth -= 1 if char == ')'
              return idx if depth.zero?

              idx += 1
            end

            nil
          end

          def merge_stub_ports!(target, addition)
            addition.each do |module_name, entry|
              target[module_name] ||= { ports: [], params: [] }
              target[module_name][:ports].concat(entry[:ports])
              target[module_name][:params].concat(entry[:params])
              target[module_name][:ports].uniq!
              target[module_name][:params].uniq!
            end
          end

          def stage_tree_module_files(workspace, force_stub_modules:)
            root = import_source_search_root
            stage_root = File.join(workspace, 'tree')

            staged = discover_tree_module_files(force_stub_modules: force_stub_modules).map do |src|
              relative = src.delete_prefix("#{root}/")
              dst = File.join(stage_root, relative)
              FileUtils.mkdir_p(File.dirname(dst))
              File.write(dst, normalize_tree_source(
                File.read(src),
                stage_root: stage_root
              ))
              dst
            end

            stage_tree_include_helpers(root, workspace, stage_root)
            staged
          end

          def stage_tree_include_helpers(source_root, workspace, stage_root)
            ao486_root = helper_include_source_root(source_root)
            return unless Dir.exist?(ao486_root)

            {
              'defines.v' => File.join(ao486_root, 'defines.v'),
              'startup_default.v' => File.join(ao486_root, 'startup_default.v')
            }.each do |target_name, src|
              next unless File.file?(src)

              FileUtils.cp(src, File.join(workspace, target_name))

              staged_ao486 = File.join(stage_root, 'ao486')
              FileUtils.mkdir_p(staged_ao486)
              FileUtils.cp(src, File.join(staged_ao486, target_name))
            end

            autogen_src = File.join(ao486_root, 'autogen')
            autogen_dst = File.join(workspace, 'autogen')
            staged_autogen_dst = File.join(stage_root, 'ao486', 'autogen')
            return unless Dir.exist?(autogen_src)

            FileUtils.rm_rf(autogen_dst) if File.exist?(autogen_dst)
            FileUtils.cp_r(autogen_src, autogen_dst)

            FileUtils.rm_rf(staged_autogen_dst) if File.exist?(staged_autogen_dst)
            FileUtils.cp_r(autogen_src, staged_autogen_dst)
          end

          def normalize_tree_source(source, stage_root:)
            ao486_stage = File.join(stage_root, 'ao486')
            defines_path = File.join(ao486_stage, 'defines.v')
            startup_path = File.join(ao486_stage, 'startup_default.v')
            autogen_root = File.join(ao486_stage, 'autogen')

            normalized = source.dup
            normalized.gsub!(/`include\s+"defines\.v"/, "`include \"#{defines_path}\"")
            normalized.gsub!(/`include\s+"startup_default\.v"/, "`include \"#{startup_path}\"")
            normalized.gsub!(/`include\s+"autogen\/([^"]+)"/) do
              "`include \"#{File.join(autogen_root, Regexp.last_match(1))}\""
            end

            return normalized if normalized.match?(/^\s*`timescale\b/m)

            "`timescale 1ns/1ps\n#{normalized}"
          end

          def find_instance_close(source, open_idx)
            depth = 0
            idx = open_idx

            while idx < source.length
              char = source[idx]
              depth += 1 if char == '('
              depth -= 1 if char == ')'

              if depth.zero?
                return idx if source[idx + 1] == ';'
                return nil
              end

              idx += 1
            end

            nil
          end

          def write_stub_file(path, stub_ports)
            File.open(path, 'w') do |f|
              stub_ports.keys.sort.each do |module_name|
                entry = stub_ports[module_name]
                ports = entry[:ports]
                params = entry[:params]

                if params.empty?
                  f.puts "module #{module_name}(#{ports.join(', ')});"
                else
                  f.puts "module #{module_name}#("
                  params.each_with_index do |param, idx|
                    comma = idx == params.length - 1 ? '' : ','
                    f.puts "  parameter #{param} = 0#{comma}"
                  end
                  f.puts ")(#{ports.join(', ')});"
                end

                ports.each { |port| f.puts "  input #{port};" }
                f.puts 'endmodule'
                f.puts
              end
            end
          end

          def write_wrapper_file(path, include_paths:, stub_path:)
            File.open(path, 'w') do |f|
              include_paths.each { |source| f.puts "`include \"#{source}\"" }
              f.puts "`include \"#{stub_path}\""
            end
          end

          def normalize_import_strategy(value)
            symbol = value.to_sym
            return symbol if VALID_IMPORT_STRATEGIES.include?(symbol)

            raise ArgumentError,
                  "Unknown AO486 import strategy: #{value.inspect}. Expected one of: #{VALID_IMPORT_STRATEGIES.join(', ')}"
          end

          def append_diagnostics(diagnostics, text, max_lines:)
            lines = text.to_s.lines.map(&:strip).reject(&:empty?)
            return if lines.empty?

            if max_lines && lines.length > max_lines
              diagnostics.concat(lines.first(max_lines))
              diagnostics << "... #{lines.length - max_lines} additional diagnostic lines omitted ..."
            else
              diagnostics.concat(lines)
            end
          end

          def normalize_core_mlir_text(text, diagnostics:)
            normalize_core_mlir(text)
          end

          def normalize_core_mlir(text)
            text.gsub(/\bhw\.module\s+private\s+@/, 'hw.module @')
          end

          def clean_output_dir!
            Dir.children(output_dir).each do |entry|
              FileUtils.rm_rf(File.join(output_dir, entry))
            end
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
                source_path
              else
                rel_dir = dirs.sort.first
                if dirs.length > 1
                  diagnostics << "AO486 layout ambiguous for #{basename}: #{dirs.sort.join(', ')}; using #{rel_dir}"
                end

                destination_dir = File.join(output_dir, rel_dir)
                FileUtils.mkdir_p(destination_dir)
                destination_path = File.join(destination_dir, basename)
                if File.expand_path(source_path) != File.expand_path(destination_path)
                  FileUtils.rm_f(destination_path)
                  FileUtils.mv(source_path, destination_path)
                end
                destination_path
              end
            end
          end

          def source_relative_path(path)
            root = File.expand_path(import_source_search_root)
            absolute = File.expand_path(path)
            prefix = "#{root}/"
            return absolute.delete_prefix(prefix) if absolute.start_with?(prefix)

            File.basename(absolute)
          end

          def artifact_basename
            top.to_s
          end

          def import_source_path
            @prepared_source_path || source_path
          end

          def import_source_search_root
            @prepared_source_search_root || source_search_root
          end

          def source_search_root
            source_root
          end

          def source_root
            File.expand_path(File.dirname(source_path))
          end

          def prepare_import_source_tree(workspace, diagnostics:, command_log:)
            @prepared_source_search_root = source_search_root
            @prepared_source_path = source_path
            patch_roots = resolved_patch_roots
            return { success: true, patch_files: [] } if patch_roots.empty?

            unless tool_available?('git')
              diagnostics << 'Required tool not found: git'
              return { success: false, patch_files: [] }
            end

            staged_root = File.join(workspace, 'patched_source')
            copy_directory_contents(source_search_root, staged_root)

            patch_files = patch_roots.flat_map { |root| patch_series_files(root) }
            relative_source_path = path_relative_to_root(source_path, source_search_root)

            patch_files.each do |patch_path|
              emit_progress("apply patch #{File.basename(patch_path)}")

              check_cmd = ['git', 'apply', '--check', patch_path]
              check_result = run_command(check_cmd, chdir: staged_root)
              command_log << check_result[:command]
              append_diagnostics(diagnostics, check_result[:stderr], max_lines: 60)
              return { success: false, patch_files: patch_files } unless check_result[:success]

              apply_cmd = ['git', 'apply', patch_path]
              apply_result = run_command(apply_cmd, chdir: staged_root)
              command_log << apply_result[:command]
              append_diagnostics(diagnostics, apply_result[:stderr], max_lines: 60)
              return { success: false, patch_files: patch_files } unless apply_result[:success]
            end

            @prepared_source_search_root = staged_root
            @prepared_source_path = File.join(staged_root, relative_source_path)

            { success: true, patch_files: patch_files }
          end

          def patch_series_files(root)
            Dir.glob(File.join(root, '**', '*'))
               .select { |path| File.file?(path) && %w[.patch .diff].include?(File.extname(path)) }
               .sort
          end

          def copy_directory_contents(source_dir, destination_dir)
            FileUtils.rm_rf(destination_dir) if File.exist?(destination_dir)
            FileUtils.mkdir_p(destination_dir)
            Dir.children(source_dir).sort.each do |entry|
              FileUtils.cp_r(File.join(source_dir, entry), destination_dir)
            end
          end

          def path_relative_to_root(path, root)
            expanded_path = File.expand_path(path)
            expanded_root = File.expand_path(root)
            prefix = "#{expanded_root}/"
            return expanded_path.delete_prefix(prefix) if expanded_path.start_with?(prefix)

            File.basename(expanded_path)
          end

          def normalize_patches_dir(value)
            return nil if value.nil? || value.to_s.strip.empty?

            expanded = File.expand_path(value)
            raise ArgumentError, "patches_dir not found: #{expanded}" unless Dir.exist?(expanded)

            expanded
          end

          def normalize_patch_profiles(patch_profile:, patch_profiles:)
            profiles = []
            profiles << patch_profile unless patch_profile.nil?
            profiles.concat(Array(patch_profiles))
            profiles = profiles.flatten.compact.map { |entry| entry.to_s.strip }.reject(&:empty?)
            profiles.each { |name| resolve_patch_profile_dir(name) }
            profiles.freeze
          end

          def resolved_patch_roots
            roots = patch_profiles.map { |name| resolve_patch_profile_dir(name) }
            roots << patches_dir if patches_dir
            roots
          end

          def resolve_patch_profile_dir(profile_name)
            path = File.join(ao486_patches_root, profile_name.to_s)
            expanded = File.expand_path(path)
            raise ArgumentError, "AO486 patch profile not found: #{profile_name} (#{expanded})" unless Dir.exist?(expanded)

            expanded
          end

          def ao486_patches_root
            DEFAULT_PATCHES_ROOT
          end

          def helper_include_source_root(root)
            ao486_root = File.join(root, 'ao486')
            return ao486_root if Dir.exist?(ao486_root)
            return root if File.file?(File.join(root, 'defines.v'))

            ao486_root
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

          def run_command(cmd, chdir: nil)
            env = git_command?(cmd) ? {
              'GIT_CONFIG_GLOBAL' => '/dev/null',
              'GIT_CONFIG_NOSYSTEM' => '1'
            } : {}
            stdout, stderr, status = if chdir
              Open3.capture3(env, *cmd, chdir: chdir)
            else
              Open3.capture3(env, *cmd)
            end
            {
              success: status.success?,
              stdout: stdout,
              stderr: stderr,
              status: status.exitstatus,
              command: cmd.map { |arg| Shellwords.escape(arg.to_s) }.join(' ')
            }
          end

          def git_command?(cmd)
            Array(cmd).first.to_s == 'git'
          end

          def tool_available?(cmd)
            return HdlToolchain.which(cmd) if defined?(HdlToolchain) && HdlToolchain.respond_to?(:which)

            ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
              exe = File.join(path, cmd)
              File.executable?(exe) && !File.directory?(exe)
            end
          end

          def emit_progress(message)
            return unless progress_callback.respond_to?(:call)

            progress_callback.call(message)
          end

          def emit_prepared_package_progress(prepared)
            stats = package_file_stats(
              [
                prepared[:wrapper_path],
                prepared[:stub_path],
                *Array(prepared[:include_paths])
              ]
            )
            emit_progress("staged pure Verilog package files=#{stats[:file_count]} size=#{format_byte_size(stats[:bytes])}")
          end

          def emit_artifact_size_progress(label, path)
            return unless path && File.file?(path)

            emit_progress("#{label} #{File.basename(path)} size=#{format_byte_size(File.size(path))}")
          end

          def emit_output_package_progress(files_written)
            stats = package_file_stats(Array(files_written))
            emit_progress("raised RHDL package files=#{stats[:file_count]} size=#{format_byte_size(stats[:bytes])}")
          end

          def package_file_stats(paths)
            files = Array(paths).compact.map { |path| File.expand_path(path) }.uniq.select { |path| File.file?(path) }
            {
              file_count: files.length,
              bytes: files.sum { |path| File.size(path) }
            }
          end

          def format_byte_size(bytes)
            value = bytes.to_i
            return '0 B' if value <= 0

            units = ['B', 'KiB', 'MiB', 'GiB'].freeze
            size = value.to_f
            unit_index = 0
            while size >= 1024.0 && unit_index < units.length - 1
              size /= 1024.0
              unit_index += 1
            end

            return "#{size.round} #{units[unit_index]}" if unit_index.zero?

            format('%.1f %s', size, units[unit_index])
          end
        end
      end
    end
  end
end
