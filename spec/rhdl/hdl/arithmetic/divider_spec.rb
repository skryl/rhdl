require 'spec_helper'

RSpec.describe RHDL::HDL::Divider do
  describe 'simulation' do
    it 'divides 8-bit numbers' do
      div = RHDL::HDL::Divider.new(nil, width: 8)

      div.set_input(:dividend, 100)
      div.set_input(:divisor, 10)
      div.propagate
      expect(div.get_output(:quotient)).to eq(10)
      expect(div.get_output(:remainder)).to eq(0)
      expect(div.get_output(:div_by_zero)).to eq(0)
    end

    it 'computes remainder' do
      div = RHDL::HDL::Divider.new(nil, width: 8)

      div.set_input(:dividend, 100)
      div.set_input(:divisor, 30)
      div.propagate
      expect(div.get_output(:quotient)).to eq(3)
      expect(div.get_output(:remainder)).to eq(10)
    end

    it 'handles division by zero' do
      div = RHDL::HDL::Divider.new(nil, width: 8)

      div.set_input(:dividend, 100)
      div.set_input(:divisor, 0)
      div.propagate
      expect(div.get_output(:div_by_zero)).to eq(1)
    end
  end

  # Note: Divider uses manual propagate logic
  # Synthesis tests are omitted since no behavior block is defined
end
