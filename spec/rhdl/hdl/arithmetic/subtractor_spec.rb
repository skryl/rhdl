require 'spec_helper'

RSpec.describe RHDL::HDL::Subtractor do
  describe 'simulation' do
    it 'subtracts 8-bit numbers' do
      sub = RHDL::HDL::Subtractor.new(nil, width: 8)

      # 100 - 50 = 50
      sub.set_input(:a, 100)
      sub.set_input(:b, 50)
      sub.set_input(:bin, 0)
      sub.propagate
      expect(sub.get_output(:diff)).to eq(50)
      expect(sub.get_output(:bout)).to eq(0)
    end

    it 'handles borrow' do
      sub = RHDL::HDL::Subtractor.new(nil, width: 8)

      # 50 - 100 = -50 (with borrow)
      sub.set_input(:a, 50)
      sub.set_input(:b, 100)
      sub.set_input(:bin, 0)
      sub.propagate
      expect(sub.get_output(:diff)).to eq(206)  # 256 - 50
      expect(sub.get_output(:bout)).to eq(1)
    end
  end

  # Note: Subtractor uses manual propagate logic
  # Synthesis tests are omitted since no behavior block is defined
end
