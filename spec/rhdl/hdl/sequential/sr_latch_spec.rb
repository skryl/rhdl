require 'spec_helper'

RSpec.describe RHDL::HDL::SRLatch do
  let(:latch) { RHDL::HDL::SRLatch.new }

  before do
    latch.set_input(:en, 1)
  end

  describe 'simulation' do
    it 'holds state when S=0 and R=0' do
      latch.set_input(:s, 1)
      latch.set_input(:r, 0)
      latch.propagate
      expect(latch.get_output(:q)).to eq(1)

      latch.set_input(:s, 0)
      latch.set_input(:r, 0)
      latch.propagate
      expect(latch.get_output(:q)).to eq(1)  # Hold
    end

    it 'resets when S=0 and R=1' do
      latch.set_input(:s, 1)
      latch.set_input(:r, 0)
      latch.propagate
      expect(latch.get_output(:q)).to eq(1)

      latch.set_input(:s, 0)
      latch.set_input(:r, 1)
      latch.propagate
      expect(latch.get_output(:q)).to eq(0)
      expect(latch.get_output(:qn)).to eq(1)
    end

    it 'sets when S=1 and R=0' do
      latch.set_input(:s, 1)
      latch.set_input(:r, 0)
      latch.propagate
      expect(latch.get_output(:q)).to eq(1)
      expect(latch.get_output(:qn)).to eq(0)
    end

    it 'handles invalid state S=1 R=1 by defaulting to 0' do
      latch.set_input(:s, 1)
      latch.set_input(:r, 0)
      latch.propagate
      expect(latch.get_output(:q)).to eq(1)

      latch.set_input(:s, 1)
      latch.set_input(:r, 1)
      latch.propagate
      expect(latch.get_output(:q)).to eq(0)  # Invalid defaults to 0
    end

    it 'is level-sensitive (no clock needed)' do
      latch.set_input(:s, 1)
      latch.set_input(:r, 0)
      latch.propagate
      expect(latch.get_output(:q)).to eq(1)

      # Change S immediately and propagate
      latch.set_input(:s, 0)
      latch.set_input(:r, 1)
      latch.propagate
      expect(latch.get_output(:q)).to eq(0)
    end

    it 'does not change when enable is low' do
      latch.set_input(:s, 1)
      latch.set_input(:r, 0)
      latch.propagate
      expect(latch.get_output(:q)).to eq(1)

      latch.set_input(:en, 0)
      latch.set_input(:s, 0)
      latch.set_input(:r, 1)
      latch.propagate
      expect(latch.get_output(:q)).to eq(1)  # Still 1 because enable is low
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::SRLatch.behavior_defined?).to be_truthy
    end

    # Note: Sequential components use stateful behavior which is not yet supported in synthesis context
    it 'generates valid IR', :pending do
      ir = RHDL::HDL::SRLatch.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(5)  # s, r, en, q, qn
    end

    it 'generates valid Verilog', :pending do
      verilog = RHDL::HDL::SRLatch.to_verilog
      expect(verilog).to include('module sr_latch')
      expect(verilog).to include('input s')
      expect(verilog).to include('input r')
      expect(verilog).to include('output q')
    end
  end
end
