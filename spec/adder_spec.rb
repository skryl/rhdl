require 'rspec'
require_relative 'spec_helper'

describe HalfAdder do

  it 'performs addition' do
    expect(described_class.new(a: 0, b: 0).outputs).to eq(s: 0, c: 0)
    expect(described_class.new(a: 0, b: 1).outputs).to eq(s: 1, c: 0)
    expect(described_class.new(a: 1, b: 0).outputs).to eq(s: 1, c: 0)
    expect(described_class.new(a: 1, b: 1).outputs).to eq(s: 0, c: 1)
  end

  it 'changes outputs when inputs change' do
    a = described_class.new(a: 0, b: 0)
    expect(a.set!(a: 0, b: 0).outputs).to eq(s: 0, c: 0)
    expect(a.set!(a: 0, b: 1).outputs).to eq(s: 1, c: 0)
    expect(a.set!(a: 1, b: 0).outputs).to eq(s: 1, c: 0)
    expect(a.set!(a: 1, b: 1).outputs).to eq(s: 0, c: 1)
  end

end


describe FullAdder do

  let(:add) { described_class.new }

  it 'performs addition' do
    expect(described_class.new(a: 0, b: 0, cin: 0).outputs).to eq(s: 0, cout: 0)
    expect(described_class.new(a: 0, b: 1, cin: 0).outputs).to eq(s: 1, cout: 0)
    expect(described_class.new(a: 1, b: 0, cin: 0).outputs).to eq(s: 1, cout: 0)
    expect(described_class.new(a: 1, b: 1, cin: 0).outputs).to eq(s: 0, cout: 1)
    expect(described_class.new(a: 0, b: 0, cin: 1).outputs).to eq(s: 1, cout: 0)
    expect(described_class.new(a: 0, b: 1, cin: 1).outputs).to eq(s: 0, cout: 1)
    expect(described_class.new(a: 1, b: 0, cin: 1).outputs).to eq(s: 0, cout: 1)
    expect(described_class.new(a: 1, b: 1, cin: 1).outputs).to eq(s: 1, cout: 1)
  end

end
