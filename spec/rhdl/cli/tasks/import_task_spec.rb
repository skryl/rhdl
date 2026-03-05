# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'tmpdir'
require 'json'

RSpec.describe RHDL::CLI::Tasks::ImportTask do
  let(:tmp_dir) { Dir.mktmpdir('rhdl_import_task_spec') }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  it 'imports verilog through external tooling without raise step' do
    input = File.join(tmp_dir, 'design.v')
    File.write(input, 'module design(input logic a, output logic y); assign y = a; endmodule')

    task = described_class.new(
      mode: :verilog,
      input: input,
      out: tmp_dir,
      raise_to_dsl: false,
      tool: 'circt-translate'
    )

    allow(RHDL::Codegen::CIRCT::Tooling).to receive(:verilog_to_circt_mlir).and_return(
      {
        success: true,
        command: 'circt-translate --import-verilog design.v -o design.mlir',
        stdout: '',
        stderr: ''
      }
    )

    expect { task.run }.to output(/Wrote CIRCT MLIR/).to_stdout
  end

  it 'raises a descriptive error when verilog tooling fails' do
    input = File.join(tmp_dir, 'broken.v')
    File.write(input, 'module broken(input logic a, output logic y); assign y = a; endmodule')

    task = described_class.new(
      mode: :verilog,
      input: input,
      out: tmp_dir,
      raise_to_dsl: false,
      tool: 'circt-translate'
    )

    allow(RHDL::Codegen::CIRCT::Tooling).to receive(:verilog_to_circt_mlir).and_return(
      {
        success: false,
        command: 'circt-translate --import-verilog broken.v -o broken.mlir',
        stdout: '',
        stderr: 'parse failed'
      }
    )

    expect { task.run }.to raise_error(RuntimeError, /Verilog->CIRCT conversion failed/)
  end

  it 'raises CIRCT MLIR into DSL files in circt mode' do
    mlir_file = File.join(tmp_dir, 'simple.mlir')
    File.write(mlir_file, <<~MLIR)
      hw.module @simple(%a: i1) -> (y: i1) {
        hw.output %a : i1
      }
    MLIR

    task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      top: 'simple'
    )

    expect { task.run }.to output(/Raised 1 DSL file/).to_stdout
    expect(File.exist?(File.join(tmp_dir, 'simple.rb'))).to be(true)
  end

  it 'prints import progress steps during circt raise flow' do
    mlir_file = File.join(tmp_dir, 'simple.mlir')
    File.write(mlir_file, <<~MLIR)
      hw.module @simple(%a: i1) -> (y: i1) {
        hw.output %a : i1
      }
    MLIR

    task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      top: 'simple'
    )

    expect do
      task.run
    end.to output(
      /Import step: Parse\/import CIRCT MLIR.*Import step: Raise CIRCT -> RHDL files.*Import step: Format RHDL output directory.*Import step: Write import report/m
    ).to_stdout
  end

  it 'requests formatted raised output during import raise flow' do
    mlir_file = File.join(tmp_dir, 'simple.mlir')
    File.write(mlir_file, <<~MLIR)
      hw.module @simple(%a: i1) -> (y: i1) {
        hw.output %a : i1
      }
    MLIR

    task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      top: 'simple'
    )

    expect(RHDL::Codegen).to receive(:raise_circt).with(
      anything,
      out_dir: tmp_dir,
      top: 'simple',
      strict: true,
      format: false
    ).and_call_original
    expect(RHDL::Codegen).to receive(:format_raised_dsl).with(tmp_dir).and_call_original

    task.run
  end

  it 'skips raise flow in circt mode when raise_to_dsl is false' do
    mlir_file = File.join(tmp_dir, 'simple.mlir')
    File.write(mlir_file, <<~MLIR)
      hw.module @simple(%a: i1) -> (y: i1) {
        hw.output %a : i1
      }
    MLIR

    task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      raise_to_dsl: false
    )

    expect { task.run }.to output(/CIRCT MLIR ready/).to_stdout
    expect(File.exist?(File.join(tmp_dir, 'simple.rb'))).to be(false)
  end

  it 'writes an import report JSON for circt mode raise flow' do
    mlir_file = File.join(tmp_dir, 'simple.mlir')
    report_file = File.join(tmp_dir, 'report.json')
    File.write(mlir_file, <<~MLIR)
      hw.module @simple(%a: i1) -> (y: i1) {
        hw.output %a : i1
      }
    MLIR

    task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      top: 'simple',
      report: report_file,
      strict: true
    )

    expect { task.run }.to output(/Wrote import report/).to_stdout
    expect(File.exist?(report_file)).to be(true)

    report = JSON.parse(File.read(report_file))
    expect(report.fetch('success')).to be(true)
    expect(report.fetch('strict')).to be(true)
    expect(report.fetch('module_count')).to eq(1)
    expect(report.fetch('modules').first.fetch('name')).to eq('simple')
  end

  it 'fails when top is missing but still writes partial output files' do
    mlir_file = File.join(tmp_dir, 'simple.mlir')
    File.write(mlir_file, <<~MLIR)
      hw.module @simple(%a: i1) -> (y: i1) {
        hw.output %a : i1
      }
    MLIR

    task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      top: 'missing_top'
    )

    expect { task.run }.to raise_error(RuntimeError, /partial output written/)
    expect(File.exist?(File.join(tmp_dir, 'simple.rb'))).to be(true)
  end

  it 'enforces strict top-closure checks unless unresolved targets are allowlisted as extern' do
    mlir_file = File.join(tmp_dir, 'closure.mlir')
    failing_report = File.join(tmp_dir, 'closure_failing_report.json')
    passing_report = File.join(tmp_dir, 'closure_passing_report.json')
    File.write(mlir_file, <<~MLIR)
      hw.module @top(%a: i1) -> (y: i1) {
        %child_y = hw.instance "u_child" @child(a: %a: i1) -> (y: i1)
        hw.output %child_y : i1
      }
    MLIR

    failing_task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      top: 'top',
      strict: true,
      report: failing_report
    )
    expect { failing_task.run }.to raise_error(RuntimeError, /partial output written/)
    expect(File.exist?(failing_report)).to be(true)
    failing = JSON.parse(File.read(failing_report))
    expect(failing.fetch('success')).to be(false)
    expect(
      failing.fetch('import_diagnostics').any? do |diag|
        diag.fetch('op') == 'import.closure' && diag.fetch('message').include?('Unresolved instance target @child')
      end
    ).to be(true)

    passing_task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      top: 'top',
      strict: true,
      extern_modules: ['child'],
      report: passing_report
    )
    expect { passing_task.run }.not_to raise_error
    passing = JSON.parse(File.read(passing_report))
    expect(passing.fetch('success')).to be(true)
    expect(File.exist?(File.join(tmp_dir, 'top.rb'))).to be(true)
  end

  it 'raises for unsupported mode' do
    task = described_class.new(mode: :unknown, input: 'x', out: tmp_dir)
    expect { task.run }.to raise_error(ArgumentError, /Unknown import mode/)
  end

  it 'postprocesses generated VHDL Verilog for known positional-parameter modules' do
    out_path = File.join(tmp_dir, 'eReg_SavestateV.v')
    File.write(out_path, "module eReg_SavestateV (\n  input clk\n);\nendmodule\n")
    task = described_class.new(mode: :mixed, out: tmp_dir)

    task.send(:postprocess_generated_vhdl_verilog!, entity: 'eReg_SavestateV', out_path: out_path)

    text = File.read(out_path)
    expect(text).to include('module eReg_SavestateV')
    expect(text).to include('parameter P4 = 0')
  end

  it 'postprocesses generated VHDL Verilog by renaming reserved do token for GBse' do
    out_path = File.join(tmp_dir, 'GBse.v')
    File.write(out_path, "module GBse(input do, output do); assign do = do; endmodule\n")
    task = described_class.new(mode: :mixed, out: tmp_dir)

    task.send(:postprocess_generated_vhdl_verilog!, entity: 'GBse', out_path: out_path)

    text = File.read(out_path)
    expect(text).to include('do_o')
    expect(text).not_to match(/\bdo\b/)
  end

  it 'lowers Moore MLIR to core before raise when mixed import emits moore.module' do
    mlir_path = File.join(tmp_dir, 'mixed.moore.mlir')
    File.write(mlir_path, "moore.module @top() {\n}\n")
    lowered_path = "#{mlir_path}.core.lowered"
    task = described_class.new(mode: :mixed, out: tmp_dir)
    status = instance_double(Process::Status, success?: true)

    expect(Open3).to receive(:capture3).with(
      'circt-opt',
      '--moore-lower-concatref',
      '--canonicalize',
      '--moore-lower-concatref',
      '--convert-moore-to-core',
      '--llhd-sig2reg',
      '--canonicalize',
      mlir_path,
      '-o',
      lowered_path
    ) do
      File.write(lowered_path, "hw.module @top() {\n  hw.output\n}\n")
      ['', '', status]
    end

    expect do
      task.send(:lower_moore_to_core_mlir_if_needed!, mlir_out: mlir_path)
    end.to output(/Lower Moore MLIR -> core\/llhd/).to_stdout

    expect(File.read(mlir_path)).to include('hw.module @top')
  end

  describe 'mixed mode' do
    it 'requires either --manifest or a top source file --input' do
      task = described_class.new(
        mode: :mixed,
        out: tmp_dir,
        raise_to_dsl: false
      )

      expect { task.run }.to raise_error(ArgumentError, /Mixed mode requires --manifest or --input/)
    end

    it 'requires --input to be a file path when manifest is omitted' do
      task = described_class.new(
        mode: :mixed,
        input: tmp_dir,
        out: tmp_dir,
        raise_to_dsl: false
      )

      expect { task.run }.to raise_error(ArgumentError, /Mixed mode autoscan requires --input to be a file path/)
    end

    it 'imports mixed sources through staging without raise step' do
      manifest_path = File.join(tmp_dir, 'mixed_import.yml')
      File.write(
        manifest_path,
        <<~YAML
          version: 1
          top:
            name: mixed_top
            language: verilog
            file: top.sv
          files:
            - path: top.sv
              language: verilog
            - path: leaf.vhd
              language: vhdl
        YAML
      )

      staged_verilog = File.join(tmp_dir, 'staged.v')
      task = described_class.new(
        mode: :mixed,
        manifest: manifest_path,
        out: tmp_dir,
        raise_to_dsl: false,
        tool: 'circt-translate'
      )

      allow(task).to receive(:build_mixed_import_staging).and_return(
        {
          staged_verilog_path: staged_verilog,
          provenance: { source_files: [] }
        }
      )
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:verilog_to_circt_mlir).and_return(
        {
          success: true,
          command: 'circt-translate --import-verilog staged.v -o mixed_top.mlir',
          stdout: '',
          stderr: ''
        }
      )

      expect { task.run }.to output(/Wrote CIRCT MLIR/).to_stdout
      expect(task).to have_received(:build_mixed_import_staging)
    end

    it 'writes mixed import provenance into report when raise flow is enabled' do
      manifest_path = File.join(tmp_dir, 'mixed_import.yml')
      report_path = File.join(tmp_dir, 'mixed_report.json')
      File.write(
        manifest_path,
        <<~YAML
          version: 1
          top:
            name: mixed_top
            language: verilog
            file: top.sv
          files:
            - path: top.sv
              language: verilog
        YAML
      )

      staged_verilog = File.join(tmp_dir, 'staged.v')
      File.write(staged_verilog, "module mixed_top(input logic a, output logic y); assign y = a; endmodule\n")

      task = described_class.new(
        mode: :mixed,
        manifest: manifest_path,
        out: tmp_dir,
        strict: true,
        report: report_path,
        tool: 'circt-translate'
      )

      allow(task).to receive(:build_mixed_import_staging).and_return(
        {
          staged_verilog_path: staged_verilog,
          top_name: 'mixed_top',
          tool_args: [],
          provenance: {
            top_name: 'mixed_top',
            top_language: 'verilog',
            top_file: staged_verilog,
            source_files: [{ path: staged_verilog, language: 'verilog' }]
          }
        }
      )
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:verilog_to_circt_mlir) do |**args|
        File.write(
          args.fetch(:out_path),
          <<~MLIR
            hw.module @mixed_top(%a: i1) -> (y: i1) {
              hw.output %a : i1
            }
          MLIR
        )
        {
          success: true,
          command: 'circt-translate --import-verilog staged.v -o mixed_top.mlir',
          stdout: '',
          stderr: ''
        }
      end

      expect { task.run }.to output(/Wrote import report/).to_stdout
      expect(File.exist?(File.join(tmp_dir, 'mixed_top.rb'))).to be(true)
      report = JSON.parse(File.read(report_path))
      expect(report.fetch('success')).to be(true)
      expect(report.fetch('top')).to eq('mixed_top')
      expect(report.fetch('mixed_import').fetch('top_name')).to eq('mixed_top')
      expect(report.fetch('mixed_import').fetch('source_files').first.fetch('language')).to eq('verilog')
    end

    it 'runs mixed autoscan end-to-end through raise flow and writes report provenance' do
      rtl_dir = File.join(tmp_dir, 'rtl')
      FileUtils.mkdir_p(rtl_dir)
      top_path = File.join(rtl_dir, 'mixed_top.sv')
      leaf_vhdl = File.join(rtl_dir, 'leaf.vhd')
      report_path = File.join(tmp_dir, 'mixed_autoscan_report.json')
      File.write(top_path, "module mixed_top(input logic a, output logic y); assign y = a; endmodule\n")
      File.write(leaf_vhdl, <<~VHDL)
        entity leaf is
        end entity;
        architecture rtl of leaf is
        begin
        end architecture;
      VHDL

      task = described_class.new(
        mode: :mixed,
        input: top_path,
        out: tmp_dir,
        top: 'mixed_top',
        strict: true,
        report: report_path,
        tool: 'circt-translate'
      )

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
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:verilog_to_circt_mlir) do |**args|
        File.write(
          args.fetch(:out_path),
          <<~MLIR
            hw.module @mixed_top(%a: i1) -> (y: i1) {
              hw.output %a : i1
            }
          MLIR
        )
        {
          success: true,
          command: 'circt-translate --import-verilog mixed_staged.v -o mixed_top.mlir',
          stdout: '',
          stderr: ''
        }
      end

      expect { task.run }.to output(/Wrote import report/).to_stdout
      expect(File.exist?(File.join(tmp_dir, 'mixed_top.rb'))).to be(true)
      expect(File.exist?(report_path)).to be(true)

      report = JSON.parse(File.read(report_path))
      expect(report.fetch('success')).to be(true)
      expect(report.fetch('top')).to eq('mixed_top')
      mixed = report.fetch('mixed_import')
      expect(mixed.fetch('autoscan_root')).to eq(File.expand_path(rtl_dir))
      expect(mixed.fetch('top_file')).to eq(File.expand_path(top_path))
      expect(mixed.fetch('top_language')).to eq('verilog')
      expect(mixed.fetch('vhdl_analysis_commands')).not_to be_empty
      expect(mixed.fetch('vhdl_synth_outputs')).not_to be_empty
      expect(mixed.fetch('staging_entry_path')).to include('.mixed_import/mixed_staged.v')
    end

    it 'fails fast when VHDL synth fails during mixed import run' do
      rtl_dir = File.join(tmp_dir, 'rtl')
      FileUtils.mkdir_p(rtl_dir)
      top_path = File.join(rtl_dir, 'mixed_top.sv')
      leaf_vhdl = File.join(rtl_dir, 'leaf.vhd')
      File.write(top_path, "module mixed_top(input logic a, output logic y); assign y = a; endmodule\n")
      File.write(leaf_vhdl, "entity leaf is end entity;\narchitecture rtl of leaf is begin end architecture;\n")

      task = described_class.new(
        mode: :mixed,
        input: top_path,
        out: tmp_dir,
        strict: true,
        tool: 'circt-translate'
      )

      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:ghdl_analyze).and_return(
        {
          success: true,
          command: 'ghdl -a --std=08 leaf.vhd',
          stdout: '',
          stderr: ''
        }
      )
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:ghdl_synth_to_verilog).and_return(
        {
          success: false,
          command: 'ghdl --synth --out=verilog leaf',
          stdout: '',
          stderr: 'synth failed'
        }
      )
      expect(RHDL::Codegen::CIRCT::Tooling).not_to receive(:verilog_to_circt_mlir)

      expect { task.run }.to raise_error(RuntimeError, /VHDL synth->Verilog failed/)
    end
  end
end
