# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'yaml'
require 'json'
require 'fileutils'

require_relative '../../../../examples/gameboy/utilities/import/system_importer'

RSpec.describe RHDL::Examples::GameBoy::Import::SystemImporter do
  def require_reference_tree!
    skip 'GameBoy reference tree not available' unless Dir.exist?(described_class::DEFAULT_REFERENCE_ROOT)
    skip 'GameBoy files.qip not available' unless File.file?(described_class::DEFAULT_QIP_PATH)
  end

  def new_importer(output_dir:, maintain_directory_structure: true, stub_modules: [], auto_stub_modules: false, patches_dir: nil)
    described_class.new(
      output_dir: output_dir,
      maintain_directory_structure: maintain_directory_structure,
      auto_stub_modules: auto_stub_modules,
      stub_modules: stub_modules,
      patches_dir: patches_dir,
      clean_output: false,
      keep_workspace: true,
      progress: ->(_msg) {}
    )
  end

  describe '#resolve_sources' do
    it 'resolves files.qip recursively with deterministic mixed source set' do
      require_reference_tree!

      Dir.mktmpdir('gameboy_import_resolve') do |out_dir|
        importer = new_importer(output_dir: out_dir)
        resolved = importer.resolve_sources

        expect(resolved[:top][:name]).to eq('gb')
        expect(resolved[:top][:file]).to eq(File.expand_path('examples/gameboy/reference/rtl/gb.v', Dir.pwd))
        expect(resolved[:top][:language]).to eq('verilog')

        files = resolved.fetch(:files)
        expect(files.length).to eq(47)
        expect(files.map { |entry| entry[:path] }.uniq.length).to eq(47)
        expect(files.all? { |entry| File.file?(entry[:path]) }).to be(true)

        ext_counts = files.each_with_object(Hash.new(0)) do |entry, counts|
          counts[File.extname(entry[:path]).downcase] += 1
        end
        expect(ext_counts.fetch('.v', 0)).to eq(26)
        expect(ext_counts.fetch('.sv', 0)).to eq(7)
        expect(ext_counts.fetch('.vhd', 0)).to eq(14)

        expect(files.any? { |entry| entry[:path].end_with?('/rtl/T80/T80.vhd') }).to be(true)
        expect(files.any? { |entry| entry[:path].end_with?('/rtl/T80/T80_ALU.vhd') }).to be(true)
      end
    end

    it 'produces stable source ordering across calls' do
      require_reference_tree!

      Dir.mktmpdir('gameboy_import_order') do |out_dir|
        importer = new_importer(output_dir: out_dir)
        first = importer.resolve_sources
        second = importer.resolve_sources

        first_paths = first.fetch(:files).map { |entry| entry[:path] }
        second_paths = second.fetch(:files).map { |entry| entry[:path] }
        expect(first_paths).to eq(second_paths)
      end
    end

    it 'applies patches_dir in the workspace before staging sources' do
      Dir.mktmpdir('gameboy_import_patch_root') do |root|
        Dir.mktmpdir('gameboy_import_patch_out') do |out_dir|
          Dir.mktmpdir('gameboy_import_patch_ws') do |workspace|
            rtl_dir = File.join(root, 'rtl')
            FileUtils.mkdir_p(rtl_dir)
            qip_path = File.join(root, 'files.qip')
            top_file = File.join(rtl_dir, 'gb.v')
            File.write(top_file, "// original\nmodule gb;\nendmodule\n")
            File.write(
              qip_path,
              "set_global_assignment -name VERILOG_FILE rtl/gb.v\n"
            )

            patches_dir = File.join(root, 'patches')
            FileUtils.mkdir_p(patches_dir)
            File.write(
              File.join(patches_dir, '0001-gb.patch'),
              <<~PATCH
                diff --git a/rtl/gb.v b/rtl/gb.v
                --- a/rtl/gb.v
                +++ b/rtl/gb.v
                @@ -1,3 +1,3 @@
                -// original
                +// patched
                 module gb;
                 endmodule
              PATCH
            )

            importer = described_class.new(
              reference_root: root,
              qip_path: qip_path,
              top_file: top_file,
              output_dir: out_dir,
              workspace_dir: workspace,
              keep_workspace: true,
              clean_output: false,
              patches_dir: patches_dir,
              progress: ->(_msg) {}
            )

            resolved = importer.resolve_sources(workspace: workspace)
            manifest_path = importer.write_manifest(workspace: workspace, resolved: resolved)
            manifest = YAML.safe_load(File.read(manifest_path))
            staged_top = manifest.fetch('top').fetch('file')

            expect(File.read(staged_top)).to include('// patched')
            expect(File.read(top_file)).to include('// original')
          end
        end
      end
    end
  end

  describe '#write_manifest' do
    it 'writes a mixed import manifest with canonical top and source list' do
      require_reference_tree!

      Dir.mktmpdir('gameboy_import_manifest') do |out_dir|
        Dir.mktmpdir('gameboy_import_workspace') do |workspace|
          importer = new_importer(output_dir: out_dir)
          resolved = importer.resolve_sources
          manifest_path = importer.write_manifest(workspace: workspace, resolved: resolved)

          expect(File.file?(manifest_path)).to be(true)
          manifest = YAML.safe_load(File.read(manifest_path))

          expect(manifest.fetch('version')).to eq(1)
          expect(manifest.fetch('top').fetch('name')).to eq('gb')
          expect(manifest.fetch('top').fetch('file')).to end_with('/mixed_sources/rtl/gb.v')
          expect(File.file?(manifest.fetch('top').fetch('file'))).to be(true)
          expect(manifest.fetch('files').length).to eq(26)
          expect(manifest.dig('vhdl', 'synth_targets')).to include(include('entity' => 'speedcontrol'))
          shim_paths = manifest.fetch('files').map { |entry| entry.fetch('path') }
          expect(shim_paths).to include(
            a_string_ending_with('/mixed_sources/altera_mf/altera_mf_components.vhd'),
            a_string_ending_with('/mixed_sources/altera_mf/altsyncram.vhd')
          )

          languages = manifest.fetch('files').map { |entry| entry.fetch('language') }.uniq.sort
          expect(languages).to eq(%w[verilog vhdl])
        end
      end
    end
  end

  describe '#write_altera_mf_altsyncram_entity' do
    it 'models UNREGISTERED outputs as combinational reads in the generated stub' do
      Dir.mktmpdir('gameboy_import_altsyncram_stub') do |out_dir|
        importer = new_importer(output_dir: out_dir)
        path = importer.send(:write_altera_mf_altsyncram_entity, out_dir)
        text = File.read(path)

        expect(text).to include('signal q_a_comb')
        expect(text).to include('signal q_b_comb')
        expect(text).to include('q_a <= q_a_comb when outdata_reg_a = "UNREGISTERED" else q_a_reg;')
        expect(text).to include('q_b <= q_b_comb when outdata_reg_b = "UNREGISTERED" else q_b_reg;')
        expect(text).to include('if wren_a = \'1\' and read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ" then')
        expect(text).to include('if wren_b = \'1\' and read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ" then')
      end
    end
  end

  describe '#normalize_verilog_for_import' do
    it 'relaxes gb boot rom disable to trigger on any FF50 write' do
      require_reference_tree!

      Dir.mktmpdir('gameboy_import_normalize_verilog') do |out_dir|
        importer = new_importer(output_dir: out_dir)
        source_path = File.expand_path('examples/gameboy/reference/rtl/gb.v', Dir.pwd)
        normalized = importer.send(:normalize_verilog_for_import, File.read(source_path), source_path: source_path)

        expect(normalized).to include("if((cpu_addr == 16'hff50) && !cpu_wr_n_edge) begin")
        expect(normalized).not_to include("if((cpu_addr == 16'hff50) && !cpu_wr_n_edge && cpu_do[0]) begin")
      end
    end
  end

  describe '#run' do
    it 'rejects a missing patches_dir' do
      expect do
        described_class.new(output_dir: '/tmp/rhdl_gameboy_out', patches_dir: '/tmp/does_not_exist')
      end.to raise_error(ArgumentError, /patches_dir not found/)
    end

    it 'delegates to mixed import task and cleans output contents before run' do
      require_reference_tree!

      fake_task_class = Class.new do
        class << self
          attr_accessor :last_options
        end

        def initialize(options)
          self.class.last_options = options
          @options = options
        end

        def run
          FileUtils.mkdir_p(@options.fetch(:out))
          File.write(File.join(@options.fetch(:out), 'generated_component.rb'), "# generated\n")
          File.write(@options.fetch(:report), "{}\n")
        end
      end

      Dir.mktmpdir('gameboy_import_run_out') do |out_dir|
        Dir.mktmpdir('gameboy_import_run_ws') do |workspace|
          File.write(File.join(out_dir, '.gitignore'), "# keep\n")
          stale_path = File.join(out_dir, 'stale.txt')
          File.write(stale_path, 'stale')

          importer = described_class.new(
            output_dir: out_dir,
            workspace_dir: workspace,
            keep_workspace: true,
            clean_output: true,
            progress: ->(_msg) {},
            import_task_class: fake_task_class
          )

          result = importer.run
          expect(result.success?).to be(true)
          expect(File.exist?(stale_path)).to be(false)
          expect(File.file?(File.join(out_dir, '.gitignore'))).to be(true)

          options = fake_task_class.last_options
          expect(options).not_to be_nil
          expect(options.fetch(:mode)).to eq(:mixed)
          expect(options.fetch(:top)).to eq('gb')
          expect(options.fetch(:require_verilog_import_top)).to be(true)
          expect(options.fetch(:out)).to eq(out_dir)
          expect(options.fetch(:format_output)).to eq(false)
          expect(options).not_to have_key(:arc_remove_llhd)
          expect(File.file?(options.fetch(:manifest))).to be(true)

          manifest = YAML.safe_load(File.read(options.fetch(:manifest)))
          expect(manifest.fetch('files').length).to eq(26)
          expect(result.files_written).to include(File.join(out_dir, 'generated_component.rb'))
          expect(File.file?(result.report_path)).to be(true)
        end
      end
    end

    it 'threads stub_modules through to the shared import task and result metadata' do
      require_reference_tree!

      fake_task_class = Class.new do
        class << self
          attr_accessor :last_options
        end

        def initialize(options)
          self.class.last_options = options
          @options = options
        end

        def run
          FileUtils.mkdir_p(@options.fetch(:out))
          File.write(File.join(@options.fetch(:out), 'generated_component.rb'), "# generated\n")
          File.write(@options.fetch(:report), "{}\n")
        end
      end

      stub_spec = [
        {
          name: 'gb_savestates',
          outputs: {
            'reset_out' => { signal: 'reset_in' }
          }
        }
      ]

      Dir.mktmpdir('gameboy_import_stubbed_out') do |out_dir|
        Dir.mktmpdir('gameboy_import_stubbed_ws') do |workspace|
          importer = described_class.new(
            output_dir: out_dir,
            workspace_dir: workspace,
            keep_workspace: true,
            clean_output: true,
            stub_modules: stub_spec,
            progress: ->(_msg) {},
            import_task_class: fake_task_class
          )

          result = importer.run
          expect(result.success?).to be(true)
          expect(fake_task_class.last_options.fetch(:stub_modules)).to eq(stub_spec)
          expect(result.stub_modules).to eq(['gb_savestates'])
        end
      end
    end

    it 'threads simulation-safe auto stubs through when requested' do
      require_reference_tree!

      fake_task_class = Class.new do
        class << self
          attr_accessor :last_options
        end

        def initialize(options)
          self.class.last_options = options
          @options = options
        end

        def run
          FileUtils.mkdir_p(@options.fetch(:out))
          File.write(File.join(@options.fetch(:out), 'generated_component.rb'), "# generated\n")
          File.write(@options.fetch(:report), "{}\n")
        end
      end

      Dir.mktmpdir('gameboy_import_auto_stubbed_out') do |out_dir|
        Dir.mktmpdir('gameboy_import_auto_stubbed_ws') do |workspace|
          importer = described_class.new(
            output_dir: out_dir,
            workspace_dir: workspace,
            keep_workspace: true,
            clean_output: true,
            auto_stub_modules: :simulation_safe,
            progress: ->(_msg) {},
            import_task_class: fake_task_class
          )

          result = importer.run
          expect(result.success?).to be(true)
          expect(fake_task_class.last_options.fetch(:stub_modules)).to eq(
            described_class::AUTO_STUB_PROFILES.fetch(:simulation_safe)
          )
          expect(result.stub_modules).to eq(
            %w[gb_savestates gb_statemanager__vhdl_2e2d161b9c1b sprites_extra]
          )
        end
      end
    end

    it 'merges explicit stub overrides on top of the auto-stub profile by module name' do
      require_reference_tree!

      fake_task_class = Class.new do
        class << self
          attr_accessor :last_options
        end

        def initialize(options)
          self.class.last_options = options
          @options = options
        end

        def run
          FileUtils.mkdir_p(@options.fetch(:out))
          File.write(File.join(@options.fetch(:out), 'generated_component.rb'), "# generated\n")
          File.write(@options.fetch(:report), "{}\n")
        end
      end

      custom_stub_spec = [
        {
          name: 'gb_savestates',
          outputs: {
            'reset_out' => { signal: 'reset_in' },
            'load_done' => 1
          }
        },
        'custom_stubbed_leaf'
      ]

      Dir.mktmpdir('gameboy_import_auto_stub_override_out') do |out_dir|
        Dir.mktmpdir('gameboy_import_auto_stub_override_ws') do |workspace|
          importer = described_class.new(
            output_dir: out_dir,
            workspace_dir: workspace,
            keep_workspace: true,
            clean_output: true,
            auto_stub_modules: true,
            stub_modules: custom_stub_spec,
            progress: ->(_msg) {},
            import_task_class: fake_task_class
          )

          result = importer.run
          expect(result.success?).to be(true)
          expect(fake_task_class.last_options.fetch(:stub_modules)).to eq(
            [
              custom_stub_spec.first,
              'gb_statemanager__vhdl_2e2d161b9c1b',
              'sprites_extra',
              'custom_stubbed_leaf'
            ]
          )
          expect(result.stub_modules).to eq(
            %w[custom_stubbed_leaf gb_savestates gb_statemanager__vhdl_2e2d161b9c1b sprites_extra]
          )
        end
      end
    end

    it 'remaps raised files into source directory structure when enabled' do
      require_reference_tree!

      fake_task_class = Class.new do
        def initialize(options)
          @options = options
        end

        def run
          out_dir = @options.fetch(:out)
          FileUtils.mkdir_p(out_dir)
          File.write(File.join(out_dir, 'gb.rb'), "# gb\n")
          File.write(File.join(out_dir, 'video.rb'), "# video\n")
          File.write(@options.fetch(:report), "{}\n")
        end
      end

      Dir.mktmpdir('gameboy_import_keep_structure_out') do |out_dir|
        Dir.mktmpdir('gameboy_import_keep_structure_ws') do |workspace|
          importer = described_class.new(
            output_dir: out_dir,
            workspace_dir: workspace,
            keep_workspace: true,
            clean_output: true,
            maintain_directory_structure: true,
            progress: ->(_msg) {},
            import_task_class: fake_task_class
          )

          result = importer.run
          expect(result.success?).to be(true)
          expect(result.files_written).to include(
            File.join(out_dir, 'rtl', 'gb.rb'),
            File.join(out_dir, 'rtl', 'video.rb')
          )
          expect(File.file?(File.join(out_dir, 'rtl', 'gb.rb'))).to be(true)
          expect(File.file?(File.join(out_dir, 'rtl', 'video.rb'))).to be(true)
          expect(File.exist?(File.join(out_dir, 'gb.rb'))).to be(false)
          expect(File.exist?(File.join(out_dir, 'video.rb'))).to be(false)
        end
      end
    end

    it 'keeps raised files flat when keep-structure is disabled' do
      require_reference_tree!

      fake_task_class = Class.new do
        def initialize(options)
          @options = options
        end

        def run
          out_dir = @options.fetch(:out)
          FileUtils.mkdir_p(out_dir)
          File.write(File.join(out_dir, 'gb.rb'), "# gb\n")
          File.write(File.join(out_dir, 'video.rb'), "# video\n")
          File.write(@options.fetch(:report), "{}\n")
        end
      end

      Dir.mktmpdir('gameboy_import_flat_out') do |out_dir|
        Dir.mktmpdir('gameboy_import_flat_ws') do |workspace|
          importer = described_class.new(
            output_dir: out_dir,
            workspace_dir: workspace,
            keep_workspace: true,
            clean_output: true,
            maintain_directory_structure: false,
            progress: ->(_msg) {},
            import_task_class: fake_task_class
          )

          result = importer.run
          expect(result.success?).to be(true)
          expect(result.files_written).to include(
            File.join(out_dir, 'gb.rb'),
            File.join(out_dir, 'video.rb')
          )
          expect(File.file?(File.join(out_dir, 'gb.rb'))).to be(true)
          expect(File.file?(File.join(out_dir, 'video.rb'))).to be(true)
        end
      end
    end

    it 'ignores runtime helper modules when building the component manifest' do
      Dir.mktmpdir('gameboy_import_helper_manifest') do |out_dir|
        importer = new_importer(output_dir: out_dir)

        helper_rb = File.join(out_dir, 'dpram_dif__vhdl_deadbeef__byte_mem.rb')
        gb_rb = File.join(out_dir, 'gb.rb')
        File.write(helper_rb, "# helper\n")
        File.write(gb_rb, "# gb\n")

        report = {
          'mixed_import' => {
            'pure_verilog_files' => []
          },
          'modules' => [
            {
              'name' => 'dpram_dif__vhdl_deadbeef__byte_mem',
              'ruby_class_name' => 'DpramDifHelper',
              'raised_rhdl_path' => helper_rb
            },
            {
              'name' => 'gb',
              'ruby_class_name' => 'Gb',
              'raised_rhdl_path' => gb_rb,
              'staged_verilog_path' => File.join(out_dir, '.mixed_import', 'pure_verilog', 'generated_vhdl', 'gb.v'),
              'staged_verilog_module_name' => 'gb',
              'origin_kind' => 'source_verilog',
              'original_source_path' => File.join(described_class::DEFAULT_REFERENCE_ROOT, 'rtl', 'gb.v')
            }
          ]
        }

        manifest = importer.send(
          :build_component_manifest,
          report: report,
          files_written: [helper_rb, gb_rb],
          module_source_relpaths: { 'gb' => 'rtl/gb.v' }
        )

        expect(manifest.length).to eq(1)
        expect(manifest.first.fetch('module_name')).to eq('gb')
      end
    end

    it 'mirrors canonical import artifacts into the workspace and records their paths in the report' do
      require_reference_tree!

      fake_task_class = Class.new do
        def initialize(options)
          @options = options
        end

        def run
          out_dir = @options.fetch(:out)
          FileUtils.mkdir_p(File.join(out_dir, '.mixed_import', 'pure_verilog'))
          File.write(File.join(out_dir, 'generated_component.rb'), "# generated\n")

          core_mlir = File.join(out_dir, '.mixed_import', 'gb.core.mlir')
          runtime_json = File.join(out_dir, '.mixed_import', 'gb.runtime.json')
          firtool_verilog = File.join(out_dir, '.mixed_import', 'gb.firtool.v')
          normalized_verilog = File.join(out_dir, '.mixed_import', 'gb.normalized.v')
          pure_entry = File.join(out_dir, '.mixed_import', 'pure_verilog_entry.v')
          pure_root = File.join(out_dir, '.mixed_import', 'pure_verilog')

          File.write(core_mlir, "hw.module @gb() {\n  hw.output\n}\n")
          File.write(runtime_json, '{"circt_json_version":1,"modules":[{"name":"gb","ports":[],"nets":[],"regs":[],"assigns":[],"processes":[],"instances":[],"memories":[],"write_ports":[],"sync_read_ports":[],"parameters":{}}]}')
          File.write(firtool_verilog, "module gb;\nendmodule\n")
          File.write(normalized_verilog, "module gb;\nendmodule\n")
          File.write(pure_entry, "`include \"#{File.join(pure_root, 'gb.v')}\"\n")
          File.write(File.join(pure_root, 'gb.v'), "module gb;\nendmodule\n")

          report = {
            success: true,
            strict: true,
            top: 'gb',
            module_count: 1,
            mixed_import: {
              top_name: 'gb',
              pure_verilog_root: pure_root,
              pure_verilog_entry_path: pure_entry,
              core_mlir_path: core_mlir,
              runtime_json_path: runtime_json,
              firtool_verilog_path: firtool_verilog,
              normalized_verilog_path: normalized_verilog
            },
            artifacts: {
              pure_verilog_root: pure_root,
              pure_verilog_entry_path: pure_entry,
              core_mlir_path: core_mlir,
              runtime_json_path: runtime_json,
              firtool_verilog_path: firtool_verilog,
              normalized_verilog_path: normalized_verilog
            }
          }
          File.write(@options.fetch(:report), JSON.pretty_generate(report))
        end
      end

      Dir.mktmpdir('gameboy_import_artifacts_out') do |out_dir|
        Dir.mktmpdir('gameboy_import_artifacts_ws') do |workspace|
          importer = described_class.new(
            output_dir: out_dir,
            workspace_dir: workspace,
            keep_workspace: true,
            clean_output: true,
            progress: ->(_msg) {},
            import_task_class: fake_task_class
          )

          result = importer.run
          expect(result.success?).to be(true)

          report = JSON.parse(File.read(result.report_path))
          artifacts = report.fetch('artifacts')
          expect(File.file?(artifacts.fetch('workspace_core_mlir_path'))).to be(true)
          expect(File.file?(artifacts.fetch('workspace_runtime_json_path'))).to be(true)
          expect(File.file?(artifacts.fetch('workspace_firtool_verilog_path'))).to be(true)
          expect(File.file?(artifacts.fetch('workspace_normalized_verilog_path'))).to be(true)
          expect(File.file?(artifacts.fetch('workspace_pure_verilog_entry_path'))).to be(true)
          expect(File.directory?(artifacts.fetch('workspace_pure_verilog_root'))).to be(true)
          expect(artifacts.fetch('workspace_normalized_verilog_path')).to start_with(File.join(workspace, 'import_artifacts'))
          expect(report.fetch('mixed_import').fetch('workspace_normalized_verilog_path')).to eq(
            artifacts.fetch('workspace_normalized_verilog_path')
          )
          expect(result.source_verilog_path).to eq(artifacts.fetch('workspace_normalized_verilog_path'))
        end
      end
    end

    it 'writes an import-local Gameboy wrapper and records it in the report' do
      require_reference_tree!

      fake_task_class = Class.new do
        def initialize(options)
          @options = options
        end

        def run
          out_dir = @options.fetch(:out)
          FileUtils.mkdir_p(out_dir)
          FileUtils.mkdir_p(File.join(out_dir, '.mixed_import', 'pure_verilog', 'rtl'))
          FileUtils.mkdir_p(File.join(out_dir, '.mixed_import', 'pure_verilog', 'generated_vhdl'))

          staged_gb = File.join(out_dir, '.mixed_import', 'pure_verilog', 'rtl', 'gb.v')
          staged_speedcontrol = File.join(out_dir, '.mixed_import', 'pure_verilog', 'generated_vhdl', 'speedcontrol.v')
          File.write(staged_gb, "module gb;\nendmodule\n")
          File.write(staged_speedcontrol, "module speedcontrol;\nendmodule\n")

          File.write(File.join(out_dir, 'gb.rb'), <<~RUBY)
            class Gb < RHDL::Sim::SequentialComponent
              include RHDL::DSL::Behavior
              include RHDL::DSL::Sequential

              def self.verilog_module_name
                'gb'
              end
            end
          RUBY

          File.write(File.join(out_dir, 'speedcontrol.rb'), <<~RUBY)
            class Speedcontrol < RHDL::Sim::SequentialComponent
              include RHDL::DSL::Behavior
              include RHDL::DSL::Sequential

              def self.verilog_module_name
                'speedcontrol'
              end
            end
          RUBY

          File.write(@options.fetch(:report), JSON.pretty_generate(
            success: true,
            strict: true,
            top: 'gb',
            module_count: 1,
            modules: [
              {
                name: 'gb',
                staged_verilog_path: staged_gb,
                staged_verilog_module_name: 'gb',
                origin_kind: 'source_verilog',
                original_source_path: staged_gb,
                emitted_dsl_features: %w[behavior sequential]
              },
              {
                name: 'speedcontrol',
                staged_verilog_path: staged_speedcontrol,
                staged_verilog_module_name: 'speedcontrol',
                origin_kind: 'source_vhdl_generated',
                original_source_path: staged_speedcontrol,
                emitted_dsl_features: %w[behavior sequential]
              }
            ],
            mixed_import: {
              pure_verilog_files: [
                {
                  path: staged_gb,
                  primary_module_name: 'gb',
                  origin_kind: 'source_verilog',
                  original_source_path: staged_gb
                },
                {
                  path: staged_speedcontrol,
                  primary_module_name: 'speedcontrol',
                  origin_kind: 'source_vhdl_generated',
                  original_source_path: staged_speedcontrol
                }
              ],
              vhdl_synth_outputs: [
                {
                  entity: 'speedcontrol',
                  module_name: 'speedcontrol',
                  source_path: File.expand_path('examples/gameboy/reference/rtl/speedcontrol.vhd', Dir.pwd),
                  output_path: staged_speedcontrol
                }
              ]
            },
            artifacts: {}
          ))
        end
      end

      Dir.mktmpdir('gameboy_import_wrapper_out') do |out_dir|
        Dir.mktmpdir('gameboy_import_wrapper_ws') do |workspace|
          importer = described_class.new(
            output_dir: out_dir,
            workspace_dir: workspace,
            keep_workspace: true,
            clean_output: true,
            progress: ->(_msg) {},
            import_task_class: fake_task_class
          )

          result = importer.run
          expect(result.success?).to be(true)

          wrapper_path = File.join(out_dir, 'gameboy.rb')
          expect(result.files_written).to include(wrapper_path)
          expect(File.read(wrapper_path)).to include('class Gameboy < RHDL::Sim::SequentialComponent')
          expect(File.read(wrapper_path)).to include('instance :speed_ctrl, Speedcontrol')
          expect(File.read(wrapper_path)).to include('instance :gb_core, Gb')
          expect(File.read(wrapper_path)).to include('port :const_zero => [:speed_ctrl, :pause]')
          expect(File.read(wrapper_path)).to include('port :const_zero => [:speed_ctrl, :DMA_on]')
          expect(File.read(wrapper_path)).to include('port :const_zero => [:speed_ctrl, :speedup]')
          expect(File.read(wrapper_path)).to include('port :const_zero => [:gb_core, :fast_boot_en]')
          expect(File.read(wrapper_path)).to include('port :const_zero => [:gb_core, :gg_reset]')
          expect(File.read(wrapper_path)).to include('port :const_one => [:gb_core, :serial_data_in]')
          expect(File.read(wrapper_path)).to include('port :const_zero => [:gb_core, :increaseSSHeaderCount]')
          expect(File.read(wrapper_path)).to include('port :const_one => [:gb_core, :cart_oe]')
          expect(File.read(wrapper_path)).to include('port :const_zero_8 => [:gb_core, :cart_ram_size]')
          expect(File.read(wrapper_path)).not_to include('input :ce')

          report = JSON.parse(File.read(result.report_path))
          expect(report.dig('artifacts', 'wrapper_ruby_path')).to eq(wrapper_path)
          expect(report.fetch('import_wrapper')).to include(
            'class_name' => 'Gameboy',
            'module_name' => 'gameboy',
            'path' => wrapper_path,
            'core_class_name' => 'Gb',
            'speedcontrol_class_name' => 'Speedcontrol',
            'uses_imported_speedcontrol' => true
          )
        end
      end
    end

    it 'writes a per-component manifest into the final report' do
      require_reference_tree!

      fake_task_class = Class.new do
        def initialize(options)
          @options = options
        end

        def run
          out_dir = @options.fetch(:out)
          staged_root = File.join(out_dir, '.mixed_import', 'pure_verilog', 'rtl')
          FileUtils.mkdir_p(staged_root)

          File.write(File.join(staged_root, 'gb.v'), "module gb(input logic a, output logic y); assign y = a; endmodule\n")
          File.write(File.join(staged_root, 'video.v'), "module video(input logic a, output logic y); assign y = a; endmodule\n")

          File.write(File.join(out_dir, 'gb.rb'), <<~RUBY)
            class Gb < RHDL::Sim::SequentialComponent
              def self.verilog_module_name
                "gb"
              end
            end
          RUBY
          File.write(File.join(out_dir, 'video.rb'), <<~RUBY)
            class Video < RHDL::Sim::SequentialComponent
              def self.verilog_module_name
                "video"
              end
            end
          RUBY

          File.write(@options.fetch(:report), JSON.pretty_generate(
            success: true,
            module_count: 2,
            modules: [
              { name: 'gb', start_line: 1, end_line: 1, import_errors: 0, import_warnings: 0, import_diagnostics: [] },
              { name: 'video', start_line: 2, end_line: 2, import_errors: 0, import_warnings: 0, import_diagnostics: [] }
            ],
            mixed_import: {
              pure_verilog_root: File.join(out_dir, '.mixed_import', 'pure_verilog'),
              pure_verilog_files: [
                {
                  path: File.join(staged_root, 'gb.v'),
                  language: 'verilog',
                  generated: false,
                  origin_kind: 'source_verilog',
                  original_source_path: File.join(Dir.pwd, 'examples/gameboy/reference/rtl/gb.v')
                },
                {
                  path: File.join(staged_root, 'video.v'),
                  language: 'verilog',
                  generated: false,
                  origin_kind: 'source_verilog',
                  original_source_path: File.join(Dir.pwd, 'examples/gameboy/reference/rtl/video.v')
                }
              ],
              source_files: []
            },
            artifacts: {
              pure_verilog_root: File.join(out_dir, '.mixed_import', 'pure_verilog')
            }
          ))
        end
      end

      Dir.mktmpdir('gameboy_import_component_manifest_out') do |out_dir|
        Dir.mktmpdir('gameboy_import_component_manifest_ws') do |workspace|
          importer = described_class.new(
            output_dir: out_dir,
            workspace_dir: workspace,
            keep_workspace: true,
            clean_output: true,
            maintain_directory_structure: true,
            progress: ->(_msg) {},
            import_task_class: fake_task_class
          )

          result = importer.run
          expect(result.success?).to be(true)

          report = JSON.parse(File.read(result.report_path))
          components = report.fetch('components')
          expect(report.fetch('component_count')).to eq(2)
          expect(components.map { |entry| entry.fetch('verilog_module_name') }).to contain_exactly('gb', 'video')
          expect(components.find { |entry| entry.fetch('verilog_module_name') == 'gb' }).to include(
            'ruby_class_name',
            'raised_rhdl_path',
            'staged_verilog_path',
            'staged_verilog_module_name',
            'origin_kind'
          )
          gb = components.find { |entry| entry.fetch('verilog_module_name') == 'gb' }
          expect(gb.fetch('origin_kind')).to eq('source_verilog')
          expect(gb.fetch('keep_structure_relative_path')).to eq(File.join('rtl', 'gb.rb'))
          expect(gb.fetch('staged_verilog_path')).to end_with('/.mixed_import/pure_verilog/rtl/gb.v')
          expect(gb.fetch('original_source_path')).to end_with('/examples/gameboy/reference/rtl/gb.v')
        end
      end
    end

    it 'prefers importer-written per-module provenance when building the final component manifest' do
      require_reference_tree!

      fake_task_class = Class.new do
        def initialize(options)
          @options = options
        end

        def run
          out_dir = @options.fetch(:out)
          generated_dir = File.join(out_dir, '.mixed_import', 'pure_verilog', 'generated_vhdl')
          FileUtils.mkdir_p(generated_dir)

          staged_verilog_path = File.join(generated_dir, 'GBse.v')
          raised_path = File.join(out_dir, 'g_bse.rb')
          original_source_path = File.join(Dir.pwd, 'examples/gameboy/reference/rtl/T80/GBse.vhd')

          File.write(staged_verilog_path, "module GBse(input logic clk, output logic q); assign q = clk; endmodule\n")
          File.write(raised_path, <<~RUBY)
            class GBse < RHDL::Sim::SequentialComponent
              include RHDL::DSL::Sequential

              def self.verilog_module_name
                "GBse"
              end
            end
          RUBY

          File.write(@options.fetch(:report), JSON.pretty_generate(
            success: true,
            module_count: 1,
            modules: [
              {
                name: 'GBse',
                expected_dsl_features: { behavior: true, sequential: true, memory: false },
                verilog_module_name: 'GBse',
                ruby_class_name: 'GBse',
                raised_rhdl_path: raised_path,
                staged_verilog_path: staged_verilog_path,
                staged_verilog_module_name: 'GBse',
                origin_kind: 'source_vhdl_generated',
                source_kind: 'generated_vhdl',
                original_source_path: original_source_path,
                emitted_dsl_features: %w[behavior sequential],
                emitted_base_class: 'RHDL::Sim::SequentialComponent',
                vhdl_synth: {
                  entity: 'GBse',
                  module_name: 'GBse',
                  library: 'work',
                  standard: '08',
                  workdir: File.join(out_dir, '.mixed_import', 'ghdl_work'),
                  extra_args: ['-gWIDTH=8'],
                  source_path: original_source_path
                }
              }
            ],
            mixed_import: {
              pure_verilog_root: File.join(out_dir, '.mixed_import', 'pure_verilog'),
              vhdl_synth_outputs: [
                {
                  entity: 'GBse',
                  module_name: 'GBse',
                  library: 'work',
                  standard: '08',
                  workdir: File.join(out_dir, '.mixed_import', 'ghdl_work'),
                  extra_args: ['-gWIDTH=8'],
                  source_path: original_source_path,
                  output_path: staged_verilog_path
                }
              ]
            },
            artifacts: {
              pure_verilog_root: File.join(out_dir, '.mixed_import', 'pure_verilog')
            }
          ))
        end
      end

      Dir.mktmpdir('gameboy_import_report_owned_provenance_out') do |out_dir|
        Dir.mktmpdir('gameboy_import_report_owned_provenance_ws') do |workspace|
          importer = described_class.new(
            output_dir: out_dir,
            workspace_dir: workspace,
            keep_workspace: true,
            clean_output: true,
            maintain_directory_structure: true,
            progress: ->(_msg) {},
            import_task_class: fake_task_class
          )

          result = importer.run
          expect(result.success?).to be(true)

          report = JSON.parse(File.read(result.report_path))
          component = report.fetch('components').fetch(0)
          expect(component).to include(
            'module_name' => 'GBse',
            'verilog_module_name' => 'GBse',
            'ruby_class_name' => 'GBse',
            'staged_verilog_path' => File.join(out_dir, '.mixed_import', 'pure_verilog', 'generated_vhdl', 'GBse.v'),
            'staged_verilog_module_name' => 'GBse',
            'origin_kind' => 'source_vhdl_generated',
            'source_kind' => 'generated_vhdl',
            'original_source_path' => File.join(Dir.pwd, 'examples/gameboy/reference/rtl/T80/GBse.vhd'),
            'raised_rhdl_path' => File.join(out_dir, 'rtl', 'T80', 'g_bse.rb'),
            'keep_structure_relative_path' => File.join('rtl', 'T80', 'g_bse.rb'),
            'expected_dsl_features' => { 'behavior' => true, 'sequential' => true, 'memory' => false },
            'behavior' => true,
            'sequential' => true,
            'memory' => false,
            'emitted_dsl_features' => contain_exactly('behavior', 'sequential'),
            'emitted_base_class' => 'RHDL::Sim::SequentialComponent',
            'vhdl_synth' => include(
              'entity' => 'GBse',
              'module_name' => 'GBse',
              'library' => 'work',
              'standard' => '08',
              'workdir' => File.join(out_dir, '.mixed_import', 'ghdl_work'),
              'extra_args' => ['-gWIDTH=8'],
              'source_path' => File.join(Dir.pwd, 'examples/gameboy/reference/rtl/T80/GBse.vhd')
            )
          )
        end
      end
    end

    it 'detects behavior DSL from raised files that emit behavior blocks without a behavior mixin' do
      Dir.mktmpdir('gameboy_import_behavior_inventory_out') do |out_dir|
        importer = new_importer(output_dir: out_dir)
        raised_path = File.join(out_dir, 'gbc_snd.rb')
        File.write(raised_path, <<~RUBY)
          class GbcSnd < RHDL::Sim::Component
            def self.verilog_module_name
              "gbc_snd"
            end

            behavior do
              out <= 0
            end
          end
        RUBY

        inventory = importer.send(:raised_component_inventory, [raised_path])
        entry = inventory.fetch('gbc_snd')

        expect(entry.fetch(:dsl_features)).to include('behavior')
      end
    end
  end

end
