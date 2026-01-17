require 'spec_helper'

RSpec.describe RHDL::HDL::IncDec do
  describe 'simulation' do
    it 'increments when inc=1' do
      incdec = RHDL::HDL::IncDec.new(nil, width: 8)

      incdec.set_input(:a, 100)
      incdec.set_input(:inc, 1)
      incdec.propagate
      expect(incdec.get_output(:result)).to eq(101)
    end

    it 'decrements when inc=0' do
      incdec = RHDL::HDL::IncDec.new(nil, width: 8)

      incdec.set_input(:a, 100)
      incdec.set_input(:inc, 0)
      incdec.propagate
      expect(incdec.get_output(:result)).to eq(99)
    end

    it 'handles overflow on increment' do
      incdec = RHDL::HDL::IncDec.new(nil, width: 8)

      incdec.set_input(:a, 255)
      incdec.set_input(:inc, 1)
      incdec.propagate
      expect(incdec.get_output(:result)).to eq(0)
      expect(incdec.get_output(:cout)).to eq(1)
    end

    it 'handles underflow on decrement' do
      incdec = RHDL::HDL::IncDec.new(nil, width: 8)

      incdec.set_input(:a, 0)
      incdec.set_input(:inc, 0)
      incdec.propagate
      expect(incdec.get_output(:result)).to eq(255)
      expect(incdec.get_output(:cout)).to eq(1)
    end
  end

  # Note: IncDec uses manual propagate logic
  # Synthesis tests are omitted since no behavior block is defined
end
