require_relative '../spec_helper'
require_relative '../../../../examples/ao486/hdl/harness'

RSpec.describe RHDL::Examples::AO486::Harness do
  let(:harness) { RHDL::Examples::AO486::Harness.new }

  describe '#initialize' do
    it 'creates a harness instance' do
      expect(harness).to be_a(RHDL::Examples::AO486::Harness)
    end
  end

  describe '#reset' do
    it 'responds to reset' do
      expect(harness).to respond_to(:reset)
    end

    it 'can be called without error' do
      expect { harness.reset }.not_to raise_error
    end
  end

  describe 'memory interface' do
    it 'responds to read_mem and write_mem' do
      expect(harness).to respond_to(:read_mem)
      expect(harness).to respond_to(:write_mem)
    end

    it 'can write and read back memory' do
      harness.write_mem(0x1000, 0x42)
      expect(harness.read_mem(0x1000)).to eq(0x42)
    end

    it 'supports 32-bit addresses' do
      harness.write_mem(0xFFFF_0000, 0xAB)
      expect(harness.read_mem(0xFFFF_0000)).to eq(0xAB)
    end
  end

  describe 'register accessors' do
    it 'provides EIP accessor' do
      expect(harness).to respond_to(:eip)
    end
  end

  describe 'state inspection' do
    it 'responds to state' do
      expect(harness).to respond_to(:state)
    end
  end
end
