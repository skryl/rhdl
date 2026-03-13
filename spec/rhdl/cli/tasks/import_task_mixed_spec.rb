# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'tmpdir'
require 'json'

RSpec.describe RHDL::CLI::Tasks::ImportTask do
  let(:tmp_dir) { Dir.mktmpdir('rhdl_import_task_mixed_spec') }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe 'mixed config resolution' do
    it 'resolves YAML manifest into normalized mixed config' do
      src_dir = File.join(tmp_dir, 'rtl')
      include_dir = File.join(src_dir, 'include')
      FileUtils.mkdir_p(include_dir)
      top = File.join(src_dir, 'top.sv')
      leaf = File.join(src_dir, 'leaf.vhd')
      File.write(top, "module top(input logic a, output logic y); assign y = a; endmodule\n")
      File.write(leaf, "entity leaf is\nend entity;\n")

      manifest = File.join(tmp_dir, 'mixed.yml')
      File.write(
        manifest,
        <<~YAML
          version: 1
          top:
            name: top
            language: verilog
            file: rtl/top.sv
          files:
            - path: rtl/top.sv
              language: verilog
            - path: rtl/leaf.vhd
              language: vhdl
              library: work
          include_dirs:
            - rtl/include
          defines:
            WIDTH: "32"
            FEATURE:
          vhdl:
            standard: "08"
        YAML
      )

      task = described_class.new(mode: :mixed, manifest: manifest, out: File.join(tmp_dir, 'out'))
      config = task.send(:resolve_mixed_import_config, out_dir: File.join(tmp_dir, 'out'))

      expect(config.fetch(:top)).to include(name: 'top', language: 'verilog')
      expect(config.fetch(:verilog_files).map { |f| f[:path] }).to include(File.expand_path(top))
      expect(config.fetch(:vhdl_files).map { |f| f[:path] }).to include(File.expand_path(leaf))
      expect(config.fetch(:tool_args)).to include("-I#{File.expand_path(include_dir)}")
      expect(config.fetch(:tool_args)).to include('-DWIDTH=32')
      expect(config.fetch(:tool_args)).to include('-DFEATURE')
      expect(config.fetch(:manifest_path)).to eq(File.expand_path(manifest))
    end

    it 'resolves optional manifest vhdl.synth_targets entries' do
      src_dir = File.join(tmp_dir, 'rtl')
      FileUtils.mkdir_p(src_dir)
      top = File.join(src_dir, 'top.sv')
      leaf = File.join(src_dir, 'leaf.vhd')
      File.write(top, "module top(input logic a, output logic y); assign y = a; endmodule\n")
      File.write(leaf, "entity leaf is\nend entity;\n")

      manifest = File.join(tmp_dir, 'mixed_with_targets.yml')
      File.write(
        manifest,
        <<~YAML
          version: 1
          top:
            name: top
            language: verilog
            file: rtl/top.sv
          files:
            - path: rtl/top.sv
              language: verilog
            - path: rtl/leaf.vhd
              language: vhdl
          vhdl:
            standard: "08"
            synth_targets:
              - leaf
              - entity: helper
                library: work
        YAML
      )

      task = described_class.new(mode: :mixed, manifest: manifest, out: File.join(tmp_dir, 'out'))
      config = task.send(:resolve_mixed_import_config, out_dir: File.join(tmp_dir, 'out'))

      expect(config.fetch(:vhdl_synth_targets)).to eq(
        [
          { entity: 'leaf', library: nil },
          { entity: 'helper', library: 'work' }
        ]
      )
    end

    it 'raises for non-array manifest vhdl.synth_targets' do
      src_dir = File.join(tmp_dir, 'rtl')
      FileUtils.mkdir_p(src_dir)
      top = File.join(src_dir, 'top.sv')
      leaf = File.join(src_dir, 'leaf.vhd')
      File.write(top, "module top(input logic a, output logic y); assign y = a; endmodule\n")
      File.write(leaf, "entity leaf is\nend entity;\n")

      manifest = File.join(tmp_dir, 'mixed_with_bad_targets.yml')
      File.write(
        manifest,
        <<~YAML
          version: 1
          top:
            name: top
            language: verilog
            file: rtl/top.sv
          files:
            - path: rtl/top.sv
              language: verilog
            - path: rtl/leaf.vhd
              language: vhdl
          vhdl:
            synth_targets: leaf
        YAML
      )

      task = described_class.new(mode: :mixed, manifest: manifest, out: File.join(tmp_dir, 'out'))
      expect do
        task.send(:resolve_mixed_import_config, out_dir: File.join(tmp_dir, 'out'))
      end.to raise_error(ArgumentError, /vhdl\.synth_targets must be an array/)
    end

    it 'resolves JSON manifest into normalized mixed config' do
      src_dir = File.join(tmp_dir, 'rtl')
      FileUtils.mkdir_p(src_dir)
      top = File.join(src_dir, 'core.vhd')
      File.write(top, "entity core is\nend entity;\n")

      manifest = File.join(tmp_dir, 'mixed.json')
      File.write(
        manifest,
        JSON.pretty_generate(
          {
            version: 1,
            top: {
              name: 'core',
              language: 'vhdl',
              file: 'rtl/core.vhd',
              library: 'work'
            },
            files: [
              {
                path: 'rtl/core.vhd',
                language: 'vhdl',
                library: 'work'
              }
            ],
            vhdl: {
              standard: '08'
            }
          }
        )
      )

      task = described_class.new(mode: :mixed, manifest: manifest, out: File.join(tmp_dir, 'out'))
      config = task.send(:resolve_mixed_import_config, out_dir: File.join(tmp_dir, 'out'))

      expect(config.fetch(:top)).to include(name: 'core', language: 'vhdl', library: 'work')
      expect(config.fetch(:vhdl_files).length).to eq(1)
      expect(config.fetch(:verilog_files)).to be_empty
    end

    it 'resolves autoscan config from top source file input' do
      root = File.join(tmp_dir, 'autoscan')
      FileUtils.mkdir_p(root)
      top = File.join(root, 'system.v')
      helper_vhdl = File.join(root, 'helper.vhd')
      File.write(top, "module system(input logic a, output logic y); assign y = a; endmodule\n")
      File.write(helper_vhdl, "entity helper is\nend entity;\n")

      task = described_class.new(mode: :mixed, input: top, out: File.join(tmp_dir, 'out'))
      config = task.send(:resolve_mixed_import_config, out_dir: File.join(tmp_dir, 'out'))

      expect(config.fetch(:autoscan_root)).to eq(File.expand_path(root))
      expect(config.fetch(:top)).to include(name: 'system', language: 'verilog')
      expect(config.fetch(:verilog_files).map { |f| f[:path] }).to include(File.expand_path(top))
      expect(config.fetch(:vhdl_files).map { |f| f[:path] }).to include(File.expand_path(helper_vhdl))
    end
  end

  describe 'mixed staging orchestration' do
    it 'synthesizes VHDL entities and writes staged Verilog entrypoint' do
      src_dir = File.join(tmp_dir, 'rtl')
      out_dir = File.join(tmp_dir, 'out')
      FileUtils.mkdir_p(src_dir)
      top = File.join(src_dir, 'top.sv')
      leaf = File.join(src_dir, 'leaf.vhd')
      File.write(top, "module top(input logic a, output logic y); assign y = a; endmodule\n")
      File.write(leaf, "entity leaf is\nend entity;\narchitecture rtl of leaf is begin end architecture;\n")

      manifest = File.join(tmp_dir, 'mixed.yml')
      File.write(
        manifest,
        <<~YAML
          version: 1
          top:
            name: top
            language: verilog
            file: rtl/top.sv
          files:
            - path: rtl/top.sv
              language: verilog
            - path: rtl/leaf.vhd
              language: vhdl
              library: work
        YAML
      )

      task = described_class.new(mode: :mixed, manifest: manifest, out: out_dir)
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:ghdl_analyze).and_return(
        {
          success: true,
          command: 'ghdl -a --std=08 leaf.vhd',
          stdout: '',
          stderr: ''
        }
      )
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:ghdl_synth_to_verilog) do |**args|
        FileUtils.mkdir_p(File.dirname(args.fetch(:out_path)))
        File.write(args.fetch(:out_path), "module leaf; endmodule\n")
        {
          success: true,
          command: 'ghdl --synth --out=verilog leaf',
          stdout: '',
          stderr: ''
        }
      end

      staging = task.send(:build_mixed_import_staging, out_dir: out_dir)
      staged_path = staging.fetch(:staged_verilog_path)

      expect(RHDL::Codegen::CIRCT::Tooling).to have_received(:ghdl_analyze).once
      expect(RHDL::Codegen::CIRCT::Tooling).to have_received(:ghdl_synth_to_verilog).once
      expect(File.exist?(staged_path)).to be(true)
      staged = File.read(staged_path)
      expect(staged).to include("`include \"#{File.expand_path(File.join(out_dir, '.mixed_import', 'pure_verilog', 'top.sv'))}\"")
      expect(staged).to include('generated_vhdl/leaf.v')
      expect(staging.fetch(:provenance).fetch(:vhdl_analysis_commands).length).to eq(1)
    end

    it 'fails fast when VHDL analysis fails' do
      src_dir = File.join(tmp_dir, 'rtl')
      out_dir = File.join(tmp_dir, 'out')
      FileUtils.mkdir_p(src_dir)
      top = File.join(src_dir, 'top.sv')
      leaf = File.join(src_dir, 'leaf.vhd')
      File.write(top, "module top(input logic a, output logic y); assign y = a; endmodule\n")
      File.write(leaf, "entity leaf is end entity;\n")

      manifest = File.join(tmp_dir, 'mixed.yml')
      File.write(
        manifest,
        <<~YAML
          version: 1
          top:
            name: top
            language: verilog
            file: rtl/top.sv
          files:
            - path: rtl/top.sv
              language: verilog
            - path: rtl/leaf.vhd
              language: vhdl
              library: work
        YAML
      )

      task = described_class.new(mode: :mixed, manifest: manifest, out: out_dir)
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:ghdl_analyze).and_return(
        {
          success: false,
          command: 'ghdl -a --std=08 leaf.vhd',
          stdout: '',
          stderr: 'analysis failed'
        }
      )

      expect do
        task.send(:build_mixed_import_staging, out_dir: out_dir)
      end.to raise_error(RuntimeError, /VHDL analysis failed/)
    end
  end
end
