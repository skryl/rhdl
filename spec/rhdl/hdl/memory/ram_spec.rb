require 'spec_helper'

RSpec.describe RHDL::HDL::RAM do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:ram) { RHDL::HDL::RAM.new }

  describe 'simulation' do
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
      ram.load_program(program, 0x80)

      expect(ram.read_mem(0x80)).to eq(0xA0)
      expect(ram.read_mem(0x81)).to eq(0x42)
      expect(ram.read_mem(0x82)).to eq(0xF0)
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

  describe 'synthesis' do
    it 'has memory DSL defined' do
      expect(RHDL::HDL::RAM.memory_dsl_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::RAM.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(5)  # clk, we, addr, din, dout
      expect(ir.memories.length).to eq(1)
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::RAM.to_verilog
      expect(verilog).to include('module ram')
      expect(verilog).to include('input [7:0] addr')
      expect(verilog).to match(/output.*\[7:0\].*dout/)
      expect(verilog).to include('reg [7:0] mem')  # Memory array
    end
  end
end
