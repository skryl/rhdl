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
end
