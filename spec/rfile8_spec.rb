require 'rspec'
require_relative 'spec_helper'

describe RFile32 do

  let(:rfile) { described_class.new }

  describe 'zero' do

    it 'zeroes out all registers' do
      expect(rfile.set!(src_addr_a: '000', src_addr_b: '001').outputs).to eq(src_a: 1.sext(32), src_b: 1.sext(32))
      expect(rfile.set!(src_addr_a: '010', src_addr_b: '011').outputs).to eq(src_a: 1.sext(32), src_b: 1.sext(32))
      expect(rfile.set!(src_addr_a: '100', src_addr_b: '101').outputs).to eq(src_a: 1.sext(32), src_b: 1.sext(32))
      expect(rfile.set!(src_addr_a: '110', src_addr_b: '111').outputs).to eq(src_a: 1.sext(32), src_b: 1.sext(32))

      (0..7).each do |idx|
        rfile.set!(data: '00000000', enable: 1, dest_addr: idx.to_b(3), clk: 0)
        rfile.set!(data: '00000000', enable: 1, dest_addr: idx.to_b(3), clk: 1)
        rfile.set!(data: '00000000', enable: 1, dest_addr: idx.to_b(3), clk: 0)
      end

      expect(rfile.set!(src_addr_a: '000', src_addr_b: '001').outputs).to eq(src_a: '00000000', src_b: '00000000')
      expect(rfile.set!(src_addr_a: '010', src_addr_b: '011').outputs).to eq(src_a: '00000000', src_b: '00000000')
      expect(rfile.set!(src_addr_a: '100', src_addr_b: '101').outputs).to eq(src_a: '00000000', src_b: '00000000')
      expect(rfile.set!(src_addr_a: '110', src_addr_b: '111').outputs).to eq(src_a: '00000000', src_b: '00000000')
    end

  end

  describe 'random' do

    it 'fills registers with random data' do
      values = {}
      (0..7).each do |idx|
        values[idx] = rand(256).to_b(8)
        rfile.set!(data: values[idx], dest_addr: idx.to_b(3), enable: 1, clk: 0)
        rfile.set!(data: values[idx], dest_addr: idx.to_b(3), enable: 1, clk: 1)
        rfile.set!(data: values[idx], dest_addr: idx.to_b(3), enable: 1, clk: 0)
      end

      (0..7).each do |idx|
        rfile.set!(src_addr_a: idx.to_b(3), src_addr_b: idx.to_b(3))
        expect(rfile.outputs).to eq(src_a: values[idx], src_b: values[idx])
      end

    end

  end

  describe 'enable bit' do

    it 'does not write if enable bit is not set' do
      values = {}
      (0..7).each do |idx|
        values[idx] = rand(256).to_b(8)
        rfile.set!(data: values[idx], dest_addr: idx.to_b(3), enable: 0, clk: 0)
        rfile.set!(data: values[idx], dest_addr: idx.to_b(3), enable: 0, clk: 1)
        rfile.set!(data: values[idx], dest_addr: idx.to_b(3), enable: 0, clk: 0)
      end

      (0..7).each do |idx|
        rfile.set!(src_addr_a: idx.to_b(3), src_addr_b: idx.to_b(3))
        expect(rfile.outputs).to eq(src_a: '11111111', src_b: '11111111')
      end
    end
  end

end
