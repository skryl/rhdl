# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::Codegen::CIRCT::Tooling do
  describe '.verilog_to_circt_mlir' do
    it 'invokes circt-translate import command with expected args' do
      status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3).with(
        'circt-translate', '--import-verilog', 'in.v', '-o', 'out.mlir'
      ).and_return(['', '', status])

      result = described_class.verilog_to_circt_mlir(verilog_path: 'in.v', out_path: 'out.mlir')
      expect(result[:success]).to be(true)
      expect(result[:command]).to include('--import-verilog')
      expect(result[:output_path]).to eq('out.mlir')
    end

    it 'returns a descriptive failure for firtool verilog import mode' do
      expect(Open3).not_to receive(:capture3)

      result = described_class.verilog_to_circt_mlir(
        verilog_path: 'in.v',
        out_path: 'out.mlir',
        tool: 'firtool'
      )
      expect(result[:success]).to be(false)
      expect(result[:stderr]).to include('does not support direct Verilog import')
      expect(result[:tool]).to eq('firtool')
    end
  end

  describe '.circt_mlir_to_verilog' do
    it 'invokes firtool export command with expected args by default' do
      status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3).with(
        'firtool',
        '--format=mlir',
        'in.mlir',
        '--verilog',
        '-o',
        'out.v',
        "--lowering-options=#{described_class::DEFAULT_FIRTOOL_LOWERING_OPTIONS}"
      ).and_return(['', '', status])

      result = described_class.circt_mlir_to_verilog(mlir_path: 'in.mlir', out_path: 'out.v')
      expect(result[:success]).to be(true)
      expect(result[:tool]).to eq('firtool')
      expect(result[:command]).to match(/--format\\?=mlir/)
      expect(result[:command]).to include('--verilog')
      expect(result[:command]).to match(/--lowering-options\\?=/)
      expect(result[:output_path]).to eq('out.v')
    end

    it 'invokes circt-translate export command when explicitly requested' do
      status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3).with(
        'circt-translate', '--export-verilog', 'in.mlir', '-o', 'out.v'
      ).and_return(['', '', status])

      result = described_class.circt_mlir_to_verilog(
        mlir_path: 'in.mlir',
        out_path: 'out.v',
        tool: 'circt-translate'
      )
      expect(result[:success]).to be(true)
      expect(result[:command]).to include('--export-verilog')
    end

    it 'returns a failure result when tool is missing' do
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)

      result = described_class.circt_mlir_to_verilog(mlir_path: 'in.mlir', out_path: 'out.v')
      expect(result[:success]).to be(false)
      expect(result[:stderr]).to include('Tool not found')
    end
  end
end
