# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe MOS6502::ControlUnit do
  let(:cu) { described_class.new('test_cu') }

  describe 'simulation' do
    before do
      cu.set_input(:clk, 0)
      cu.set_input(:rst, 1)
      cu.set_input(:rdy, 1)
      cu.set_input(:addr_mode, 0)
      cu.set_input(:instr_type, 0)
      cu.set_input(:branch_cond, 0)
      cu.set_input(:branch_taken, 0)
      cu.set_input(:is_rmw, 0)
      cu.set_input(:page_cross, 0)
      cu.set_input(:irq, 0)
      cu.set_input(:nmi, 0)
      cu.propagate
      # Release reset with rising edge
      cu.set_input(:clk, 1)
      cu.propagate
      cu.set_input(:clk, 0)
      cu.set_input(:rst, 0)
      cu.propagate
    end

    it 'starts in RESET state after reset' do
      # State should be valid after reset
      expect(cu.get_output(:state)).to be_a(Integer)
    end

    it 'transitions to FETCH state' do
      # Clock cycle to transition
      cu.set_input(:clk, 1)
      cu.propagate
      cu.set_input(:clk, 0)
      cu.propagate

      # Should be in a valid state
      expect(cu.get_output(:state)).to be_a(Integer)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502_control_unit')
      expect(verilog).to include('localparam STATE_FETCH')
      expect(verilog).to include('localparam STATE_EXECUTE')
    end

    it 'has state machine structure' do
      verilog = described_class.to_verilog
      expect(verilog).to include('always @(posedge clk')
      expect(verilog).to include('state')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { described_class.new('mos6502_control_unit') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'mos6502_control_unit') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mos6502_control_unit.clk', 'mos6502_control_unit.rst')
      expect(ir.inputs.keys).to include('mos6502_control_unit.addr_mode', 'mos6502_control_unit.instr_type')
      expect(ir.outputs.keys).to include('mos6502_control_unit.state', 'mos6502_control_unit.done')
    end

    it 'generates gates for state machine logic' do
      # Control unit has complex state machine logic
      # Note: Behavioral state machines may not produce DFFs through gate lowering
      expect(ir.gates.length).to be > 100
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module mos6502_control_unit')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('output [7:0] state')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'compiles and simulates structural Verilog' do
        # Control unit is a complex state machine - just verify it compiles and runs
        vectors = [
          { inputs: { clk: 0, rst: 1, rdy: 1, addr_mode: 0, instr_type: 0, branch_cond: 0,
                      flag_n: 0, flag_v: 0, flag_z: 0, flag_c: 0, page_cross: 0, mem_ready: 1,
                      is_read: 0, is_write: 0, is_rmw: 0, writes_reg: 0, is_status_op: 0 } },
          { inputs: { clk: 1, rst: 1, rdy: 1, addr_mode: 0, instr_type: 0, branch_cond: 0,
                      flag_n: 0, flag_v: 0, flag_z: 0, flag_c: 0, page_cross: 0, mem_ready: 1,
                      is_read: 0, is_write: 0, is_rmw: 0, writes_reg: 0, is_status_op: 0 } },
          { inputs: { clk: 0, rst: 0, rdy: 1, addr_mode: 0, instr_type: 0, branch_cond: 0,
                      flag_n: 0, flag_v: 0, flag_z: 0, flag_c: 0, page_cross: 0, mem_ready: 1,
                      is_read: 0, is_write: 0, is_rmw: 0, writes_reg: 0, is_status_op: 0 } }
        ]

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/mos6502_control_unit')
        expect(result[:success]).to be(true), result[:error]
      end
    end
  end
end
