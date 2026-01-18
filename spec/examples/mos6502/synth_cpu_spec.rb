# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../../../examples/mos6502/hdl/cpu'

RSpec.describe MOS6502::CPU do
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

    it 'instantiates datapath and memory' do
      instance_names = described_class._instance_defs.map { |i| i[:name] }
      expect(instance_names).to include(:datapath, :memory)
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
      expect(verilog).to include('datapath (')
      expect(verilog).to include('memory (')
    end

    it 'generates hierarchical Verilog with all submodules' do
      verilog = described_class.to_verilog_hierarchy
      # Should include all submodule definitions
      expect(verilog).to include('module mos6502_datapath')
      expect(verilog).to include('module mos6502_memory')
      expect(verilog).to include('module mos6502_registers')
      expect(verilog).to include('module mos6502_alu')
      expect(verilog).to include('module mos6502_control_unit')
      expect(verilog).to include('module mos6502_cpu')  # Top module last
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'behavior Verilog compiles and runs' do
        # Use to_verilog_hierarchy to include all sub-module definitions
        verilog = described_class.to_verilog_hierarchy

        inputs = { clk: 1, rst: 1, rdy: 1, irq: 1, nmi: 1 }
        outputs = {
          addr: 16, data_out: 8, rw: 1, sync: 1,
          reg_a: 8, reg_x: 8, reg_y: 8, reg_sp: 8, reg_pc: 16, reg_p: 8,
          opcode: 8, state: 8, halted: 1, cycle_count: 32
        }

        # CPU is a complex hierarchical component - verify compilation
        vectors = [
          { inputs: { clk: 0, rst: 1, rdy: 1, irq: 1, nmi: 1 } },
          { inputs: { clk: 1, rst: 1, rdy: 1, irq: 1, nmi: 1 } },
          { inputs: { clk: 0, rst: 0, rdy: 1, irq: 1, nmi: 1 } },
          { inputs: { clk: 1, rst: 0, rdy: 1, irq: 1, nmi: 1 } }
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
end
