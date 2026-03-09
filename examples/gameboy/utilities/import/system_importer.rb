# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'yaml'
require 'json'
require 'set'
require 'pathname'

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
          VALID_IMPORT_STRATEGIES = %i[mixed].freeze
          DEFAULT_VHDL_STANDARD = '08'
          DEFAULT_VHDL_ANALYZE_ARGS = %w[-fsynopsys].freeze
          DEFAULT_VHDL_SYNTH_ARGS = %w[-fsynopsys].freeze
          DEFAULT_VHDL_SYNTH_TARGETS = %w[
            GBse
            gbc_snd
            gb_savestates
            gb_statemanager
            eReg_SavestateV
            spram
            dpram
            dpram_dif
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
            keyword_init: true
          ) do
            def success?
              !!success
            end
          end

          attr_reader :reference_root, :qip_path, :top, :top_file, :output_dir, :workspace_dir,
                      :keep_workspace, :clean_output, :strict, :progress_callback, :import_task_class,
                      :import_strategy, :maintain_directory_structure, :emit_runtime_json

          def initialize(reference_root: DEFAULT_REFERENCE_ROOT,
                         qip_path: DEFAULT_QIP_PATH,
                         top: DEFAULT_TOP,
                         top_file: DEFAULT_TOP_FILE,
                         output_dir: DEFAULT_OUTPUT_DIR,
                         workspace_dir: nil,
                         keep_workspace: false,
                         clean_output: true,
                         maintain_directory_structure: true,
                         emit_runtime_json: true,
                         strict: true,
                         progress: nil,
                         import_task_class: nil,
                         import_strategy: DEFAULT_IMPORT_STRATEGY)
            @reference_root = File.expand_path(reference_root)
            @qip_path = File.expand_path(qip_path)
            @top = top.to_s
            @top_file = File.expand_path(top_file)
            @output_dir = File.expand_path(output_dir)
            @workspace_dir = workspace_dir && File.expand_path(workspace_dir)
            @keep_workspace = keep_workspace
            @clean_output = clean_output
            @maintain_directory_structure = maintain_directory_structure
            @emit_runtime_json = emit_runtime_json
            @strict = strict
            @progress_callback = progress
            @import_task_class = import_task_class
            @import_strategy = normalize_strategy(import_strategy)
            @selected_verilog_analysis_cache = {}
            @verilog_file_analysis_cache = {}
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

            emit_progress('run import strategy: mixed')
            requested_mlir_path = File.join(output_dir, '.mixed_import', "#{top}.core.mlir")
            import_result = run_import_task(
              mode: :mixed,
              manifest_path: manifest_path,
              mlir_path: requested_mlir_path,
              report_path: report_path
            )

            diagnostics.concat(Array(import_result[:diagnostics]))
            raise_diagnostics.concat(Array(import_result[:raise_diagnostics]))

            if import_result[:success]
              files_written = import_result[:files_written]
              report = read_report(report_path)
              module_source_relpaths = module_source_relpaths_for_report(report: report, resolved: resolved)
              if maintain_directory_structure
                emit_progress('remap output to source directory layout')
                files_written = remap_output_layout(
                  files_written: files_written,
                  module_source_relpaths: module_source_relpaths,
                  diagnostics: diagnostics
                )
              end
              component_manifest = build_component_manifest(
                report: report,
                files_written: files_written,
                module_source_relpaths: module_source_relpaths
              )
              report = merge_component_manifest_into_report(
                report_path: report_path,
                components: component_manifest,
                raised_files: files_written
              )
              workspace_artifacts = stage_workspace_artifacts(
                workspace: workspace,
                artifacts: report.fetch('artifacts', {}),
                report_path: report_path
              )
              report = merge_workspace_artifacts_into_report(
                report_path: report_path,
                workspace_artifacts: workspace_artifacts
              )
              artifacts = report.fetch('artifacts', {})
              return Result.new(
                success: true,
                output_dir: output_dir,
                workspace: workspace,
                files_written: files_written,
                manifest_path: manifest_path,
                mlir_path: artifacts['core_mlir_path'] || requested_mlir_path,
                report_path: report_path,
                diagnostics: diagnostics,
                raise_diagnostics: raise_diagnostics,
                strategy_requested: import_strategy,
                strategy_used: :mixed,
                fallback_used: false,
                attempted_strategies: [:mixed],
                source_verilog_path: artifacts['workspace_normalized_verilog_path'] ||
                  artifacts['pure_verilog_entry_path'] ||
                  artifacts['normalized_verilog_path']
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
              attempted_strategies: [:mixed],
              source_verilog_path: nil
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
              attempted_strategies: [:mixed],
              source_verilog_path: nil
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

          def rewrite_video_spr_extra_tile_array_text(text)
            updated = text.dup
            updated.gsub!(
              /\bwire\s+\[7:0\]\s+spr_extra_tile\s*\[0:1\]\s*;/,
              "wire [7:0] spr_extra_tile0;\nwire [7:0] spr_extra_tile1;"
            )
            updated.gsub!(/\bspr_extra_tile\[0\]/, 'spr_extra_tile0')
            updated.gsub!(/\bspr_extra_tile\[1\]/, 'spr_extra_tile1')
            updated
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

            prepared = resolved.fetch(:files).flat_map do |entry|
              source_path = File.expand_path(entry.fetch(:path))

              if entry.fetch(:language) == 'verilog'
                next [] unless selected_verilog_paths.include?(source_path)

                [{
                  path: stage_verilog_source(path: source_path, staged_root: staged_root),
                  language: 'verilog',
                  library: nil
                }]
              elsif entry.fetch(:language) == 'vhdl'
                [{
                  path: stage_vhdl_source(path: source_path, staged_root: staged_root),
                  language: 'vhdl',
                  library: entry[:library]
                }]
              else
                []
              end
            end
            prepared.unshift(*vendor_vhdl_shim_entries(staged_root: staged_root))
            prepared
          end

          def selected_verilog_source_paths_for_mixed(resolved:)
            selected_verilog_analysis_for_mixed(resolved: resolved).fetch(:selected_paths)
          end

          def selected_module_source_relpaths_for_mixed(resolved:)
            selected_verilog_analysis_for_mixed(resolved: resolved).fetch(:module_source_relpaths)
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
            when 'video.v'
              text = rewrite_video_spr_extra_tile_array_text(text)
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

          def vendor_vhdl_shim_entries(staged_root:)
            [
              {
                path: write_altera_mf_components_package(staged_root),
                language: 'vhdl',
                library: 'altera_mf'
              },
              {
                path: write_altera_mf_altsyncram_entity(staged_root),
                language: 'vhdl',
                library: 'altera_mf'
              }
            ]
          end

          def write_altera_mf_components_package(staged_root)
            path = File.join(staged_root, 'altera_mf', 'altera_mf_components.vhd')
            return path if File.file?(path)

            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, <<~VHDL)
              library ieee;
              use ieee.std_logic_1164.all;

              package altera_mf_components is
                component altsyncram is
                  generic (
                    address_reg_b : string := "CLOCK1";
                    clock_enable_input_a : string := "NORMAL";
                    clock_enable_input_b : string := "NORMAL";
                    clock_enable_output_a : string := "BYPASS";
                    clock_enable_output_b : string := "BYPASS";
                    indata_reg_b : string := "CLOCK1";
                    init_file : string := " ";
                    intended_device_family : string := "Cyclone V";
                    lpm_hint : string := "ENABLE_RUNTIME_MOD=NO";
                    lpm_type : string := "altsyncram";
                    numwords_a : integer := 256;
                    numwords_b : integer := 256;
                    operation_mode : string := "SINGLE_PORT";
                    outdata_aclr_a : string := "NONE";
                    outdata_aclr_b : string := "NONE";
                    outdata_reg_a : string := "UNREGISTERED";
                    outdata_reg_b : string := "UNREGISTERED";
                    power_up_uninitialized : string := "FALSE";
                    read_during_write_mode_port_a : string := "NEW_DATA_NO_NBE_READ";
                    read_during_write_mode_port_b : string := "NEW_DATA_NO_NBE_READ";
                    widthad_a : integer := 8;
                    widthad_b : integer := 8;
                    width_a : integer := 8;
                    width_b : integer := 8;
                    width_byteena_a : integer := 1;
                    width_byteena_b : integer := 1;
                    wrcontrol_wraddress_reg_b : string := "CLOCK1"
                  );
                  port (
                    address_a : in std_logic_vector(widthad_a - 1 downto 0);
                    address_b : in std_logic_vector(widthad_b - 1 downto 0) := (others => '0');
                    clock0 : in std_logic;
                    clock1 : in std_logic := '0';
                    clocken0 : in std_logic := '1';
                    clocken1 : in std_logic := '1';
                    data_a : in std_logic_vector(width_a - 1 downto 0) := (others => '0');
                    data_b : in std_logic_vector(width_b - 1 downto 0) := (others => '0');
                    wren_a : in std_logic := '0';
                    wren_b : in std_logic := '0';
                    q_a : out std_logic_vector(width_a - 1 downto 0);
                    q_b : out std_logic_vector(width_b - 1 downto 0)
                  );
                end component;
              end package;

              package body altera_mf_components is
              end package body;
            VHDL
            path
          end

          def write_altera_mf_altsyncram_entity(staged_root)
            path = File.join(staged_root, 'altera_mf', 'altsyncram.vhd')
            return path if File.file?(path)

            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, <<~VHDL)
              library ieee;
              use ieee.std_logic_1164.all;
              use ieee.numeric_std.all;

              entity altsyncram is
                generic (
                  address_reg_b : string := "CLOCK1";
                  clock_enable_input_a : string := "NORMAL";
                  clock_enable_input_b : string := "NORMAL";
                  clock_enable_output_a : string := "BYPASS";
                  clock_enable_output_b : string := "BYPASS";
                  indata_reg_b : string := "CLOCK1";
                  init_file : string := " ";
                  intended_device_family : string := "Cyclone V";
                  lpm_hint : string := "ENABLE_RUNTIME_MOD=NO";
                  lpm_type : string := "altsyncram";
                  numwords_a : integer := 256;
                  numwords_b : integer := 256;
                  operation_mode : string := "SINGLE_PORT";
                  outdata_aclr_a : string := "NONE";
                  outdata_aclr_b : string := "NONE";
                  outdata_reg_a : string := "UNREGISTERED";
                  outdata_reg_b : string := "UNREGISTERED";
                  power_up_uninitialized : string := "FALSE";
                  read_during_write_mode_port_a : string := "NEW_DATA_NO_NBE_READ";
                  read_during_write_mode_port_b : string := "NEW_DATA_NO_NBE_READ";
                  widthad_a : integer := 8;
                  widthad_b : integer := 8;
                  width_a : integer := 8;
                  width_b : integer := 8;
                  width_byteena_a : integer := 1;
                  width_byteena_b : integer := 1;
                  wrcontrol_wraddress_reg_b : string := "CLOCK1"
                );
                port (
                  address_a : in std_logic_vector(widthad_a - 1 downto 0);
                  address_b : in std_logic_vector(widthad_b - 1 downto 0) := (others => '0');
                  clock0 : in std_logic;
                  clock1 : in std_logic := '0';
                  clocken0 : in std_logic := '1';
                  clocken1 : in std_logic := '1';
                  data_a : in std_logic_vector(width_a - 1 downto 0) := (others => '0');
                  data_b : in std_logic_vector(width_b - 1 downto 0) := (others => '0');
                  wren_a : in std_logic := '0';
                  wren_b : in std_logic := '0';
                  q_a : out std_logic_vector(width_a - 1 downto 0);
                  q_b : out std_logic_vector(width_b - 1 downto 0)
                );
              end entity;

              architecture synth of altsyncram is
                function max_int(lhs : integer; rhs : integer) return integer is
                begin
                  if lhs > rhs then
                    return lhs;
                  end if;
                  return rhs;
                end function;

                constant MEM_WIDTH : integer := max_int(width_a, width_b);
                constant MEM_DEPTH : integer := max_int(numwords_a, numwords_b);

                type mem_t is array (0 to MEM_DEPTH - 1) of std_logic_vector(MEM_WIDTH - 1 downto 0);
                signal mem : mem_t := (others => (others => '0'));
                signal q_a_reg : std_logic_vector(width_a - 1 downto 0) := (others => '0');
                signal q_b_reg : std_logic_vector(width_b - 1 downto 0) := (others => '0');
              begin
                process (clock0, clock1)
                  variable idx_a : integer;
                  variable idx_b : integer;
                  variable word_a : std_logic_vector(MEM_WIDTH - 1 downto 0);
                  variable word_b : std_logic_vector(MEM_WIDTH - 1 downto 0);
                begin
                  if rising_edge(clock0) then
                    if clocken0 = '1' then
                      idx_a := to_integer(unsigned(address_a));
                      if idx_a >= 0 and idx_a < MEM_DEPTH then
                        word_a := mem(idx_a);
                        if wren_a = '1' then
                          word_a(width_a - 1 downto 0) := data_a;
                          mem(idx_a) <= word_a;
                        end if;
                        q_a_reg <= word_a(width_a - 1 downto 0);
                      else
                        q_a_reg <= (others => '0');
                      end if;
                    end if;
                  end if;

                  if rising_edge(clock1) then
                    if clocken1 = '1' then
                      idx_b := to_integer(unsigned(address_b));
                      if idx_b >= 0 and idx_b < MEM_DEPTH then
                        word_b := mem(idx_b);
                        if wren_b = '1' then
                          word_b(width_b - 1 downto 0) := data_b;
                          mem(idx_b) <= word_b;
                        end if;
                        q_b_reg <= word_b(width_b - 1 downto 0);
                      else
                        q_b_reg <= (others => '0');
                      end if;
                    end if;
                  end if;
                end process;

                q_a <= q_a_reg;
                q_b <= q_b_reg;
              end architecture;
            VHDL
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
              raise_to_dsl: true,
              format_output: false,
              emit_runtime_json: emit_runtime_json
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

          def stage_workspace_artifacts(workspace:, artifacts:, report_path:)
            return {} if workspace.nil? || workspace.to_s.empty?

            staged = {}
            import_artifacts_dir = File.join(workspace, 'import_artifacts')
            FileUtils.mkdir_p(import_artifacts_dir)

            artifact_map = {
              'core_mlir_path' => File.join(import_artifacts_dir, "#{top}.core.mlir"),
              'runtime_json_path' => File.join(import_artifacts_dir, "#{top}.runtime.json"),
              'firtool_verilog_path' => File.join(import_artifacts_dir, "#{top}.firtool.v"),
              'normalized_verilog_path' => File.join(import_artifacts_dir, "#{top}.normalized.v"),
              'pure_verilog_entry_path' => File.join(import_artifacts_dir, "#{top}.pure_entry.v"),
              'pure_verilog_root' => File.join(import_artifacts_dir, 'pure_verilog')
            }

            artifact_map.each do |source_key, destination|
              source = artifacts[source_key]
              next if source.nil? || source.to_s.empty?
              next unless File.exist?(source)

              if File.directory?(source)
                FileUtils.rm_rf(destination)
                FileUtils.cp_r(source, destination)
              else
                FileUtils.mkdir_p(File.dirname(destination))
                FileUtils.cp(source, destination)
              end
              staged["workspace_#{source_key}"] = destination
            end

            if File.file?(report_path)
              workspace_report_path = File.join(import_artifacts_dir, 'import_report.json')
              FileUtils.cp(report_path, workspace_report_path)
              staged['workspace_report_path'] = workspace_report_path
            end

            staged
          end

          def merge_workspace_artifacts_into_report(report_path:, workspace_artifacts:)
            report = read_report(report_path)
            return report if report.empty? || workspace_artifacts.empty?

            report['artifacts'] ||= {}
            workspace_artifacts.each do |key, value|
              report['artifacts'][key] = value
              report['mixed_import'][key] = value if report['mixed_import'].is_a?(Hash)
            end
            File.write(report_path, JSON.pretty_generate(report))
            report
          end

          def merge_component_manifest_into_report(report_path:, components:, raised_files:)
            report = read_report(report_path)
            return report if report.empty?

            report['raised_files'] = Array(raised_files).sort
            report['component_count'] = components.length
            report['components'] = components
            File.write(report_path, JSON.pretty_generate(report))
            report
          end

          def module_source_relpaths_for_report(report:, resolved:)
            mappings = selected_module_source_relpaths_for_mixed(resolved: resolved)
            Array(report.dig('mixed_import', 'vhdl_synth_outputs')).each do |entry|
              module_name = (entry['module_name'] || entry[:module_name]).to_s
              source_path = (entry['source_path'] || entry[:source_path]).to_s
              next if module_name.empty? || source_path.empty?

              mappings[module_name] ||= source_relative_path(source_path)
            end
            mappings
          end

          def build_component_manifest(report:, files_written:, module_source_relpaths:)
            modules = Array(report['modules'])
            return [] if modules.empty?

            staged_inventory = staged_module_inventory(report.fetch('mixed_import', {}).fetch('pure_verilog_files', []))
            raised_inventory = raised_component_inventory(files_written)
            synth_inventory = synth_output_inventory(report.dig('mixed_import', 'vhdl_synth_outputs'))

            modules.map do |entry|
              module_name = entry.fetch('name').to_s
              staged = component_staged_metadata_from_report(entry) || staged_inventory[module_name]
              raise "Missing staged pure-Verilog module mapping for imported component #{module_name}" unless staged

              raised = raised_inventory[module_name] || component_raised_metadata_from_report(entry)
              raise "Missing raised RHDL file mapping for imported component #{module_name}" unless raised

              keep_structure_relative_path =
                if %w[source_verilog source_vhdl_generated].include?(staged[:origin_kind].to_s)
                  relative_output_path(raised[:raised_rhdl_path])
                end
              synth = component_vhdl_synth_metadata_from_report(entry) || synth_inventory[File.expand_path(staged[:path])]
              source_kind = entry['source_kind'] || source_kind_for_origin(staged[:origin_kind])
              emitted_dsl_features = Array(entry['emitted_dsl_features'] || raised[:dsl_features]).map(&:to_s)

              {
                'module_name' => module_name,
                'verilog_module_name' => module_name,
                'ruby_class_name' => entry['ruby_class_name'] || raised[:ruby_class_name],
                'raised_rhdl_path' => raised[:raised_rhdl_path],
                'staged_verilog_path' => staged[:path],
                'staged_verilog_module_name' => staged[:module_name],
                'origin_kind' => staged[:origin_kind],
                'source_kind' => source_kind,
                'original_source_path' => staged[:original_source_path],
                'keep_structure_relative_path' => keep_structure_relative_path,
                'expected_dsl_features' => entry['expected_dsl_features'],
                'behavior' => emitted_dsl_features.include?('behavior'),
                'sequential' => emitted_dsl_features.include?('sequential'),
                'memory' => emitted_dsl_features.include?('memory'),
                'emitted_dsl_features' => emitted_dsl_features,
                'vhdl_synth' => synth,
                'emitted_base_class' => entry['emitted_base_class'] || raised[:base_class]
              }.compact
            end.sort_by { |entry| entry.fetch('verilog_module_name') }
          end

          def component_staged_metadata_from_report(entry)
            path = entry['staged_verilog_path']
            return nil if path.nil? || path.to_s.empty?

            {
              module_name: entry['staged_verilog_module_name'] || entry['verilog_module_name'] || entry['name'],
              path: path,
              origin_kind: entry['origin_kind'],
              original_source_path: entry['original_source_path']
            }
          end

          def component_raised_metadata_from_report(entry)
            path = entry['raised_rhdl_path']
            return nil if path.nil? || path.to_s.empty?

            {
              ruby_class_name: entry['ruby_class_name'],
              raised_rhdl_path: path,
              base_class: entry['emitted_base_class'],
              dsl_features: Array(entry['emitted_dsl_features']).map(&:to_s)
            }
          end

          def component_vhdl_synth_metadata_from_report(entry)
            value = entry['vhdl_synth']
            return nil unless value.is_a?(Hash)

            {
              entity: value['entity'] || value[:entity],
              module_name: value['module_name'] || value[:module_name],
              library: value['library'] || value[:library],
              standard: value['standard'] || value[:standard],
              workdir: value['workdir'] || value[:workdir],
              extra_args: value['extra_args'] || value[:extra_args],
              source_path: value['source_path'] || value[:source_path]
            }.compact
          end

          def source_kind_for_origin(origin_kind)
            case origin_kind.to_s
            when 'source_verilog'
              'verilog'
            when 'source_vhdl_generated', 'generated_helper'
              'generated_vhdl'
            else
              origin_kind.to_s
            end
          end

          def relative_output_path(path)
            Pathname.new(File.expand_path(path)).relative_path_from(Pathname.new(output_dir)).to_s
          end

          def staged_module_inventory(pure_verilog_files)
            Array(pure_verilog_files).each_with_object({}) do |entry, acc|
              path = File.expand_path(entry['path'] || entry[:path])
              next unless File.file?(path)

              primary_module_name = (entry['primary_module_name'] || entry[:primary_module_name]).to_s
              base_origin_kind = (entry['origin_kind'] || entry[:origin_kind]).to_s
              generated = entry.key?('generated') ? entry['generated'] : entry[:generated]
              base_origin_kind = 'source_verilog' if base_origin_kind.empty? && !generated
              base_origin_kind = 'source_vhdl_generated' if base_origin_kind.empty? && generated
              original_source_path = entry['original_source_path'] || entry[:original_source_path]

              parse_verilog_module_names(path).each do |module_name|
                existing = acc[module_name]
                if existing && File.expand_path(existing[:path]) != File.expand_path(path)
                  raise "Ambiguous staged module mapping for #{module_name}: #{existing[:path]} and #{path}"
                end

                origin_kind =
                  if base_origin_kind == 'source_vhdl_generated' &&
                     !primary_module_name.empty? &&
                     module_name != primary_module_name
                    'generated_helper'
                  else
                    base_origin_kind
                  end

                acc[module_name] = {
                  module_name: module_name,
                  path: path,
                  origin_kind: origin_kind,
                  original_source_path: original_source_path
                }
              end
            end
          end

          def parse_verilog_module_names(path)
            verilog_file_analysis(path).fetch(:module_names)
          end

          def raised_component_inventory(files_written)
            Array(files_written).each_with_object({}) do |path, acc|
              next unless File.file?(path)

              text = File.read(path)
              module_name = text[/def\s+self\.verilog_module_name.*?\n\s*["']([^"']+)["']/m, 1]
              next if module_name.nil? || module_name.empty?

              ruby_class_name = text[/^class\s+([A-Za-z0-9_:]+)\s+</, 1]
              base_class = text[/^class\s+[A-Za-z0-9_:]+\s+<\s+([A-Za-z0-9_:]+)/, 1]
              dsl_features = []
              dsl_features << 'behavior' if text.include?('behavior do')
              dsl_features << 'sequential' if text.include?('include RHDL::DSL::Sequential')
              dsl_features << 'memory' if text.include?('include RHDL::DSL::Memory')

              acc[module_name] = {
                ruby_class_name: ruby_class_name,
                raised_rhdl_path: path,
                base_class: base_class,
                dsl_features: dsl_features
              }
            end
          end

          def source_inventory_by_relative_path(files)
            Array(files).each_with_object({}) do |entry, acc|
              rel = source_relative_path(entry.fetch(:path))
              acc[rel] = {
                path: File.expand_path(entry.fetch(:path)),
                language: entry.fetch(:language)
              }
            end
          end

          def synth_output_inventory(outputs)
            Array(outputs).each_with_object({}) do |entry, acc|
              output_path = entry['output_path'] || entry[:output_path]
              next if output_path.nil? || output_path.empty?

              acc[File.expand_path(output_path)] = {
                entity: entry['entity'] || entry[:entity],
                module_name: entry['module_name'] || entry[:module_name],
                library: entry['library'] || entry[:library],
                extra_args: entry['extra_args'] || entry[:extra_args],
                source_path: entry['source_path'] || entry[:source_path]
              }
            end
          end

          def vhdl_entity_source_map(files)
            Array(files)
              .select { |entry| entry.fetch(:language) == 'vhdl' }
              .each_with_object(Hash.new { |h, k| h[k] = [] }) do |entry, acc|
                path = File.expand_path(entry.fetch(:path))
                text = File.read(path)
                text.scan(/\bentity\s+([A-Za-z_][A-Za-z0-9_]*)\s+is\b/i).flatten.each do |entity|
                  acc[entity] << path unless acc[entity].include?(path)
                end
              end
          end

          def component_origin_metadata(staged:, pure_verilog_root:, source_inventory:, synth_inventory:, vhdl_entity_sources:)
            staged_path = File.expand_path(staged.fetch(:path))
            relative = if pure_verilog_root && staged_path.start_with?(File.expand_path(pure_verilog_root).to_s + '/')
                         staged_path.delete_prefix("#{File.expand_path(pure_verilog_root)}/")
                       else
                         File.basename(staged_path)
                       end

            if (source_entry = source_inventory[relative])
              return {
                origin_kind: source_entry[:language] == 'verilog' ? 'source_verilog' : 'generated_helper',
                original_source_path: source_entry[:path]
              }
            end

            if (synth_entry = synth_inventory[staged_path])
              original_source_path = nil
              entity_sources = vhdl_entity_sources[synth_entry[:entity].to_s]
              original_source_path = entity_sources.first if entity_sources.length == 1
              return {
                origin_kind: 'source_vhdl_generated',
                original_source_path: original_source_path
              }
            end

            {
              origin_kind: 'generated_helper'
            }
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
                  diagnostics << "GameBoy layout ambiguous for #{basename}: #{dirs.sort.join(', ')}; using #{rel_dir}"
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
              verilog_file_analysis(path).fetch(:module_names).each do |name|
                acc[name] ||= path
              end
            end
          end

          def module_reference_graph(files)
            graph = Hash.new { |h, k| h[k] = Set.new }
            files.each do |path|
              verilog_file_analysis(path).fetch(:reference_graph).each do |mod_name, targets|
                graph[mod_name].merge(targets)
              end
            end
            graph.transform_values(&:to_a)
          end

          def module_closure(start, graph)
            seen = {}
            queue = [start.to_s]
            idx = 0
            while idx < queue.length
              current = queue[idx]
              idx += 1
              next if seen[current]

              seen[current] = true
              Array(graph[current]).each { |child| queue << child }
            end
            seen.keys
          end

          def selected_verilog_analysis_for_mixed(resolved:)
            verilog_paths = resolved.fetch(:files)
              .select { |entry| entry.fetch(:language) == 'verilog' }
              .map { |entry| File.expand_path(entry.fetch(:path)) }
            cache_key = [top.to_s, File.expand_path(top_file), verilog_paths].freeze

            @selected_verilog_analysis_cache[cache_key] ||= begin
              module_to_file = module_index(verilog_paths)
              refs = module_reference_graph(verilog_paths)
              closure_modules = module_closure(top, refs)
              selected_paths = closure_modules.filter_map { |name| module_to_file[name] }.map { |path| File.expand_path(path) }
              top_path = File.expand_path(top_file)
              if File.extname(top_path).downcase.match?(/\A\.(v|sv)\z/) && File.file?(top_path)
                selected_paths << top_path
              end
              selected_path_set = selected_paths.to_set
              module_source_relpaths = module_to_file.each_with_object({}) do |(module_name, path), acc|
                expanded_path = File.expand_path(path)
                next unless selected_path_set.include?(expanded_path)

                acc[module_name] = source_relative_path(expanded_path)
              end

              {
                selected_paths: selected_path_set,
                module_source_relpaths: module_source_relpaths
              }
            end
          end

          def verilog_file_analysis(path)
            normalized_path = File.expand_path(path)
            @verilog_file_analysis_cache[normalized_path] ||= begin
              stripped_text = strip_comments(File.read(normalized_path))
              module_names = []
              reference_graph = Hash.new { |h, k| h[k] = Set.new }

              stripped_text.scan(/\bmodule\s+([A-Za-z_][A-Za-z0-9_$]*)\b(.*?)\bendmodule\b/m) do |mod_name, body|
                module_names << mod_name
                body.scan(/\b([A-Za-z_][A-Za-z0-9_$]*)\s*(?:#\s*\(.*?\))?\s+([A-Za-z_][A-Za-z0-9_$]*)\s*\(/m) do |target, _inst_name|
                  next if INSTANCE_KEYWORDS.include?(target)
                  next if target == 'endcase'

                  reference_graph[mod_name] << target
                end
              end

              {
                module_names: module_names.uniq.freeze,
                reference_graph: reference_graph.transform_values { |targets| targets.to_a.freeze }.freeze
              }.freeze
            end
          end

          def strip_comments(text)
            text
              .gsub(%r{//.*$}, '')
              .gsub(%r{/\*.*?\*/}m, '')
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
