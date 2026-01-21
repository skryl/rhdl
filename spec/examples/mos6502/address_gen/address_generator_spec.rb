# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe MOS6502::AddressGenerator do
  let(:ag) { described_class.new('test_ag') }

  describe 'simulation' do
    before do
      ag.set_input(:mode, 0)
      ag.set_input(:operand_lo, 0)
      ag.set_input(:operand_hi, 0)
      ag.set_input(:x_reg, 0)
      ag.set_input(:y_reg, 0)
      ag.set_input(:pc, 0)
      ag.set_input(:sp, 0xFF)
      ag.set_input(:indirect_lo, 0)
      ag.set_input(:indirect_hi, 0)
      ag.propagate
    end

    it 'computes zero page address' do
      ag.set_input(:mode, MOS6502::AddressGenerator::MODE_ZERO_PAGE)
      ag.set_input(:operand_lo, 0x80)
      ag.propagate

      expect(ag.get_output(:eff_addr)).to eq(0x0080)
      expect(ag.get_output(:is_zero_page)).to eq(1)
    end

    it 'computes absolute address' do
      ag.set_input(:mode, MOS6502::AddressGenerator::MODE_ABSOLUTE)
      ag.set_input(:operand_lo, 0x34)
      ag.set_input(:operand_hi, 0x12)
      ag.propagate

      expect(ag.get_output(:eff_addr)).to eq(0x1234)
    end

    it 'computes zero page X indexed address' do
      ag.set_input(:mode, MOS6502::AddressGenerator::MODE_ZERO_PAGE_X)
      ag.set_input(:operand_lo, 0x80)
      ag.set_input(:x_reg, 0x10)
      ag.propagate

      expect(ag.get_output(:eff_addr)).to eq(0x0090)
      expect(ag.get_output(:is_zero_page)).to eq(1)
    end

    it 'computes absolute X indexed address' do
      ag.set_input(:mode, MOS6502::AddressGenerator::MODE_ABSOLUTE_X)
      ag.set_input(:operand_lo, 0x00)
      ag.set_input(:operand_hi, 0x10)
      ag.set_input(:x_reg, 0x20)
      ag.propagate

      expect(ag.get_output(:eff_addr)).to eq(0x1020)
    end

    it 'computes stack address' do
      ag.set_input(:mode, MOS6502::AddressGenerator::MODE_STACK)
      ag.set_input(:sp, 0xFD)
      ag.propagate

      expect(ag.get_output(:eff_addr)).to eq(0x01FD)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502_address_generator')
      expect(verilog).to include('input [3:0] mode')
      expect(verilog).to include('output')
      expect(verilog).to include('eff_addr')
    end

    it 'generates valid FIRRTL' do
      firrtl = described_class.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit mos6502_address_generator')
      expect(firrtl).to include('input mode')
      expect(firrtl).to include('output eff_addr')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile FIRRTL to Verilog' do
        result = CirctHelper.validate_firrtl_syntax(
          described_class,
          base_dir: 'tmp/circt_test/mos6502_address_generator'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end

    context 'when iverilog is available', :slow, if: HdlToolchain.iverilog_available? do
      it 'behavior Verilog matches RHDL simulation' do
        verilog = described_class.to_verilog
        behavior = described_class.new('behavior')
        vectors = []

        inputs = { mode: 4, operand_lo: 8, operand_hi: 8, x_reg: 8, y_reg: 8, pc: 16, sp: 8, indirect_lo: 8, indirect_hi: 8 }
        outputs = { eff_addr: 16, is_zero_page: 1, page_cross: 1 }

        base_inputs = { operand_lo: 0, operand_hi: 0, x_reg: 0, y_reg: 0, pc: 0, sp: 0xFF, indirect_lo: 0, indirect_hi: 0 }

        # Test zero page mode
        behavior.set_input(:mode, MOS6502::AddressGenerator::MODE_ZERO_PAGE)
        behavior.set_input(:operand_lo, 0x80)
        base_inputs.each { |k, v| behavior.set_input(k, v) unless k == :mode || k == :operand_lo }
        behavior.propagate
        vectors << {
          inputs: base_inputs.merge(mode: MOS6502::AddressGenerator::MODE_ZERO_PAGE, operand_lo: 0x80),
          expected: { eff_addr: behavior.get_output(:eff_addr), is_zero_page: behavior.get_output(:is_zero_page), page_cross: behavior.get_output(:page_cross) }
        }

        # Test absolute mode
        behavior.set_input(:mode, MOS6502::AddressGenerator::MODE_ABSOLUTE)
        behavior.set_input(:operand_lo, 0x34)
        behavior.set_input(:operand_hi, 0x12)
        behavior.propagate
        vectors << {
          inputs: base_inputs.merge(mode: MOS6502::AddressGenerator::MODE_ABSOLUTE, operand_lo: 0x34, operand_hi: 0x12),
          expected: { eff_addr: behavior.get_output(:eff_addr), is_zero_page: behavior.get_output(:is_zero_page), page_cross: behavior.get_output(:page_cross) }
        }

        result = NetlistHelper.run_behavior_simulation(
          verilog,
          module_name: 'mos6502_address_generator',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/mos6502_address_generator'
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
    let(:component) { described_class.new('mos6502_address_generator') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'mos6502_address_generator') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mos6502_address_generator.mode')
      expect(ir.inputs.keys).to include('mos6502_address_generator.operand_lo', 'mos6502_address_generator.operand_hi')
      expect(ir.outputs.keys).to include('mos6502_address_generator.eff_addr')
    end

    it 'generates gates for combinational address logic' do
      # Address generator is purely combinational
      expect(ir.gates.length).to be > 10
      expect(ir.dffs.length).to eq(0)
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module mos6502_address_generator')
      expect(verilog).to include('input [3:0] mode')
      expect(verilog).to include('output [15:0] eff_addr')
    end

    context 'when iverilog is available', :slow, if: HdlToolchain.iverilog_available? do
      it 'matches behavior simulation for address modes' do
        behavior = described_class.new('behavior')
        vectors = []
        base_inputs = { operand_lo: 0, operand_hi: 0, x_reg: 0, y_reg: 0, pc: 0, sp: 0xFF, indirect_lo: 0, indirect_hi: 0 }

        # Test zero page mode
        behavior.set_input(:mode, MOS6502::AddressGenerator::MODE_ZERO_PAGE)
        behavior.set_input(:operand_lo, 0x80)
        base_inputs.each { |k, v| behavior.set_input(k, v) unless k == :mode || k == :operand_lo }
        behavior.propagate
        vectors << {
          inputs: base_inputs.merge(mode: MOS6502::AddressGenerator::MODE_ZERO_PAGE, operand_lo: 0x80),
          expected: { eff_addr: behavior.get_output(:eff_addr), is_zero_page: behavior.get_output(:is_zero_page), page_cross: behavior.get_output(:page_cross) }
        }

        # Test absolute mode
        behavior.set_input(:mode, MOS6502::AddressGenerator::MODE_ABSOLUTE)
        behavior.set_input(:operand_lo, 0x34)
        behavior.set_input(:operand_hi, 0x12)
        behavior.propagate
        vectors << {
          inputs: base_inputs.merge(mode: MOS6502::AddressGenerator::MODE_ABSOLUTE, operand_lo: 0x34, operand_hi: 0x12),
          expected: { eff_addr: behavior.get_output(:eff_addr), is_zero_page: behavior.get_output(:is_zero_page), page_cross: behavior.get_output(:page_cross) }
        }

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/mos6502_address_generator')
        expect(result[:success]).to be(true), result[:error]

        vectors.each_with_index do |vec, idx|
          expect(result[:results][idx]).to eq(vec[:expected]),
            "Vector #{idx}: expected #{vec[:expected]}, got #{result[:results][idx]}"
        end
      end
    end
  end
end
