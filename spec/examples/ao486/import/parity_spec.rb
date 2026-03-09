# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'

require_relative '../../../../examples/ao486/utilities/import/system_importer'

RSpec.describe 'AO486 import parity (stubbed system baseline)' do
  INPUT_WIDTHS = {
    reset: 1,
    clk_sys: 1,
    clock_rate: 28,
    l1_disable: 1,
    l2_disable: 1,
    floppy_wp: 2,
    joystick_dis: 2,
    joystick_dig_1: 14,
    joystick_dig_2: 14,
    joystick_ana_1: 16,
    joystick_ana_2: 16,
    joystick_mode: 2,
    joystick_timed: 2,
    mgmt_address: 16,
    mgmt_read: 1,
    mgmt_write: 1,
    mgmt_writedata: 16,
    ps2_kbclk_in: 1,
    ps2_kbdat_in: 1,
    ps2_mouseclk_in: 1,
    ps2_mousedat_in: 1,
    bootcfg: 6,
    uma_ram: 1,
    clk_uart1: 1,
    uart1_rx: 1,
    uart1_cts_n: 1,
    uart1_dcd_n: 1,
    uart1_dsr_n: 1,
    clk_uart2: 1,
    uart2_rx: 1,
    uart2_cts_n: 1,
    uart2_dcd_n: 1,
    uart2_dsr_n: 1,
    clk_mpu: 1,
    mpu_rx: 1,
    clk_audio: 1,
    sound_fm_mode: 1,
    sound_cms_en: 1,
    clk_vga: 1,
    clock_rate_vga: 28,
    video_f60: 1,
    video_fb_en: 1,
    video_lores: 1,
    video_border: 1,
    DDRAM_BUSY: 1,
    DDRAM_DOUT: 64,
    DDRAM_DOUT_READY: 1
  }.freeze

  OUTPUT_WIDTHS = {
    fdd_request: 2,
    ide0_request: 3,
    ide1_request: 3,
    mgmt_readdata: 16,
    ps2_kbclk_out: 1,
    ps2_kbdat_out: 1,
    ps2_mouseclk_out: 1,
    ps2_mousedat_out: 1,
    ps2_reset_n: 1,
    uart1_tx: 1,
    uart1_rts_n: 1,
    uart1_dtr_n: 1,
    uart2_tx: 1,
    uart2_rts_n: 1,
    uart2_dtr_n: 1,
    mpu_tx: 1,
    sample_sb_l: 16,
    sample_sb_r: 16,
    sample_opl_l: 16,
    sample_opl_r: 16,
    speaker_out: 1,
    vol_l: 5,
    vol_r: 5,
    vol_spk: 2,
    vol_en: 5,
    video_ce: 1,
    video_blank_n: 1,
    video_hsync: 1,
    video_vsync: 1,
    video_r: 8,
    video_g: 8,
    video_b: 8,
    video_pal_a: 8,
    video_pal_d: 18,
    video_pal_we: 1,
    video_start_addr: 20,
    video_width: 9,
    video_height: 11,
    video_flags: 4,
    video_stride: 9,
    video_off: 1,
    DDRAM_BURSTCNT: 8,
    DDRAM_ADDR: 25,
    DDRAM_RD: 1,
    DDRAM_DIN: 64,
    DDRAM_BE: 8,
    DDRAM_WE: 1
  }.freeze

  def diagnostic_summary(result)
    lines = []
    diagnostics = result.respond_to?(:diagnostics) ? Array(result.diagnostics) : []
    lines.concat(diagnostics)
    extra_raise = result.respond_to?(:raise_diagnostics) ? Array(result.raise_diagnostics) : []
    extra_raise.each do |diag|
      lines << "[#{diag.severity}]#{diag.op ? " #{diag.op}:" : ''} #{diag.message}"
    end
    lines.join("\n")
  end

  def base_inputs
    INPUT_WIDTHS.each_with_object({}) { |(name, _), acc| acc[name] = 0 }.merge(
      ps2_kbclk_in: 1,
      ps2_kbdat_in: 1,
      ps2_mouseclk_in: 1,
      ps2_mousedat_in: 1,
      uart1_rx: 1,
      uart1_cts_n: 1,
      uart1_dcd_n: 1,
      uart1_dsr_n: 1,
      uart2_rx: 1,
      uart2_cts_n: 1,
      uart2_dcd_n: 1,
      uart2_dsr_n: 1,
      mpu_rx: 1
    )
  end

  def vectors
    defaults = base_inputs
    [
      defaults.merge(reset: 1, clk_sys: 0),
      defaults.merge(reset: 1, clk_sys: 1),
      defaults.merge(reset: 1, clk_sys: 0),
      defaults.merge(reset: 0, clk_sys: 1, mgmt_address: 0xF000, mgmt_read: 1, bootcfg: 0x3F, clock_rate: 12_345,
                     clock_rate_vga: 54_321),
      defaults.merge(reset: 0, clk_sys: 0, mgmt_address: 0xF000, mgmt_read: 1, bootcfg: 0x3F, clock_rate: 12_345,
                     clock_rate_vga: 54_321),
      defaults.merge(reset: 0, clk_sys: 1, mgmt_address: 0xF000, mgmt_read: 1, bootcfg: 0x3F, clock_rate: 12_345,
                     clock_rate_vga: 54_321, video_fb_en: 1, video_lores: 1, DDRAM_DOUT: 0x1234_5678_9ABC_DEF0),
      defaults.merge(reset: 0, clk_sys: 0, mgmt_address: 0xF000, mgmt_read: 1, bootcfg: 0x3F, clock_rate: 12_345,
                     clock_rate_vga: 54_321, l1_disable: 1, l2_disable: 1),
      defaults.merge(reset: 0, clk_sys: 1, mgmt_address: 0xF000, mgmt_read: 1, bootcfg: 0x3F, clock_rate: 12_345,
                     clock_rate_vga: 54_321, l1_disable: 1, l2_disable: 1, video_fb_en: 1, video_lores: 1,
                     DDRAM_DOUT_READY: 1)
    ]
  end

  def run_importer(out_dir:, workspace:)
    RHDL::Examples::AO486::Import::SystemImporter.new(
      output_dir: out_dir,
      workspace_dir: workspace,
      keep_workspace: true
    ).run
  end

  def normalize(value, width)
    mask = width >= 64 ? ((1 << 64) - 1) : ((1 << width) - 1)
    value.to_i & mask
  end

  def parse_trace(stdout)
    stdout.lines.filter_map do |line|
      next unless line.start_with?('sample ')

      fields = line.strip.split(' ')
      pairs = fields.drop(2)
      sample = {}
      pairs.each do |pair|
        key, value = pair.split('=')
        sample[key.to_sym] = value.to_i
      end
      sample
    end
  end

  def verilator_cpp_for_vectors
    output_formats = OUTPUT_WIDTHS.keys.map { |name| "#{name}=%llu" }.join(' ')
    output_values = OUTPUT_WIDTHS.keys.map { |name| "(unsigned long long)dut->#{name}" }.join(",\n      ")

    cases = vectors.each_with_index.map do |vector, idx|
      assigns = INPUT_WIDTHS.keys.map do |name|
        value = normalize(vector.fetch(name), INPUT_WIDTHS.fetch(name))
        "      dut->#{name} = #{value}ULL;"
      end.join("\n")

      <<~CPP
        case #{idx}:
#{assigns}
          break;
      CPP
    end.join("\n")

    <<~CPP
      #include "Vsystem.h"
      #include "verilated.h"
      #include <cstdio>

      static void apply_vector(Vsystem* dut, int idx) {
        switch (idx) {
      #{cases}
          default:
            break;
        }
      }

      static void print_outputs(Vsystem* dut, int idx) {
        std::printf("sample %d #{output_formats}\\n", idx,
          #{output_values});
      }

      int main(int argc, char** argv) {
        Verilated::commandArgs(argc, argv);
        Vsystem* dut = new Vsystem();

        const int sample_count = #{vectors.length};
        for (int i = 0; i < sample_count; ++i) {
          apply_vector(dut, i);
          dut->eval();
          print_outputs(dut, i);
        }

        dut->final();
        delete dut;
        return 0;
      }
    CPP
  end

  def run_verilator_trace(wrapper_path:, workspace:)
    obj_dir = File.join(workspace, 'obj_dir')
    cpp_path = File.join(workspace, 'parity_tb.cpp')

    File.write(cpp_path, verilator_cpp_for_vectors)

    verilator_cmd = [
      'verilator',
      '--cc',
      '--top-module', 'system',
      '--x-assign', '0',
      '--x-initial', '0',
      '-Wno-fatal',
      '-Wno-UNOPTFLAT',
      '-Wno-PINMISSING',
      '-Wno-WIDTHEXPAND',
      '-Wno-WIDTHTRUNC',
      '--Mdir', obj_dir,
      wrapper_path,
      '--exe', cpp_path
    ]
    stdout, stderr, status = Open3.capture3(*verilator_cmd)
    expect(status.success?).to be(true), "Verilator compile failed:\n#{stdout}\n#{stderr}"

    make_stdout, make_stderr, make_status = Open3.capture3('make', '-C', obj_dir, '-f', 'Vsystem.mk')
    expect(make_status.success?).to be(true), "Verilator make failed:\n#{make_stdout}\n#{make_stderr}"

    bin_path = File.join(obj_dir, 'Vsystem')
    run_stdout, run_stderr, run_status = Open3.capture3(bin_path)
    expect(run_status.success?).to be(true), "Verilator run failed:\n#{run_stdout}\n#{run_stderr}"

    parse_trace(run_stdout).map do |sample|
      OUTPUT_WIDTHS.each_with_object({}) do |(name, width), acc|
        acc[name] = normalize(sample.fetch(name), width)
      end
    end
  end

  def run_ir_trace(normalized_mlir_path:)
    backend = AO486SpecSupport::IRBackendHelper.preferred_ir_backend
    raise 'IR compiler/JIT backend unavailable' unless backend

    run_ir_trace_with_backend(normalized_mlir_path: normalized_mlir_path, backend: backend)
  end

  def run_ir_trace_with_backend(normalized_mlir_path:, backend:)
    raised = RHDL::Codegen.raise_circt_components(
      File.read(normalized_mlir_path),
      namespace: Module.new,
      top: 'system'
    )
    expect(raised.success?).to be(true), diagnostic_summary(raised)

    system_component = raised.components.fetch('system')
    ir_nodes = system_component.to_flat_circt_nodes(top_name: 'system')
    ir_json = RHDL::Sim::Native::IR.sim_json(ir_nodes, backend: backend)
    sim = RHDL::Sim::Native::IR::Simulator.new(ir_json, backend: backend)

    vectors.map do |vector|
      INPUT_WIDTHS.each_key do |name|
        sim.poke(name.to_s, normalize(vector.fetch(name), INPUT_WIDTHS.fetch(name)))
      end

      if normalize(vector.fetch(:clk_sys), 1) == 1
        sim.tick
      else
        sim.evaluate
      end

      OUTPUT_WIDTHS.each_with_object({}) do |(name, width), acc|
        acc[name] = normalize(sim.peek(name.to_s), width)
      end
    end
  end

  def available_ir_backends
    AO486SpecSupport::IRBackendHelper.preferred_ir_backends
  end

  it 'matches source Verilog (Verilator) and raised RHDL on the selected IR backend for bounded stub-safe signals',
     timeout: 600 do
    skip 'circt-verilog not available' unless HdlToolchain.which('circt-verilog')
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'verilator not available' unless HdlToolchain.verilator_available?
    skip 'IR compiler/JIT backend unavailable' if available_ir_backends.empty?

    Dir.mktmpdir('ao486_parity_out') do |out_dir|
      Dir.mktmpdir('ao486_parity_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        expect(result.success?).to be(true), diagnostic_summary(result)

        strategy = result.respond_to?(:strategy_used) && result.strategy_used ? result.strategy_used : :stubbed
        wrapper_path = File.join(workspace, "import_all.#{strategy}.sv")
        wrapper_path = File.join(workspace, 'import_all.sv') unless File.exist?(wrapper_path)
        expect(File.exist?(wrapper_path)).to be(true)

        source_trace = run_verilator_trace(wrapper_path: wrapper_path, workspace: workspace)
        available_ir_backends.each do |backend|
          target_trace = run_ir_trace_with_backend(
            normalized_mlir_path: result.normalized_core_mlir_path,
            backend: backend
          )
          expect(source_trace).to eq(target_trace), "Parity mismatch for backend=#{backend}"
        end
      end
    end
  end
end
