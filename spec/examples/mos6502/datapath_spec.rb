# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe MOS6502::Datapath do
  describe 'structure' do
    it 'has structure defined' do
      expect(described_class.structure_defined?).to be_truthy
    end

    it 'defines expected ports' do
      datapath = described_class.new('test_dp')

      # Clock and control
      expect(datapath.inputs.keys).to include(:clk, :rst, :rdy)

      # Memory interface
      expect(datapath.inputs.keys).to include(:data_in)
      expect(datapath.outputs.keys).to include(:data_out, :addr, :rw)

      # Debug outputs
      expect(datapath.outputs.keys).to include(:reg_a, :reg_x, :reg_y, :reg_pc)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502_datapath')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('output [15:0] addr')
    end

    it 'includes internal component instances' do
      verilog = described_class.to_verilog
      # Should reference subcomponents or have internal signals
      expect(verilog.length).to be > 1000  # Complex module
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'behavior Verilog compiles and runs' do
        # Use to_verilog_hierarchy to include all sub-module definitions
        verilog = described_class.to_verilog_hierarchy

        inputs = { clk: 1, rst: 1, rdy: 1, data_in: 8 }
        outputs = { addr: 16, data_out: 8, rw: 1, reg_a: 8, reg_x: 8, reg_y: 8, reg_pc: 16 }

        # Datapath is a complex hierarchical component - verify compilation
        vectors = [
          { inputs: { clk: 0, rst: 1, rdy: 1, data_in: 0 } },
          { inputs: { clk: 1, rst: 1, rdy: 1, data_in: 0 } },
          { inputs: { clk: 0, rst: 0, rdy: 1, data_in: 0 } }
        ]

        result = NetlistHelper.run_behavior_simulation(
          verilog,
          module_name: 'mos6502_datapath',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/mos6502_datapath',
          has_clock: true
        )
        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { described_class.new('mos6502_datapath') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'mos6502_datapath') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mos6502_datapath.clk', 'mos6502_datapath.rst')
      expect(ir.inputs.keys).to include('mos6502_datapath.data_in')
      expect(ir.outputs.keys).to include('mos6502_datapath.addr', 'mos6502_datapath.data_out')
    end

    it 'generates complex netlist with gates and DFFs' do
      # Datapath is a complex hierarchical component
      expect(ir.gates.length).to be > 100
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module mos6502_datapath')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'compiles and simulates structure Verilog' do
        # Datapath is a complex hierarchical component - verify compilation
        vectors = [
          { inputs: { clk: 0, rst: 1, rdy: 1, data_in: 0 } },
          { inputs: { clk: 1, rst: 1, rdy: 1, data_in: 0 } },
          { inputs: { clk: 0, rst: 0, rdy: 1, data_in: 0 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/mos6502_datapath')
        expect(result[:success]).to be(true), result[:error]
      end
    end
  end
end
