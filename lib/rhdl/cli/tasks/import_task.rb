# frozen_string_literal: true

require_relative '../task'
require 'digest'
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
        FormatResult = Struct.new(:success, :diagnostics, keyword_init: true) do
          def success?
            !!success
          end
        end

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
          mlir_out = options[:mlir_out] || File.join(out_dir, "#{base}.core.mlir")
          tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL

          result = with_timed_step("Verilog -> CIRCT MLIR (#{tool})") do
            RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
              verilog_path: input,
              out_path: mlir_out,
              tool: tool,
              extra_args: Array(options[:tool_args])
            )
          end

          unless result[:success]
            raise RuntimeError,
                  "Verilog->CIRCT conversion failed with '#{tool}'.\nCommand: #{result[:command]}\n#{result[:stderr]}"
          end

          puts "Wrote CIRCT MLIR: #{mlir_out}"
          puts "Command: #{result[:command]}"

          cleanup_imported_core_mlir!(
            mlir_out: mlir_out,
            top_name: options[:top]
          )

          return unless raise_to_dsl?

          run_raise_flow(
            mlir_out: mlir_out,
            out_dir: out_dir,
            artifact_paths: { core_mlir_path: mlir_out }
          )
        end

        def import_mixed
          out_dir = fetch_out_dir
          ensure_dir(out_dir)

          staging = with_timed_step('Mixed source staging') do
            build_mixed_import_staging(out_dir: out_dir)
          end
          staged_verilog_path = staging.fetch(:pure_verilog_entry_path)
          resolved_top_name = staging[:top_name]

          base = resolved_top_name || File.basename(staged_verilog_path, File.extname(staged_verilog_path))
          mlir_out = options[:mlir_out] || File.join(out_dir, "#{base}.core.mlir")
          tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL
          tool_args = Array(options[:tool_args]) + Array(staging[:tool_args])

          result = with_timed_step("Verilog -> CIRCT MLIR (#{tool})") do
            RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
              verilog_path: staged_verilog_path,
              out_path: mlir_out,
              tool: tool,
              extra_args: tool_args
            )
          end

          unless result[:success]
            raise RuntimeError,
                  "Mixed Verilog/VHDL->CIRCT conversion failed with '#{tool}'.\nCommand: #{result[:command]}\n#{result[:stderr]}"
          end

          puts "Wrote CIRCT MLIR: #{mlir_out}"
          puts "Command: #{result[:command]}"

          cleanup_imported_core_mlir!(
            mlir_out: mlir_out,
            top_name: resolved_top_name
          )

          return unless raise_to_dsl?

          verilog_artifacts = emit_normalized_verilog_from_core_mlir!(
            mlir_out: mlir_out,
            out_dir: out_dir,
            base: base,
            pure_verilog_root: staging.fetch(:pure_verilog_root)
          )
          normalized_verilog_path = verilog_artifacts.fetch(:normalized_verilog_path)
          staging[:provenance] = staging.fetch(:provenance).merge(
            pure_verilog_root: staging.fetch(:pure_verilog_root),
            pure_verilog_entry_path: staging.fetch(:pure_verilog_entry_path),
            core_mlir_path: mlir_out,
            normalized_verilog_path: normalized_verilog_path,
            firtool_verilog_path: verilog_artifacts[:firtool_verilog_path],
            normalized_verilog_overlay_modules: verilog_artifacts[:overlay_modules]
          )

          run_raise_flow(
            mlir_out: mlir_out,
            out_dir: out_dir,
            top_override: resolved_top_name,
            mixed_provenance: staging[:provenance],
            artifact_paths: {
              pure_verilog_root: staging.fetch(:pure_verilog_root),
              pure_verilog_entry_path: staging.fetch(:pure_verilog_entry_path),
              core_mlir_path: mlir_out,
              normalized_verilog_path: normalized_verilog_path,
              firtool_verilog_path: verilog_artifacts[:firtool_verilog_path]
            }
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

        def run_raise_flow(mlir_out:, out_dir:, top_override: nil, mixed_provenance: nil, artifact_paths: nil,
                           import_result: nil)
          normalize_llhd_mlir_if_needed!(mlir_out: mlir_out)
          strict = options.fetch(:strict, true)
          extern_modules = Array(options[:extern_modules]).map(&:to_s)
          top_name = top_override || options[:top]
          artifact_paths = (artifact_paths || {}).dup
          mixed_provenance = mixed_provenance&.dup

          unless import_result
            import_result = with_timed_step('Parse/import CIRCT MLIR') do
              mlir = File.read(mlir_out)
              RHDL::Codegen.import_circt_mlir(
                mlir,
                strict: strict,
                top: top_name,
                extern_modules: extern_modules
              )
            end
            emit_diagnostics(import_result.diagnostics)
          end

          runtime_json_path = emit_runtime_json_artifact!(
            import_result: import_result,
            out_dir: out_dir,
            top_name: top_name,
            mixed_mode: !mixed_provenance.nil?
          )
          if runtime_json_path
            artifact_paths[:runtime_json_path] = runtime_json_path
            mixed_provenance[:runtime_json_path] = runtime_json_path if mixed_provenance
          end

          raise_result = with_timed_step('Raise CIRCT -> RHDL files') do
            RHDL::Codegen.raise_circt(
              import_result.modules,
              out_dir: out_dir,
              top: top_name,
              strict: strict,
              format: false
            )
          end
          emit_diagnostics(raise_result.diagnostics)

          puts "Raised #{raise_result.files_written.length} DSL file(s):"
          raise_result.files_written.each { |path| puts "  - #{path}" }

          format_result = if format_output?
                            result = with_timed_step('Format RHDL output directory') do
                              RHDL::Codegen.format_raised_dsl(out_dir)
                            end
                            emit_diagnostics(result.diagnostics)
                            result
                          else
                            puts 'Import step: Skip formatting RHDL output directory'
                            FormatResult.new(success: true, diagnostics: [])
                          end

          combined_raise_diagnostics = Array(raise_result.diagnostics) + Array(format_result.diagnostics)
          raise_success = raise_result.success? && format_result.success?
          report_path = with_timed_step('Write import report') do
            write_report(
              out_dir: out_dir,
              strict: strict,
              extern_modules: extern_modules,
              top_name: top_name,
              import_result: import_result,
              raise_result: raise_result,
              raise_diagnostics: combined_raise_diagnostics,
              raise_success: raise_success,
              mixed_provenance: mixed_provenance,
              artifact_paths: artifact_paths
            )
          end
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
                         raise_success: nil, mixed_provenance: nil, artifact_paths: nil)
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
          report[:artifacts] = artifact_paths if artifact_paths

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

        def format_output?
          options.fetch(:format_output, options.fetch(:format, false))
        end

        def build_mixed_import_staging(out_dir:)
          config = resolve_mixed_import_config(out_dir: out_dir)
          staging_dir = File.join(out_dir, '.mixed_import')
          pure_verilog_root = File.join(staging_dir, 'pure_verilog')
          generated_dir = File.join(pure_verilog_root, 'generated_vhdl')
          pure_verilog_entry_path = File.join(staging_dir, 'pure_verilog_entry.v')
          FileUtils.rm_rf(pure_verilog_root)
          FileUtils.mkdir_p(generated_dir)

          analysis_commands = []
          synth_outputs = []
          generated_verilog_files = []
          generated_entity_outputs = {}
          vhdl_standard = config.fetch(:vhdl_standard, '08')
          vhdl_workdir = config.fetch(:vhdl_workdir)
          vhdl_analyze_args = Array(config[:vhdl_analyze_args])
          vhdl_synth_args = Array(config[:vhdl_synth_args])
          FileUtils.mkdir_p(vhdl_workdir)

          unless config[:vhdl_files].empty?
            with_timed_step("Analyze VHDL sources (#{config[:vhdl_files].length} file(s))") do
              analyze_vhdl_files!(
                vhdl_files: config[:vhdl_files],
                workdir: vhdl_workdir,
                std: vhdl_standard,
                analyze_args: vhdl_analyze_args,
                analysis_commands: analysis_commands
              )
            end

            synth_targets = Array(config[:vhdl_synth_targets])
            synth_targets = mixed_vhdl_synth_targets(config) if synth_targets.empty?
            specialization = expand_vhdl_synth_targets_for_specializations(
              synth_targets: synth_targets,
              verilog_files: config[:verilog_files],
              vhdl_files: config[:vhdl_files]
            )
            synth_targets = specialization.fetch(:targets)
            unless synth_targets.empty?
              with_timed_step("Synthesize VHDL sources to Verilog (#{synth_targets.length} target(s))") do
                synth_targets.each do |target|
                  generated_module_name = target[:module_name].to_s.strip
                  generated_module_name = target.fetch(:entity).to_s if generated_module_name.empty?
                  out_path = File.join(generated_dir, "#{generated_module_name}.v")
                  synth = RHDL::Codegen::CIRCT::Tooling.ghdl_synth_to_verilog(
                    entity: target.fetch(:entity),
                    out_path: out_path,
                    workdir: vhdl_workdir,
                    std: vhdl_standard,
                    work: effective_work_library(target[:library]),
                    extra_args: Array(vhdl_synth_args) + Array(target[:extra_args])
                  )
                  unless synth[:success]
                    raise RuntimeError,
                          "VHDL synth->Verilog failed.\nCommand: #{synth[:command]}\n#{synth[:stderr]}"
                  end

                  postprocess_generated_vhdl_verilog!(
                    entity: target.fetch(:entity),
                    out_path: out_path,
                    module_name: target[:module_name]
                  )
                  generated_verilog_files << out_path
                  generated_entity_outputs[generated_module_name.downcase] = out_path
                  synth_outputs << {
                    entity: target.fetch(:entity),
                    module_name: generated_module_name,
                    library: effective_work_library(target[:library]),
                    extra_args: Array(target[:extra_args]),
                    output_path: out_path,
                    command: synth[:command]
                  }
                end
              end
            end
          end

          source_files = config[:verilog_files].map { |entry| entry.fetch(:path) } + generated_verilog_files
          if source_files.empty?
            raise ArgumentError, 'Mixed import found no Verilog sources to stage after VHDL conversion'
          end

          staged_source_files = stage_mixed_verilog_files!(
            verilog_files: config[:verilog_files],
            pure_verilog_root: pure_verilog_root,
            source_root: config.fetch(:source_root),
            specialization_rewrites: specialization && specialization.fetch(:rewrite_plan)
          ) + generated_verilog_files

          write_staged_verilog_entry(staged_verilog_path: pure_verilog_entry_path, source_files: staged_source_files)

          canonical_top_file =
            if config[:top][:language] == 'verilog'
              staged_source_files.find do |path|
                path.end_with?(staged_mixed_source_relative_path(
                  path: config[:top][:file],
                  source_root: config.fetch(:source_root)
                ))
              end || config[:top][:file]
            else
              generated_entity_outputs[config[:top][:name].to_s.downcase] || config[:top][:file]
            end

          {
            pure_verilog_root: pure_verilog_root,
            pure_verilog_entry_path: pure_verilog_entry_path,
            staged_verilog_path: pure_verilog_entry_path,
            top_name: config[:top][:name],
            tool_args: config[:tool_args],
            provenance: {
              manifest_path: config[:manifest_path],
              autoscan_root: config[:autoscan_root],
              top_name: config[:top][:name],
              top_language: config[:top][:language],
              top_file: canonical_top_file,
              source_files: config[:all_files].map do |entry|
                { path: entry[:path], language: entry[:language], library: entry[:library] }
              end,
              pure_verilog_root: pure_verilog_root,
              pure_verilog_entry_path: pure_verilog_entry_path,
              pure_verilog_files: staged_source_files.sort.map do |path|
                { path: path, language: 'verilog', generated: path.start_with?("#{generated_dir}/") }
              end,
              vhdl_analysis_commands: analysis_commands,
              vhdl_synth_outputs: synth_outputs,
              staging_entry_path: pure_verilog_entry_path
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
              source_root: mixed_source_root(files.map { |entry| entry[:path] }),
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
            source_root: root,
            manifest_path: nil,
            autoscan_root: root
          )
        end

        def normalize_mixed_config(all_files:, top:, include_dirs:, defines:, vhdl_standard:, vhdl_workdir:,
                                   vhdl_analyze_args:, vhdl_synth_args:, vhdl_synth_targets:, source_root:, manifest_path:,
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
            source_root: source_root,
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
            text.scan(/\bentity\s+([A-Za-z_][A-Za-z0-9_]*)\s+is\b(.*?)\bend(?:\s+entity)?(?:\s+\1)?\s*;/im) do |name, body|
              key = name.downcase
              entities[key] ||= {
                entity: name,
                library: entry[:library],
                generic_names: extract_vhdl_generic_names(body.to_s)
              }
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

        def stage_mixed_verilog_files!(verilog_files:, pure_verilog_root:, source_root:, specialization_rewrites: {})
          Array(verilog_files).map do |entry|
            source_path = File.expand_path(entry.fetch(:path))
            relative = staged_mixed_source_relative_path(path: source_path, source_root: source_root)
            staged_path = File.join(pure_verilog_root, relative)
            ensure_dir(File.dirname(staged_path))
            source = File.read(source_path)
            rewritten = rewrite_vhdl_specialized_instantiations(
              source,
              rewrite_plan: specialization_rewrites
            )
            File.write(staged_path, rewritten)
            staged_path
          end
        end

        def staged_mixed_source_relative_path(path:, source_root:)
          full_path = File.expand_path(path)
          root_path = File.expand_path(source_root)
          relative = Pathname.new(full_path).relative_path_from(Pathname.new(root_path)).to_s
          return relative unless relative.start_with?('../')

          full_path.delete_prefix('/').gsub(File::SEPARATOR, '/')
        rescue ArgumentError
          full_path.delete_prefix('/').gsub(File::SEPARATOR, '/')
        end

        def mixed_source_root(paths)
          expanded = Array(paths).map { |path| File.expand_path(path) }
          raise ArgumentError, 'Mixed import requires at least one source path' if expanded.empty?

          directories = expanded.map { |path| File.dirname(path).split(File::SEPARATOR) }
          common = directories.shift
          directories.each do |parts|
            common = common.zip(parts).take_while { |lhs, rhs| lhs == rhs }.map(&:first)
          end

          root = common.join(File::SEPARATOR)
          root = "#{File::SEPARATOR}#{root}" unless root.start_with?(File::SEPARATOR)
          root.empty? ? File::SEPARATOR : root
        end

        def emit_normalized_verilog_from_core_mlir!(mlir_out:, out_dir:, base:, pure_verilog_root: nil)
          normalized_verilog_path = File.join(out_dir, '.mixed_import', "#{base}.normalized.v")
          firtool_verilog_path = File.join(out_dir, '.mixed_import', "#{base}.firtool.v")
          result = with_timed_step(
            "Export normalized Verilog (#{RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_EXPORT_TOOL})"
          ) do
            RHDL::Codegen::CIRCT::Tooling.circt_mlir_to_verilog(
              mlir_path: mlir_out,
              out_path: firtool_verilog_path,
              tool: RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_EXPORT_TOOL
            )
          end
          unless result[:success]
            raise RuntimeError,
                  "CIRCT->Verilog export failed with '#{RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_EXPORT_TOOL}'.\nCommand: #{result[:command]}\n#{result[:stderr]}"
          end

          FileUtils.cp(firtool_verilog_path, normalized_verilog_path)
          overlay_modules = overlay_generated_memory_modules!(
            normalized_verilog_path: normalized_verilog_path,
            pure_verilog_root: pure_verilog_root
          )
          puts "Wrote raw firtool Verilog: #{firtool_verilog_path}"
          puts "Wrote normalized Verilog: #{normalized_verilog_path}"
          {
            normalized_verilog_path: normalized_verilog_path,
            firtool_verilog_path: firtool_verilog_path,
            overlay_modules: overlay_modules
          }
        end

        def emit_runtime_json_artifact!(import_result:, out_dir:, top_name:, mixed_mode:)
          return nil unless import_result&.success?

          resolved_top = top_name || import_result.modules.first&.name&.to_s
          return nil if resolved_top.nil? || resolved_top.empty?

          runtime_json_path =
            if mixed_mode
              File.join(out_dir, '.mixed_import', "#{resolved_top}.runtime.json")
            else
              File.join(out_dir, "#{resolved_top}.runtime.json")
            end

          with_timed_step('Emit imported runtime JSON artifact') do
            begin
              flat = RHDL::Codegen::CIRCT::Flatten.to_flat_module(import_result.modules, top: resolved_top)
            rescue KeyError => e
              puts "Import step: Skip runtime JSON artifact (#{e.message})"
              return nil
            end

            json = RHDL::Codegen::CIRCT::RuntimeJSON.dump(flat)
            FileUtils.mkdir_p(File.dirname(runtime_json_path))
            File.write(runtime_json_path, json)
          end
          puts "Wrote runtime JSON: #{runtime_json_path}"
          runtime_json_path
        end

        def overlay_generated_memory_modules!(normalized_verilog_path:, pure_verilog_root:)
          generated_dir = pure_verilog_root && File.join(pure_verilog_root, 'generated_vhdl')
          return [] unless generated_dir && Dir.exist?(generated_dir)

          overlay_modules = {}
          Dir.glob(File.join(generated_dir, '**', '*.v')).sort.each do |path|
            source_text = File.read(path)
            next unless source_text.match?(/\breg\s+\[[^\]]+\]\s+\w+\s*\[[^\]]+\s*:\s*[^\]]+\]\s*;/)

            verilog_module_blocks(source_text).each do |name, block|
              overlay_modules[name] = block
            end
          end

          return [] if overlay_modules.empty?

          normalized_text = File.read(normalized_verilog_path)
          replaced = []
          overlay_modules.each do |name, block|
            pattern = /\bmodule\s+#{Regexp.escape(name)}\b.*?\bendmodule\b/m
            next unless normalized_text.match?(pattern)

            normalized_text.sub!(pattern, block)
            replaced << name
          end

          unless replaced.empty?
            File.write(normalized_verilog_path, normalized_text)
            puts "Patched canonical Verilog memory modules: #{replaced.join(', ')}"
          end

          replaced
        end

        def verilog_module_blocks(text)
          blocks = {}
          idx = 0

          while (header = text.match(/\bmodule\s+([A-Za-z_][A-Za-z0-9_$]*)\b.*?;/m, idx))
            body_start = header.end(0)
            footer = text.match(/\bendmodule\b/m, body_start)
            break unless footer

            blocks[header[1]] = text[header.begin(0)...footer.end(0)]
            idx = footer.end(0)
          end

          blocks
        end

        def normalize_llhd_mlir_if_needed!(mlir_out:)
          return unless File.file?(mlir_out)

          text = File.read(mlir_out)
          return unless text.include?('llhd.process')

          lowered_path = "#{mlir_out}.llhd.lowered"
          cmd = [
            'circt-opt',
            '--llhd-lower-processes',
            '--canonicalize',
            mlir_out,
            '-o',
            lowered_path
          ]
          stdout = nil
          stderr = nil
          status = nil
          with_timed_step('Normalize LLHD processes') do
            stdout, stderr, status = Open3.capture3(*cmd)
          end
          unless status.success?
            raise RuntimeError,
                  "LLHD process normalization failed.\nCommand: #{cmd.join(' ')}\n#{stdout}\n#{stderr}"
          end

          FileUtils.mv(lowered_path, mlir_out)
        end

        def cleanup_imported_core_mlir!(mlir_out:, top_name:)
          return nil unless File.file?(mlir_out)

          text = File.read(mlir_out)
          unless needs_imported_core_cleanup?(text)
            puts 'Import step: Skip imported CIRCT core cleanup (no cleanup markers found)'
            return nil
          end

          cleanup = with_timed_step('Cleanup imported CIRCT core MLIR') do
            RHDL::Codegen::CIRCT::ImportCleanup.cleanup_imported_core_mlir(
              text,
              strict: options.fetch(:strict, true),
              top: top_name,
              extern_modules: Array(options[:extern_modules]).map(&:to_s)
            )
          end
          emit_diagnostics(cleanup.import_result.diagnostics)
          unless cleanup.success?
            raise RuntimeError, 'Imported CIRCT core cleanup failed'
          end

          File.write(mlir_out, cleanup.cleaned_text)
          puts "Wrote cleaned CIRCT MLIR: #{mlir_out}"
          cleanup.import_result
        end

        def needs_imported_core_cleanup?(text)
          text.include?('llhd.')
        end

        def postprocess_generated_vhdl_verilog!(entity:, out_path:, module_name: nil)
          name = entity.to_s.strip
          return if name.empty?
          return unless File.file?(out_path)

          rename_generated_module!(out_path: out_path, from: name, to: module_name)
          namespace_generated_helper_modules!(
            out_path: out_path,
            primary_module_name: module_name.to_s.strip.empty? ? name : module_name.to_s
          )

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

        def rename_generated_module!(out_path:, from:, to:)
          replacement = to.to_s.strip
          return if replacement.empty? || replacement == from

          source = File.read(out_path)
          updated = source.sub(/\bmodule\s+#{Regexp.escape(from)}\b/im, "module #{replacement}")
          return if updated == source

          File.write(out_path, updated)
        end

        def namespace_generated_helper_modules!(out_path:, primary_module_name:)
          source = File.read(out_path)
          module_names = source.scan(/^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)\b/).flatten.uniq
          helper_names = module_names - [primary_module_name.to_s]
          return if helper_names.empty?

          suffix = "__#{Digest::SHA1.hexdigest(primary_module_name.to_s)[0, 8]}"
          updated = source.dup
          helper_names.each do |helper_name|
            updated.gsub!(/\b#{Regexp.escape(helper_name)}\b/, "#{helper_name}#{suffix}")
          end
          return if updated == source

          File.write(out_path, updated)
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

        def expand_vhdl_synth_targets_for_specializations(synth_targets:, verilog_files:, vhdl_files:)
          entity_metadata = discover_vhdl_entities(vhdl_files)
          rewrite_plan = {}
          expanded_targets = Array(synth_targets).flat_map do |target|
            entity_name = target.fetch(:entity).to_s
            metadata = entity_metadata[entity_name.downcase]
            generic_names = Array(metadata && metadata[:generic_names])
            instances = discover_parameterized_verilog_instances(
              verilog_files: verilog_files,
              module_name: entity_name
            )
            specializations = instances.filter_map do |instance|
              parameter_overrides = verilog_parameter_overrides_for_instance(
                params: instance.fetch(:params),
                generic_names: generic_names
              )
              next if parameter_overrides.empty?

              {
                entity: entity_name,
                library: target[:library],
                module_name: specialized_vhdl_module_name(
                  entity_name: entity_name,
                  parameter_overrides: parameter_overrides
                ),
                extra_args: parameter_overrides.map { |name, value| "-g#{name}=#{value}" }
              }
            end

            if specializations.empty?
              [target]
            else
              rewrite_plan[entity_name.downcase] = specializations.each_with_object({}) do |specialization, acc|
                key = specialization_value_key(
                  Array(specialization[:extra_args]).map do |arg|
                    _name, value = arg.to_s.sub(/\A-g/, '').split('=', 2)
                    normalize_vhdl_generic_override_value(value)
                  end
                )
                acc[key] = specialization.fetch(:module_name)
              end
              specializations.uniq { |entry| [entry.fetch(:module_name), Array(entry[:extra_args])] }
            end
          end

          {
            targets: expanded_targets.uniq { |entry| [entry.fetch(:entity).to_s.downcase, entry[:module_name].to_s, Array(entry[:extra_args]), entry[:library].to_s] },
            rewrite_plan: rewrite_plan
          }
        end

        def extract_vhdl_generic_names(entity_body)
          match = entity_body.match(/\bgeneric\s*\((.*?)\)\s*;/im)
          return [] unless match

          body = match[1].gsub(/--.*$/, '')
          body.split(';').flat_map do |clause|
            head = clause.to_s.split(':', 2).first.to_s.strip
            next [] if head.empty?

            head.split(/\s*,\s*/)
          end
        end

        def discover_parameterized_verilog_instances(verilog_files:, module_name:)
          Array(verilog_files).flat_map do |entry|
            next [] unless File.file?(entry.fetch(:path))

            source = File.read(entry.fetch(:path))
            find_parameterized_module_instantiations(source: source, module_name: module_name)
          end
        end

        def find_parameterized_module_instantiations(source:, module_name:)
          pattern = /\b#{Regexp.escape(module_name)}\b/i
          matches = []
          cursor = 0
          while (found = pattern.match(source, cursor))
            start_index = found.begin(0)
            scan_index = skip_verilog_spacing(source, found.end(0))
            unless source[scan_index] == '#'
              cursor = found.end(0)
              next
            end

            scan_index = skip_verilog_spacing(source, scan_index + 1)
            unless source[scan_index] == '('
              cursor = found.end(0)
              next
            end

            params_text, params_end = extract_verilog_parenthesized(source, scan_index)
            cursor_after_params = skip_verilog_spacing(source, params_end)
            instance_match = /\A([A-Za-z_][A-Za-z0-9_$]*)/.match(source[cursor_after_params..])
            unless instance_match
              cursor = params_end
              next
            end

            instance_name = instance_match[1]
            cursor_after_instance = skip_verilog_spacing(source, cursor_after_params + instance_name.length)
            unless source[cursor_after_instance] == '('
              cursor = params_end
              next
            end

            matches << {
              start: start_index,
              replace_end: cursor_after_instance,
              instance_name: instance_name,
              params: split_verilog_argument_list(params_text)
            }
            cursor = cursor_after_instance
          end
          matches
        end

        def rewrite_vhdl_specialized_instantiations(source, rewrite_plan:)
          updated = source.dup
          Array(rewrite_plan).each do |entity_name, specializations|
            next if specializations.nil? || specializations.empty?

            replacements = find_parameterized_module_instantiations(source: updated, module_name: entity_name).reverse_each.map do |instance|
              key = specialization_key_from_params(instance.fetch(:params))
              specialized_module = specializations[key]
              next unless specialized_module

              [instance.fetch(:start), instance.fetch(:replace_end), "#{specialized_module} #{instance.fetch(:instance_name)}"]
            end.compact

            replacements.each do |start_index, end_index, replacement|
              updated[start_index...end_index] = replacement
            end
          end
          updated
        end

        def verilog_parameter_overrides_for_instance(params:, generic_names:)
          values = Array(params)
          return [] if values.empty?

          if values.any? { |value| value.start_with?('.') }
            named = values.each_with_object([]) do |value, acc|
              match = value.match(/\A\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*\((.*)\)\z/m)
              next unless match

              acc << [match[1], normalize_vhdl_generic_override_value(match[2])]
            end
            return named
          end

          Array(generic_names).zip(values).filter_map do |generic_name, value|
            next if generic_name.nil?
            next if value.nil? || value.to_s.strip.empty?

            [generic_name, normalize_vhdl_generic_override_value(value)]
          end
        end

        def normalize_vhdl_generic_override_value(value)
          stripped = value.to_s.strip
          case stripped
          when /\A\d+'h([0-9a-fA-F_]+)\z/i
            return %(X"#{$1.delete('_')}")
          when /\A\d+'o([0-7_]+)\z/i
            return %(O"#{$1.delete('_')}")
          when /\A\d+'b([01xXzZ_]+)\z/i
            return %(B"#{$1.delete('_')}")
          when /\A\d+'d([0-9_]+)\z/i
            return $1.delete('_')
          end

          if stripped.start_with?('"') && stripped.end_with?('"') && stripped.length >= 2
            stripped[1..-2]
          else
            stripped
          end
        end

        def specialized_vhdl_module_name(entity_name:, parameter_overrides:)
          digest = Digest::SHA1.hexdigest(
            Array(parameter_overrides).map { |name, value| "#{name}=#{value}" }.join("\u001f")
          )[0, 12]
          "#{entity_name}__vhdl_#{digest}"
        end

        def specialization_key_from_params(params)
          specialization_value_key(
            Array(params).map { |value| normalize_vhdl_generic_override_value(value) }
          )
        end

        def specialization_key_from_overrides(parameter_overrides)
          Array(parameter_overrides).map do |name, value|
            "#{name}=#{normalize_vhdl_generic_override_value(value)}"
          end.join("\u001f")
        end

        def specialization_value_key(values)
          Array(values).map { |value| normalize_vhdl_generic_override_value(value) }.join("\u001f")
        end

        def skip_verilog_spacing(source, index)
          cursor = index
          cursor += 1 while cursor < source.length && source[cursor].match?(/\s/)
          cursor
        end

        def extract_verilog_parenthesized(source, open_index)
          depth = 0
          cursor = open_index
          quote = nil
          while cursor < source.length
            char = source[cursor]
            if quote
              quote = nil if char == quote && source[cursor - 1] != '\\'
            elsif char == '"'
              quote = char
            elsif char == '('
              depth += 1
            elsif char == ')'
              depth -= 1
              return [source[(open_index + 1)...cursor], cursor + 1] if depth.zero?
            end
            cursor += 1
          end

          raise ArgumentError, 'Unbalanced Verilog parameter list while specializing mixed import'
        end

        def split_verilog_argument_list(text)
          args = []
          current = +''
          depth = 0
          quote = nil

          text.each_char do |char|
            if quote
              current << char
              quote = nil if char == quote && current[-2] != '\\'
              next
            end

            case char
            when '"'
              quote = char
              current << char
            when '(', '[', '{'
              depth += 1
              current << char
            when ')', ']', '}'
              depth -= 1 if depth.positive?
              current << char
            when ','
              if depth.zero?
                value = current.strip
                args << value unless value.empty?
                current = +''
              else
                current << char
              end
            else
              current << char
            end
          end

          value = current.strip
          args << value unless value.empty?
          args
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

        def with_timed_step(label)
          puts "Import step: #{label}"
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = yield
          puts "Import step complete: #{label} (#{format_step_duration(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at)})"
          result
        rescue StandardError
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
          puts "Import step failed: #{label} after #{format_step_duration(elapsed)}"
          raise
        end

        def format_step_duration(seconds)
          format('%.2fs', seconds)
        end
      end
    end
  end
end
