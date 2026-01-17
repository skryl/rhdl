require 'spec_helper'

RSpec.describe RHDL::HDL::AddSub do
  describe 'simulation' do
    it 'performs addition when sub=0' do
      addsub = RHDL::HDL::AddSub.new(nil, width: 8)

      addsub.set_input(:a, 100)
      addsub.set_input(:b, 50)
      addsub.set_input(:sub, 0)
      addsub.propagate
      expect(addsub.get_output(:result)).to eq(150)
    end

    it 'performs subtraction when sub=1' do
      addsub = RHDL::HDL::AddSub.new(nil, width: 8)

      addsub.set_input(:a, 100)
      addsub.set_input(:b, 50)
      addsub.set_input(:sub, 1)
      addsub.propagate
      expect(addsub.get_output(:result)).to eq(50)
    end
  end

  # Note: AddSub uses manual propagate logic
  # Synthesis tests are omitted since no behavior block is defined
end
