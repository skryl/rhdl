# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'yaml'
require 'json'
require 'set'

module RHDL
  module Examples
    module GameBoy
      module Import
        # System-level mixed HDL importer for the Game Boy reference design.
        # Resolves source files from Quartus QIP manifests and delegates import
        # execution to the shared CLI ImportTask flow.
        class SystemImporter
          DEFAULT_REFERENCE_ROOT = File.expand_path('../../reference', __dir__)
          DEFAULT_QIP_PATH = File.join(DEFAULT_REFERENCE_ROOT, 'files.qip')
          DEFAULT_TOP = 'gb'
          DEFAULT_TOP_FILE = File.join(DEFAULT_REFERENCE_ROOT, 'rtl', 'gb.v')
          DEFAULT_OUTPUT_DIR = File.expand_path('../../import', __dir__)
          DEFAULT_IMPORT_STRATEGY = :mixed
          VALID_IMPORT_STRATEGIES = %i[mixed compat].freeze

          MAX_COMPAT_RETRIES = 20
          DEFAULT_VHDL_STANDARD = '08'
          DEFAULT_VHDL_ANALYZE_ARGS = %w[-fsynopsys].freeze
          DEFAULT_VHDL_SYNTH_ARGS = %w[-fsynopsys].freeze
          DEFAULT_VHDL_SYNTH_TARGETS = %w[
            GBse
            gbc_snd
            gb_savestates
            gb_statemanager
            eReg_SavestateV
          ].freeze

          SOURCE_ASSIGNMENT_LANGUAGE = {
            'VERILOG_FILE' => 'verilog',
            'SYSTEMVERILOG_FILE' => 'verilog',
            'VHDL_FILE' => 'vhdl'
          }.freeze

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
            :files_written,
            :manifest_path,
            :mlir_path,
            :report_path,
            :diagnostics,
            :raise_diagnostics,
            :strategy_requested,
            :strategy_used,
            :fallback_used,
            :attempted_strategies,
            :source_verilog_path,
            :compatibility_metadata,
            keyword_init: true
          ) do
            def success?
              !!success
            end
          end

          attr_reader :reference_root, :qip_path, :top, :top_file, :output_dir, :workspace_dir,
                      :keep_workspace, :clean_output, :strict, :progress_callback, :import_task_class,
                      :import_strategy, :fallback_to_compat

          def initialize(reference_root: DEFAULT_REFERENCE_ROOT,
                         qip_path: DEFAULT_QIP_PATH,
                         top: DEFAULT_TOP,
                         top_file: DEFAULT_TOP_FILE,
                         output_dir: DEFAULT_OUTPUT_DIR,
                         workspace_dir: nil,
                         keep_workspace: false,
                         clean_output: true,
                         strict: true,
                         progress: nil,
                         import_task_class: nil,
                         import_strategy: DEFAULT_IMPORT_STRATEGY,
                         fallback_to_compat: true)
            @reference_root = File.expand_path(reference_root)
            @qip_path = File.expand_path(qip_path)
            @top = top.to_s
            @top_file = File.expand_path(top_file)
            @output_dir = File.expand_path(output_dir)
            @workspace_dir = workspace_dir && File.expand_path(workspace_dir)
            @keep_workspace = keep_workspace
            @clean_output = clean_output
            @strict = strict
            @progress_callback = progress
            @import_task_class = import_task_class
            @import_strategy = normalize_strategy(import_strategy)
            @fallback_to_compat = fallback_to_compat
          end

          def run
            diagnostics = []
            raise_diagnostics = []
            workspace = workspace_dir || Dir.mktmpdir('rhdl_gameboy_import')
            temp_workspace = workspace if workspace_dir.nil?

            emit_progress('resolve mixed sources from QIP')
            resolved = resolve_sources

            emit_progress("prepare output directory: #{output_dir}")
            prepare_output_dir!

            emit_progress('write mixed import manifest')
            manifest_path = write_manifest(workspace: workspace, resolved: resolved)
            report_path = File.join(output_dir, 'import_report.json')

            attempts = strategy_attempts
            attempts.each do |strategy|
              emit_progress("run import strategy: #{strategy}")

              if strategy == :mixed
                source_verilog_path = nil
                mlir_path = File.join(workspace, "#{top}.mlir")
                import_result = run_import_task(
                  mode: :mixed,
                  manifest_path: manifest_path,
                  mlir_path: mlir_path,
                  report_path: report_path
                )
                compatibility_metadata = nil
              else
                compat = build_compat_wrapper(workspace: workspace, resolved: resolved)
                source_verilog_path = compat.fetch(:wrapper_path)
                mlir_path = File.join(workspace, "#{top}.compat.core.mlir")
                import_result = run_compat_import_task(
                  wrapper_path: source_verilog_path,
                  core_mlir_path: mlir_path,
                  report_path: report_path
                )
                compatibility_metadata = compat.reject { |k, _| k == :wrapper_path }
              end

              attempt_diags = Array(import_result[:diagnostics])
              diagnostics.concat(attempt_diags)
              raise_diagnostics.concat(Array(import_result[:raise_diagnostics]))

              next unless import_result[:success]

              augment_report_for_compat(
                report_path: report_path,
                resolved: resolved,
                source_verilog_path: source_verilog_path,
                compatibility_metadata: compatibility_metadata
              ) if strategy == :compat

              return Result.new(
                success: true,
                output_dir: output_dir,
                workspace: workspace,
                files_written: import_result[:files_written],
                manifest_path: manifest_path,
                mlir_path: mlir_path,
                report_path: report_path,
                diagnostics: diagnostics,
                raise_diagnostics: raise_diagnostics,
                strategy_requested: import_strategy,
                strategy_used: strategy,
                fallback_used: strategy != import_strategy,
                attempted_strategies: attempts,
                source_verilog_path: source_verilog_path,
                compatibility_metadata: compatibility_metadata
              )
            end

            Result.new(
              success: false,
              output_dir: output_dir,
              workspace: workspace,
              files_written: [],
              manifest_path: manifest_path,
              mlir_path: nil,
              report_path: report_path,
              diagnostics: diagnostics,
              raise_diagnostics: raise_diagnostics,
              strategy_requested: import_strategy,
              strategy_used: nil,
              fallback_used: false,
              attempted_strategies: attempts,
              source_verilog_path: nil,
              compatibility_metadata: nil
            )
          rescue StandardError, SystemStackError => e
            diagnostics << e.message
            Result.new(
              success: false,
              output_dir: output_dir,
              workspace: workspace_dir,
              files_written: [],
              manifest_path: nil,
              mlir_path: nil,
              report_path: nil,
              diagnostics: diagnostics,
              raise_diagnostics: raise_diagnostics,
              strategy_requested: import_strategy,
              strategy_used: nil,
              fallback_used: false,
              attempted_strategies: strategy_attempts,
              source_verilog_path: nil,
              compatibility_metadata: nil
            )
          ensure
            FileUtils.rm_rf(temp_workspace) if defined?(temp_workspace) && temp_workspace && !keep_workspace
          end

          def resolve_sources
            validate_source_inputs!

            visited_qips = {}
            ordered_qips = []
            ordered_sources = []
            seen_sources = {}
            parse_qip_recursive(
              qip_path,
              visited_qips: visited_qips,
              ordered_qips: ordered_qips,
              ordered_sources: ordered_sources,
              seen_sources: seen_sources
            )

            normalized_top_file = File.expand_path(top_file)
            unless ordered_sources.any? { |entry| File.expand_path(entry[:path]) == normalized_top_file }
              top_lang = normalize_language(path: normalized_top_file)
              ordered_sources << { path: normalized_top_file, language: top_lang, library: nil }
            end

            {
              top: {
                name: top,
                file: normalized_top_file,
                language: normalize_language(path: normalized_top_file)
              },
              files: ordered_sources,
              qip_files: ordered_qips
            }
          end

          def write_manifest(workspace:, resolved: nil)
            resolved ||= resolve_sources
            manifest_path = File.join(workspace, 'gameboy_mixed_import.yml')
            prepared_files = manifest_source_files(workspace: workspace, resolved: resolved)
            staged_root = File.join(workspace, 'mixed_sources')
            original_top_file = resolved.fetch(:top).fetch(:file)
            staged_top_file = staged_path_for_source(path: original_top_file, staged_root: staged_root)
            top_file_for_manifest = prepared_files.any? { |entry| File.expand_path(entry.fetch(:path)) == File.expand_path(staged_top_file) } ? staged_top_file : original_top_file

            payload = {
              'version' => 1,
              'top' => {
                'name' => resolved.fetch(:top).fetch(:name),
                'file' => top_file_for_manifest,
                'language' => resolved.fetch(:top).fetch(:language)
              },
              'files' => prepared_files.map do |entry|
                data = {
                  'path' => entry.fetch(:path),
                  'language' => entry.fetch(:language)
                }
                data['library'] = entry[:library] if entry[:library]
                data
              end,
              'vhdl' => {
                'standard' => DEFAULT_VHDL_STANDARD,
                'analyze_args' => DEFAULT_VHDL_ANALYZE_ARGS,
                'synth_args' => DEFAULT_VHDL_SYNTH_ARGS,
                'synth_targets' => DEFAULT_VHDL_SYNTH_TARGETS.map { |name| { 'entity' => name } }
              }
            }

            File.write(manifest_path, YAML.dump(payload))
            manifest_path
          end

          private

          def normalize_strategy(value)
            strategy = value.to_sym
            return strategy if VALID_IMPORT_STRATEGIES.include?(strategy)

            raise ArgumentError,
                  "Unknown import_strategy #{value.inspect}. Expected one of: #{VALID_IMPORT_STRATEGIES.join(', ')}"
          end

          def strategy_attempts
            attempts = [import_strategy]
            attempts << :compat if import_strategy == :mixed && fallback_to_compat
            attempts.uniq
          end

          def emit_progress(message)
            if progress_callback.respond_to?(:call)
              progress_callback.call(message)
            else
              puts "GameBoy import step: #{message}"
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

          def manifest_source_files(workspace:, resolved:)
            staged_root = File.join(workspace, 'mixed_sources')
            FileUtils.mkdir_p(staged_root)
            selected_verilog_paths = selected_verilog_source_paths_for_mixed(resolved: resolved)

            resolved.fetch(:files).flat_map do |entry|
              source_path = File.expand_path(entry.fetch(:path))

              if entry.fetch(:language) == 'verilog'
                next [] unless selected_verilog_paths.include?(source_path)

                [{
                  path: stage_verilog_source(path: source_path, staged_root: staged_root),
                  language: 'verilog',
                  library: nil
                }]
              elsif entry.fetch(:language) == 'vhdl'
                case File.basename(source_path).downcase
                when 'spram.vhd'
                  [{
                    path: write_spram_verilog_replacement(staged_root),
                    language: 'verilog',
                    library: nil
                  }]
                when 'dpram.vhd'
                  [{
                    path: write_dpram_verilog_replacement(staged_root),
                    language: 'verilog',
                    library: nil
                  }]
                else
                  [{
                    path: stage_vhdl_source(path: source_path, staged_root: staged_root),
                    language: 'vhdl',
                    library: entry[:library]
                  }]
                end
              else
                []
              end
            end
          end

          def selected_verilog_source_paths_for_mixed(resolved:)
            verilog_paths = resolved.fetch(:files)
              .select { |entry| entry.fetch(:language) == 'verilog' }
              .map { |entry| File.expand_path(entry.fetch(:path)) }

            module_to_file = module_index(verilog_paths)
            refs = module_reference_graph(verilog_paths)
            closure_modules = module_closure(top, refs)
            selected = closure_modules.filter_map { |name| module_to_file[name] }.uniq
            top_path = File.expand_path(top_file)
            selected << top_path if File.extname(top_path).downcase.match?(/\A\.(v|sv)\z/) && File.file?(top_path)
            selected.to_set
          end

          def stage_verilog_source(path:, staged_root:)
            staged_path = staged_path_for_source(path: path, staged_root: staged_root)
            FileUtils.mkdir_p(File.dirname(staged_path))
            content = normalize_verilog_for_import(File.read(path), source_path: path)
            File.write(staged_path, content)
            staged_path
          end

          def normalize_verilog_for_import(content, source_path:)
            text = normalize_verilog_for_circt(content)
            # CIRCT import is stricter about procedural assignments to plain `output`.
            text = text.gsub(/\boutput\b(?!\s+(?:reg|logic)\b)/, 'output logic')

            case File.basename(source_path).downcase
            when 'cheatcodes.sv'
              text = text.sub(
                /module\s+CODES\s*\((.*?)\);\s*parameter\s+ADDR_WIDTH\s*=\s*16\s*;.*?parameter\s+DATA_WIDTH\s*=\s*8\s*;.*?parameter\s+MAX_CODES\s*=\s*32\s*;/m,
                "module CODES #(\n\tparameter ADDR_WIDTH = 16,\n\tparameter DATA_WIDTH = 8,\n\tparameter MAX_CODES = 32\n)(\\1);"
              )
              text = text.gsub(/\bwire\s+\[INDEX_SIZE-1:0\]\s+index\s*,\s*dup_index\s*;/, 'logic [INDEX_SIZE-1:0] index, dup_index;')
              text = text.gsub(/\bwire\s+found_dup\s*;/, 'logic found_dup;')
            end

            text
          end

          def stage_vhdl_source(path:, staged_root:)
            staged_path = staged_path_for_source(path: path, staged_root: staged_root)
            FileUtils.mkdir_p(File.dirname(staged_path))
            content = normalize_vhdl_for_ghdl(File.read(path), source_path: path)
            File.write(staged_path, content)
            staged_path
          end

          def staged_path_for_source(path:, staged_root:)
            relative = if path.start_with?(reference_root)
                         path.delete_prefix("#{reference_root}/")
                       else
                         File.basename(path)
                       end
            File.join(staged_root, relative)
          end

          def normalize_vhdl_for_ghdl(content, source_path:)
            text = content.dup
            case File.basename(source_path).downcase
            when 'bus_savestates.vhd'
              # `default` as a record field name trips older/stricter frontends.
              text = text.gsub(/\bdefault\s*:/, 'default_value :')
              text = text.gsub(/\bReg\.default\b/, 'Reg.default_value')
            when 'gbc_snd.vhd'
              # This reference uses non-standard scalar `'high` on integer signal.
              text = text.gsub(/\bdac_decay_timer'high\b/, '100')
            end
            text
          end

          def write_spram_verilog_replacement(staged_root)
            path = File.join(staged_root, 'spram_compat.v')
            return path if File.file?(path)

            text = <<~VERILOG
              // Auto-generated fallback replacement for spram.vhd (altera_mf).
              module spram
              #(
                parameter addr_width = 8,
                parameter data_width = 8
              )
              (
                input clock,
                input clken,
                input [addr_width-1:0] address,
                input [data_width-1:0] data,
                input wren,
                output reg [data_width-1:0] q
              );
                localparam DEPTH = (1 << addr_width);
                reg [data_width-1:0] mem [0:DEPTH-1];

                always @(posedge clock) begin
                  if (clken) begin
                    if (wren) begin
                      mem[address] <= data;
                      q <= data;
                    end else begin
                      q <= mem[address];
                    end
                  end
                end
              endmodule
            VERILOG
            File.write(path, text)
            path
          end

          def write_dpram_verilog_replacement(staged_root)
            path = File.join(staged_root, 'dpram_compat.v')
            return path if File.file?(path)

            text = <<~VERILOG
              // Auto-generated fallback replacement for dpram.vhd (altera_mf).
              module dpram
              #(
                parameter addr_width = 8,
                parameter data_width = 8
              )
              (
                input clock_a,
                input clken_a,
                input [addr_width-1:0] address_a,
                input [data_width-1:0] data_a,
                input wren_a,
                output reg [data_width-1:0] q_a,
                input clock_b,
                input clken_b,
                input [addr_width-1:0] address_b,
                input [data_width-1:0] data_b,
                input wren_b,
                output reg [data_width-1:0] q_b
              );
                localparam DEPTH = (1 << addr_width);
                reg [data_width-1:0] mem [0:DEPTH-1];

                always @(posedge clock_a) begin
                  if (clken_a) begin
                    if (wren_a) begin
                      mem[address_a] <= data_a;
                      q_a <= data_a;
                    end else begin
                      q_a <= mem[address_a];
                    end
                  end
                end

                always @(posedge clock_b) begin
                  if (clken_b) begin
                    if (wren_b) begin
                      mem[address_b] <= data_b;
                      q_b <= data_b;
                    end else begin
                      q_b <= mem[address_b];
                    end
                  end
                end
              endmodule

              module dpram_dif
              #(
                parameter addr_width_a = 8,
                parameter data_width_a = 8,
                parameter addr_width_b = 8,
                parameter data_width_b = 8,
                parameter mem_init_file = " "
              )
              (
                input clock,
                input [addr_width_a-1:0] address_a,
                input [data_width_a-1:0] data_a,
                input enable_a,
                input wren_a,
                output [data_width_a-1:0] q_a,
                input cs_a,
                input [addr_width_b-1:0] address_b,
                input [data_width_b-1:0] data_b,
                input enable_b,
                input wren_b,
                output [data_width_b-1:0] q_b,
                input cs_b
              );
                localparam MAX_DATA_WIDTH = (data_width_a > data_width_b) ? data_width_a : data_width_b;
                localparam MAX_ADDR_WIDTH = (addr_width_a > addr_width_b) ? addr_width_a : addr_width_b;
                localparam DEPTH = (1 << MAX_ADDR_WIDTH);

                reg [MAX_DATA_WIDTH-1:0] mem [0:DEPTH-1];
                reg [data_width_a-1:0] q0;
                reg [data_width_b-1:0] q1;
                wire wren_a_comb = wren_a & cs_a;
                wire wren_b_comb = wren_b & cs_b;

                always @(posedge clock) begin
                  if (enable_a) begin
                    if (wren_a_comb) begin
                      mem[address_a][data_width_a-1:0] <= data_a;
                      q0 <= data_a;
                    end else begin
                      q0 <= mem[address_a][data_width_a-1:0];
                    end
                  end

                  if (enable_b) begin
                    if (wren_b_comb) begin
                      mem[address_b][data_width_b-1:0] <= data_b;
                      q1 <= data_b;
                    end else begin
                      q1 <= mem[address_b][data_width_b-1:0];
                    end
                  end
                end

                assign q_a = cs_a ? q0 : {data_width_a{1'b1}};
                assign q_b = cs_b ? q1 : {data_width_b{1'b1}};
              endmodule
            VERILOG
            File.write(path, text)
            path
          end

          def run_import_task(mode:, mlir_path:, report_path:, manifest_path: nil, input_path: nil)
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
              raise_to_dsl: true
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

          def run_compat_import_task(wrapper_path:, core_mlir_path:, report_path:)
            require 'rhdl/codegen'
            require 'open3'

            moore_mlir_path = core_mlir_path.sub(/\.core\.mlir\z/, '.moore.mlir')
            import = RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
              verilog_path: wrapper_path,
              out_path: moore_mlir_path,
              tool: RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL
            )
            unless import[:success]
              return {
                success: false,
                diagnostics: [
                  "Compatibility Verilog->Moore import failed.\nCommand: #{import[:command]}\n#{import[:stderr]}"
                ],
                raise_diagnostics: [],
                files_written: []
              }
            end

            lower_cmd = [
              'circt-opt',
              '--moore-lower-concatref',
              '--canonicalize',
              '--moore-lower-concatref',
              '--convert-moore-to-core',
              '--llhd-sig2reg',
              '--canonicalize',
              moore_mlir_path,
              '-o',
              core_mlir_path
            ]
            lower_stdout, lower_stderr, lower_status = Open3.capture3(*lower_cmd)
            unless lower_status.success?
              return {
                success: false,
                diagnostics: [
                  "Compatibility Moore->core lowering failed.\nCommand: #{lower_cmd.join(' ')}\n#{lower_stdout}\n#{lower_stderr}"
                ],
                raise_diagnostics: [],
                files_written: []
              }
            end

            run_import_task(
              mode: :circt,
              input_path: core_mlir_path,
              mlir_path: core_mlir_path,
              report_path: report_path
            )
          end

          def augment_report_for_compat(report_path:, resolved:, source_verilog_path:, compatibility_metadata:)
            return unless File.file?(report_path)

            report = JSON.parse(File.read(report_path))
            report['mixed_import'] ||= {
              'top_name' => resolved.fetch(:top).fetch(:name),
              'top_language' => resolved.fetch(:top).fetch(:language),
              'top_file' => resolved.fetch(:top).fetch(:file),
              'source_files' => resolved.fetch(:files).map do |entry|
                {
                  'path' => entry.fetch(:path),
                  'language' => entry.fetch(:language),
                  'library' => entry[:library]
                }
              end,
              'staging_entry_path' => source_verilog_path,
              'compatibility' => compatibility_metadata
            }
            File.write(report_path, JSON.pretty_generate(report))
          rescue JSON::ParserError
            # Keep original report if JSON is malformed.
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

          def build_compat_wrapper(workspace:, resolved:)
            require 'rhdl/codegen'

            compat_root = File.join(workspace, 'compat')
            FileUtils.mkdir_p(compat_root)

            verilog_files = resolved.fetch(:files)
              .select { |entry| entry[:language] == 'verilog' }
              .map { |entry| File.expand_path(entry.fetch(:path)) }

            module_to_file = module_index(verilog_files)
            module_refs = module_reference_graph(verilog_files)
            closure_modules = module_closure(top, module_refs)
            selected_files = closure_modules.filter_map { |name| module_to_file[name] }.uniq
            missing_modules = closure_modules - module_to_file.keys

            stub_profiles = missing_modules.each_with_object({}) { |name, acc| acc[name] = empty_stub_profile }
            excluded_files = []
            promoted_output_logic = []

            wrapper_path = File.join(compat_root, 'compat_wrapper.sv')
            stub_path = File.join(compat_root, 'compat_stubs.sv')
            dryrun_mlir = File.join(compat_root, 'compat_dryrun.mlir')

            MAX_COMPAT_RETRIES.times do |attempt|
              staged_map = stage_compat_sources(
                compat_root: compat_root,
                selected_files: selected_files,
                excluded_files: excluded_files,
                attempt: attempt
              )
              staged_reverse = {}
              staged_map.each do |original, staged|
                staged_reverse[staged] = original
                staged_reverse[canonical_path(staged)] = original
              end

              write_stub_file(stub_path, stub_profiles)
              write_wrapper_file(wrapper_path, staged_paths: staged_map.values, stub_path: stub_path)

              dryrun = RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
                verilog_path: wrapper_path,
                out_path: dryrun_mlir,
                tool: RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL
              )
              if dryrun[:success]
                return {
                  wrapper_path: wrapper_path,
                  excluded_files: excluded_files.sort,
                  promoted_output_logic: promoted_output_logic.sort,
                  stub_modules: stub_profiles.keys.sort,
                  closure_modules: closure_modules.sort
                }
              end

              changed = apply_compat_diagnostics!(
                stderr: dryrun[:stderr],
                stub_profiles: stub_profiles,
                excluded_files: excluded_files,
                promoted_output_logic: promoted_output_logic,
                top_file: File.expand_path(top_file),
                staged_reverse: staged_reverse,
                module_to_file: module_to_file
              )

              next if changed

              excerpt = dryrun[:stderr].to_s.lines.first(40).join
              raise RuntimeError,
                    "Compatibility import staging failed to converge.\nCommand: #{dryrun[:command]}\n#{excerpt}"
            end

            raise RuntimeError, "Compatibility import exceeded retry limit (#{MAX_COMPAT_RETRIES})"
          end

          def stage_compat_sources(compat_root:, selected_files:, excluded_files:, attempt:)
            stage_dir = File.join(compat_root, "stage_#{attempt}")
            FileUtils.rm_rf(stage_dir)
            FileUtils.mkdir_p(stage_dir)

            selected_files.each_with_object({}) do |path, acc|
              next if excluded_files.include?(path)

              rel = path.sub(%r{\A/}, '').gsub('/', '__')
              staged = File.join(stage_dir, rel)
              text = File.read(path)
              File.write(staged, normalize_verilog_for_circt(text))
              acc[path] = staged
            end
          end

          def apply_compat_diagnostics!(stderr:, stub_profiles:, excluded_files:, promoted_output_logic:, top_file:, staged_reverse:, module_to_file:)
            changed = false
            text = stderr.to_s
            canonical_top = canonical_path(top_file)

            text.scan(/unknown module '([A-Za-z_][A-Za-z0-9_$]*)'/).flatten.each do |mod|
              next if stub_profiles.key?(mod)

              stub_profiles[mod] = empty_stub_profile
              changed = true
            end

            text.scan(/port '([A-Za-z_][A-Za-z0-9_$]*)' does not exist in '([A-Za-z_][A-Za-z0-9_$]*)'/).each do |port, mod|
              profile = stub_profiles[mod] ||= empty_stub_profile
              next if profile[:named_ports].include?(port)

              profile[:named_ports] << port
              changed = true
            end

            text.scan(/too many parameter assignments given for '([A-Za-z_][A-Za-z0-9_$]*)' \((\d+) given/).each do |mod, count|
              profile = stub_profiles[mod] ||= empty_stub_profile
              n = count.to_i
              next unless profile[:positional_params] < n

              profile[:positional_params] = n
              changed = true
            end

            text.scan(/too many port connections given to instantiation of '([A-Za-z_][A-Za-z0-9_$]*)' \((\d+) given/).each do |mod, count|
              profile = stub_profiles[mod] ||= empty_stub_profile
              n = count.to_i
              next unless profile[:positional_ports] < n

              profile[:positional_ports] = n
              changed = true
            end

            problematic_errors = text.scan(%r{^([^:\n]+\.(?:v|sv)):\d+:\d+:\s+error:\s+(.+)$})
            problematic_errors.each do |path, message|
              next unless message.match?(/cannot assign to a net within a procedural context|identifier '.*?' used before its declaration/)

              expanded_path = File.expand_path(path, Dir.pwd)
              canonical_pathname = canonical_path(expanded_path)
              original = staged_reverse[path] || staged_reverse[expanded_path] || staged_reverse[canonical_pathname] || expanded_path

              if message.include?('cannot assign to a net within a procedural context')
                staged_file = [path, expanded_path, canonical_pathname].find { |candidate| candidate && File.file?(candidate) }
                if staged_file && !promoted_output_logic.include?(staged_file)
                  if promote_output_nets_to_logic!(staged_file)
                    promoted_output_logic << staged_file
                    changed = true
                    next
                  end
                end
              end

              next if canonical_path(original) == canonical_top
              next if excluded_files.include?(original)

              excluded_files << original
              changed = true
              module_names_for_file(original, module_to_file).each do |mod|
                stub_profiles[mod] ||= empty_stub_profile
              end
            end

            changed
          end

          def empty_stub_profile
            {
              named_ports: [],
              positional_ports: 0,
              named_params: [],
              positional_params: 0
            }
          end

          def module_names_for_file(path, module_to_file)
            module_to_file.each_with_object([]) do |(name, file), acc|
              acc << name if file == path
            end
          end

          def write_stub_file(path, stub_profiles)
            lines = []
            lines << '// Auto-generated compatibility stubs for unsupported modules'
            lines << ''

            stub_profiles.keys.sort.each do |module_name|
              profile = stub_profiles.fetch(module_name)
              params = profile[:named_params].map { |name| "parameter #{name}=0" }
              if profile[:positional_params] > params.length
                (params.length...profile[:positional_params]).each { |idx| params << "parameter P#{idx}=0" }
              end

              ports = profile[:named_ports].dup
              if profile[:positional_ports] > ports.length
                (ports.length...profile[:positional_ports]).each { |idx| ports << "p#{idx}" }
              end

              header = "module #{module_name}"
              header += " #(#{params.join(', ')})" if params.any?
              if ports.any?
                lines << "#{header} (#{ports.map { |name| "input #{name}" }.join(', ')});"
              else
                lines << "#{header};"
              end
              lines << 'endmodule'
              lines << ''
            end

            File.write(path, "#{lines.join("\n")}\n")
          end

          def write_wrapper_file(path, staged_paths:, stub_path:)
            lines = []
            lines << '// Auto-generated compatibility wrapper'
            staged_paths.each do |source_path|
              escaped = source_path.gsub('\\', '/').gsub('"', '\\"')
              lines << "`include \"#{escaped}\""
            end
            escaped_stub = stub_path.gsub('\\', '/').gsub('"', '\\"')
            lines << "`include \"#{escaped_stub}\""
            File.write(path, "#{lines.join("\n")}\n")
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
                body.scan(/\b([A-Za-z_][A-Za-z0-9_$]*)\s*(?:#\s*\(.*?\))?\s+([A-Za-z_][A-Za-z0-9_$]*)\s*\(/m) do |target, _inst_name|
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

          def strip_comments(text)
            text
              .gsub(%r{//.*$}, '')
              .gsub(%r{/\*.*?\*/}m, '')
          end

          def promote_output_nets_to_logic!(path)
            return false unless File.file?(path)

            source = File.read(path)
            updated = source.dup
            updated.gsub!(/\boutput\s+wire\b/, 'output logic')
            updated.gsub!(/\boutput\b(?!\s+(?:reg|logic)\b)/, 'output logic')
            return false if updated == source

            File.write(path, updated)
            true
          end

          def canonical_path(path)
            return nil if path.nil? || path.empty?

            File.realpath(path)
          rescue StandardError
            File.expand_path(path)
          end

          def normalize_verilog_for_circt(text)
            out = +''
            idx = 0

            while (module_match = text.match(/\bmodule\s+[A-Za-z_][A-Za-z0-9_$]*\b.*?;/m, idx))
              break unless module_match.begin(0) >= idx

              out << text[idx...module_match.begin(0)]
              header = module_match[0]
              body_start = module_match.end(0)
              end_match = text.match(/\bendmodule\b/m, body_start)
              break unless end_match

              body = text[body_start...end_match.begin(0)]
              out << header
              out << normalize_module_body(body)
              out << 'endmodule'
              idx = end_match.end(0)
            end

            out << text[idx..] if idx < text.length
            out
          end

          def normalize_module_body(body)
            params = []
            declarations = []
            remainder = []

            body.each_line do |line|
              code = strip_trailing_line_comment(line).strip
              if parameter_statement?(code)
                params << line
                next
              end

              if declaration_statement?(code)
                rewritten_decl, rewritten_assign = split_initialized_declaration(line, code)
                declarations << rewritten_decl
                remainder << rewritten_assign if rewritten_assign
                next
              end

              remainder << line
            end

            rebuilt = +"\n"
            rebuilt << params.join
            rebuilt << "\n" if params.any?
            rebuilt << declarations.join
            rebuilt << "\n" if declarations.any?
            rebuilt << remainder.join
            rebuilt
          end

          def parameter_statement?(code)
            return false if code.nil? || code.empty?
            return false unless code.start_with?('parameter ', 'localparam ')

            code.end_with?(';')
          end

          def declaration_statement?(code)
            return false if code.nil? || code.empty?
            return false unless code.match?(/\A(?:wire|reg|logic)\b/)

            code.end_with?(';')
          end

          def split_initialized_declaration(line, code)
            # Preserve multi-signal declarations in place.
            return [line, nil] if code.include?(',')

            match = code.match(/\A((?:wire|reg|logic)\b[^=;]*?)=\s*(.+);\z/)
            return [line, nil] unless match

            lhs = match[1].strip
            rhs = match[2].strip
            signal_name = declaration_name(lhs)
            return [line, nil] unless signal_name

            indent = line[/\A\s*/] || ''
            comment = extract_trailing_line_comment(line)
            decl_line = +"#{indent}#{lhs};"
            decl_line << " #{comment}" if comment
            decl_line << "\n"
            assign_line = "#{indent}assign #{signal_name} = #{rhs};\n"
            [decl_line, assign_line]
          end

          def strip_trailing_line_comment(line)
            line.to_s.sub(%r{//.*$}, '')
          end

          def extract_trailing_line_comment(line)
            comment_idx = line.index('//')
            return nil unless comment_idx

            line[comment_idx..].strip
          end

          def declaration_name(lhs)
            return nil if lhs.nil? || lhs.empty?

            m = lhs.match(/([A-Za-z_][A-Za-z0-9_$]*)\s*(?:\[[^\]]+\])?\s*\z/)
            m && m[1]
          end

          def validate_source_inputs!
            raise ArgumentError, "GameBoy reference root not found: #{reference_root}" unless Dir.exist?(reference_root)
            raise ArgumentError, "QIP file not found: #{qip_path}" unless File.file?(qip_path)
            raise ArgumentError, "Top source file not found: #{top_file}" unless File.file?(top_file)
          end

          def parse_qip_recursive(path, visited_qips:, ordered_qips:, ordered_sources:, seen_sources:)
            normalized = File.expand_path(path)
            return if visited_qips.key?(normalized)

            visited_qips[normalized] = true
            ordered_qips << normalized
            base_dir = File.dirname(normalized)

            File.readlines(normalized, chomp: true).each do |line|
              parsed = parse_qip_assignment(line)
              next unless parsed

              assignment = parsed.fetch(:assignment)
              raw_value = parsed.fetch(:value)
              candidate = resolve_qip_value(raw_value, base_dir: base_dir)
              next if candidate.nil? || candidate.empty?

              if assignment == 'QIP_FILE'
                parse_qip_recursive(
                  candidate,
                  visited_qips: visited_qips,
                  ordered_qips: ordered_qips,
                  ordered_sources: ordered_sources,
                  seen_sources: seen_sources
                )
                next
              end

              language = SOURCE_ASSIGNMENT_LANGUAGE[assignment]
              next unless language
              next unless File.file?(candidate)

              key = File.expand_path(candidate)
              next if seen_sources[key]

              seen_sources[key] = true
              ordered_sources << {
                path: key,
                language: language,
                library: nil
              }
            end
          end

          def parse_qip_assignment(line)
            stripped = line.to_s.sub(/#.*/, '').strip
            return nil if stripped.empty?

            match = stripped.match(/\Aset_global_assignment\s+-name\s+(\S+)\s+(.+)\z/i)
            return nil unless match

            assignment = match[1].to_s.upcase
            value = match[2].to_s.strip
            { assignment: assignment, value: value }
          end

          def resolve_qip_value(raw_value, base_dir:)
            value = raw_value.strip
            join_match = value.match(/\A\[file\s+join\s+\$::quartus\(qip_path\)\s+(.+)\]\z/i)
            if join_match
              rest = join_match[1].strip
              tokens = rest.split(/\s+/).map { |token| strip_quotes(token) }.reject(&:empty?)
              return nil if tokens.empty?

              return File.expand_path(File.join(base_dir, *tokens))
            end

            File.expand_path(File.join(base_dir, strip_quotes(value)))
          end

          def strip_quotes(value)
            value.to_s.gsub(/\A['"]|['"]\z/, '').strip
          end

          def normalize_language(path:)
            ext = File.extname(path).downcase
            return 'vhdl' if %w[.vhd .vhdl].include?(ext)

            'verilog'
          end
        end
      end
    end
  end
end
