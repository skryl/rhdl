require 'spec_helper'

RSpec.describe 'HDL Memory Components' do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  describe RHDL::HDL::RAM do
    let(:ram) { RHDL::HDL::RAM.new(nil, data_width: 8, addr_width: 8) }

    it 'writes and reads data' do
      # Write 0xAB to address 0x10
      ram.set_input(:addr, 0x10)
      ram.set_input(:din, 0xAB)
      ram.set_input(:we, 1)
      clock_cycle(ram)

      # Read back
      ram.set_input(:we, 0)
      ram.propagate
      expect(ram.get_output(:dout)).to eq(0xAB)
    end

    it 'maintains data when not writing' do
      # Write initial value
      ram.set_input(:addr, 0x20)
      ram.set_input(:din, 0x42)
      ram.set_input(:we, 1)
      clock_cycle(ram)

      # Change din but keep we=0
      ram.set_input(:we, 0)
      ram.set_input(:din, 0xFF)
      clock_cycle(ram)

      # Value should still be 0x42
      expect(ram.get_output(:dout)).to eq(0x42)
    end

    it 'supports direct memory access' do
      ram.write_mem(0x50, 0xCD)
      expect(ram.read_mem(0x50)).to eq(0xCD)
    end

    it 'loads program data' do
      program = [0xA0, 0x42, 0xF0]
      ram.load_program(program, 0x100)

      expect(ram.read_mem(0x100)).to eq(0xA0)
      expect(ram.read_mem(0x101)).to eq(0x42)
      expect(ram.read_mem(0x102)).to eq(0xF0)
    end

    it 'reads different addresses' do
      ram.write_mem(0x00, 0x11)
      ram.write_mem(0x01, 0x22)
      ram.write_mem(0x02, 0x33)

      ram.set_input(:we, 0)

      ram.set_input(:addr, 0x00)
      ram.propagate
      expect(ram.get_output(:dout)).to eq(0x11)

      ram.set_input(:addr, 0x01)
      ram.propagate
      expect(ram.get_output(:dout)).to eq(0x22)

      ram.set_input(:addr, 0x02)
      ram.propagate
      expect(ram.get_output(:dout)).to eq(0x33)
    end
  end

  describe RHDL::HDL::ROM do
    let(:contents) { [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77] }
    let(:rom) { RHDL::HDL::ROM.new(nil, data_width: 8, addr_width: 8, contents: contents) }

    it 'reads stored data' do
      rom.set_input(:en, 1)
      rom.set_input(:addr, 0)
      rom.propagate
      expect(rom.get_output(:dout)).to eq(0x00)

      rom.set_input(:addr, 3)
      rom.propagate
      expect(rom.get_output(:dout)).to eq(0x33)

      rom.set_input(:addr, 7)
      rom.propagate
      expect(rom.get_output(:dout)).to eq(0x77)
    end

    it 'outputs zero when disabled' do
      rom.set_input(:en, 0)
      rom.set_input(:addr, 3)
      rom.propagate
      expect(rom.get_output(:dout)).to eq(0)
    end

    it 'returns zero for uninitialized addresses' do
      rom.set_input(:en, 1)
      rom.set_input(:addr, 100)
      rom.propagate
      expect(rom.get_output(:dout)).to eq(0)
    end
  end

  describe RHDL::HDL::RegisterFile do
    let(:regfile) { RHDL::HDL::RegisterFile.new(nil, data_width: 8, num_regs: 8) }

    before do
      regfile.set_input(:we, 0)
    end

    it 'writes and reads registers' do
      # Write 0x42 to register 3
      regfile.set_input(:waddr, 3)
      regfile.set_input(:wdata, 0x42)
      regfile.set_input(:we, 1)
      clock_cycle(regfile)

      # Read from register 3
      regfile.set_input(:we, 0)
      regfile.set_input(:raddr1, 3)
      regfile.propagate
      expect(regfile.get_output(:rdata1)).to eq(0x42)
    end

    it 'supports dual read ports' do
      # Write to two registers
      regfile.set_input(:waddr, 1)
      regfile.set_input(:wdata, 0xAA)
      regfile.set_input(:we, 1)
      clock_cycle(regfile)

      regfile.set_input(:waddr, 2)
      regfile.set_input(:wdata, 0xBB)
      clock_cycle(regfile)

      # Read both simultaneously
      regfile.set_input(:we, 0)
      regfile.set_input(:raddr1, 1)
      regfile.set_input(:raddr2, 2)
      regfile.propagate

      expect(regfile.get_output(:rdata1)).to eq(0xAA)
      expect(regfile.get_output(:rdata2)).to eq(0xBB)
    end
  end

  describe RHDL::HDL::Stack do
    let(:stack) { RHDL::HDL::Stack.new(nil, data_width: 8, depth: 4) }

    before do
      stack.set_input(:rst, 0)
      stack.set_input(:push, 0)
      stack.set_input(:pop, 0)
      stack.propagate  # Initialize outputs
    end

    it 'pushes and pops values' do
      # Push 0x11
      stack.set_input(:din, 0x11)
      stack.set_input(:push, 1)
      clock_cycle(stack)

      stack.set_input(:push, 0)
      expect(stack.get_output(:dout)).to eq(0x11)
      expect(stack.get_output(:empty)).to eq(0)

      # Push 0x22
      stack.set_input(:din, 0x22)
      stack.set_input(:push, 1)
      clock_cycle(stack)

      stack.set_input(:push, 0)
      expect(stack.get_output(:dout)).to eq(0x22)

      # Pop - should get 0x22
      stack.set_input(:pop, 1)
      clock_cycle(stack)

      stack.set_input(:pop, 0)
      expect(stack.get_output(:dout)).to eq(0x11)
    end

    it 'indicates empty and full' do
      expect(stack.get_output(:empty)).to eq(1)
      expect(stack.get_output(:full)).to eq(0)

      # Fill the stack
      4.times do |i|
        stack.set_input(:din, i + 1)
        stack.set_input(:push, 1)
        clock_cycle(stack)
        stack.set_input(:push, 0)
      end

      expect(stack.get_output(:empty)).to eq(0)
      expect(stack.get_output(:full)).to eq(1)
    end

    it 'resets correctly' do
      # Push some values
      stack.set_input(:din, 0xFF)
      stack.set_input(:push, 1)
      clock_cycle(stack)

      stack.set_input(:push, 0)
      expect(stack.get_output(:empty)).to eq(0)

      # Reset
      stack.set_input(:rst, 1)
      clock_cycle(stack)

      expect(stack.get_output(:empty)).to eq(1)
    end
  end

  describe RHDL::HDL::FIFO do
    let(:fifo) { RHDL::HDL::FIFO.new(nil, data_width: 8, depth: 4) }

    before do
      fifo.set_input(:rst, 0)
      fifo.set_input(:wr_en, 0)
      fifo.set_input(:rd_en, 0)
      fifo.propagate  # Initialize outputs
    end

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

  describe RHDL::HDL::StackPointer do
    let(:sp) { RHDL::HDL::StackPointer.new(nil, width: 8) }

    before do
      sp.set_input(:rst, 0)
      sp.set_input(:push, 0)
      sp.set_input(:pop, 0)
      sp.propagate  # Initialize outputs
    end

    it 'initializes to 0xFF' do
      expect(sp.get_output(:q)).to eq(0xFF)
      expect(sp.get_output(:empty)).to eq(1)
    end

    it 'decrements on push' do
      sp.set_input(:push, 1)
      clock_cycle(sp)
      expect(sp.get_output(:q)).to eq(0xFE)
      expect(sp.get_output(:empty)).to eq(0)
    end

    it 'increments on pop' do
      # First push
      sp.set_input(:push, 1)
      clock_cycle(sp)
      sp.set_input(:push, 0)

      # Then pop
      sp.set_input(:pop, 1)
      clock_cycle(sp)
      expect(sp.get_output(:q)).to eq(0xFF)
      expect(sp.get_output(:empty)).to eq(1)
    end

    it 'indicates full when SP reaches 0' do
      # Set SP near bottom
      sp.instance_variable_set(:@state, 1)
      sp.propagate

      sp.set_input(:push, 1)
      clock_cycle(sp)

      expect(sp.get_output(:q)).to eq(0)
      expect(sp.get_output(:full)).to eq(1)
    end

    it 'resets to 0xFF' do
      sp.set_input(:push, 1)
      clock_cycle(sp)
      sp.set_input(:push, 0)

      sp.set_input(:rst, 1)
      clock_cycle(sp)

      expect(sp.get_output(:q)).to eq(0xFF)
      expect(sp.get_output(:empty)).to eq(1)
    end
  end
end
