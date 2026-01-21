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

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::RegisterFile.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit register_file')
      expect(firrtl).to include('input clk')
      expect(firrtl).to include('input wdata')
      expect(firrtl).to include('output rdata1')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile FIRRTL to Verilog' do
        result = CirctHelper.validate_firrtl_syntax(
          RHDL::HDL::RegisterFile,
          base_dir: 'tmp/circt_test/register_file'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::RegisterFile.new('regfile') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'regfile') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('regfile.clk', 'regfile.we', 'regfile.waddr', 'regfile.wdata', 'regfile.raddr1', 'regfile.raddr2')
      expect(ir.outputs.keys).to include('regfile.rdata1', 'regfile.rdata2')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module regfile')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input we')
      expect(verilog).to include('input [2:0] waddr')
      expect(verilog).to include('input [7:0] wdata')
      expect(verilog).to include('output [7:0] rdata1')
      expect(verilog).to include('output [7:0] rdata2')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavior simulation' do
        test_vectors = []
        behavior = RHDL::HDL::RegisterFile.new
        behavior.set_input(:we, 0)

        test_cases = [
          { waddr: 1, wdata: 0xAA, we: 1, raddr1: 1, raddr2: 0 },  # write reg1
          { waddr: 2, wdata: 0xBB, we: 1, raddr1: 1, raddr2: 2 },  # write reg2
          { waddr: 0, wdata: 0, we: 0, raddr1: 1, raddr2: 2 },     # read both
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavior.set_input(:waddr, tc[:waddr])
          behavior.set_input(:wdata, tc[:wdata])
          behavior.set_input(:we, tc[:we])
          behavior.set_input(:raddr1, tc[:raddr1])
          behavior.set_input(:raddr2, tc[:raddr2])
          behavior.set_input(:clk, 0)
          behavior.propagate
          behavior.set_input(:clk, 1)
          behavior.propagate

          test_vectors << { inputs: tc }
          expected_outputs << {
            rdata1: behavior.get_output(:rdata1),
            rdata2: behavior.get_output(:rdata2)
          }
        end

        base_dir = File.join('tmp', 'iverilog', 'regfile')
        result = NetlistHelper.run_structure_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:rdata1]).to eq(expected[:rdata1]),
            "Cycle #{idx}: expected rdata1=#{expected[:rdata1]}, got #{result[:results][idx][:rdata1]}"
        end
      end
    end

    describe 'simulator comparison' do
      it 'all simulators produce matching results', pending: 'Memory components have complex synthesis requirements' do
        test_cases = [
          { waddr: 1, wdata: 0xAA, we: 1, raddr1: 1, raddr2: 0 },
          { waddr: 2, wdata: 0xBB, we: 1, raddr1: 1, raddr2: 2 },
          { waddr: 0, wdata: 0, we: 0, raddr1: 1, raddr2: 2 }
        ]

        NetlistHelper.compare_and_validate!(
          RHDL::HDL::RegisterFile,
          'register_file',
          test_cases,
          base_dir: 'tmp/netlist_comparison/register_file',
          has_clock: true
        )
      end
    end
  end
end
