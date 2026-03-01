# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/rhdl/cli/tasks/utilities/web_apple2_arcilator_build'

RSpec.describe RHDL::CLI::Tasks::WebApple2ArcilatorBuild do
  let(:mod) { described_class }

  describe '.missing_tools' do
    it 'returns an array of tool names' do
      result = mod.missing_tools
      expect(result).to be_an(Array)
      result.each { |t| expect(t).to be_a(String) }
    end

    it 'checks all required CIRCT and compiler tools' do
      expect(described_class::REQUIRED_TOOLS).to include('firtool', 'arcilator', 'clang', 'wasm-ld')
    end
  end

  describe '.tools_available?' do
    it 'returns a boolean' do
      expect(mod.tools_available?).to eq(mod.missing_tools.empty?)
    end
  end

  describe '.signal_width_type' do
    it 'maps 1-bit to SIG_BIT' do
      expect(mod.signal_width_type(1)).to eq('SIG_BIT')
    end

    it 'maps 2-8 bits to SIG_U8' do
      expect(mod.signal_width_type(2)).to eq('SIG_U8')
      expect(mod.signal_width_type(8)).to eq('SIG_U8')
    end

    it 'maps 9-16 bits to SIG_U16' do
      expect(mod.signal_width_type(9)).to eq('SIG_U16')
      expect(mod.signal_width_type(16)).to eq('SIG_U16')
    end

    it 'maps >16 bits to SIG_U32' do
      expect(mod.signal_width_type(32)).to eq('SIG_U32')
    end
  end

  describe '.build_signal_table' do
    let(:offsets) do
      {
        'clk_14m' => { offset: 0, num_bits: 1 },
        'reset' => { offset: 1, num_bits: 1 },
        'ram_addr' => { offset: 10, num_bits: 16 },
        'speaker' => { offset: 20, num_bits: 1 },
        'pc_debug' => { offset: 30, num_bits: 16 },
        'unknown_signal' => { offset: 99, num_bits: 8 }
      }
    end

    it 'includes known Apple II signals that exist in offsets' do
      table = mod.build_signal_table(offsets)
      names = table.map { |e| e[:name] }
      expect(names).to include('clk_14m', 'reset', 'ram_addr', 'speaker', 'pc_debug')
    end

    it 'excludes unknown signals not in INPUT_SIGNALS or OUTPUT_SIGNALS' do
      table = mod.build_signal_table(offsets)
      names = table.map { |e| e[:name] }
      expect(names).not_to include('unknown_signal')
    end

    it 'marks input signals correctly' do
      table = mod.build_signal_table(offsets)
      clk_entry = table.find { |e| e[:name] == 'clk_14m' }
      speaker_entry = table.find { |e| e[:name] == 'speaker' }
      expect(clk_entry[:is_input]).to eq(1)
      expect(speaker_entry[:is_input]).to eq(0)
    end

    it 'assigns correct width types' do
      table = mod.build_signal_table(offsets)
      clk_entry = table.find { |e| e[:name] == 'clk_14m' }
      addr_entry = table.find { |e| e[:name] == 'ram_addr' }
      expect(clk_entry[:width]).to eq('SIG_BIT')
      expect(addr_entry[:width]).to eq('SIG_U16')
    end
  end

  describe '.generate_offset_defines' do
    let(:offsets) do
      {
        'clk_14m' => { offset: 0, num_bits: 1 },
        'ram_addr' => { offset: 10, num_bits: 16 },
        'unknown' => { offset: 99, num_bits: 8 }
      }
    end

    it 'generates #define lines for known signals' do
      result = mod.generate_offset_defines(offsets)
      expect(result).to include('#define OFF_CLK_14M 0')
      expect(result).to include('#define OFF_RAM_ADDR 10')
    end

    it 'does not define offsets for unknown signals' do
      result = mod.generate_offset_defines(offsets)
      expect(result).not_to include('OFF_UNKNOWN')
    end
  end

  describe '.generate_signal_table' do
    let(:entries) do
      [
        { name: 'clk_14m', offset: 0, width: 'SIG_BIT', is_input: 1 },
        { name: 'speaker', offset: 20, width: 'SIG_BIT', is_input: 0 }
      ]
    end

    it 'generates a valid C signal table array' do
      result = mod.generate_signal_table(entries)
      expect(result).to include('#define SIGNAL_COUNT 2')
      expect(result).to include('g_signal_table[SIGNAL_COUNT]')
      expect(result).to include('"clk_14m"')
      expect(result).to include('"speaker"')
    end
  end

  describe '.generate_name_csv_strings' do
    let(:entries) do
      [
        { name: 'clk_14m', offset: 0, width: 'SIG_BIT', is_input: 1 },
        { name: 'reset', offset: 1, width: 'SIG_BIT', is_input: 1 },
        { name: 'speaker', offset: 20, width: 'SIG_BIT', is_input: 0 },
        { name: 'ram_addr', offset: 10, width: 'SIG_U16', is_input: 0 }
      ]
    end

    it 'generates CSV strings separating inputs and outputs' do
      result = mod.generate_name_csv_strings(entries)
      expect(result).to include('g_input_names_csv[] = "clk_14m,reset"')
      expect(result).to include('g_output_names_csv[] = "speaker,ram_addr"')
    end
  end

  describe '.rewrite_llvm_ir_for_wasm32' do
    it 'replaces target triple with wasm32' do
      ir = <<~IR
        target datalayout = "e-m:o-i64:64-i128:128-n32:64-S128-Fn32"
        target triple = "arm64-apple-macosx15.0.0"
        define void @apple2_eval(ptr %0) {
          ret void
        }
      IR

      result = mod.rewrite_llvm_ir_for_wasm32(ir)
      expect(result).to include('target triple = "wasm32-unknown-unknown"')
      expect(result).to include('target datalayout = "e-m:e-p:32:32')
      expect(result).not_to include('arm64-apple-macosx')
    end

    it 'preserves non-target lines unchanged' do
      ir = "define void @apple2_eval(ptr %0) {\n  ret void\n}\n"
      result = mod.rewrite_llvm_ir_for_wasm32(ir)
      expect(result).to include('define void @apple2_eval')
    end
  end

  describe '.build_wrapper_source' do
    let(:offsets) do
      {
        'clk_14m' => { offset: 0, num_bits: 1 },
        'reset' => { offset: 1, num_bits: 1 },
        'ram_do' => { offset: 2, num_bits: 8 },
        'ps2_clk' => { offset: 3, num_bits: 1 },
        'ps2_data' => { offset: 4, num_bits: 1 },
        'ram_addr' => { offset: 10, num_bits: 16 },
        'ram_we' => { offset: 12, num_bits: 1 },
        'd' => { offset: 13, num_bits: 8 },
        'speaker' => { offset: 14, num_bits: 1 },
        'pc_debug' => { offset: 20, num_bits: 16 },
        'a_debug' => { offset: 22, num_bits: 8 },
        'x_debug' => { offset: 23, num_bits: 8 },
        'y_debug' => { offset: 24, num_bits: 8 },
        'pause' => { offset: 25, num_bits: 1 },
        'gameport' => { offset: 26, num_bits: 8 },
        'pd' => { offset: 27, num_bits: 8 },
        'flash_clk' => { offset: 28, num_bits: 1 }
      }
    end

    subject(:source) { mod.build_wrapper_source(offsets, 4096) }

    it 'generates valid C source with all required WASM exports' do
      %w[sim_create sim_destroy sim_free_error sim_get_caps
         sim_signal sim_exec sim_trace sim_blob
         sim_wasm_alloc sim_wasm_dealloc
         runner_get_caps runner_mem runner_run runner_control runner_probe].each do |fn|
        expect(source).to include("export_name(\"#{fn}\")"), "Missing export: #{fn}"
      end
    end

    it 'includes signal offset defines' do
      expect(source).to include('#define OFF_CLK_14M 0')
      expect(source).to include('#define OFF_RESET 1')
      expect(source).to include('#define OFF_RAM_ADDR 10')
    end

    it 'includes the signal lookup table' do
      expect(source).to include('g_signal_table')
      expect(source).to include('"clk_14m"')
    end

    it 'includes the arcilator eval extern declaration' do
      expect(source).to include('extern void apple2_apple2_eval(void *state)')
    end

    it 'implements the 14 MHz cycle with memory bridge' do
      expect(source).to include('run_14m_cycle')
      expect(source).to include('OFF_CLK_14M')
      expect(source).to include('apple2_apple2_eval')
    end

    it 'defines RUNNER_KIND_APPLE2' do
      expect(source).to include('RUNNER_KIND_APPLE2')
    end

    it 'includes RAM and ROM size constants' do
      expect(source).to include("#define RAM_SIZE #{48 * 1024}")
      expect(source).to include("#define ROM_SIZE #{12 * 1024}")
    end
  end

  describe '.build' do
    context 'when tools are not available' do
      before do
        allow(mod).to receive(:missing_tools).and_return(['firtool', 'arcilator'])
      end

      it 'returns false and prints a warning' do
        expect { expect(mod.build).to be false }.to output(/arcilator WASM build skipped/).to_stderr
      end
    end
  end
end
