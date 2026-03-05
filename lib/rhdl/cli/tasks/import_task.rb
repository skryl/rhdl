# frozen_string_literal: true

require_relative '../task'
require 'fileutils'
require 'json'
require 'yaml'
require 'pathname'
require 'open3'

module RHDL
  module CLI
    module Tasks
      # Import task for CIRCT-based ingestion flows.
      # Verilog parsing/emission is delegated to external LLVM/CIRCT tooling.
      class ImportTask < Task
        SUPPORTED_MIXED_MANIFEST_EXTENSIONS = %w[.yml .yaml .json].freeze
        VERILOG_EXTENSIONS = %w[.v .sv .vh].freeze
        VHDL_EXTENSIONS = %w[.vhd .vhdl].freeze
        SOURCE_EXTENSIONS = (VERILOG_EXTENSIONS + VHDL_EXTENSIONS).freeze

        def run
          require 'rhdl'

          mode = options[:mode]&.to_sym
          case mode
          when :verilog
            import_verilog
          when :mixed
            import_mixed
          when :circt
            import_circt_mlir
          else
            raise ArgumentError, "Unknown import mode: #{mode.inspect}. Expected :verilog, :mixed, or :circt"
          end
        end

        private

        def import_verilog
          input = fetch_input_path
          out_dir = fetch_out_dir
          ensure_dir(out_dir)

          base = File.basename(input, File.extname(input))
          mlir_out = options[:mlir_out] || File.join(out_dir, "#{base}.mlir")
          tool = options[:tool] || RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL

          puts "Import step: Verilog -> CIRCT MLIR (#{tool})"
          result = RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
            verilog_path: input,
            out_path: mlir_out,
            tool: tool,
            extra_args: Array(options[:tool_args])
          )

          unless result[:success]
            raise RuntimeError,
                  "Verilog->CIRCT conversion failed with '#{tool}'.\nCommand: #{result[:command]}\n#{result[:stderr]}"
          end

          puts "Wrote CIRCT MLIR: #{mlir_out}"
          puts "Command: #{result[:command]}"

          return unless raise_to_dsl?

          run_raise_flow(mlir_out: mlir_out, out_dir: out_dir)
        end

        def import_mixed
          out_dir = fetch_out_dir
          ensure_dir(out_dir)

          puts 'Import step: Mixed source staging'
          staging = build_mixed_import_staging(out_dir: out_dir)
          staged_verilog_path = staging.fetch(:staged_verilog_path)
          resolved_top_name = staging[:top_name]

          base = resolved_top_name || File.basename(staged_verilog_path, File.extname(staged_verilog_path))
          mlir_out = options[:mlir_out] || File.join(out_dir, "#{base}.mlir")
          tool = options[:tool] || RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL
          tool_args = Array(options[:tool_args]) + Array(staging[:tool_args])

          puts "Import step: Verilog -> CIRCT MLIR (#{tool})"
          result = RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
            verilog_path: staged_verilog_path,
            out_path: mlir_out,
            tool: tool,
            extra_args: tool_args
          )

          unless result[:success]
            raise RuntimeError,
                  "Mixed Verilog/VHDL->CIRCT conversion failed with '#{tool}'.\nCommand: #{result[:command]}\n#{result[:stderr]}"
          end

          puts "Wrote CIRCT MLIR: #{mlir_out}"
          puts "Command: #{result[:command]}"

          return unless raise_to_dsl?

          lower_moore_to_core_mlir_if_needed!(mlir_out: mlir_out)
          run_raise_flow(
            mlir_out: mlir_out,
            out_dir: out_dir,
            top_override: resolved_top_name,
            mixed_provenance: staging[:provenance]
          )
        end

        def import_circt_mlir
          input = fetch_input_path
          out_dir = fetch_out_dir
          ensure_dir(out_dir)

          unless raise_to_dsl?
            puts "CIRCT MLIR ready: #{input}"
            return
          end

          run_raise_flow(mlir_out: input, out_dir: out_dir)
        end

        def run_raise_flow(mlir_out:, out_dir:, top_override: nil, mixed_provenance: nil)
          puts 'Import step: Parse/import CIRCT MLIR'
          mlir = File.read(mlir_out)
          strict = options.fetch(:strict, true)
          extern_modules = Array(options[:extern_modules]).map(&:to_s)
          top_name = top_override || options[:top]

          import_result = RHDL::Codegen.import_circt_mlir(
            mlir,
            strict: strict,
            top: top_name,
            extern_modules: extern_modules
          )
          emit_diagnostics(import_result.diagnostics)

          puts 'Import step: Raise CIRCT -> RHDL files'
          raise_result = RHDL::Codegen.raise_circt(
            import_result.modules,
            out_dir: out_dir,
            top: top_name,
            strict: strict,
            format: false
          )
          emit_diagnostics(raise_result.diagnostics)

          puts "Raised #{raise_result.files_written.length} DSL file(s):"
          raise_result.files_written.each { |path| puts "  - #{path}" }

          puts 'Import step: Format RHDL output directory'
          format_result = RHDL::Codegen.format_raised_dsl(out_dir)
          emit_diagnostics(format_result.diagnostics)

          puts 'Import step: Write import report'
          combined_raise_diagnostics = Array(raise_result.diagnostics) + Array(format_result.diagnostics)
          raise_success = raise_result.success? && format_result.success?
          report_path = write_report(
            out_dir: out_dir,
            strict: strict,
            extern_modules: extern_modules,
            top_name: top_name,
            import_result: import_result,
            raise_result: raise_result,
            raise_diagnostics: combined_raise_diagnostics,
            raise_success: raise_success,
            mixed_provenance: mixed_provenance
          )
          puts "Wrote import report: #{report_path}"

          unless import_result.success? && raise_success
            raise RuntimeError, 'CIRCT import/raise completed with errors (partial output written)'
          end
        end

        def emit_diagnostics(diags)
          Array(diags).each do |diag|
            level = diag.severity.to_s.upcase
            op = diag.respond_to?(:op) && diag.op ? " #{diag.op}:" : ''
            puts "[#{level}]#{op} #{diag.message}"
          end
        end

        def write_report(out_dir:, strict:, extern_modules:, top_name:, import_result:, raise_result:, raise_diagnostics: nil,
                         raise_success: nil, mixed_provenance: nil)
          raise_diagnostics ||= Array(raise_result.diagnostics)
          raise_success = raise_result.success? if raise_success.nil?
          path = options[:report] || File.join(out_dir, 'import_report.json')
          report = {
            success: import_result.success? && raise_success,
            strict: strict,
            top: top_name,
            extern_modules: extern_modules,
            module_count: import_result.modules.length,
            op_census: import_result.op_census,
            modules: import_result.modules.map do |mod|
              mod_name = mod.name.to_s
              module_diags = Array(import_result.module_diagnostics.fetch(mod_name, []))
              span = import_result.module_spans[mod_name] || {}
              {
                name: mod_name,
                start_line: span[:start_line],
                end_line: span[:end_line],
                import_errors: module_diags.count { |diag| diag.severity.to_s == 'error' },
                import_warnings: module_diags.count { |diag| diag.severity.to_s == 'warning' },
                import_diagnostics: module_diags.map { |diag| diagnostic_to_hash(diag) }
              }
            end,
            import_diagnostics: Array(import_result.diagnostics).map { |diag| diagnostic_to_hash(diag) },
            raise_diagnostics: Array(raise_diagnostics).map { |diag| diagnostic_to_hash(diag) }
          }
          report[:mixed_import] = mixed_provenance if mixed_provenance

          File.write(path, JSON.pretty_generate(report))
          path
        end

        def diagnostic_to_hash(diag)
          {
            severity: diag.respond_to?(:severity) ? diag.severity.to_s : nil,
            op: diag.respond_to?(:op) ? diag.op : nil,
            message: diag.respond_to?(:message) ? diag.message : diag.to_s,
            line: diag.respond_to?(:line) ? diag.line : nil,
            column: diag.respond_to?(:column) ? diag.column : nil
          }
        end

        def fetch_input_path
          input = options[:input]
          raise ArgumentError, 'Input file is required (--input)' if input.nil? || input.strip.empty?
          raise ArgumentError, "Input file not found: #{input}" unless File.exist?(input)

          input
        end

        def fetch_out_dir
          out_dir = options[:out]
          raise ArgumentError, 'Output directory is required (--out)' if out_dir.nil? || out_dir.strip.empty?

          out_dir
        end

        def raise_to_dsl?
          options.fetch(:raise_to_dsl, true)
        end

        def build_mixed_import_staging(out_dir:)
          config = resolve_mixed_import_config(out_dir: out_dir)
          staging_dir = File.join(out_dir, '.mixed_import')
          generated_dir = File.join(staging_dir, 'generated_vhdl')
          FileUtils.mkdir_p(generated_dir)

          analysis_commands = []
          synth_outputs = []
          generated_verilog_files = []
          vhdl_standard = config.fetch(:vhdl_standard, '08')
          vhdl_workdir = config.fetch(:vhdl_workdir)
          vhdl_analyze_args = Array(config[:vhdl_analyze_args])
          vhdl_synth_args = Array(config[:vhdl_synth_args])
          FileUtils.mkdir_p(vhdl_workdir)

          unless config[:vhdl_files].empty?
            puts "Import step: Analyze VHDL sources (#{config[:vhdl_files].length} file(s))"
            analyze_vhdl_files!(
              vhdl_files: config[:vhdl_files],
              workdir: vhdl_workdir,
              std: vhdl_standard,
              analyze_args: vhdl_analyze_args,
              analysis_commands: analysis_commands
            )

            synth_targets = Array(config[:vhdl_synth_targets])
            synth_targets = mixed_vhdl_synth_targets(config) if synth_targets.empty?
            unless synth_targets.empty?
              puts "Import step: Synthesize VHDL sources to Verilog (#{synth_targets.length} target(s))"
            end

            synth_targets.each do |target|
              out_path = File.join(generated_dir, "#{target.fetch(:entity)}.v")
              synth = RHDL::Codegen::CIRCT::Tooling.ghdl_synth_to_verilog(
                entity: target.fetch(:entity),
                out_path: out_path,
                workdir: vhdl_workdir,
                std: vhdl_standard,
                work: effective_work_library(target[:library]),
                extra_args: vhdl_synth_args
              )
              unless synth[:success]
                raise RuntimeError,
                      "VHDL synth->Verilog failed.\nCommand: #{synth[:command]}\n#{synth[:stderr]}"
              end

              postprocess_generated_vhdl_verilog!(entity: target.fetch(:entity), out_path: out_path)
              generated_verilog_files << out_path
              synth_outputs << {
                entity: target.fetch(:entity),
                library: effective_work_library(target[:library]),
                output_path: out_path,
                command: synth[:command]
              }
            end
          end

          staged_verilog_path = File.join(staging_dir, 'mixed_staged.v')
          source_files = config[:verilog_files].map { |entry| entry.fetch(:path) } + generated_verilog_files
          if source_files.empty?
            raise ArgumentError, 'Mixed import found no Verilog sources to stage after VHDL conversion'
          end

          write_staged_verilog_entry(staged_verilog_path: staged_verilog_path, source_files: source_files)

          {
            staged_verilog_path: staged_verilog_path,
            top_name: config[:top][:name],
            tool_args: config[:tool_args],
            provenance: {
              manifest_path: config[:manifest_path],
              autoscan_root: config[:autoscan_root],
              top_name: config[:top][:name],
              top_language: config[:top][:language],
              top_file: config[:top][:file],
              source_files: config[:all_files].map do |entry|
                { path: entry[:path], language: entry[:language], library: entry[:library] }
              end,
              vhdl_analysis_commands: analysis_commands,
              vhdl_synth_outputs: synth_outputs,
              staging_entry_path: staged_verilog_path
            }
          }
        end

        def resolve_mixed_import_config(out_dir:)
          manifest = options[:manifest]
          if manifest && !manifest.to_s.strip.empty?
            resolve_mixed_config_from_manifest(manifest_path: manifest, out_dir: out_dir)
          else
            resolve_mixed_config_from_autoscan(out_dir: out_dir)
          end
        end

        def resolve_mixed_config_from_manifest(manifest_path:, out_dir:)
          path = manifest_path.to_s
          raise ArgumentError, "Manifest file not found: #{path}" unless File.exist?(path)

          ext = File.extname(path).downcase
          unless SUPPORTED_MIXED_MANIFEST_EXTENSIONS.include?(ext)
            raise ArgumentError, "Unsupported manifest extension '#{ext}'. Expected one of: #{SUPPORTED_MIXED_MANIFEST_EXTENSIONS.join(', ')}"
          end

          raw = load_manifest(path: path, ext: ext)
          unless raw.is_a?(Hash)
            raise ArgumentError, "Mixed import manifest must decode to a mapping/hash: #{path}"
          end

          version = raw['version'] || raw[:version]
          unless version.to_i == 1
            raise ArgumentError, "Mixed import manifest version must be 1 (got #{version.inspect})"
          end

          root = File.dirname(File.expand_path(path))
          top_hash = symbolize_hash(raw.fetch('top') { raw.fetch(:top) })
          top_name = top_hash[:name].to_s.strip
          raise ArgumentError, 'Mixed import manifest top.name is required' if top_name.empty?

          top_file_raw = top_hash[:file].to_s.strip
          raise ArgumentError, 'Mixed import manifest top.file is required' if top_file_raw.empty?

          top_file = expand_relative_path(top_file_raw, root: root)
          raise ArgumentError, "Top source file not found: #{top_file}" unless File.file?(top_file)

          top_language = normalize_language(top_hash[:language], path: top_file)
          top_library = normalize_library(top_hash[:library])

          files = Array(raw['files'] || raw[:files]).map do |entry|
            parse_mixed_file_entry(entry, root: root)
          end
          if files.empty?
            raise ArgumentError, 'Mixed import manifest requires at least one file entry under files'
          end

          unless files.any? { |entry| File.expand_path(entry[:path]) == File.expand_path(top_file) }
            files << { path: top_file, language: top_language, library: top_library }
          end

          include_dirs = Array(raw['include_dirs'] || raw[:include_dirs]).map do |dir|
            expand_relative_path(dir.to_s, root: root)
          end
          defines = normalize_defines(raw['defines'] || raw[:defines])
          vhdl = symbolize_hash(raw['vhdl'] || raw[:vhdl] || {})
          vhdl_standard = (vhdl[:standard] || '08').to_s
          vhdl_workdir = vhdl[:workdir] ? expand_relative_path(vhdl[:workdir].to_s, root: root) : File.join(out_dir, '.mixed_import', 'ghdl_work')
          vhdl_synth_targets = normalize_vhdl_synth_targets(vhdl[:synth_targets])

          normalize_mixed_config(
            all_files: files,
            top: { name: top_name, language: top_language, file: top_file, library: top_library },
            include_dirs: include_dirs,
            defines: defines,
            vhdl_standard: vhdl_standard,
              vhdl_workdir: vhdl_workdir,
              vhdl_analyze_args: Array(vhdl[:analyze_args]),
              vhdl_synth_args: Array(vhdl[:synth_args]),
              vhdl_synth_targets: vhdl_synth_targets,
              manifest_path: File.expand_path(path),
              autoscan_root: nil
            )
        end

        def resolve_mixed_config_from_autoscan(out_dir:)
          input = options[:input].to_s.strip
          raise ArgumentError, 'Mixed mode requires --manifest or --input' if input.empty?
          raise ArgumentError, "Mixed mode input path not found: #{input}" unless File.exist?(input)
          raise ArgumentError, 'Mixed mode autoscan requires --input to be a file path' unless File.file?(input)

          top_file = File.expand_path(input)
          top_language = normalize_language(nil, path: top_file)
          root = File.dirname(top_file)
          top_name = options[:top].to_s.strip
          top_name = File.basename(top_file, File.extname(top_file)) if top_name.empty?

          files = Dir.glob(File.join(root, '**', '*')).sort.filter_map do |path|
            next unless File.file?(path)
            ext = File.extname(path).downcase
            next unless SOURCE_EXTENSIONS.include?(ext)

            { path: File.expand_path(path), language: normalize_language(nil, path: path), library: nil }
          end
          raise ArgumentError, "Mixed mode autoscan found no source files under: #{root}" if files.empty?

          normalize_mixed_config(
            all_files: files,
            top: { name: top_name, language: top_language, file: top_file, library: nil },
            include_dirs: [],
            defines: {},
            vhdl_standard: '08',
            vhdl_workdir: File.join(out_dir, '.mixed_import', 'ghdl_work'),
            vhdl_analyze_args: [],
            vhdl_synth_args: [],
            vhdl_synth_targets: nil,
            manifest_path: nil,
            autoscan_root: root
          )
        end

        def normalize_mixed_config(all_files:, top:, include_dirs:, defines:, vhdl_standard:, vhdl_workdir:,
                                   vhdl_analyze_args:, vhdl_synth_args:, vhdl_synth_targets:, manifest_path:,
                                   autoscan_root:)
          verilog_files, vhdl_files = all_files.partition { |entry| entry[:language] == 'verilog' }

          {
            all_files: all_files,
            verilog_files: verilog_files,
            vhdl_files: vhdl_files,
            top: top,
            tool_args: mixed_tool_args(include_dirs: include_dirs, defines: defines),
            vhdl_standard: vhdl_standard,
            vhdl_workdir: vhdl_workdir,
            vhdl_analyze_args: Array(vhdl_analyze_args),
            vhdl_synth_args: Array(vhdl_synth_args),
            vhdl_synth_targets: Array(vhdl_synth_targets).map do |target|
              {
                entity: target.fetch(:entity).to_s,
                library: normalize_library(target[:library])
              }
            end,
            manifest_path: manifest_path,
            autoscan_root: autoscan_root
          }
        end

        def mixed_tool_args(include_dirs:, defines:)
          args = include_dirs.map { |dir| "-I#{dir}" }
          defines.each do |key, value|
            args << if value.nil? || value.to_s.empty?
                      "-D#{key}"
                    else
                      "-D#{key}=#{value}"
                    end
          end
          args
        end

        def parse_mixed_file_entry(entry, root:)
          raw = symbolize_hash(entry)
          file = raw[:path].to_s.strip
          raise ArgumentError, 'Mixed import file entry requires path' if file.empty?

          full = expand_relative_path(file, root: root)
          raise ArgumentError, "Mixed import source file not found: #{full}" unless File.file?(full)

          {
            path: full,
            language: normalize_language(raw[:language], path: full),
            library: normalize_library(raw[:library])
          }
        end

        def load_manifest(path:, ext:)
          text = File.read(path)
          case ext
          when '.json'
            JSON.parse(text)
          when '.yaml', '.yml'
            YAML.safe_load(text, aliases: false)
          else
            raise ArgumentError, "Unsupported manifest extension '#{ext}'"
          end
        rescue JSON::ParserError, Psych::SyntaxError => e
          raise ArgumentError, "Failed to parse manifest #{path}: #{e.message}"
        end

        def symbolize_hash(value)
          case value
          when Hash
            value.each_with_object({}) do |(k, v), out|
              out[k.to_sym] = symbolize_hash(v)
            end
          when Array
            value.map { |v| symbolize_hash(v) }
          else
            value
          end
        end

        def normalize_language(raw, path:)
          value = raw&.to_s&.strip&.downcase
          return value if %w[verilog vhdl].include?(value)

          ext = File.extname(path.to_s).downcase
          return 'verilog' if VERILOG_EXTENSIONS.include?(ext)
          return 'vhdl' if VHDL_EXTENSIONS.include?(ext)

          raise ArgumentError, "Cannot infer source language for #{path}. Supported extensions: #{SOURCE_EXTENSIONS.join(', ')}"
        end

        def normalize_library(raw)
          lib = raw&.to_s&.strip
          lib.nil? || lib.empty? ? nil : lib
        end

        def normalize_defines(raw)
          return {} if raw.nil?
          raise ArgumentError, 'Mixed import defines must be a key/value map' unless raw.is_a?(Hash)

          raw.each_with_object({}) do |(k, v), out|
            out[k.to_s] = v.nil? ? nil : v.to_s
          end
        end

        def normalize_vhdl_synth_targets(raw)
          return [] if raw.nil?
          raise ArgumentError, 'Mixed import vhdl.synth_targets must be an array' unless raw.is_a?(Array)

          raw.map do |entry|
            case entry
            when String, Symbol
              name = entry.to_s.strip
              raise ArgumentError, 'Mixed import vhdl.synth_targets entries must not be empty' if name.empty?

              { entity: name, library: nil }
            when Hash
              target = symbolize_hash(entry)
              name = (target[:entity] || target[:name]).to_s.strip
              raise ArgumentError, 'Mixed import vhdl.synth_targets entry requires entity/name' if name.empty?

              { entity: name, library: normalize_library(target[:library]) }
            else
              raise ArgumentError, "Mixed import vhdl.synth_targets entries must be string/symbol/hash (got #{entry.class})"
            end
          end
        end

        def mixed_vhdl_synth_targets(config)
          top = config.fetch(:top)
          if top[:language] == 'vhdl'
            return [
              {
                entity: top.fetch(:name),
                library: top[:library]
              }
            ]
          end

          discover_vhdl_entities(config[:vhdl_files]).values
        end

        def discover_vhdl_entities(vhdl_files)
          entities = {}
          vhdl_files.each do |entry|
            next unless File.file?(entry.fetch(:path))

            text = File.read(entry.fetch(:path))
            text.scan(/^\s*entity\s+([A-Za-z_][A-Za-z0-9_]*)\s+is\b/i).flatten.each do |name|
              key = name.downcase
              entities[key] ||= { entity: name, library: entry[:library] }
            end
          end
          entities
        end

        def write_staged_verilog_entry(staged_verilog_path:, source_files:)
          ensure_dir(File.dirname(staged_verilog_path))
          lines = []
          lines << '// Auto-generated by rhdl import --mode mixed'
          source_files.each do |path|
            escaped = path.to_s.gsub('\\', '/').gsub('"', '\"')
            lines << "`include \"#{escaped}\""
          end
          File.write(staged_verilog_path, "#{lines.join("\n")}\n")
        end

        def lower_moore_to_core_mlir_if_needed!(mlir_out:)
          return unless File.file?(mlir_out)

          text = File.read(mlir_out)
          return unless text.include?('moore.module')

          lowered_path = "#{mlir_out}.core.lowered"
          cmd = [
            'circt-opt',
            '--moore-lower-concatref',
            '--canonicalize',
            '--moore-lower-concatref',
            '--convert-moore-to-core',
            '--llhd-sig2reg',
            '--canonicalize',
            mlir_out,
            '-o',
            lowered_path
          ]
          stdout, stderr, status = Open3.capture3(*cmd)
          unless status.success?
            raise RuntimeError,
                  "Moore->core lowering failed.\nCommand: #{cmd.join(' ')}\n#{stdout}\n#{stderr}"
          end

          FileUtils.mv(lowered_path, mlir_out)
          puts 'Import step: Lower Moore MLIR -> core/llhd'
        end

        def postprocess_generated_vhdl_verilog!(entity:, out_path:)
          name = entity.to_s.strip
          return if name.empty?
          return unless File.file?(out_path)

          case name.downcase
          when 'ereg_savestatev'
            ensure_positional_parameters_for_generated_module!(
              out_path: out_path,
              module_name: name,
              parameter_count: 5
            )
          when 'gb_statemanager'
            ensure_positional_parameters_for_generated_module!(
              out_path: out_path,
              module_name: name,
              parameter_count: 2
            )
          when 'gbse', 'gbc_snd'
            rename_generated_identifier_token!(
              out_path: out_path,
              from: 'do',
              to: 'do_o'
            )
          end
        end

        def ensure_positional_parameters_for_generated_module!(out_path:, module_name:, parameter_count:)
          source = File.read(out_path)
          return if source.match?(/\bmodule\s+#{Regexp.escape(module_name)}\b\s*#\s*\(/im)

          params = (0...parameter_count).map { |idx| "    parameter P#{idx} = 0" }.join(",\n")
          replacement = "module #{module_name}\n  #(\n#{params}\n  )\n  ("
          updated = source.sub(/\bmodule\s+#{Regexp.escape(module_name)}\b\s*\(/im, replacement)
          return if updated == source

          File.write(out_path, updated)
        end

        def rename_generated_identifier_token!(out_path:, from:, to:)
          source = File.read(out_path)
          updated = source.gsub(/\b#{Regexp.escape(from)}\b/, to)
          return if updated == source

          File.write(out_path, updated)
        end

        # Analyze VHDL files with retry passes to tolerate dependency ordering
        # in source manifests/QIP lists (for example package declarations that
        # appear after units that depend on them).
        def analyze_vhdl_files!(vhdl_files:, workdir:, std:, analyze_args:, analysis_commands:)
          pending = Array(vhdl_files).dup
          loop do
            progressed = false
            failures = {}

            next_pending = pending.each_with_object([]) do |entry, retry_list|
              analysis = RHDL::Codegen::CIRCT::Tooling.ghdl_analyze(
                vhdl_path: entry.fetch(:path),
                workdir: workdir,
                std: std,
                work: effective_work_library(entry[:library]),
                extra_args: Array(analyze_args)
              )
              analysis_commands << analysis[:command]

              if analysis[:success]
                progressed = true
              else
                failures[entry.fetch(:path)] = analysis
                retry_list << entry
              end
            end

            return if next_pending.empty?

            unless progressed
              failed_entry = next_pending.first
              failed = failures.fetch(failed_entry.fetch(:path))
              raise RuntimeError,
                    "VHDL analysis failed.\nCommand: #{failed[:command]}\n#{failed[:stderr]}"
            end

            pending = next_pending
          end
        end

        def effective_work_library(value)
          lib = value.to_s.strip
          lib.empty? ? 'work' : lib
        end

        def expand_relative_path(path, root:)
          expanded = Pathname.new(path)
          expanded = Pathname.new(root).join(expanded) unless expanded.absolute?
          expanded.cleanpath.to_s
        end
      end
    end
  end
end
