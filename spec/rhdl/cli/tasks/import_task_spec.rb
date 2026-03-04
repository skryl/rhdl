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
      format: true
    ).and_call_original

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
end
