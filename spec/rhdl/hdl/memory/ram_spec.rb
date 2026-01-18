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

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::RAM.new('ram') }
    let(:ir) { RHDL::Export::Structural::Lower.from_components([component], name: 'ram') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('ram.clk', 'ram.we', 'ram.addr', 'ram.din')
      expect(ir.outputs.keys).to include('ram.dout')
      # RAM uses memory cells, expect significant gate count for address decoding
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module ram')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input we')
      expect(verilog).to include('input [7:0] addr')
      expect(verilog).to include('input [7:0] din')
      expect(verilog).to include('output [7:0] dout')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavioral simulation' do
        test_vectors = []
        behavioral = RHDL::HDL::RAM.new

        test_cases = [
          { addr: 0, din: 0xAB, we: 1 },  # write 0xAB to addr 0
          { addr: 0, din: 0, we: 0 },      # read from addr 0
          { addr: 1, din: 0x55, we: 1 },  # write 0x55 to addr 1
          { addr: 1, din: 0, we: 0 },      # read from addr 1
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavioral.set_input(:addr, tc[:addr])
          behavioral.set_input(:din, tc[:din])
          behavioral.set_input(:we, tc[:we])
          behavioral.set_input(:clk, 0)
          behavioral.propagate
          behavioral.set_input(:clk, 1)
          behavioral.propagate

          test_vectors << { inputs: tc }
          expected_outputs << { dout: behavioral.get_output(:dout) }
        end

        base_dir = File.join('tmp', 'iverilog', 'ram')
        result = NetlistHelper.run_structural_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:dout]).to eq(expected[:dout]),
            "Cycle #{idx}: expected dout=#{expected[:dout]}, got #{result[:results][idx][:dout]}"
        end
      end
    end
  end
end
