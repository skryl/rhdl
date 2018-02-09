require 'rspec'
require_relative 'spec_helper'

describe 'logic gates' do

  describe Rhdl::AndGate do

    it 'performs logical and' do
      expect(described_class.new(a: 0, b: 0).value).to eq 0
      expect(described_class.new(a: 0, b: 1).value).to eq 0
      expect(described_class.new(a: 1, b: 0).value).to eq 0
      expect(described_class.new(a: 1, b: 1).value).to eq 1
    end

    it 'changes outputs when inputs change' do
      a = described_class.new(a: 0, b: 0)
      expect(a.set!(a: 0, b: 0).value).to eq 0
      expect(a.set!(a: 0, b: 1).value).to eq 0
      expect(a.set!(a: 1, b: 0).value).to eq 0
      expect(a.set!(a: 1, b: 1).value).to eq 1
    end

  end

  describe Rhdl::NandGate do

    it 'performs logical nand' do
      expect(described_class.new(a: 0, b: 0).value).to eq 1
      expect(described_class.new(a: 0, b: 1).value).to eq 1
      expect(described_class.new(a: 1, b: 0).value).to eq 1
      expect(described_class.new(a: 1, b: 1).value).to eq 0
    end

    it 'changes outputs when inputs change' do
      a = described_class.new(a: 0, b: 0)
      expect(a.set!(a: 0, b: 0).value).to eq 1
      expect(a.set!(a: 0, b: 1).value).to eq 1
      expect(a.set!(a: 1, b: 0).value).to eq 1
      expect(a.set!(a: 1, b: 1).value).to eq 0
    end

  end

  describe Rhdl::OrGate do

    it 'performs logical or' do
      expect(described_class.new(a: 0, b: 0).value).to eq 0
      expect(described_class.new(a: 0, b: 1).value).to eq 1
      expect(described_class.new(a: 1, b: 0).value).to eq 1
      expect(described_class.new(a: 1, b: 1).value).to eq 1
    end

    it 'changes outputs when inputs change' do
      a = described_class.new(a: 0, b: 0)
      expect(a.set!(a: 0, b: 0).value).to eq 0
      expect(a.set!(a: 0, b: 1).value).to eq 1
      expect(a.set!(a: 1, b: 0).value).to eq 1
      expect(a.set!(a: 1, b: 1).value).to eq 1
    end

  end

  describe Rhdl::XorGate do

    it 'performs logical xor' do
      expect(described_class.new(a: 0, b: 0).value).to eq 0
      expect(described_class.new(a: 0, b: 1).value).to eq 1
      expect(described_class.new(a: 1, b: 0).value).to eq 1
      expect(described_class.new(a: 1, b: 1).value).to eq 0
    end

    it 'changes outputs when inputs change' do
      a = described_class.new(a: 0, b: 0)
      expect(a.set!(a: 0, b: 0).value).to eq 0
      expect(a.set!(a: 0, b: 1).value).to eq 1
      expect(a.set!(a: 1, b: 0).value).to eq 1
      expect(a.set!(a: 1, b: 1).value).to eq 0
    end

  end

  describe Rhdl::NorGate do

    it 'performs logical nor' do
      expect(described_class.new(a: 0, b: 0).value).to eq 1
      expect(described_class.new(a: 0, b: 1).value).to eq 0
      expect(described_class.new(a: 1, b: 0).value).to eq 0
      expect(described_class.new(a: 1, b: 1).value).to eq 0
    end

    it 'changes outputs when inputs change' do
      a = described_class.new(a: 0, b: 0)
      expect(a.set!(a: 0, b: 0).value).to eq 1
      expect(a.set!(a: 0, b: 1).value).to eq 0
      expect(a.set!(a: 1, b: 0).value).to eq 0
      expect(a.set!(a: 1, b: 1).value).to eq 0
    end

  end

  describe Rhdl::NotGate do

    it 'performs logical not' do
      expect(described_class.new(a: 0).value).to eq 1
      expect(described_class.new(a: 1).value).to eq 0
    end

    it 'changes outputs when inputs change' do
      a = described_class.new(a: 0)
      expect(a.set!(a: 0).value).to eq 1
      expect(a.set!(a: 1).value).to eq 0
    end

  end

end
