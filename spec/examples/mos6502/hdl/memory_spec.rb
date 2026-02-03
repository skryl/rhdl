require_relative '../spec_helper'
require_relative '../../../../examples/mos6502/hdl/memory'

RSpec.describe RHDL::Examples::MOS6502::Memory do
  let(:mem) { RHDL::Examples::MOS6502::Memory.new }

  it 'reads and writes RAM' do
    mem.write(0x0000, 0x42)
    expect(mem.read(0x0000)).to eq(0x42)
  end

  it 'loads programs' do
    program = [0xA9, 0x42, 0x60]
    mem.load_program(program, 0x8000)

    expect(mem.read(0x8000)).to eq(0xA9)
    expect(mem.read(0x8001)).to eq(0x42)
    expect(mem.read(0x8002)).to eq(0x60)
  end

  it 'sets vectors' do
    mem.set_reset_vector(0x8000)
    expect(mem.read(0xFFFC)).to eq(0x00)
    expect(mem.read(0xFFFD)).to eq(0x80)
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = RHDL::Examples::MOS6502::Memory.to_verilog
      expect(verilog).to include('module mos6502_memory')
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::Examples::MOS6502::Memory.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit mos6502_memory')
      expect(firrtl).to include('input clk')
      expect(firrtl).to include('input addr')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile FIRRTL to Verilog' do
        result = CirctHelper.validate_firrtl_syntax(
          RHDL::Examples::MOS6502::Memory,
          base_dir: 'tmp/circt_test/mos6502_memory'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    # Memory uses behavior RAM which cannot be lowered to primitive gates
    # Gate-level synthesis is not supported for memory components
    it 'is not supported for behavior memory' do
      component = RHDL::Examples::MOS6502::Memory.new('mos6502_memory')
      expect {
        RHDL::Export::Structure::Lower.from_components([component], name: 'mos6502_memory')
      }.to raise_error(ArgumentError, /Unsupported component/)
    end
  end
end
