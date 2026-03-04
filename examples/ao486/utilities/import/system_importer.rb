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
            keyword_init: true
          ) do
            def success?
              !!success
            end
          end

          attr_reader :source_path, :output_dir, :top, :keep_workspace, :workspace_dir, :clean_output,
                      :import_strategy, :fallback_to_stubbed, :maintain_directory_structure, :strict

          def initialize(source_path: DEFAULT_SOURCE_PATH,
                         output_dir:,
                         top: DEFAULT_TOP,
                         keep_workspace: false,
                         workspace_dir: nil,
                         clean_output: true,
                         import_strategy: DEFAULT_IMPORT_STRATEGY,
                         fallback_to_stubbed: true,
                         maintain_directory_structure: true,
                         strict: true)
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
            @strict = strict
          end

          def run
            diagnostics = []
            command_log = []
            temp_workspace = nil
            prepared = nil

            unless File.exist?(source_path)
              diagnostics << "Source file not found: #{source_path}"
              return failed_result(diagnostics: diagnostics, command_log: command_log)
            end

            %w[circt-translate circt-opt].each do |tool|
              next if tool_available?(tool)

              diagnostics << "Required tool not found: #{tool}"
            end
            return failed_result(diagnostics: diagnostics, command_log: command_log) unless diagnostics.empty?

            workspace = workspace_dir || Dir.mktmpdir('rhdl_ao486_import')
            temp_workspace = workspace if workspace_dir.nil?

            attempts = strategy_attempts
            strategy_used = nil
            attempts.each_with_index do |strategy, idx|
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
                stub_modules: prepared[:stub_modules]
              )
            end

            raise "AO486 import strategy loop failed unexpectedly" unless strategy_used

            normalized_core_mlir = normalize_core_mlir(File.read(prepared[:core_mlir_path]))
            File.write(prepared[:normalized_core_mlir_path], normalized_core_mlir)

            FileUtils.mkdir_p(output_dir)
            clean_output_dir! if clean_output

            raise_result = RHDL::Codegen.raise_circt(
              normalized_core_mlir,
              out_dir: output_dir,
              top: top,
              strict: strict,
              format: true
            )
            files_written = raise_result.files_written
            if maintain_directory_structure
              files_written = remap_output_layout(
                files_written: files_written,
                module_source_relpaths: prepared[:module_source_relpaths],
                diagnostics: diagnostics
              )
            end

            success = raise_result.success?
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
              raise_diagnostics: raise_result.diagnostics,
              strategy_requested: import_strategy,
              strategy_used: strategy_used,
              fallback_used: strategy_used != import_strategy,
              attempted_strategies: attempts,
              stub_modules: prepared[:stub_modules]
            )
          ensure
            FileUtils.rm_rf(temp_workspace) if temp_workspace && !keep_workspace
          end

          private

          def failed_result(diagnostics:, command_log:, workspace: nil, moore_mlir_path: nil, core_mlir_path: nil,
                            normalized_core_mlir_path: nil, strategy_requested: import_strategy, strategy_used: nil,
                            fallback_used: false, attempted_strategies: strategy_attempts, stub_modules: [])
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
              stub_modules: stub_modules
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

            staged_system_path = File.join(workspace, 'system.v')
            stub_path = File.join(workspace, "stubs.#{strategy}.v")
            wrapper_path = File.join(workspace, "import_all.#{strategy}.sv")
            moore_mlir_path = File.join(workspace, "system.#{strategy}.moore.mlir")
            core_mlir_path = File.join(workspace, "system.#{strategy}.core.mlir")
            normalized_core_mlir_path = File.join(workspace, "system.#{strategy}.normalized.core.mlir")

            FileUtils.cp(source_path, staged_system_path)
            normalize_system_source!(staged_system_path)

            include_paths = [staged_system_path]
            stub_ports = {}
            module_to_file, = build_module_index(File.dirname(source_path))
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

            write_stub_file(stub_path, stub_ports)
            write_wrapper_file(wrapper_path, include_paths: include_paths, stub_path: stub_path)

            {
              strategy: strategy,
              staged_system_path: staged_system_path,
              stub_path: stub_path,
              wrapper_path: wrapper_path,
              moore_mlir_path: moore_mlir_path,
              core_mlir_path: core_mlir_path,
              normalized_core_mlir_path: normalized_core_mlir_path,
              stub_modules: stub_ports.keys.sort,
              module_source_relpaths: module_source_relpaths,
              command_chdir: (strategy == :tree ? workspace : nil)
            }
          end

          def run_import_pipeline(prepared, diagnostics:, command_log:)
            import_cmd = [
              'circt-translate',
              '--import-verilog',
              prepared[:wrapper_path],
              '-o',
              prepared[:moore_mlir_path]
            ]
            import_result = run_command(import_cmd, chdir: prepared[:command_chdir])
            command_log << import_result[:command]
            append_diagnostics(diagnostics, import_result[:stderr], max_lines: 60)
            return { success: false, stage: :import, stderr: import_result[:stderr] } unless import_result[:success]

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
            lower_result = run_command(lower_cmd, chdir: prepared[:command_chdir])
            command_log << lower_result[:command]
            append_diagnostics(diagnostics, lower_result[:stderr], max_lines: 60)
            return { success: false, stage: :lower, stderr: lower_result[:stderr] } unless lower_result[:success]

            { success: true, stage: :done }
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
            root = File.dirname(source_path)
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

            source_expanded = File.expand_path(source_path)
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
            source_root = File.dirname(source_path)
            stage_root = File.join(workspace, 'tree')

            staged = discover_tree_module_files(force_stub_modules: force_stub_modules).map do |src|
              relative = src.delete_prefix("#{source_root}/")
              dst = File.join(stage_root, relative)
              FileUtils.mkdir_p(File.dirname(dst))
              File.write(dst, normalize_tree_source(
                File.read(src),
                stage_root: stage_root
              ))
              dst
            end

            stage_tree_include_helpers(source_root, workspace, stage_root)
            staged
          end

          def stage_tree_include_helpers(source_root, workspace, stage_root)
            ao486_root = File.join(source_root, 'ao486')
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
            root = File.expand_path(File.dirname(source_path))
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

          def run_command(cmd, chdir: nil)
            stdout, stderr, status = if chdir
              Open3.capture3(*cmd, chdir: chdir)
            else
              Open3.capture3(*cmd)
            end
            {
              success: status.success?,
              stdout: stdout,
              stderr: stderr,
              status: status.exitstatus,
              command: cmd.map { |arg| Shellwords.escape(arg.to_s) }.join(' ')
            }
          end

          def tool_available?(cmd)
            return HdlToolchain.which(cmd) if defined?(HdlToolchain) && HdlToolchain.respond_to?(:which)

            ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
              exe = File.join(path, cmd)
              File.executable?(exe) && !File.directory?(exe)
            end
          end
        end
      end
    end
  end
end
