require 'spec_helper'

RSpec.describe 'HDL Sequential Components' do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  describe RHDL::HDL::DFlipFlop do
    let(:dff) { RHDL::HDL::DFlipFlop.new }

    before do
      dff.set_input(:rst, 0)
      dff.set_input(:en, 1)
    end

    it 'captures input on rising edge' do
      dff.set_input(:d, 1)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(1)
      expect(dff.get_output(:qn)).to eq(0)
    end

    it 'holds value when enable is low' do
      dff.set_input(:d, 1)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(1)

      dff.set_input(:en, 0)
      dff.set_input(:d, 0)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(1)  # Still 1
    end

    it 'resets on reset signal' do
      dff.set_input(:d, 1)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(1)

      dff.set_input(:rst, 1)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(0)
    end
  end

  describe RHDL::HDL::TFlipFlop do
    let(:tff) { RHDL::HDL::TFlipFlop.new }

    before do
      tff.set_input(:rst, 0)
      tff.set_input(:en, 1)
    end

    it 'toggles on T=1' do
      tff.set_input(:t, 1)

      clock_cycle(tff)
      expect(tff.get_output(:q)).to eq(1)

      clock_cycle(tff)
      expect(tff.get_output(:q)).to eq(0)

      clock_cycle(tff)
      expect(tff.get_output(:q)).to eq(1)
    end

    it 'holds on T=0' do
      tff.set_input(:t, 1)
      clock_cycle(tff)
      expect(tff.get_output(:q)).to eq(1)

      tff.set_input(:t, 0)
      clock_cycle(tff)
      expect(tff.get_output(:q)).to eq(1)
    end
  end

  describe RHDL::HDL::Register do
    let(:reg) { RHDL::HDL::Register.new(nil, width: 8) }

    before do
      reg.set_input(:rst, 0)
      reg.set_input(:en, 1)
    end

    it 'stores 8-bit values' do
      reg.set_input(:d, 0xAB)
      clock_cycle(reg)
      expect(reg.get_output(:q)).to eq(0xAB)
    end

    it 'resets to zero' do
      reg.set_input(:d, 0xFF)
      clock_cycle(reg)
      expect(reg.get_output(:q)).to eq(0xFF)

      reg.set_input(:rst, 1)
      clock_cycle(reg)
      expect(reg.get_output(:q)).to eq(0)
    end
  end

  describe RHDL::HDL::Counter do
    let(:counter) { RHDL::HDL::Counter.new(nil, width: 4) }

    before do
      counter.set_input(:rst, 0)
      counter.set_input(:en, 1)
      counter.set_input(:up, 1)
      counter.set_input(:load, 0)
    end

    it 'counts up' do
      expect(counter.get_output(:q)).to eq(0)

      clock_cycle(counter)
      expect(counter.get_output(:q)).to eq(1)

      clock_cycle(counter)
      expect(counter.get_output(:q)).to eq(2)
    end

    it 'counts down' do
      counter.set_input(:load, 1)
      counter.set_input(:d, 5)
      clock_cycle(counter)
      counter.set_input(:load, 0)

      counter.set_input(:up, 0)
      clock_cycle(counter)
      expect(counter.get_output(:q)).to eq(4)
    end

    it 'wraps around' do
      counter.set_input(:load, 1)
      counter.set_input(:d, 15)
      clock_cycle(counter)
      counter.set_input(:load, 0)

      clock_cycle(counter)
      expect(counter.get_output(:q)).to eq(0)
      expect(counter.get_output(:tc)).to eq(1)
    end
  end

  describe RHDL::HDL::ShiftRegister do
    let(:sr) { RHDL::HDL::ShiftRegister.new(nil, width: 8) }

    before do
      sr.set_input(:rst, 0)
      sr.set_input(:en, 1)
      sr.set_input(:load, 0)
      sr.set_input(:dir, 1)  # Shift left
      sr.set_input(:d_in, 0)
    end

    it 'shifts left' do
      sr.set_input(:load, 1)
      sr.set_input(:d, 0b00001111)
      clock_cycle(sr)
      sr.set_input(:load, 0)

      clock_cycle(sr)
      expect(sr.get_output(:q)).to eq(0b00011110)

      clock_cycle(sr)
      expect(sr.get_output(:q)).to eq(0b00111100)
    end

    it 'shifts right' do
      sr.set_input(:load, 1)
      sr.set_input(:d, 0b11110000)
      clock_cycle(sr)
      sr.set_input(:load, 0)

      sr.set_input(:dir, 0)  # Shift right
      clock_cycle(sr)
      expect(sr.get_output(:q)).to eq(0b01111000)
    end
  end

  describe RHDL::HDL::ProgramCounter do
    let(:pc) { RHDL::HDL::ProgramCounter.new(nil, width: 16) }

    before do
      pc.set_input(:rst, 0)
      pc.set_input(:en, 1)
      pc.set_input(:load, 0)
      pc.set_input(:inc, 1)
    end

    it 'increments by 1 by default' do
      expect(pc.get_output(:q)).to eq(0)

      clock_cycle(pc)
      expect(pc.get_output(:q)).to eq(1)

      clock_cycle(pc)
      expect(pc.get_output(:q)).to eq(2)
    end

    it 'loads a new address' do
      pc.set_input(:load, 1)
      pc.set_input(:d, 0x1000)
      clock_cycle(pc)

      expect(pc.get_output(:q)).to eq(0x1000)
    end

    it 'increments by variable amount' do
      pc.set_input(:inc, 3)
      clock_cycle(pc)
      expect(pc.get_output(:q)).to eq(3)
    end
  end
end
