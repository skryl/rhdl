# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe MOS6502::IndirectAddressCalc do
  let(:calc) { described_class.new('test_iac') }

  describe 'simulation' do
    before do
      calc.set_input(:mode, 0)
      calc.set_input(:operand_lo, 0)
      calc.set_input(:operand_hi, 0)
      calc.set_input(:x_reg, 0)
      calc.propagate
    end

    it 'computes indexed indirect (zp,X) pointer address' do
      calc.set_input(:mode, MOS6502::AddressGenerator::MODE_INDEXED_IND)
      calc.set_input(:operand_lo, 0x40)
      calc.set_input(:x_reg, 0x10)
      calc.propagate

      # Pointer address should be (operand + X) wrapped to zero page
      expect(calc.get_output(:ptr_addr_lo) & 0xFF).to eq(0x50)
    end

    it 'computes indirect indexed (zp),Y pointer address' do
      calc.set_input(:mode, MOS6502::AddressGenerator::MODE_INDIRECT_IDX)
      calc.set_input(:operand_lo, 0x80)
      calc.propagate

      # Pointer address is just the operand for indirect Y
      expect(calc.get_output(:ptr_addr_lo) & 0xFF).to eq(0x80)
    end

    it 'wraps zero page addresses for indexed indirect' do
      calc.set_input(:mode, MOS6502::AddressGenerator::MODE_INDEXED_IND)
      calc.set_input(:operand_lo, 0xF0)
      calc.set_input(:x_reg, 0x20)
      calc.propagate

      # Should wrap: (0xF0 + 0x20) & 0xFF = 0x10
      expect(calc.get_output(:ptr_addr_lo) & 0xFF).to eq(0x10)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502_indirect_address_calc')
      expect(verilog).to include('ptr_addr_lo')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'behavior Verilog matches RHDL simulation' do
        verilog = described_class.to_verilog
        behavior = described_class.new('behavior')
        vectors = []

        inputs = { mode: 4, operand_lo: 8, operand_hi: 8, x_reg: 8 }
        outputs = { ptr_addr_lo: 8, ptr_addr_hi: 8 }

        # Test indexed indirect (zp,X)
        behavior.set_input(:mode, MOS6502::AddressGenerator::MODE_INDEXED_IND)
        behavior.set_input(:operand_lo, 0x40)
        behavior.set_input(:operand_hi, 0)
        behavior.set_input(:x_reg, 0x10)
        behavior.propagate
        vectors << {
          inputs: { mode: MOS6502::AddressGenerator::MODE_INDEXED_IND, operand_lo: 0x40, operand_hi: 0, x_reg: 0x10 },
          expected: { ptr_addr_lo: behavior.get_output(:ptr_addr_lo), ptr_addr_hi: behavior.get_output(:ptr_addr_hi) }
        }

        # Test indirect indexed (zp),Y
        behavior.set_input(:mode, MOS6502::AddressGenerator::MODE_INDIRECT_IDX)
        behavior.set_input(:operand_lo, 0x80)
        behavior.propagate
        vectors << {
          inputs: { mode: MOS6502::AddressGenerator::MODE_INDIRECT_IDX, operand_lo: 0x80, operand_hi: 0, x_reg: 0 },
          expected: { ptr_addr_lo: behavior.get_output(:ptr_addr_lo), ptr_addr_hi: behavior.get_output(:ptr_addr_hi) }
        }

        result = NetlistHelper.run_behavior_simulation(
          verilog,
          module_name: 'mos6502_indirect_address_calc',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/mos6502_indirect_address_calc'
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
    let(:component) { described_class.new('mos6502_indirect_addr_calc') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'mos6502_indirect_addr_calc') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mos6502_indirect_addr_calc.mode')
      expect(ir.inputs.keys).to include('mos6502_indirect_addr_calc.operand_lo')
      expect(ir.outputs.keys).to include('mos6502_indirect_addr_calc.ptr_addr_lo')
    end

    it 'generates gates for combinational logic' do
      # Indirect address calc is purely combinational
      expect(ir.gates.length).to be > 5
      expect(ir.dffs.length).to eq(0)
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module mos6502_indirect_addr_calc')
      expect(verilog).to include('input [3:0] mode')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'matches behavior simulation for indirect addressing' do
        behavior = described_class.new('behavior')
        vectors = []

        # Test indexed indirect (zp,X)
        behavior.set_input(:mode, MOS6502::AddressGenerator::MODE_INDEXED_IND)
        behavior.set_input(:operand_lo, 0x40)
        behavior.set_input(:operand_hi, 0)
        behavior.set_input(:x_reg, 0x10)
        behavior.propagate
        vectors << {
          inputs: { mode: MOS6502::AddressGenerator::MODE_INDEXED_IND, operand_lo: 0x40, operand_hi: 0, x_reg: 0x10 },
          expected: { ptr_addr_lo: behavior.get_output(:ptr_addr_lo), ptr_addr_hi: behavior.get_output(:ptr_addr_hi) }
        }

        # Test indirect indexed (zp),Y
        behavior.set_input(:mode, MOS6502::AddressGenerator::MODE_INDIRECT_IDX)
        behavior.set_input(:operand_lo, 0x80)
        behavior.propagate
        vectors << {
          inputs: { mode: MOS6502::AddressGenerator::MODE_INDIRECT_IDX, operand_lo: 0x80, operand_hi: 0, x_reg: 0 },
          expected: { ptr_addr_lo: behavior.get_output(:ptr_addr_lo), ptr_addr_hi: behavior.get_output(:ptr_addr_hi) }
        }

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/mos6502_indirect_addr_calc')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected]),
            "Vector #{idx}: expected #{vec[:expected]}, got #{result[:results][idx]}"
        end
      end
    end
  end
end
