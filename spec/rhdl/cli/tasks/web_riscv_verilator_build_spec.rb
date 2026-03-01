# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/rhdl/cli/tasks/utilities/web_riscv_verilator_build'

RSpec.describe RHDL::CLI::Tasks::WebRiscvVerilatorBuild do
  let(:mod) { described_class }

  describe '.missing_tools' do
    it 'returns an array of tool names' do
      result = mod.missing_tools
      expect(result).to be_an(Array)
      result.each { |entry| expect(entry).to be_a(String) }
    end

    it 'includes required tools in constants' do
      expect(mod::REQUIRED_TOOLS).to include('verilator', 'em++')
    end
  end

  describe '.tools_available?' do
    it 'matches missing_tools emptiness' do
      expect(mod.tools_available?).to eq(mod.missing_tools.empty?)
    end
  end

  describe '.build_wrapper_source' do
    before do
      allow(mod).to receive(:load_runner_cycle_sources).and_return(['/* common */', '/* run */'])
    end

    subject(:source) { mod.build_wrapper_source }

    it 'contains required exported sim API symbols' do
      %w[
        sim_create sim_destroy sim_reset sim_eval sim_poke sim_peek
        sim_write_pc sim_load_mem sim_read_mem_word sim_run_cycles
        sim_uart_rx_push sim_uart_tx_len sim_uart_tx_copy sim_uart_tx_clear
        sim_disk_load sim_disk_read_byte sim_wasm_alloc sim_wasm_dealloc
      ].each do |name|
        expect(source).to include("export_name(\"#{name}\")"), "missing export #{name}"
      end
    end

    it 'includes RISC-V Verilator model accessors' do
      expect(source).to include('#include "Vriscv.h"')
      expect(source).to include('ctx->dut->debug_pc')
      expect(source).to include('riscv_cpu__DOT__pc_reg___05Fpc')
    end
  end

  describe '.build' do
    it 'returns false with warning when required tools are missing' do
      allow(mod).to receive(:missing_tools).and_return(['verilator'])
      expect { expect(mod.build).to be(false) }.to output(/RISC-V verilator WASM build skipped/).to_stderr
    end
  end
end
