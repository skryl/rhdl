require 'spec_helper'

RSpec.describe RHDL::HDL::FIFO do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:fifo) { RHDL::HDL::FIFO.new(nil, data_width: 8, depth: 4) }

  before do
    fifo.set_input(:rst, 0)
    fifo.set_input(:wr_en, 0)
    fifo.set_input(:rd_en, 0)
    fifo.propagate  # Initialize outputs
  end

  describe 'simulation' do
    it 'maintains FIFO order' do
      # Write 1, 2, 3
      [1, 2, 3].each do |val|
        fifo.set_input(:din, val)
        fifo.set_input(:wr_en, 1)
        clock_cycle(fifo)
        fifo.set_input(:wr_en, 0)
      end

      # Read should get 1, 2, 3 in order
      [1, 2, 3].each do |expected|
        expect(fifo.get_output(:dout)).to eq(expected)
        fifo.set_input(:rd_en, 1)
        clock_cycle(fifo)
        fifo.set_input(:rd_en, 0)
      end
    end

    it 'indicates empty and full states' do
      expect(fifo.get_output(:empty)).to eq(1)
      expect(fifo.get_output(:full)).to eq(0)
      expect(fifo.get_output(:count)).to eq(0)

      # Fill FIFO
      4.times do |i|
        fifo.set_input(:din, i)
        fifo.set_input(:wr_en, 1)
        clock_cycle(fifo)
        fifo.set_input(:wr_en, 0)
      end

      expect(fifo.get_output(:empty)).to eq(0)
      expect(fifo.get_output(:full)).to eq(1)
      expect(fifo.get_output(:count)).to eq(4)
    end

    it 'resets to empty state' do
      # Write something
      fifo.set_input(:din, 0xFF)
      fifo.set_input(:wr_en, 1)
      clock_cycle(fifo)
      fifo.set_input(:wr_en, 0)

      expect(fifo.get_output(:empty)).to eq(0)

      # Reset
      fifo.set_input(:rst, 1)
      clock_cycle(fifo)

      expect(fifo.get_output(:empty)).to eq(1)
      expect(fifo.get_output(:count)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::FIFO.behavior_defined?).to be_truthy
    end

    # Note: Memory components use internal state arrays which are not yet supported in synthesis context
    it 'generates valid IR', :pending do
      ir = RHDL::HDL::FIFO.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(9)  # clk, rst, wr_en, rd_en, din, dout, empty, full, count
    end

    it 'generates valid Verilog', :pending do
      verilog = RHDL::HDL::FIFO.to_verilog
      expect(verilog).to include('module fifo')
      expect(verilog).to include('input [7:0] din')
      expect(verilog).to include('output [7:0] dout')
    end
  end
end
