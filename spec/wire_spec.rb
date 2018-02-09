require 'rspec'
require_relative 'spec_helper'

describe Rhdl::Wire do

  it 'holds a value' do
    expect(described_class.new(0)).to eq 0
    expect(described_class.new(1)).to eq 1
  end

end
