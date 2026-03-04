# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'tmpdir'

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

  it 'raises for unsupported mode' do
    task = described_class.new(mode: :unknown, input: 'x', out: tmp_dir)
    expect { task.run }.to raise_error(ArgumentError, /Unknown import mode/)
  end
end
