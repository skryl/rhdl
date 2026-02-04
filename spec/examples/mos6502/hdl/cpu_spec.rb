# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe RHDL::Examples::MOS6502::CPU do
  describe 'structure' do
    it 'has structure defined' do
      expect(described_class.structure_defined?).to be_truthy
    end

    it 'defines expected ports' do
      # Inputs
      expect(described_class._port_defs.map { |p| p[:name] }).to include(:clk, :rst, :rdy, :irq, :nmi)

      # Outputs
      output_ports = described_class._port_defs.select { |p| p[:direction] == :out }.map { |p| p[:name] }
      expect(output_ports).to include(:reg_a, :reg_x, :reg_y, :reg_sp, :reg_pc, :reg_p)
      expect(output_ports).to include(:addr, :data_out, :rw)
      expect(output_ports).to include(:halted, :cycle_count)
    end

    it 'instantiates CPU components' do
      instance_names = described_class._instance_defs.map { |i| i[:name] }
      expect(instance_names).to include(:registers, :status_reg, :pc, :sp, :ir)
      expect(instance_names).to include(:alu, :decoder, :control)
      expect(instance_names).to include(:addr_gen, :addr_calc, :addr_latch, :data_latch)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502_cpu')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('output [15:0] addr')
      expect(verilog).to include('output halted')
    end

    it 'includes component instances' do
      verilog = described_class.to_verilog
      expect(verilog).to include('registers (')
      expect(verilog).to include('alu (')
      expect(verilog).to include('control (')
    end

    it 'generates hierarchical Verilog with all submodules' do
      verilog = described_class.to_verilog_hierarchy
      # Should include all submodule definitions
      expect(verilog).to include('module mos6502_registers')
      expect(verilog).to include('module mos6502_alu')
      expect(verilog).to include('module mos6502_control_unit')
      expect(verilog).to include('module mos6502_cpu')  # Top module last
    end

    it 'generates valid FIRRTL' do
      firrtl = described_class.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit mos6502_cpu')
      expect(firrtl).to include('input clk')
      expect(firrtl).to include('output addr')
    end

    it 'generates hierarchical FIRRTL with all submodules' do
      firrtl = described_class.to_circt_hierarchy
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit mos6502_cpu')
      # Should include submodule definitions
      expect(firrtl).to include('module mos6502_registers')
      expect(firrtl).to include('module mos6502_alu')
      expect(firrtl).to include('module mos6502_control_unit')
      expect(firrtl).to include('public module mos6502_cpu')  # Top module marked as public
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile hierarchical FIRRTL to Verilog' do
        result = CirctHelper.validate_hierarchical_firrtl(
          described_class,
          base_dir: 'tmp/circt_test/mos6502_cpu'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'behavior Verilog compiles and runs' do
        # Use to_verilog_hierarchy to include all sub-module definitions
        verilog = described_class.to_verilog_hierarchy

        inputs = { clk: 1, rst: 1, rdy: 1, irq: 1, nmi: 1, data_in: 8 }
        outputs = {
          addr: 16, data_out: 8, rw: 1, sync: 1,
          reg_a: 8, reg_x: 8, reg_y: 8, reg_sp: 8, reg_pc: 16, reg_p: 8,
          opcode: 8, state: 8, halted: 1, cycle_count: 32
        }

        # CPU is a complex hierarchical component - verify compilation
        vectors = [
          { inputs: { clk: 0, rst: 1, rdy: 1, irq: 1, nmi: 1, data_in: 0 } },
          { inputs: { clk: 1, rst: 1, rdy: 1, irq: 1, nmi: 1, data_in: 0 } },
          { inputs: { clk: 0, rst: 0, rdy: 1, irq: 1, nmi: 1, data_in: 0 } },
          { inputs: { clk: 1, rst: 0, rdy: 1, irq: 1, nmi: 1, data_in: 0 } }
        ]

        result = NetlistHelper.run_behavior_simulation(
          verilog,
          module_name: 'mos6502_cpu',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/mos6502_cpu',
          has_clock: true
        )
        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { described_class.new('mos6502_cpu') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'mos6502_cpu') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mos6502_cpu.clk', 'mos6502_cpu.rst')
      expect(ir.inputs.keys).to include('mos6502_cpu.data_in')
      expect(ir.outputs.keys).to include('mos6502_cpu.addr', 'mos6502_cpu.data_out')
    end

    it 'generates complex netlist with gates and DFFs' do
      # CPU is a complex hierarchical component
      expect(ir.gates.length).to be > 100
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module mos6502_cpu')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'compiles and simulates structure Verilog' do
        # CPU is a complex hierarchical component - verify compilation
        vectors = [
          { inputs: { clk: 0, rst: 1, rdy: 1, irq: 1, nmi: 1, data_in: 0 } },
          { inputs: { clk: 1, rst: 1, rdy: 1, irq: 1, nmi: 1, data_in: 0 } },
          { inputs: { clk: 0, rst: 0, rdy: 1, irq: 1, nmi: 1, data_in: 0 } }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/mos6502_cpu')
        expect(result[:success]).to be(true), result[:error]
      end
    end
  end
end
