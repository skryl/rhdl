# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

module RHDL
  module SpecFixtures
    class CIRCTToolingAdder < RHDL::Sim::Component
      input :a, width: 8
      input :b, width: 8
      output :y, width: 8

      behavior do
        y <= a + b
      end
    end
  end
end

RSpec.describe 'RHDL::Codegen CIRCT APIs' do
  let(:mlir) do
    <<~MLIR
      hw.module @top(%a: i8, %b: i8) -> (y: i8) {
        %sum = comb.add %a, %b : i8
        hw.output %sum : i8
      }
    MLIR
  end

  describe '.import_circt_mlir' do
    it 'imports MLIR into CIRCT modules with diagnostics' do
      result = RHDL::Codegen.import_circt_mlir(mlir)
      expect(result).to be_a(RHDL::Codegen::CIRCT::ImportResult)
      expect(result.success?).to be(true)
      expect(result.modules.map(&:name)).to eq(['top'])
    end
  end

  describe '.raise_circt_sources' do
    it 'raises nodes/MLIR into in-memory ruby sources' do
      result = RHDL::Codegen.raise_circt_sources(mlir, top: 'top')
      expect(result).to be_a(RHDL::Codegen::CIRCT::SourceResult)
      expect(result.success?).to be(true)
      expect(result.sources.keys).to include('top')
      expect(result.sources['top']).to include('class Top')
    end
  end

  describe '.raise_circt' do
    it 'writes raised DSL files to disk' do
      Dir.mktmpdir('rhdl_codegen_api_spec') do |dir|
        result = RHDL::Codegen.raise_circt(mlir, out_dir: dir, top: 'top')
        expect(result.success?).to be(true)
        expect(result.files_written).to include(File.join(dir, 'top.rb'))
        expect(File.read(File.join(dir, 'top.rb'))).to include('behavior do')
      end
    end
  end

  describe '.raise_circt_components' do
    it 'loads raised DSL classes into a namespace module' do
      namespace = Module.new
      result = RHDL::Codegen.raise_circt_components(mlir, namespace: namespace, top: 'top')
      expect(result.success?).to be(true)
      expect(result.components.keys).to include('top')
      expect(result.components['top']).to be < RHDL::Sim::Component
      expect(namespace.const_defined?(:Top, false)).to be(true)
    end
  end

  describe '.verilog_from_mlir' do
    it 'exports MLIR to Verilog through external tooling wrapper' do
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:circt_mlir_to_verilog) do |kwargs|
        File.write(kwargs[:out_path], "module top(input [7:0] a, input [7:0] b, output [7:0] y);\nendmodule\n")
        { success: true, command: 'circt-translate --export-verilog input.mlir -o output.v', stdout: '', stderr: '' }
      end

      verilog = RHDL::Codegen.verilog_from_mlir(mlir)
      expect(verilog).to include('module top')
      expect(verilog).to include('output [7:0] y')
    end

    it 'raises a descriptive error when tooling export fails' do
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:circt_mlir_to_verilog).and_return(
        { success: false, command: 'circt-translate --export-verilog input.mlir -o output.v', stdout: '', stderr: 'export failed' }
      )

      expect { RHDL::Codegen.verilog_from_mlir(mlir) }.to raise_error(RuntimeError, /CIRCT MLIR->Verilog conversion failed/)
    end
  end

  describe '.verilog_via_circt' do
    it 'exports a component via MLIR + external tooling path' do
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:circt_mlir_to_verilog) do |kwargs|
        File.write(kwargs[:out_path], "module spec_fixtures_circt_tooling_adder;\nendmodule\n")
        { success: true, command: 'circt-translate --export-verilog input.mlir -o output.v', stdout: '', stderr: '' }
      end

      verilog = RHDL::Codegen.verilog_via_circt(RHDL::SpecFixtures::CIRCTToolingAdder)
      expect(verilog).to include('module spec_fixtures_circt_tooling_adder')
    end
  end
end
