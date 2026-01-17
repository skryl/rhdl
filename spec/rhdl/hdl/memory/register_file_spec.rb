require 'spec_helper'

RSpec.describe RHDL::HDL::RegisterFile do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:regfile) { RHDL::HDL::RegisterFile.new }

  before do
    regfile.set_input(:we, 0)
  end

  describe 'simulation' do
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

  describe 'synthesis' do
    it 'has memory DSL defined' do
      expect(RHDL::HDL::RegisterFile.memory_dsl_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::RegisterFile.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(8)  # clk, we, waddr, wdata, raddr1, raddr2, rdata1, rdata2
      expect(ir.memories.length).to eq(1)
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::RegisterFile.to_verilog
      expect(verilog).to include('module register_file')
      expect(verilog).to include('input [7:0] wdata')
      expect(verilog).to match(/output.*\[7:0\].*rdata1/)
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::RegisterFile.new('regfile') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'regfile') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('regfile.clk', 'regfile.we', 'regfile.waddr', 'regfile.wdata', 'regfile.raddr1', 'regfile.raddr2')
      expect(ir.outputs.keys).to include('regfile.rdata1', 'regfile.rdata2')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module regfile')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input we')
      expect(verilog).to include('input [2:0] waddr')
      expect(verilog).to include('input [7:0] wdata')
      expect(verilog).to include('output [7:0] rdata1')
      expect(verilog).to include('output [7:0] rdata2')
    end
  end
end
