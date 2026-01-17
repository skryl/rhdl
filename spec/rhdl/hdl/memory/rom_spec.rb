require 'spec_helper'

RSpec.describe RHDL::HDL::ROM do
  let(:contents) { [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77] }
  let(:rom) { RHDL::HDL::ROM.new(nil, contents: contents) }

  describe 'simulation' do
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

  describe 'synthesis' do
    it 'has memory DSL defined' do
      expect(RHDL::HDL::ROM.memory_dsl_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::ROM.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(3)  # en, addr, dout
      expect(ir.memories.length).to eq(1)
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::ROM.to_verilog
      expect(verilog).to include('module rom')
      expect(verilog).to include('input [7:0] addr')
      expect(verilog).to match(/output.*\[7:0\].*dout/)
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::ROM.new('rom', contents: [0x00, 0x11, 0x22, 0x33]) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'rom') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('rom.addr', 'rom.en')
      expect(ir.outputs.keys).to include('rom.dout')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module rom')
      expect(verilog).to include('input [7:0] addr')
      expect(verilog).to include('input en')
      expect(verilog).to include('output [7:0] dout')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavioral simulation' do
        test_vectors = []
        behavioral = RHDL::HDL::ROM.new(nil, contents: [0x00, 0x11, 0x22, 0x33])

        test_cases = [
          { addr: 0, en: 1 },  # read addr 0
          { addr: 1, en: 1 },  # read addr 1
          { addr: 2, en: 1 },  # read addr 2
          { addr: 3, en: 1 },  # read addr 3
          { addr: 0, en: 0 },  # disabled
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavioral.set_input(:addr, tc[:addr])
          behavioral.set_input(:en, tc[:en])
          behavioral.propagate

          test_vectors << { inputs: tc }
          expected_outputs << { dout: behavioral.get_output(:dout) }
        end

        base_dir = File.join('tmp', 'iverilog', 'rom')
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
