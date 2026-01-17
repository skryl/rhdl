require 'spec_helper'

RSpec.describe RHDL::HDL::Comparator do
  let(:cmp) { RHDL::HDL::Comparator.new(nil, width: 8) }

  describe 'simulation' do
    it 'compares equal values' do
      cmp.set_input(:a, 42)
      cmp.set_input(:b, 42)
      cmp.set_input(:signed, 0)
      cmp.propagate

      expect(cmp.get_output(:eq)).to eq(1)
      expect(cmp.get_output(:gt)).to eq(0)
      expect(cmp.get_output(:lt)).to eq(0)
    end

    it 'compares greater than' do
      cmp.set_input(:a, 50)
      cmp.set_input(:b, 30)
      cmp.set_input(:signed, 0)
      cmp.propagate

      expect(cmp.get_output(:eq)).to eq(0)
      expect(cmp.get_output(:gt)).to eq(1)
      expect(cmp.get_output(:lt)).to eq(0)
    end

    it 'compares less than' do
      cmp.set_input(:a, 20)
      cmp.set_input(:b, 40)
      cmp.set_input(:signed, 0)
      cmp.propagate

      expect(cmp.get_output(:eq)).to eq(0)
      expect(cmp.get_output(:gt)).to eq(0)
      expect(cmp.get_output(:lt)).to eq(1)
    end
  end

  # Note: Comparator uses complex signed/unsigned conditional logic
  # Synthesis tests are omitted since the behavior DSL doesn't support conditionals yet
end
