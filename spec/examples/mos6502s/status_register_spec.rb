# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe MOS6502S::StatusRegister do
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
      expect(verilog).to include('module mos6502s_status_register')
      expect(verilog).to include('output')
      expect(verilog).to include('p')
    end
  end
end
