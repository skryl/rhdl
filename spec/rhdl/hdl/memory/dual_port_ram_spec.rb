require 'spec_helper'

RSpec.describe RHDL::HDL::DualPortRAM do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:dpram) { RHDL::HDL::DualPortRAM.new }

  describe 'simulation' do
    it 'writes and reads from port A' do
      # Write 0xAB via port A
      dpram.set_input(:addr_a, 0x10)
      dpram.set_input(:din_a, 0xAB)
      dpram.set_input(:we_a, 1)
      clock_cycle(dpram)

      # Read back from port A
      dpram.set_input(:we_a, 0)
      dpram.propagate
      expect(dpram.get_output(:dout_a)).to eq(0xAB)
    end

    it 'writes and reads from port B' do
      # Write 0xCD via port B
      dpram.set_input(:addr_b, 0x20)
      dpram.set_input(:din_b, 0xCD)
      dpram.set_input(:we_b, 1)
      clock_cycle(dpram)

      # Read back from port B
      dpram.set_input(:we_b, 0)
      dpram.propagate
      expect(dpram.get_output(:dout_b)).to eq(0xCD)
    end

    it 'allows simultaneous read from both ports' do
      # Write values to two addresses via port A
      dpram.set_input(:addr_a, 0x10)
      dpram.set_input(:din_a, 0x11)
      dpram.set_input(:we_a, 1)
      clock_cycle(dpram)

      dpram.set_input(:addr_a, 0x20)
      dpram.set_input(:din_a, 0x22)
      clock_cycle(dpram)

      # Read both values simultaneously
      dpram.set_input(:we_a, 0)
      dpram.set_input(:we_b, 0)
      dpram.set_input(:addr_a, 0x10)
      dpram.set_input(:addr_b, 0x20)
      dpram.propagate

      expect(dpram.get_output(:dout_a)).to eq(0x11)
      expect(dpram.get_output(:dout_b)).to eq(0x22)
    end

    it 'allows port B to read what port A wrote' do
      # Write via port A
      dpram.set_input(:addr_a, 0x30)
      dpram.set_input(:din_a, 0x55)
      dpram.set_input(:we_a, 1)
      dpram.set_input(:we_b, 0)
      clock_cycle(dpram)

      # Read via port B
      dpram.set_input(:we_a, 0)
      dpram.set_input(:addr_b, 0x30)
      dpram.propagate

      expect(dpram.get_output(:dout_b)).to eq(0x55)
    end
  end

  describe 'synthesis' do
    it 'has memory DSL defined' do
      expect(RHDL::HDL::DualPortRAM.memory_dsl_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::DualPortRAM.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(9)  # clk, we_a, we_b, addr_a, addr_b, din_a, din_b, dout_a, dout_b
      expect(ir.memories.length).to eq(1)
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::DualPortRAM.to_verilog
      expect(verilog).to include('module dual_port_ram')
      expect(verilog).to include('input [7:0] addr_a')
      expect(verilog).to match(/output.*\[7:0\].*dout_a/)
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::DualPortRAM.new('dpram') }
    let(:ir) { RHDL::Export::Structural::Lower.from_components([component], name: 'dpram') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('dpram.clk', 'dpram.we_a', 'dpram.we_b', 'dpram.addr_a', 'dpram.addr_b', 'dpram.din_a', 'dpram.din_b')
      expect(ir.outputs.keys).to include('dpram.dout_a', 'dpram.dout_b')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module dpram')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input we_a')
      expect(verilog).to include('input we_b')
      expect(verilog).to include('input [7:0] addr_a')
      expect(verilog).to include('input [7:0] addr_b')
      expect(verilog).to include('output [7:0] dout_a')
      expect(verilog).to include('output [7:0] dout_b')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavioral simulation' do
        test_vectors = []
        behavioral = RHDL::HDL::DualPortRAM.new

        test_cases = [
          { addr_a: 0, din_a: 0xAB, we_a: 1, addr_b: 0, din_b: 0, we_b: 0 },  # write A
          { addr_a: 0, din_a: 0, we_a: 0, addr_b: 0, din_b: 0, we_b: 0 },     # read both
          { addr_a: 1, din_a: 0, we_a: 0, addr_b: 1, din_b: 0x55, we_b: 1 },  # write B
          { addr_a: 1, din_a: 0, we_a: 0, addr_b: 1, din_b: 0, we_b: 0 },     # read both
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavioral.set_input(:addr_a, tc[:addr_a])
          behavioral.set_input(:din_a, tc[:din_a])
          behavioral.set_input(:we_a, tc[:we_a])
          behavioral.set_input(:addr_b, tc[:addr_b])
          behavioral.set_input(:din_b, tc[:din_b])
          behavioral.set_input(:we_b, tc[:we_b])
          behavioral.set_input(:clk, 0)
          behavioral.propagate
          behavioral.set_input(:clk, 1)
          behavioral.propagate

          test_vectors << { inputs: tc }
          expected_outputs << {
            dout_a: behavioral.get_output(:dout_a),
            dout_b: behavioral.get_output(:dout_b)
          }
        end

        base_dir = File.join('tmp', 'iverilog', 'dpram')
        result = NetlistHelper.run_structural_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:dout_a]).to eq(expected[:dout_a]),
            "Cycle #{idx}: expected dout_a=#{expected[:dout_a]}, got #{result[:results][idx][:dout_a]}"
        end
      end
    end
  end
end
