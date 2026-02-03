# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe MOS6502::StatusRegister do
  let(:sr) { described_class.new('test_sr') }

  describe 'simulation' do
    before do
      sr.set_input(:clk, 0)
      sr.set_input(:rst, 0)
      sr.set_input(:load_n, 0)
      sr.set_input(:load_v, 0)
      sr.set_input(:load_z, 0)
      sr.set_input(:load_c, 0)
      sr.set_input(:load_i, 0)
      sr.set_input(:load_d, 0)
      sr.set_input(:load_b, 0)
      sr.set_input(:load_all, 0)
      sr.set_input(:load_flags, 0)
      sr.set_input(:n_in, 0)
      sr.set_input(:v_in, 0)
      sr.set_input(:z_in, 0)
      sr.set_input(:c_in, 0)
      sr.set_input(:i_in, 0)
      sr.set_input(:d_in, 0)
      sr.set_input(:b_in, 0)
      sr.set_input(:data_in, 0)
      sr.propagate
    end

    it 'sets negative flag' do
      sr.set_input(:n_in, 1)
      sr.set_input(:load_n, 1)
      sr.set_input(:clk, 1)
      sr.propagate

      expect(sr.get_output(:n)).to eq(1)
    end

    it 'sets zero flag' do
      sr.set_input(:z_in, 1)
      sr.set_input(:load_z, 1)
      sr.set_input(:clk, 1)
      sr.propagate

      expect(sr.get_output(:z)).to eq(1)
    end

    it 'sets carry flag' do
      sr.set_input(:c_in, 1)
      sr.set_input(:load_c, 1)
      sr.set_input(:clk, 1)
      sr.propagate

      expect(sr.get_output(:c)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502_status_register')
      expect(verilog).to include('output')
      expect(verilog).to include('p')
    end

    it 'generates valid FIRRTL' do
      firrtl = described_class.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit mos6502_status_register')
      expect(firrtl).to include('input clk')
      expect(firrtl).to include('output p')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile FIRRTL to Verilog' do
        result = CirctHelper.validate_firrtl_syntax(
          described_class,
          base_dir: 'tmp/circt_test/mos6502_status_register'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'behavior Verilog compiles and runs' do
        verilog = described_class.to_verilog

        inputs = { clk: 1, rst: 1, load_n: 1, load_v: 1, load_z: 1, load_c: 1,
                   load_i: 1, load_d: 1, load_b: 1, load_all: 1, load_flags: 1,
                   n_in: 1, v_in: 1, z_in: 1, c_in: 1, i_in: 1, d_in: 1, b_in: 1, data_in: 8 }
        outputs = { p: 8, n: 1, v: 1, z: 1, c: 1, i: 1, d: 1, b: 1 }

        # Status register is sequential - verify compilation and basic operation
        vectors = [
          { inputs: { clk: 0, rst: 1, load_n: 0, load_v: 0, load_z: 0, load_c: 0,
                      load_i: 0, load_d: 0, load_b: 0, load_all: 0, load_flags: 0,
                      n_in: 0, v_in: 0, z_in: 0, c_in: 0, i_in: 0, d_in: 0, b_in: 0, data_in: 0 } },
          { inputs: { clk: 1, rst: 1, load_n: 0, load_v: 0, load_z: 0, load_c: 0,
                      load_i: 0, load_d: 0, load_b: 0, load_all: 0, load_flags: 0,
                      n_in: 0, v_in: 0, z_in: 0, c_in: 0, i_in: 0, d_in: 0, b_in: 0, data_in: 0 } },
          { inputs: { clk: 0, rst: 0, load_n: 1, load_v: 0, load_z: 0, load_c: 0,
                      load_i: 0, load_d: 0, load_b: 0, load_all: 0, load_flags: 0,
                      n_in: 1, v_in: 0, z_in: 0, c_in: 0, i_in: 0, d_in: 0, b_in: 0, data_in: 0 } }
        ]

        result = NetlistHelper.run_behavior_simulation(
          verilog,
          module_name: 'mos6502_status_register',
          inputs: inputs,
          outputs: outputs,
          test_vectors: vectors,
          base_dir: 'tmp/behavior_test/mos6502_status_register',
          has_clock: true
        )
        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { described_class.new('mos6502_status_register') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'mos6502_status_register') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mos6502_status_register.clk', 'mos6502_status_register.rst')
      expect(ir.inputs.keys).to include('mos6502_status_register.n_in', 'mos6502_status_register.z_in')
      expect(ir.outputs.keys).to include('mos6502_status_register.p')
      expect(ir.outputs.keys).to include('mos6502_status_register.n', 'mos6502_status_register.z', 'mos6502_status_register.c')
    end

    it 'generates DFFs for flag storage' do
      # Status register has 8-bit p register requiring DFFs
      expect(ir.dffs.length).to be > 0
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module mos6502_status_register')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('output [7:0] p')
    end

    context 'when iverilog is available', if: HdlToolchain.iverilog_available? do
      it 'compiles and simulates structure Verilog' do
        # Status register is sequential - verify compilation and basic operation
        base_inputs = { clk: 0, rst: 0, load_n: 0, load_v: 0, load_z: 0, load_c: 0,
                        load_i: 0, load_d: 0, load_b: 0, load_all: 0, load_flags: 0,
                        n_in: 0, v_in: 0, z_in: 0, c_in: 0, i_in: 0, d_in: 0, b_in: 0, data_in: 0 }

        vectors = [
          { inputs: base_inputs.dup },
          { inputs: base_inputs.merge(clk: 1) },
          { inputs: base_inputs.merge(n_in: 1, load_n: 1) },
          { inputs: base_inputs.merge(n_in: 1, load_n: 1, clk: 1) }
        ]

        result = NetlistHelper.run_structure_simulation(ir, vectors, base_dir: 'tmp/netlist_test/mos6502_status_register')
        expect(result[:success]).to be(true), result[:error]
      end
    end
  end
end
