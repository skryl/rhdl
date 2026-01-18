require_relative 'spec_helper'
require_relative '../../../examples/mos6502/hdl/alu'

RSpec.describe MOS6502::ALU do
  let(:alu) { MOS6502::ALU.new }

  before do
    alu.set_input(:c_in, 0)
    alu.set_input(:d_flag, 0)
  end

  describe 'ADC' do
    it 'adds two numbers' do
      alu.set_input(:a, 0x10)
      alu.set_input(:b, 0x20)
      alu.set_input(:op, MOS6502::ALU::OP_ADC)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0x30)
      expect(alu.get_output(:z)).to eq(0)
      expect(alu.get_output(:n)).to eq(0)
      expect(alu.get_output(:c)).to eq(0)
    end

    it 'adds with carry in' do
      alu.set_input(:a, 0x10)
      alu.set_input(:b, 0x20)
      alu.set_input(:c_in, 1)
      alu.set_input(:op, MOS6502::ALU::OP_ADC)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0x31)
    end

    it 'sets carry on overflow' do
      alu.set_input(:a, 0xFF)
      alu.set_input(:b, 0x01)
      alu.set_input(:op, MOS6502::ALU::OP_ADC)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0x00)
      expect(alu.get_output(:c)).to eq(1)
      expect(alu.get_output(:z)).to eq(1)
    end
  end

  describe 'SBC' do
    it 'subtracts two numbers with borrow clear' do
      alu.set_input(:a, 0x30)
      alu.set_input(:b, 0x10)
      alu.set_input(:c_in, 1)  # Carry set means no borrow
      alu.set_input(:op, MOS6502::ALU::OP_SBC)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0x20)
      expect(alu.get_output(:c)).to eq(1)
    end
  end

  describe 'Logic operations' do
    it 'performs AND' do
      alu.set_input(:a, 0xF0)
      alu.set_input(:b, 0x0F)
      alu.set_input(:op, MOS6502::ALU::OP_AND)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0x00)
      expect(alu.get_output(:z)).to eq(1)
    end

    it 'performs ORA' do
      alu.set_input(:a, 0xF0)
      alu.set_input(:b, 0x0F)
      alu.set_input(:op, MOS6502::ALU::OP_ORA)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0xFF)
      expect(alu.get_output(:n)).to eq(1)
    end
  end

  describe 'Shift operations' do
    it 'performs ASL' do
      alu.set_input(:a, 0x81)
      alu.set_input(:op, MOS6502::ALU::OP_ASL)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0x02)
      expect(alu.get_output(:c)).to eq(1)
    end

    it 'performs LSR' do
      alu.set_input(:a, 0x81)
      alu.set_input(:op, MOS6502::ALU::OP_LSR)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0x40)
      expect(alu.get_output(:c)).to eq(1)
    end
  end

  describe 'Compare' do
    it 'compares equal values' do
      alu.set_input(:a, 0x42)
      alu.set_input(:b, 0x42)
      alu.set_input(:op, MOS6502::ALU::OP_CMP)
      alu.propagate

      expect(alu.get_output(:z)).to eq(1)
      expect(alu.get_output(:c)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = MOS6502::ALU.to_verilog
      expect(verilog).to include('module mos6502_alu')
      expect(verilog).to include('input [3:0] op')
      expect(verilog).to include('output')
      expect(verilog).to include('result')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'behavioral Verilog matches RHDL simulation' do
        verilog = MOS6502::ALU.to_verilog
        behavioral = MOS6502::ALU.new
        vectors = []

        inputs = { a: 8, b: 8, op: 4, c_in: 1, d_flag: 1 }
        outputs = { result: 8, n: 1, z: 1, c: 1, v: 1 }

        # Test ADC: 0x10 + 0x20 = 0x30
        behavioral.set_input(:a, 0x10)
        behavioral.set_input(:b, 0x20)
        behavioral.set_input(:op, MOS6502::ALU::OP_ADC)
        behavioral.set_input(:c_in, 0)
        behavioral.set_input(:d_flag, 0)
        behavioral.propagate
        vectors << {
          inputs: { a: 0x10, b: 0x20, op: MOS6502::ALU::OP_ADC, c_in: 0, d_flag: 0 },
          expected: { result: behavioral.get_output(:result), n: behavioral.get_output(:n), z: behavioral.get_output(:z), c: behavioral.get_output(:c), v: behavioral.get_output(:v) }
        }

        # Test AND: 0xF0 & 0x0F = 0x00
        behavioral.set_input(:a, 0xF0)
        behavioral.set_input(:b, 0x0F)
        behavioral.set_input(:op, MOS6502::ALU::OP_AND)
        behavioral.propagate
        vectors << {
          inputs: { a: 0xF0, b: 0x0F, op: MOS6502::ALU::OP_AND, c_in: 0, d_flag: 0 },
          expected: { result: behavioral.get_output(:result), n: behavioral.get_output(:n), z: behavioral.get_output(:z), c: behavioral.get_output(:c), v: behavioral.get_output(:v) }
        }

        # Test ORA: 0xF0 | 0x0F = 0xFF
        behavioral.set_input(:a, 0xF0)
        behavioral.set_input(:b, 0x0F)
        behavioral.set_input(:op, MOS6502::ALU::OP_ORA)
        behavioral.propagate
        vectors << {
          inputs: { a: 0xF0, b: 0x0F, op: MOS6502::ALU::OP_ORA, c_in: 0, d_flag: 0 },
          expected: { result: behavioral.get_output(:result), n: behavioral.get_output(:n), z: behavioral.get_output(:z), c: behavioral.get_output(:c), v: behavioral.get_output(:v) }
        }

        result = NetlistHelper.run_behavioral_simulation(
          verilog,
          module_name: 'mos6502_alu',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavioral_test/mos6502_alu'
        )
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected]),
            "Vector #{idx}: expected #{vec[:expected]}, got #{result[:results][idx]}"
        end
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { MOS6502::ALU.new('mos6502_alu') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'mos6502_alu') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mos6502_alu.a', 'mos6502_alu.b', 'mos6502_alu.op')
      expect(ir.inputs.keys).to include('mos6502_alu.c_in', 'mos6502_alu.d_flag')
      expect(ir.outputs.keys).to include('mos6502_alu.result', 'mos6502_alu.n', 'mos6502_alu.z', 'mos6502_alu.c', 'mos6502_alu.v')
    end

    it 'generates gates for combinational logic' do
      # ALU is a complex combinational component with many gates
      expect(ir.gates.length).to be > 50
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module mos6502_alu')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('input [7:0] b')
      expect(verilog).to include('input [3:0] op')
      expect(verilog).to include('output [7:0] result')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'matches behavioral simulation for ADC operations' do
        # Run behavioral simulation to get expected results
        behavioral = MOS6502::ALU.new
        vectors = []

        # Test ADC: 0x10 + 0x20 = 0x30
        behavioral.set_input(:a, 0x10)
        behavioral.set_input(:b, 0x20)
        behavioral.set_input(:op, MOS6502::ALU::OP_ADC)
        behavioral.set_input(:c_in, 0)
        behavioral.set_input(:d_flag, 0)
        behavioral.propagate
        vectors << {
          inputs: { a: 0x10, b: 0x20, op: MOS6502::ALU::OP_ADC, c_in: 0, d_flag: 0 },
          expected: { result: behavioral.get_output(:result), n: behavioral.get_output(:n), z: behavioral.get_output(:z), c: behavioral.get_output(:c), v: behavioral.get_output(:v) }
        }

        # Test ADC with carry: 0xFF + 0x01 = 0x00 with carry
        behavioral.set_input(:a, 0xFF)
        behavioral.set_input(:b, 0x01)
        behavioral.set_input(:op, MOS6502::ALU::OP_ADC)
        behavioral.set_input(:c_in, 0)
        behavioral.propagate
        vectors << {
          inputs: { a: 0xFF, b: 0x01, op: MOS6502::ALU::OP_ADC, c_in: 0, d_flag: 0 },
          expected: { result: behavioral.get_output(:result), n: behavioral.get_output(:n), z: behavioral.get_output(:z), c: behavioral.get_output(:c), v: behavioral.get_output(:v) }
        }

        # Test AND: 0xF0 & 0x0F = 0x00
        behavioral.set_input(:a, 0xF0)
        behavioral.set_input(:b, 0x0F)
        behavioral.set_input(:op, MOS6502::ALU::OP_AND)
        behavioral.propagate
        vectors << {
          inputs: { a: 0xF0, b: 0x0F, op: MOS6502::ALU::OP_AND, c_in: 0, d_flag: 0 },
          expected: { result: behavioral.get_output(:result), n: behavioral.get_output(:n), z: behavioral.get_output(:z), c: behavioral.get_output(:c), v: behavioral.get_output(:v) }
        }

        # Test ORA: 0xF0 | 0x0F = 0xFF
        behavioral.set_input(:a, 0xF0)
        behavioral.set_input(:b, 0x0F)
        behavioral.set_input(:op, MOS6502::ALU::OP_ORA)
        behavioral.propagate
        vectors << {
          inputs: { a: 0xF0, b: 0x0F, op: MOS6502::ALU::OP_ORA, c_in: 0, d_flag: 0 },
          expected: { result: behavioral.get_output(:result), n: behavioral.get_output(:n), z: behavioral.get_output(:z), c: behavioral.get_output(:c), v: behavioral.get_output(:v) }
        }

        result = NetlistHelper.run_structural_simulation(ir, vectors, base_dir: 'tmp/netlist_test/mos6502_alu')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected]),
            "Vector #{idx}: expected #{vec[:expected]}, got #{result[:results][idx]}"
        end
      end
    end
  end
end
