# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require_relative '../../../../examples/gameboy/utilities/runners/verilator_runner'
require_relative '../../../../examples/gameboy/utilities/clock_enable_waveform'

RSpec.describe RHDL::Examples::GameBoy::VerilogRunner do
  let(:runner) { described_class.allocate }
  let(:minimal_gb_module) do
    <<~VERILOG
      module gb(
        input wire clk_sys,
        input wire reset,
        input wire ce,
        input wire ce_n,
        input wire ce_2x,
        input wire [7:0] joystick,
        input wire isGBC,
        input wire real_cgb_boot,
        input wire isSGB,
        input wire extra_spr_en,
        output wire [14:0] ext_bus_addr,
        output wire ext_bus_a15,
        output wire cart_rd,
        output wire cart_wr,
        input wire [7:0] cart_do,
        output wire [7:0] cart_di,
        input wire cart_oe,
        input wire cgb_boot_download,
        input wire dmg_boot_download,
        input wire sgb_boot_download,
        input wire ioctl_wr,
        input wire [24:0] ioctl_addr,
        input wire [15:0] ioctl_dout,
        input wire boot_gba_en,
        input wire fast_boot_en,
        input wire audio_no_pops,
        input wire megaduck,
        output wire lcd_clkena,
        output wire [14:0] lcd_data,
        output wire [1:0] lcd_data_gb,
        output wire [1:0] lcd_mode,
        output wire lcd_on,
        output wire lcd_vsync,
        output wire [15:0] audio_l,
        output wire [15:0] audio_r,
        output wire [1:0] joy_p54,
        input wire [3:0] joy_din,
        input wire gg_reset,
        input wire gg_en,
        input wire [128:0] gg_code,
        input wire serial_clk_in,
        input wire serial_data_in,
        input wire increaseSSHeaderCount,
        input wire [7:0] cart_ram_size,
        input wire save_state,
        input wire load_state,
        input wire [1:0] savestate_number,
        input wire [63:0] SaveStateExt_Dout,
        input wire [7:0] Savestate_CRAMReadData,
        input wire [63:0] SAVE_out_Dout,
        input wire SAVE_out_done,
        input wire rewind_on,
        input wire rewind_active
      );
      endmodule
    VERILOG
  end
  let(:minimal_speedcontrol_module) do
    <<~VERILOG
      module speedcontrol(
        input wire clk_sys,
        input wire pause,
        input wire speedup,
        input wire cart_act,
        input wire DMA_on,
        output wire ce,
        output wire ce_n,
        output wire ce_2x
      );
        assign ce = 1'b0;
        assign ce_n = 1'b0;
        assign ce_2x = 1'b0;
      endmodule
    VERILOG
  end

  describe '#runtime_staged_verilog_entry' do
    it 'does not use staged mixed verilog unless explicitly enabled' do
      Dir.mktmpdir('rhdl_gb_staged') do |dir|
        staged = File.join(dir, '.mixed_import', 'pure_verilog_entry.v')
        FileUtils.mkdir_p(File.dirname(staged))
        File.write(staged, '// staged')

        runner.instance_variable_set(:@resolved_hdl_dir, dir)
        runner.instance_variable_set(:@use_staged_verilog, false)
        expect(runner.send(:runtime_staged_verilog_entry)).to be_nil
      end
    end

    it 'uses staged mixed verilog when explicitly enabled' do
      Dir.mktmpdir('rhdl_gb_staged') do |dir|
        staged = File.join(dir, '.mixed_import', 'pure_verilog_entry.v')
        FileUtils.mkdir_p(File.dirname(staged))
        File.write(staged, '// staged')

        runner.instance_variable_set(:@resolved_hdl_dir, dir)
        runner.instance_variable_set(:@use_staged_verilog, true)
        runner.instance_variable_set(:@import_top_name, 'gb')
        runner.instance_variable_set(:@top_module_name, 'gb')
        expect(runner.send(:runtime_staged_verilog_entry)).to eq(staged)
      end
    end

    it 'prefers normalized verilog from import report when present' do
      Dir.mktmpdir('rhdl_gb_staged') do |dir|
        runtime = File.join(dir, '.mixed_import', 'gb.normalized.v')
        staged = File.join(dir, '.mixed_import', 'pure_verilog_entry.v')
        FileUtils.mkdir_p(File.dirname(runtime))
        File.write(runtime, '// runtime')
        File.write(staged, '// staged')
        File.write(
          File.join(dir, 'import_report.json'),
          JSON.pretty_generate(
            'artifacts' => {
              'normalized_verilog_path' => runtime,
              'pure_verilog_entry_path' => staged
            },
            'mixed_import' => {
              'normalized_verilog_path' => runtime,
              'pure_verilog_entry_path' => staged
            }
          )
        )

        runner.instance_variable_set(:@resolved_hdl_dir, dir)
        runner.instance_variable_set(:@use_staged_verilog, true)
        runner.instance_variable_set(:@import_top_name, 'gb')
        runner.instance_variable_set(:@top_module_name, 'gb')
        expect(runner.send(:runtime_staged_verilog_entry)).to eq(runtime)
      end
    end

    it 'does not use staged core verilog when the selected top is the import wrapper' do
      Dir.mktmpdir('rhdl_gb_staged') do |dir|
        runtime = File.join(dir, '.mixed_import', 'gb.normalized.v')
        FileUtils.mkdir_p(File.dirname(runtime))
        File.write(runtime, '// runtime')

        runner.instance_variable_set(:@resolved_hdl_dir, dir)
        runner.instance_variable_set(:@use_staged_verilog, true)
        runner.instance_variable_set(:@import_top_name, 'Gameboy')
        runner.instance_variable_set(:@top_module_name, 'gameboy')

        expect(runner.send(:runtime_staged_verilog_entry)).to be_nil
      end
    end
  end

  describe '#resolve_direct_verilog_source_plan' do
    it 'uses normalized imported verilog and builds a generated wrapper top' do
      Dir.mktmpdir('rhdl_gb_direct_verilog') do |dir|
        mixed_dir = File.join(dir, '.mixed_import')
        FileUtils.mkdir_p(mixed_dir)
        normalized = File.join(mixed_dir, 'gb.normalized.v')
        speedcontrol = File.join(mixed_dir, 'speedcontrol.v')
        File.write(normalized, minimal_gb_module)
        File.write(speedcontrol, minimal_speedcontrol_module)
        File.write(
          File.join(dir, 'import_report.json'),
          JSON.pretty_generate(
            'mixed_import' => {
              'normalized_verilog_path' => normalized,
              'vhdl_synth_outputs' => [
                { 'entity' => 'speedcontrol', 'module_name' => 'speedcontrol', 'output_path' => speedcontrol }
              ]
            },
            'components' => [
              { 'verilog_module_name' => 'speedcontrol', 'module_name' => 'speedcontrol', 'staged_verilog_path' => speedcontrol }
            ]
          )
        )

        plan = runner.send(
          :resolve_direct_verilog_source_plan,
          verilog_dir: dir,
          top: 'Gameboy',
          use_staged_verilog: false
        )

        expect(plan[:source_verilog_path]).to eq(normalized)
        expect(plan[:core_verilog_path]).to eq(normalized)
        expect(plan[:top_module_name]).to eq('gameboy')
        expect(plan[:support_modules]).to include('speedcontrol')
        expect(plan[:support_verilog_paths]).to include(speedcontrol)
        expect(plan[:dependency_paths]).to include(speedcontrol)
        expect(plan[:wrapper_source]).to include('speedcontrol speed_ctrl')
        expect(plan[:wrapper_source]).to include(".pause(1'b0)")
        expect(plan[:wrapper_source]).to include(".speedup(1'b0)")
        expect(plan[:wrapper_source]).to include(".DMA_on(1'b0)")
        expect(plan[:wrapper_source]).to include(".cart_oe(1'b1)")
        expect(plan[:wrapper_source]).to include(".cart_ram_size(8'd0)")
        expect(plan[:wrapper_source]).to include(".fast_boot_en(1'b0)")
        expect(plan[:wrapper_source]).to include(".gg_reset(1'b0)")
        expect(plan[:wrapper_source]).to include(".serial_data_in(1'b1)")
        expect(plan[:wrapper_source]).to include(".increaseSSHeaderCount(1'b0)")
        expect(plan[:wrapper_source]).to include('module gameboy')
        expect(plan[:port_declarations]).to include(
          include(direction: :in, name: 'boot_rom_do', width: 8),
          include(direction: :out, name: 'lcd_vsync', width: 1)
        )
        expect(plan[:port_declarations]).not_to include(include(name: 'cart_oe'))
        expect(plan[:port_declarations]).not_to include(include(name: 'cart_ram_size'))
        expect(plan[:port_declarations]).not_to include(include(name: 'ce'))
      end
    end

    it 'uses the staged entry artifact when requested and keeps the staged core file for wrapper profiling' do
      Dir.mktmpdir('rhdl_gb_direct_verilog_staged') do |dir|
        staged_root = File.join(dir, '.mixed_import', 'pure_verilog', 'rtl')
        generated_vhdl_root = File.join(dir, '.mixed_import', 'pure_verilog', 'generated_vhdl')
        FileUtils.mkdir_p(staged_root)
        FileUtils.mkdir_p(generated_vhdl_root)
        staged_gb = File.join(staged_root, 'gb.v')
        speedcontrol = File.join(generated_vhdl_root, 'speedcontrol.v')
        staged_entry = File.join(dir, '.mixed_import', 'pure_verilog_entry.v')
        File.write(staged_gb, minimal_gb_module)
        File.write(speedcontrol, minimal_speedcontrol_module)
        File.write(staged_entry, "`include \"#{staged_gb}\"\n`include \"#{speedcontrol}\"\n")
        File.write(
          File.join(dir, 'import_report.json'),
          JSON.pretty_generate(
            'mixed_import' => {
              'pure_verilog_entry_path' => staged_entry,
              'top_file' => staged_gb,
              'pure_verilog_root' => File.dirname(staged_root)
            },
            'components' => [
              { 'verilog_module_name' => 'speedcontrol', 'module_name' => 'speedcontrol', 'staged_verilog_path' => speedcontrol }
            ]
          )
        )

        plan = runner.send(
          :resolve_direct_verilog_source_plan,
          verilog_dir: dir,
          top: 'Gameboy',
          use_staged_verilog: true
        )

        expect(plan[:source_verilog_path]).to eq(staged_entry)
        expect(plan[:core_verilog_path]).to eq(staged_gb)
        expect(plan[:top_module_name]).to eq('gameboy')
        expect(plan[:dependency_paths]).to include(staged_entry, staged_gb, speedcontrol)
        expect(plan[:support_modules]).to include('speedcontrol')
        expect(plan[:support_verilog_paths]).to be_empty
        expect(plan[:wrapper_source]).to include('speedcontrol speed_ctrl')
        expect(plan[:wrapper_source]).to include(".pause(1'b0)")
        expect(plan[:wrapper_source]).to include(".speedup(1'b0)")
        expect(plan[:wrapper_source]).to include(".DMA_on(1'b0)")
        expect(plan[:wrapper_source]).to include(".cart_oe(1'b1)")
        expect(plan[:wrapper_source]).to include(".cart_ram_size(8'd0)")
        expect(plan[:wrapper_source]).to include(".fast_boot_en(1'b0)")
        expect(plan[:wrapper_source]).to include(".gg_reset(1'b0)")
        expect(plan[:wrapper_source]).to include(".serial_data_in(1'b1)")
        expect(plan[:wrapper_source]).to include(".increaseSSHeaderCount(1'b0)")
      end
    end

    it 'falls back to a raw Verilog tree when no normalized artifact is present' do
      Dir.mktmpdir('rhdl_gb_direct_raw_verilog') do |dir|
        rtl_dir = File.join(dir, 'rtl')
        FileUtils.mkdir_p(rtl_dir)
        top_file = File.join(rtl_dir, 'system_top.sv')
        helper_file = File.join(rtl_dir, 'helper.v')
        File.write(top_file, minimal_gb_module.sub('module gb(', 'module gb('))
        File.write(helper_file, "module helper; endmodule\n")

        plan = runner.send(
          :resolve_direct_verilog_source_plan,
          verilog_dir: dir,
          top: 'gb',
          use_staged_verilog: false
        )

        expect(plan[:source_verilog_path]).to eq(top_file)
        expect(plan[:core_verilog_path]).to eq(top_file)
        expect(plan[:top_module_name]).to eq('gb')
        expect(plan[:support_modules]).to be_empty
        expect(plan[:support_verilog_paths]).to include(helper_file)
        expect(plan[:dependency_paths]).to include(top_file, helper_file)
        expect(plan[:wrapper_source]).to be_nil
        expect(plan[:port_declarations]).to include(
          include(direction: :in, name: 'clk_sys', width: 1),
          include(direction: :out, name: 'lcd_vsync', width: 1)
        )
      end
    end

    it 'maps the generated wrapper top back to raw gb sources when using a raw Verilog tree' do
      Dir.mktmpdir('rhdl_gb_direct_raw_wrapper') do |dir|
        rtl_dir = File.join(dir, 'rtl')
        FileUtils.mkdir_p(rtl_dir)
        top_file = File.join(rtl_dir, 'system_top.sv')
        speedcontrol = File.join(rtl_dir, 'speedcontrol.v')
        File.write(top_file, minimal_gb_module)
        File.write(speedcontrol, minimal_speedcontrol_module)

        plan = runner.send(
          :resolve_direct_verilog_source_plan,
          verilog_dir: dir,
          top: 'Gameboy',
          use_staged_verilog: false
        )

        expect(plan[:source_verilog_path]).to eq(top_file)
        expect(plan[:core_verilog_path]).to eq(top_file)
        expect(plan[:top_module_name]).to eq('gameboy')
        expect(plan[:support_verilog_paths]).to include(speedcontrol)
        expect(plan[:wrapper_source]).to include('module gameboy')
      end
    end
  end

  describe '#default_import_top_name' do
    it 'reads the generated wrapper class name from the import report' do
      Dir.mktmpdir('rhdl_gb_import_report') do |dir|
        File.write(
          File.join(dir, 'import_report.json'),
          JSON.pretty_generate(
            'import_wrapper' => {
              'class_name' => 'Gameboy'
            }
          )
        )

        expect(runner.send(:default_import_top_name, resolved_hdl_dir: dir)).to eq('Gameboy')
      end
    end
  end

  describe '#build_artifact_stem' do
    it 'varies by resolved HDL directory even for the same top module' do
      Dir.mktmpdir('rhdl_gb_hdl_a') do |dir_a|
        Dir.mktmpdir('rhdl_gb_hdl_b') do |dir_b|
          runner_a = described_class.allocate
          runner_b = described_class.allocate

          runner_a.instance_variable_set(:@top_module_name, 'game_boy_gameboy')
          runner_a.instance_variable_set(:@resolved_hdl_dir, dir_a)
          runner_a.instance_variable_set(:@import_top_name, nil)
          runner_a.instance_variable_set(:@use_staged_verilog, false)

          runner_b.instance_variable_set(:@top_module_name, 'game_boy_gameboy')
          runner_b.instance_variable_set(:@resolved_hdl_dir, dir_b)
          runner_b.instance_variable_set(:@import_top_name, nil)
          runner_b.instance_variable_set(:@use_staged_verilog, false)

          expect(runner_a.send(:build_artifact_stem)).not_to eq(runner_b.send(:build_artifact_stem))
        end
      end
    end

    it 'varies when staged mixed Verilog is enabled' do
      Dir.mktmpdir('rhdl_gb_staged_stem') do |dir|
        staged = File.join(dir, '.mixed_import', 'pure_verilog_entry.v')
        FileUtils.mkdir_p(File.dirname(staged))
        File.write(staged, '// staged')

        generated_runner = described_class.allocate
        staged_runner = described_class.allocate

        generated_runner.instance_variable_set(:@top_module_name, 'gb')
        generated_runner.instance_variable_set(:@resolved_hdl_dir, dir)
        generated_runner.instance_variable_set(:@import_top_name, 'gb')
        generated_runner.instance_variable_set(:@use_staged_verilog, false)

        staged_runner.instance_variable_set(:@top_module_name, 'gb')
        staged_runner.instance_variable_set(:@resolved_hdl_dir, dir)
        staged_runner.instance_variable_set(:@import_top_name, 'gb')
        staged_runner.instance_variable_set(:@use_staged_verilog, true)

        expect(generated_runner.send(:build_artifact_stem)).not_to eq(staged_runner.send(:build_artifact_stem))
      end
    end
  end

  describe '#c_cart_feed_lines' do
    before do
      allow(runner).to receive(:resolve_port_name).with('ext_bus_addr').and_return('ext_bus_addr')
      allow(runner).to receive(:resolve_port_name).with('ext_bus_a15').and_return('ext_bus_a15')
      allow(runner).to receive(:resolve_port_name).with('cart_do').and_return('cart_do')
      allow(runner).to receive(:resolve_port_name).with('cart_oe').and_return('cart_oe')
      allow(runner).to receive(:resolve_port_name).with('cart_wr').and_return('cart_wr')
      allow(runner).to receive(:resolve_port_name).with('cart_di').and_return('cart_di')
      allow(runner).to receive(:resolve_port_name).with('cart_rd').and_return('cart_rd')
    end

    it 'keeps the delayed cartridge pipeline for direct verilog runs' do
      runner.instance_variable_set(:@direct_verilog_source_plan, { resolved_root: '/tmp/import' })

      lines = runner.send(:c_cart_feed_lines, indent: '  ')

      expect(lines).to include('unsigned int read_active = ctx->dut->cart_rd ? 1u : 0u;')
      expect(lines).to include('ctx->dut->cart_do = read_active ? cart_read_byte(ctx, full_addr) : 0xFFu;')
      expect(lines).to include('ctx->dut->cart_oe = 1u;')
      expect(lines).not_to include('ctx->dut->cart_do = ctx->cart_do_latched;')
    end

    it 'drives the delayed cartridge latch for generated HDL runs' do
      runner.instance_variable_set(:@direct_verilog_source_plan, nil)

      lines = runner.send(:c_cart_feed_lines, indent: '  ')

      expect(lines).to include('ctx->dut->cart_do = ctx->cart_do_latched;')
      expect(lines).to include('ctx->dut->cart_oe = 1u;')
      expect(lines).to include('ctx->cart_last_rd = ctx->dut->cart_rd ? 1u : 0u;')
    end
  end

  describe '#initialize_inputs' do
    it 'matches the minimal wrapper tie-offs for cart_oe and savestate header count' do
      pokes = []

      runner.instance_variable_set(:@sim_ctx, Object.new)
      runner.instance_variable_set(
        :@input_port_aliases,
        {
          'cart_oe' => 'cart_oe',
          'increaseSSHeaderCount' => 'increaseSSHeaderCount'
        }
      )
      runner.instance_variable_set(:@cartridge, { ram_size_code: 0 })

      allow(runner).to receive(:verilator_poke) { |name, value| pokes << [name, value] }
      allow(runner).to receive(:verilator_eval)
      allow(runner).to receive(:update_joypad_input)
      allow(runner).to receive(:drive_clock_enable_inputs)

      runner.send(:initialize_inputs)

      expect(pokes).to include(['cart_oe', 1], ['increaseSSHeaderCount', 0])
    end
  end

  describe '#create_cpp_wrapper' do
    it 'keeps a delayed address pipeline in the native cartridge shim' do
      Dir.mktmpdir('rhdl_gb_cpp_wrapper') do |dir|
        header = File.join(dir, 'sim_wrapper.h')
        cpp = File.join(dir, 'sim_wrapper.cpp')

        runner.instance_variable_set(:@verilator_prefix, 'Vgb')
        runner.instance_variable_set(:@top_module_name, 'gb')
        runner.instance_variable_set(:@output_port_aliases, {})
        runner.instance_variable_set(:@input_port_aliases, {})

        allow(runner).to receive(:resolve_port_name).and_return(nil)
        allow(runner).to receive(:write_file_if_changed) { |path, content| File.write(path, content) }

        runner.send(:create_cpp_wrapper, cpp, header)

        source = File.read(cpp)
        expect(source).to include('ctx->cart_read_pipeline[0] = ctx->cart_last_full_addr;')
        expect(source).to include('ctx->cart_read_valid[0] = ctx->cart_last_rd;')
        expect(source).to include('ctx->cart_do_latched = cart_read_byte(ctx, ctx->cart_read_pipeline[5]);')
      end
    end
  end

  describe '#c_peek_dispatch_lines' do
    it 'does not assume generated gb internal nets for direct verilog tops' do
      runner.instance_variable_set(:@top_module_name, 'gb')
      runner.instance_variable_set(:@direct_verilog_source_plan, { resolved_root: '/tmp/import' })
      runner.instance_variable_set(:@output_port_aliases, {})

      lines = runner.send(:c_peek_dispatch_lines)

      expect(lines).to include('strcmp(name, "cpu_pc_internal") == 0')
      expect(lines).not_to include('rootp->gb__DOT___cpu_A')
      expect(lines).not_to include('rootp->gb__DOT__rt_tmp_22_1')
    end

    it 'uses normalized imported gb internals when the direct verilog source is normalized' do
      runner.instance_variable_set(:@top_module_name, 'gb')
      runner.instance_variable_set(
        :@direct_verilog_source_plan,
        {
          resolved_root: '/tmp/import',
          source_verilog_path: '/tmp/import/.mixed_import/gb.normalized.v'
        }
      )
      runner.instance_variable_set(:@output_port_aliases, {})

      lines = runner.send(:c_peek_dispatch_lines)

      expect(lines).to include('strcmp(name, "cpu_pc_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__pc;')
      expect(lines).to include('strcmp(name, "cpu_addr_internal") == 0) return ctx->dut->rootp->gb__DOT___md_swizz_a_out;')
      expect(lines).to include('strcmp(name, "cpu_addr_raw_internal") == 0) return ctx->dut->rootp->gb__DOT___cpu_A;')
      expect(lines).to include('strcmp(name, "cpu_di_reg_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__di_reg;')
      expect(lines).to include('strcmp(name, "cpu_t80_di_reg_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__di_reg;')
      expect(lines).to include('strcmp(name, "cpu_set_addr_to_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__set_addr_to;')
      expect(lines).to include('strcmp(name, "cpu_iorq_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__iorq_i;')
      expect(lines).to include('strcmp(name, "cpu_mcycle_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__mcycle;')
      expect(lines).to include('strcmp(name, "cpu_tstate_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__tstate;')
      expect(lines).to include('strcmp(name, "cpu_save_mux_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__save_mux;')
      expect(lines).to include('strcmp(name, "cpu_save_alu_r_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__save_alu_r;')
      expect(lines).to include('strcmp(name, "cpu_clken_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__clken;')
      expect(lines).to include('strcmp(name, "cpu_regdih_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regdih;')
      expect(lines).to include('strcmp(name, "cpu_regdil_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regdil;')
      expect(lines).to include('strcmp(name, "cpu_regweh_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regweh;')
      expect(lines).to include('strcmp(name, "cpu_regwel_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regwel;')
      expect(lines).to include('strcmp(name, "cpu_regaddra_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regaddra;')
      expect(lines).to include('strcmp(name, "cpu_regbusa_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regbusa;')
      expect(lines).to include('strcmp(name, "cpu_regbusc_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__regbusc;')
      expect(lines).to include('strcmp(name, "cpu_tmpaddr_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__tmpaddr;')
      expect(lines).to include('strcmp(name, "cpu_id16_internal") == 0) return ctx->dut->rootp->gb__DOT__cpu__DOT__u0__DOT__id16;')
      expect(lines).to include('strcmp(name, "boot_rom_enabled_internal") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_22_1;')
      expect(lines).to include('strcmp(name, "cpu_do_internal") == 0) return ctx->dut->rootp->gb__DOT___cpu_DO;')
      expect(lines).to include('strcmp(name, "cpu_wr_n_internal") == 0) return ctx->dut->rootp->gb__DOT___cpu_WR_n;')
      expect(lines).to include('strcmp(name, "cpu_rd_n_internal") == 0) return ctx->dut->rootp->gb__DOT___cpu_RD_n;')
      expect(lines).to include('strcmp(name, "interrupt_flags_internal") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_11_8;')
      expect(lines).to include('strcmp(name, "old_vblank_irq_internal") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_13_1;')
      expect(lines).to include('strcmp(name, "old_video_irq_internal") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_14_1;')
      expect(lines).to include('strcmp(name, "old_timer_irq_internal") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_15_1;')
      expect(lines).to include('strcmp(name, "old_serial_irq_internal") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_16_1;')
      expect(lines).to include('strcmp(name, "old_ack_internal") == 0) return ctx->dut->rootp->gb__DOT__rt_tmp_17_1;')
      expect(lines).to include('strcmp(name, "irq_ack_internal") == 0) return (~ctx->dut->rootp->gb__DOT___cpu_IORQ_n & ~ctx->dut->rootp->gb__DOT___cpu_M1_n) ? 1u : 0u;')
      expect(lines).to include('strcmp(name, "video_vblank_irq_internal") == 0) return ctx->dut->rootp->gb__DOT___video_vblank_irq;')
      expect(lines).to include('strcmp(name, "sel_ff50_internal") == 0) return ctx->dut->rootp->gb__DOT___md_swizz_a_out == 0xFF50u ? 1u : 0u;')
      expect(lines).to include('strcmp(name, "savestate_reset_out_internal") == 0) return ctx->dut->rootp->gb__DOT___gb_savestates_reset_out;')
      expect(lines).to include('strcmp(name, "request_loadstate_internal") == 0) return ctx->dut->rootp->gb__DOT___gb_statemanager_request_loadstate;')
      expect(lines).to include('strcmp(name, "request_savestate_internal") == 0) return ctx->dut->rootp->gb__DOT___gb_statemanager_request_savestate;')
      expect(lines).to include('strcmp(name, "video_lcd_on_internal") == 0) return ctx->dut->rootp->gb__DOT__video__DOT__lcd_on;')
      expect(lines).to include('strcmp(name, "video_lcd_clkena_internal") == 0) return ctx->dut->rootp->gb__DOT__video__DOT__lcd_clkena;')
      expect(lines).to include('strcmp(name, "video_lcd_vsync_internal") == 0) return ctx->dut->rootp->gb__DOT__video__DOT__lcd_vsync;')
      expect(lines).to include('strcmp(name, "video_mode_internal") == 0) return ctx->dut->rootp->gb__DOT___video_mode;')
    end

    it 'uses wrapped gb_core internals for direct gameboy wrapper tops' do
      runner.instance_variable_set(:@top_module_name, 'gameboy')
      runner.instance_variable_set(
        :@direct_verilog_source_plan,
        {
          resolved_root: '/tmp/import',
          source_verilog_path: '/tmp/import/.mixed_import/gb.normalized.v'
        }
      )
      runner.instance_variable_set(:@output_port_aliases, {})

      lines = runner.send(:c_peek_dispatch_lines)

      expect(lines).to include('strcmp(name, "cpu_pc_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__pc;')
      expect(lines).to include('strcmp(name, "cpu_addr_raw_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___cpu_A;')
      expect(lines).to include('strcmp(name, "cpu_di_reg_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__di_reg;')
      expect(lines).to include('strcmp(name, "cpu_t80_di_reg_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__di_reg;')
      expect(lines).to include('strcmp(name, "cpu_set_addr_to_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__set_addr_to;')
      expect(lines).to include('strcmp(name, "cpu_iorq_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__iorq_i;')
      expect(lines).to include('strcmp(name, "cpu_mcycle_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__mcycle;')
      expect(lines).to include('strcmp(name, "cpu_tstate_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__tstate;')
      expect(lines).to include('strcmp(name, "cpu_regbusc_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__regbusc;')
      expect(lines).to include('strcmp(name, "cpu_tmpaddr_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__tmpaddr;')
      expect(lines).to include('strcmp(name, "boot_rom_enabled_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__rt_tmp_22_1;')
      expect(lines).to include('strcmp(name, "interrupt_flags_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__rt_tmp_11_8;')
      expect(lines).to include('strcmp(name, "old_vblank_irq_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__rt_tmp_13_1;')
      expect(lines).to include('strcmp(name, "old_video_irq_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__rt_tmp_14_1;')
      expect(lines).to include('strcmp(name, "old_timer_irq_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__rt_tmp_15_1;')
      expect(lines).to include('strcmp(name, "old_serial_irq_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__rt_tmp_16_1;')
      expect(lines).to include('strcmp(name, "old_ack_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__rt_tmp_17_1;')
      expect(lines).to include('strcmp(name, "irq_ack_internal") == 0) return (~ctx->dut->rootp->gameboy__DOT__gb_core__DOT___cpu_IORQ_n & ~ctx->dut->rootp->gameboy__DOT__gb_core__DOT___cpu_M1_n) ? 1u : 0u;')
      expect(lines).to include('strcmp(name, "video_vblank_irq_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___video_vblank_irq;')
      expect(lines).to include('strcmp(name, "savestate_reset_out_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___gb_savestates_reset_out;')
      expect(lines).to include('strcmp(name, "request_loadstate_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT___gb_statemanager_request_loadstate;')
      expect(lines).to include('strcmp(name, "video_lcd_on_internal") == 0) return ctx->dut->rootp->gameboy__DOT__gb_core__DOT__video__DOT__lcd_on;')
      expect(lines).to include('strcmp(name, "ce_internal") == 0) return ctx->dut->rootp->gameboy__DOT__ce;')
      expect(lines).to include('strcmp(name, "boot_upload_active_internal") == 0) return ctx->dut->rootp->gameboy__DOT__boot_upload_active;')
    end

    it 'does not assume normalized wrapper internals for raw direct gameboy wrappers' do
      runner.instance_variable_set(:@top_module_name, 'gameboy')
      runner.instance_variable_set(
        :@direct_verilog_source_plan,
        {
          resolved_root: '/tmp/import',
          source_verilog_path: '/tmp/import/pure_verilog/rtl/gb.v'
        }
      )
      runner.instance_variable_set(:@output_port_aliases, {})

      lines = runner.send(:c_peek_dispatch_lines)

      expect(lines).not_to include('gameboy__DOT__gb_core__DOT___cpu_A')
      expect(lines).not_to include('gameboy__DOT__gb_core__DOT__cpu__DOT__u0__DOT__pc')
    end
  end

  describe '#cpu_state' do
    before do
      allow(runner).to receive(:verilator_peek).and_return(0)
      allow(runner).to receive(:debug_port_available?).with('debug_pc').and_return(true)
      allow(runner).to receive(:simulator_type).and_return(:hdl_verilator)
      runner.instance_variable_set(:@cycles, 500)
      runner.instance_variable_set(:@halted, false)
    end

    it 'falls back to bus pc when debug pc is zero' do
      allow(runner).to receive(:verilator_peek).with('debug_pc').and_return(0)
      allow(runner).to receive(:verilator_peek).with('ext_bus_a15').and_return(1)
      allow(runner).to receive(:verilator_peek).with('ext_bus_addr').and_return(0x1234)

      state = runner.send(:cpu_state)
      expect(state[:pc]).to eq(0x9234)
    end

    it 'prefers debug pc when it is non-zero' do
      allow(runner).to receive(:verilator_peek).with('debug_pc').and_return(0x00AA)
      allow(runner).to receive(:verilator_peek).with('ext_bus_a15').and_return(1)
      allow(runner).to receive(:verilator_peek).with('ext_bus_addr').and_return(0x1234)
      allow(runner).to receive(:verilator_peek).with('cpu_pc_internal').and_return(0xBEEF)

      state = runner.send(:cpu_state)
      expect(state[:pc]).to eq(0x00AA)
    end

    it 'falls back to internal imported cpu pc when debug and bus pc are zero' do
      allow(runner).to receive(:verilator_peek).with('debug_pc').and_return(0)
      allow(runner).to receive(:verilator_peek).with('ext_bus_a15').and_return(0)
      allow(runner).to receive(:verilator_peek).with('ext_bus_addr').and_return(0)
      allow(runner).to receive(:verilator_peek).with('cpu_pc_internal').and_return(0x00C7)

      state = runner.send(:cpu_state)
      expect(state[:pc]).to eq(0x00C7)
    end

    it 'falls back to internal imported cpu registers when debug outputs are zero' do
      allow(runner).to receive(:verilator_peek).with('debug_pc').and_return(0x1234)
      allow(runner).to receive(:verilator_peek).with('ext_bus_a15').and_return(0)
      allow(runner).to receive(:verilator_peek).with('ext_bus_addr').and_return(0)
      allow(runner).to receive(:verilator_peek).with('cpu_pc_internal').and_return(0x00C7)
      allow(runner).to receive(:verilator_peek).with('debug_acc').and_return(0)
      allow(runner).to receive(:verilator_peek).with('debug_f').and_return(0)
      allow(runner).to receive(:verilator_peek).with('debug_sp').and_return(0)
      allow(runner).to receive(:verilator_peek).with('debug_acc_internal').and_return(0x42)
      allow(runner).to receive(:verilator_peek).with('debug_f_internal').and_return(0xB0)
      allow(runner).to receive(:verilator_peek).with('debug_sp_internal').and_return(0xC001)

      state = runner.send(:cpu_state)
      expect(state[:a]).to eq(0x42)
      expect(state[:f]).to eq(0xB0)
      expect(state[:sp]).to eq(0xC001)
    end
  end

  describe 'clock enable waveform' do
    it 'matches the reference speedcontrol divider phases' do
      sequence = 8.times.map { |phase| RHDL::Examples::GameBoy::ClockEnableWaveform.values_for_phase(phase) }
      expect(sequence).to eq([
        { ce: 1, ce_n: 0, ce_2x: 1 },
        { ce: 0, ce_n: 0, ce_2x: 0 },
        { ce: 0, ce_n: 0, ce_2x: 0 },
        { ce: 0, ce_n: 0, ce_2x: 0 },
        { ce: 0, ce_n: 1, ce_2x: 1 },
        { ce: 0, ce_n: 0, ce_2x: 0 },
        { ce: 0, ce_n: 0, ce_2x: 0 },
        { ce: 0, ce_n: 0, ce_2x: 0 }
      ])
    end
  end

  describe '#c_constant_tieoff_lines' do
    it 'zeros wide imported gb tie-off inputs in the native wrapper' do
      runner.instance_variable_set(:@top_module_name, 'gb')
      allow(runner).to receive(:resolve_port_name).with('gg_code').and_return('gg_code')
      allow(runner).to receive(:resolve_port_name).with('SaveStateExt_Dout').and_return('SaveStateExt_Dout')
      allow(runner).to receive(:resolve_port_name).with('SAVE_out_Dout').and_return('SAVE_out_Dout')

      lines = runner.send(:c_constant_tieoff_lines, indent: '  ')

      expect(lines).to include('ctx->dut->gg_code[i] = 0u;')
      expect(lines).to include('ctx->dut->SaveStateExt_Dout = 0ULL;')
      expect(lines).to include('ctx->dut->SAVE_out_Dout = 0ULL;')
    end
  end

  describe 'cartridge mapping' do
    it 'maps MBC1 ROM bank writes into banked cartridge reads' do
      rom = Array.new(8 * 0x4000, 0)
      8.times do |bank|
        start = bank * 0x4000
        rom[start, 0x4000] = Array.new(0x4000, bank)
      end
      rom[0x147] = 0x01
      rom[0x148] = 0x02
      rom[0x149] = 0x00

      runner.instance_variable_set(:@rom, rom)
      runner.instance_variable_set(:@cartridge, runner.send(:cartridge_state_for_rom, rom))
      runner.send(:reset_cartridge_runtime_state!)

      expect(runner.send(:cartridge_read_byte, 0x0150)).to eq(0)
      expect(runner.send(:cartridge_read_byte, 0x4000)).to eq(1)

      runner.send(:handle_cartridge_write, 0x2000, 0x02)
      expect(runner.send(:cartridge_read_byte, 0x4000)).to eq(2)

      runner.send(:handle_cartridge_write, 0x2000, 0x00)
      expect(runner.send(:cartridge_read_byte, 0x4000)).to eq(1)
    end

    it 'falls back to flat ROM reads for ROM-only cartridges' do
      rom = Array.new(0x8000, 0)
      rom[0x147] = 0x00
      rom[0x148] = 0x00
      rom[0x149] = 0x00
      rom[0x0123] = 0xAA
      rom[0x4567] = 0xBB

      runner.instance_variable_set(:@rom, rom)
      runner.instance_variable_set(:@cartridge, runner.send(:cartridge_state_for_rom, rom))

      expect(runner.send(:cartridge_read_byte, 0x0123)).to eq(0xAA)
      expect(runner.send(:cartridge_read_byte, 0x4567)).to eq(0xBB)
    end
  end

  describe '#advance_cartridge_read_pipeline!' do
    it 'latches the current cartridge address once the external read delay expires' do
      rom = Array.new(0x8000, 0)
      rom[0x147] = 0x00
      rom[0x148] = 0x00
      rom[0x149] = 0x00
      rom[0x0100] = 0x00
      rom[0x0101] = 0xC3

      runner.instance_variable_set(:@rom, rom)
      runner.instance_variable_set(:@cartridge, runner.send(:cartridge_state_for_rom, rom))
      runner.send(:reset_cartridge_runtime_state!)

      cartridge = runner.instance_variable_get(:@cartridge)
      cartridge[:read_pipeline] = [true, true, true, true, true, true]
      cartridge[:last_rd] = true
      cartridge[:last_full_addr] = 0x0101

      runner.send(:advance_cartridge_read_pipeline!)

      expect(cartridge[:cart_do_latched]).to eq(0xC3)
      expect(cartridge[:cart_oe_latched]).to eq(1)
    end
  end
end
