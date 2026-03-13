# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'

require_relative '../../../../examples/gameboy/utilities/runners/arcilator_runner'

RSpec.describe RHDL::Examples::GameBoy::ArcilatorRunner do
  describe '#load_import_report!' do
    it 'falls back to the staged core mlir when import_report.json is absent' do
      Dir.mktmpdir('rhdl_gameboy_arc_report') do |dir|
        mixed_dir = File.join(dir, '.mixed_import')
        FileUtils.mkdir_p(mixed_dir)
        core_mlir = File.join(mixed_dir, 'gb.core.mlir')
        File.write(core_mlir, 'module {}')

        runner = described_class.allocate
        report = runner.send(:load_import_report!, dir)

        expect(report.dig('artifacts', 'core_mlir_path')).to eq(core_mlir)
        expect(report.dig('mixed_import', 'top_name')).to eq('gb')
      end
    end
  end

  describe '#parse_state_file!' do
    it 'extracts the required imported core port signals from arcilator state JSON' do
      Dir.mktmpdir('rhdl_gameboy_arc_state') do |dir|
        state_path = File.join(dir, 'state.json')
        states = described_class::CORE_SIGNAL_SPECS.to_a.each_with_index.map do |entry, idx|
          _key, spec = entry
          {
            'name' => spec.fetch(:name),
            'type' => spec.fetch(:preferred_type),
            'offset' => idx * 8,
            'numBits' => 8
          }
        end

        File.write(
          state_path,
          JSON.pretty_generate(
            [
              {
                'name' => 'gb',
                'numStateBytes' => 4096,
                'states' => states
              }
            ]
          )
        )

        runner = described_class.allocate
        runner.instance_variable_set(:@import_report, { 'mixed_import' => { 'top_name' => 'gb' } })

        info = runner.send(:parse_state_file!, state_path)
        expect(info.fetch(:module_name)).to eq('gb')
        expect(info.fetch(:state_size)).to eq(4096)
        expect(info.fetch(:signals)).to include(:clk_sys, :reset, :cart_do, :lcd_clkena, :joy_p54)
        expect(info.fetch(:signals).fetch(:lcd_data_gb)).to include(offset: kind_of(Integer), bits: 8)
      end
    end

    it 'extracts the generated Gameboy wrapper port signals when the wrapper top is selected' do
      Dir.mktmpdir('rhdl_gameboy_arc_wrapper_state') do |dir|
        state_path = File.join(dir, 'state.json')
        states = described_class::WRAPPER_SIGNAL_SPECS.to_a.each_with_index.filter_map do |entry, idx|
          key, spec = entry
          next if spec[:required] == false

          {
            'name' => spec.fetch(:name),
            'type' => spec.fetch(:preferred_type),
            'offset' => idx * 8,
            'numBits' => 8
          }
        end

        File.write(
          state_path,
          JSON.pretty_generate(
            [
              {
                'name' => 'gameboy',
                'numStateBytes' => 4096,
                'states' => states
              }
            ]
          )
        )

        runner = described_class.allocate
        runner.instance_variable_set(:@import_report, {
                                       'mixed_import' => { 'top_name' => 'gb' },
                                       'import_wrapper' => { 'class_name' => 'Gameboy', 'module_name' => 'gameboy' }
                                     })
        runner.instance_variable_set(:@requested_top, nil)

        info = runner.send(:parse_state_file!, state_path)
        expect(info.fetch(:module_name)).to eq('gameboy')
        expect(info.fetch(:signals)).to include(:boot_rom_do, :boot_rom_addr, :lcd_data_gb)
      end
    end

    it 'prefers wrapper wire states over duplicated output aliases' do
      Dir.mktmpdir('rhdl_gameboy_arc_wrapper_dupes') do |dir|
        state_path = File.join(dir, 'state.json')
        states = [
          { 'name' => 'reset', 'type' => 'input', 'offset' => 1, 'numBits' => 1 },
          { 'name' => 'clk_sys', 'type' => 'input', 'offset' => 2, 'numBits' => 1 },
          { 'name' => 'joystick', 'type' => 'input', 'offset' => 3, 'numBits' => 8 },
          { 'name' => 'is_gbc', 'type' => 'input', 'offset' => 4, 'numBits' => 1 },
          { 'name' => 'is_sgb', 'type' => 'input', 'offset' => 5, 'numBits' => 1 },
          { 'name' => 'cart_do', 'type' => 'input', 'offset' => 6, 'numBits' => 8 },
          { 'name' => 'boot_rom_do', 'type' => 'input', 'offset' => 7, 'numBits' => 8 },
          { 'name' => 'ext_bus_addr', 'type' => 'wire', 'offset' => 10, 'numBits' => 15 },
          { 'name' => 'ext_bus_addr', 'type' => 'output', 'offset' => 110, 'numBits' => 15 },
          { 'name' => 'ext_bus_a15', 'type' => 'wire', 'offset' => 11, 'numBits' => 1 },
          { 'name' => 'ext_bus_a15', 'type' => 'output', 'offset' => 111, 'numBits' => 1 },
          { 'name' => 'cart_rd', 'type' => 'wire', 'offset' => 12, 'numBits' => 1 },
          { 'name' => 'cart_rd', 'type' => 'output', 'offset' => 112, 'numBits' => 1 },
          { 'name' => 'cart_wr', 'type' => 'wire', 'offset' => 13, 'numBits' => 1 },
          { 'name' => 'cart_wr', 'type' => 'output', 'offset' => 113, 'numBits' => 1 },
          { 'name' => 'cart_di', 'type' => 'wire', 'offset' => 14, 'numBits' => 8 },
          { 'name' => 'cart_di', 'type' => 'output', 'offset' => 114, 'numBits' => 8 },
          { 'name' => 'lcd_clkena', 'type' => 'wire', 'offset' => 15, 'numBits' => 1 },
          { 'name' => 'lcd_clkena', 'type' => 'output', 'offset' => 115, 'numBits' => 1 },
          { 'name' => 'lcd_data_gb', 'type' => 'wire', 'offset' => 16, 'numBits' => 2 },
          { 'name' => 'lcd_data_gb', 'type' => 'output', 'offset' => 116, 'numBits' => 2 },
          { 'name' => 'lcd_vsync', 'type' => 'wire', 'offset' => 17, 'numBits' => 1 },
          { 'name' => 'lcd_vsync', 'type' => 'output', 'offset' => 117, 'numBits' => 1 },
          { 'name' => 'lcd_on', 'type' => 'wire', 'offset' => 18, 'numBits' => 1 },
          { 'name' => 'lcd_on', 'type' => 'output', 'offset' => 118, 'numBits' => 1 },
          { 'name' => 'boot_rom_addr', 'type' => 'wire', 'offset' => 19, 'numBits' => 8 },
          { 'name' => 'boot_rom_addr', 'type' => 'output', 'offset' => 119, 'numBits' => 8 }
        ]

        File.write(
          state_path,
          JSON.pretty_generate(
            [
              {
                'name' => 'gameboy',
                'numStateBytes' => 4096,
                'states' => states
              }
            ]
          )
        )

        runner = described_class.allocate
        runner.instance_variable_set(:@import_report, {
                                       'mixed_import' => { 'top_name' => 'gb' },
                                       'import_wrapper' => { 'class_name' => 'Gameboy', 'module_name' => 'gameboy' }
                                     })
        runner.instance_variable_set(:@requested_top, nil)

        info = runner.send(:parse_state_file!, state_path)
        expect(info.fetch(:signals).fetch(:lcd_vsync)).to include(type: 'wire', offset: 17)
        expect(info.fetch(:signals).fetch(:cart_rd)).to include(type: 'wire', offset: 12)
        expect(info.fetch(:signals).fetch(:boot_rom_addr)).to include(type: 'wire', offset: 19)
      end
    end
  end

  describe '#requested_top_name' do
    it 'defaults to the generated Gameboy wrapper when present' do
      runner = described_class.allocate
      runner.instance_variable_set(:@import_report, {
                                     'mixed_import' => { 'top_name' => 'gb' },
                                     'import_wrapper' => { 'class_name' => 'Gameboy', 'module_name' => 'gameboy' }
                                   })
      runner.instance_variable_set(:@requested_top, nil)

      expect(runner.send(:requested_top_name)).to eq('Gameboy')
      expect(runner.send(:using_import_wrapper?)).to be(true)
      expect(runner.send(:state_top_name)).to eq('gameboy')
    end
  end

  describe 'imported verilog source selection' do
    it 'defaults to the staged imported Verilog source when available' do
      Dir.mktmpdir('rhdl_gameboy_arc_source_default') do |dir|
        staged = File.join(dir, 'pure_verilog_entry.v')
        normalized = File.join(dir, 'gb.normalized.v')
        File.write(staged, "// staged\n")
        File.write(normalized, "// normalized\n")

        runner = described_class.allocate
        runner.instance_variable_set(:@use_staged_verilog, true)
        runner.instance_variable_set(:@use_normalized_verilog, false)
        runner.instance_variable_set(:@import_report, {
                                       'artifacts' => {
                                         'pure_verilog_entry_path' => staged,
                                         'normalized_verilog_path' => normalized
                                       },
                                       'mixed_import' => { 'top_name' => 'gb' }
                                     })

        expect(runner.send(:selected_import_verilog_path)).to eq(staged)
      end
    end

    it 'uses the normalized imported Verilog source when explicitly requested' do
      Dir.mktmpdir('rhdl_gameboy_arc_source_normalized') do |dir|
        staged = File.join(dir, 'pure_verilog_entry.v')
        normalized = File.join(dir, 'gb.normalized.v')
        File.write(staged, "// staged\n")
        File.write(normalized, "// normalized\n")

        runner = described_class.allocate
        runner.instance_variable_set(:@use_staged_verilog, false)
        runner.instance_variable_set(:@use_normalized_verilog, true)
        runner.instance_variable_set(:@import_report, {
                                       'artifacts' => {
                                         'pure_verilog_entry_path' => staged,
                                         'normalized_verilog_path' => normalized
                                       },
                                       'mixed_import' => { 'top_name' => 'gb' }
                                     })

        expect(runner.send(:selected_import_verilog_path)).to eq(normalized)
      end
    end

    it 'disables imported-Verilog selection when rhdl source is requested' do
      Dir.mktmpdir('rhdl_gameboy_arc_source_rhdl') do |dir|
        staged = File.join(dir, 'pure_verilog_entry.v')
        normalized = File.join(dir, 'gb.normalized.v')
        File.write(staged, "// staged\n")
        File.write(normalized, "// normalized\n")

        runner = described_class.allocate
        runner.instance_variable_set(:@use_staged_verilog, true)
        runner.instance_variable_set(:@use_normalized_verilog, false)
        runner.instance_variable_set(:@use_rhdl_source, true)
        runner.instance_variable_set(:@import_report, {
                                       'artifacts' => {
                                         'pure_verilog_entry_path' => staged,
                                         'normalized_verilog_path' => normalized
                                       },
                                       'mixed_import' => { 'top_name' => 'gb' }
                                     })

        expect(runner.send(:selected_import_verilog_path)).to be_nil
      end
    end
  end

  describe '#wrapper_uses_imported_speedcontrol?' do
    it 'prefers the staged Verilog modules over stale wrapper metadata' do
      Dir.mktmpdir('rhdl_gameboy_arc_speedcontrol') do |dir|
        staged = File.join(dir, 'pure_verilog_entry.v')
        File.write(staged, "module speedcontrol(input wire clk_sys); endmodule\nmodule gb; endmodule\n")

        runner = described_class.allocate
        runner.instance_variable_set(:@import_report, {
                                       'artifacts' => { 'pure_verilog_entry_path' => staged },
                                       'mixed_import' => { 'top_name' => 'gb', 'pure_verilog_entry_path' => staged },
                                       'import_wrapper' => { 'class_name' => 'Gameboy', 'module_name' => 'gameboy', 'uses_imported_speedcontrol' => false }
                                     })

        expect(runner.send(:wrapper_uses_imported_speedcontrol?)).to be(true)
      end
    end

    it 'detects speedcontrol through staged include entries' do
      Dir.mktmpdir('rhdl_gameboy_arc_speedcontrol_include') do |dir|
        staged = File.join(dir, 'pure_verilog_entry.v')
        File.write(staged, "`include \"/tmp/generated_vhdl/speedcontrol.v\"\nmodule gb; endmodule\n")

        runner = described_class.allocate
        runner.instance_variable_set(:@import_report, {
                                       'artifacts' => { 'pure_verilog_entry_path' => staged },
                                       'mixed_import' => { 'top_name' => 'gb', 'pure_verilog_entry_path' => staged },
                                       'import_wrapper' => { 'class_name' => 'Gameboy', 'module_name' => 'gameboy', 'uses_imported_speedcontrol' => false }
                                     })

        expect(runner.send(:wrapper_uses_imported_speedcontrol?)).to be(true)
      end
    end
  end

  describe '#manual_clock_enable_drive?' do
    it 'does not drive ce inputs when the imported wrapper already contains speedcontrol' do
      runner = described_class.allocate
      runner.instance_variable_set(:@import_report, {
                                     'artifacts' => { 'pure_verilog_entry_path' => __FILE__ },
                                     'mixed_import' => { 'top_name' => 'gb', 'pure_verilog_entry_path' => __FILE__ },
                                     'import_wrapper' => { 'class_name' => 'Gameboy', 'module_name' => 'gameboy', 'uses_imported_speedcontrol' => true }
                                   })
      runner.instance_variable_set(:@requested_top, nil)

      signals = { ce: { offset: 1 }, ce_n: { offset: 2 }, ce_2x: { offset: 3 } }
      expect(runner.send(:manual_clock_enable_drive?, signals)).to be(false)
    end
  end

  describe '#llvm_threads' do
    it 'defaults to 8 threads and clamps invalid values' do
      runner = described_class.allocate
      previous = ENV['RHDL_GAMEBOY_ARC_LLVM_THREADS']

      ENV.delete('RHDL_GAMEBOY_ARC_LLVM_THREADS')
      expect(runner.send(:llvm_threads)).to eq(8)

      ENV['RHDL_GAMEBOY_ARC_LLVM_THREADS'] = 'bogus'
      expect(runner.send(:llvm_threads)).to eq(8)

      ENV['RHDL_GAMEBOY_ARC_LLVM_THREADS'] = '12'
      expect(runner.send(:llvm_threads)).to eq(12)
    ensure
      previous.nil? ? ENV.delete('RHDL_GAMEBOY_ARC_LLVM_THREADS') : ENV['RHDL_GAMEBOY_ARC_LLVM_THREADS'] = previous
    end
  end

  describe '#jit_mode?' do
    it 'honors the explicit runner setting and the env fallback' do
      runner = described_class.allocate
      previous = ENV['RHDL_GAMEBOY_ARC_JIT']

      runner.instance_variable_set(:@jit, true)
      expect(runner.send(:jit_mode?)).to be(true)

      runner.instance_variable_set(:@jit, false)
      expect(runner.send(:jit_mode?)).to be(false)

      ENV['RHDL_GAMEBOY_ARC_JIT'] = '1'
      expect(runner.send(:env_truthy?, 'RHDL_GAMEBOY_ARC_JIT')).to be(true)

      ENV['RHDL_GAMEBOY_ARC_JIT'] = '0'
      expect(runner.send(:env_truthy?, 'RHDL_GAMEBOY_ARC_JIT')).to be(false)
    ensure
      previous.nil? ? ENV.delete('RHDL_GAMEBOY_ARC_JIT') : ENV['RHDL_GAMEBOY_ARC_JIT'] = previous
    end
  end

  describe '#llvm_object_compiler' do
    it 'honors an explicit compiler override and otherwise prefers llc' do
      runner = described_class.allocate
      previous = ENV['RHDL_GAMEBOY_ARC_OBJECT_COMPILER']

      ENV['RHDL_GAMEBOY_ARC_OBJECT_COMPILER'] = 'clang'
      expect(runner.send(:llvm_object_compiler)).to eq('clang')

      ENV['RHDL_GAMEBOY_ARC_OBJECT_COMPILER'] = 'llc'
      expect(runner.send(:llvm_object_compiler)).to eq('llc')

      ENV.delete('RHDL_GAMEBOY_ARC_OBJECT_COMPILER')
      expected = runner.send(:command_available?, 'llc') ? 'llc' : 'clang'
      expect(runner.send(:llvm_object_compiler)).to eq(expected)
    ensure
      previous.nil? ? ENV.delete('RHDL_GAMEBOY_ARC_OBJECT_COMPILER') : ENV['RHDL_GAMEBOY_ARC_OBJECT_COMPILER'] = previous
    end
  end

  describe '#core_mlir_digest' do
    it 'tracks the imported core MLIR content for cache invalidation' do
      Dir.mktmpdir('rhdl_gameboy_arc_digest') do |dir|
        core_mlir = File.join(dir, 'gb.core.mlir')
        File.write(core_mlir, 'module @gb {}')

        runner = described_class.allocate
        runner.instance_variable_set(:@import_report, {
                                       'artifacts' => { 'core_mlir_path' => core_mlir },
                                       'mixed_import' => { 'top_name' => 'gb', 'core_mlir_path' => core_mlir }
                                     })

        first = runner.send(:core_mlir_digest)
        runner.remove_instance_variable(:@core_mlir_digest)
        File.write(core_mlir, 'module @gb { hw.output }')
        second = runner.send(:core_mlir_digest)

        expect(first).not_to eq(second)
      end
    end
  end

  describe 'interactive display helpers' do
    it 'tracks screen dirty state across frame-producing runs' do
      runner = described_class.allocate
      runner.instance_variable_set(:@jit, true)
      runner.instance_variable_set(:@screen_dirty, false)
      runner.instance_variable_set(:@frame_count, 0)
      runner.instance_variable_set(:@cycles, 0)
      allow(runner).to receive(:send_jit_command).with('RUN 123').and_return('RUN 123 2 2')

      runner.run_steps(123)

      expect(runner.screen_dirty?).to be(true)
      expect(runner.frame_count).to eq(2)
      expect(runner.cycle_count).to eq(123)

      runner.clear_screen_dirty
      expect(runner.screen_dirty?).to be(false)
    end

    it 'renders the captured framebuffer through the shared LCD renderer' do
      runner = described_class.allocate
      framebuffer = Array.new(described_class::SCREEN_HEIGHT) { Array.new(described_class::SCREEN_WIDTH, 0) }
      framebuffer[0][0] = 3
      allow(runner).to receive(:read_framebuffer).and_return(framebuffer)

      braille = runner.render_lcd_braille(chars_wide: 40)
      color = runner.render_lcd_color(chars_wide: 40)

      expect(braille).to be_a(String)
      expect(braille).not_to be_empty
      expect(color).to be_a(String)
      expect(color).to include("\e[")
    end
  end

  describe '#parse_jit_state' do
    it 'parses the protocol response into integer fields' do
      runner = described_class.allocate
      parsed = runner.send(:parse_jit_state, 'STATE 4660 22136 1 7 1 0 254 253 49 1 1 170 1 0 1 153 1 2 0 43981 62 3 2 48879 55 66 1 0 1 0 1 1 0 1 3 4 5 6 144 89 100 4 252 255 170 18 52 86 120 154 188 222 5 3 1 0 171 205 240 15 204 221 17 34')

      expect(parsed).to eq(
        last_fetch_addr: 0x1234,
        ext_bus_addr: 0x5678,
        lcd_on: 1,
        frame_count: 7,
        boot_upload_active: 1,
        boot_upload_phase: 0,
        boot_upload_index: 254,
        boot_rom_addr: 253,
        boot_upload_low_byte: 49,
        gb_core_reset_r: 1,
        gb_core_boot_rom_enabled: 1,
        gb_core_boot_q: 170,
        ext_bus_a15: 1,
        cart_rd: 0,
        cart_wr: 1,
        cart_do: 153,
        lcd_clkena: 1,
        lcd_data_gb: 2,
        lcd_vsync: 0,
        gb_core_cpu_pc: 0xABCD,
        gb_core_cpu_ir: 62,
        gb_core_cpu_tstate: 3,
        gb_core_cpu_mcycle: 2,
        gb_core_cpu_addr: 0xBEEF,
        gb_core_cpu_di: 55,
        gb_core_cpu_do: 66,
        gb_core_cpu_m1_n: 1,
        gb_core_cpu_mreq_n: 0,
        gb_core_cpu_iorq_n: 1,
        gb_core_cpu_rd_n: 0,
        gb_core_cpu_wr_n: 1,
        speed_ctrl_ce: 1,
        speed_ctrl_ce_n: 0,
        speed_ctrl_ce_2x: 1,
        speed_ctrl_state: 3,
        speed_ctrl_clkdiv: 4,
        speed_ctrl_unpause_cnt: 5,
        speed_ctrl_fastforward_cnt: 6,
        video_h_cnt: 144,
        video_v_cnt: 89,
        video_scy: 100,
        video_scx: 4,
        video_bg_palette: 252,
        video_obj_palette0: 255,
        video_obj_palette1: 170,
        video_bg_shift_lo: 18,
        video_bg_shift_hi: 52,
        video_bg_attr: 86,
        video_obj_shift_lo: 120,
        video_obj_shift_hi: 154,
        video_obj_meta0: 188,
        video_obj_meta1: 222,
        video_fetch_phase: 5,
        video_fetch_slot: 3,
        video_fetch_hold0: 1,
        video_fetch_hold1: 0,
        video_fetch_data0: 171,
        video_fetch_data1: 205,
        video_tile_lo: 240,
        video_tile_hi: 15,
        video_input_vram_data: 204,
        video_input_vram1_data: 221,
        vram0_q_a_reg: 17,
        vram1_q_a_reg: 34
      )
    end
  end

  describe '#build_simulation' do
    it 'prepares the imported core through the shared ARC helper before arcilator build' do
      Dir.mktmpdir('rhdl_gameboy_arc_build') do |dir|
        import_root = File.join(dir, 'import')
        build_dir = File.join(dir, 'build')
        FileUtils.mkdir_p(import_root)

        core_mlir = File.join(import_root, '.mixed_import', 'gb.core.mlir')
        FileUtils.mkdir_p(File.dirname(core_mlir))
        File.write(core_mlir, 'hw.module @gb() { hw.output }')

        report_path = File.join(import_root, 'import_report.json')
        File.write(
          report_path,
          JSON.pretty_generate(
            {
              'artifacts' => { 'core_mlir_path' => core_mlir },
              'mixed_import' => { 'top_name' => 'gb', 'core_mlir_path' => core_mlir }
            }
          )
        )

        runner = described_class.allocate
        runner.instance_variable_set(:@import_root, import_root)
        runner.instance_variable_set(:@requested_top, nil)
        runner.instance_variable_set(:@jit, false)
        runner.instance_variable_set(
          :@import_report,
          {
            'artifacts' => { 'core_mlir_path' => core_mlir },
            'mixed_import' => { 'top_name' => 'gb', 'core_mlir_path' => core_mlir }
          }
        )

        allow(runner).to receive(:build_dir).and_return(build_dir)
        allow(runner).to receive(:shared_lib_path).and_return(File.join(build_dir, 'libgameboy_arc_sim.so'))
        allow(runner).to receive(:runtime_bitcode_path).and_return(File.join(build_dir, 'gameboy_arc_runtime.bc'))
        allow(runner).to receive(:llvm_object_path).and_return(File.join(build_dir, 'gameboy_arc.o'))
        allow(runner).to receive(:linked_bitcode_path).and_return(File.join(build_dir, 'gameboy_arc_jit.bc'))
        allow(runner).to receive(:jit_mode?).and_return(false)
        allow(runner).to receive(:run_arcilator!)
        allow(runner).to receive(:parse_state_file!).and_return(module_name: 'gb', state_size: 1, signals: {})
        allow(runner).to receive(:write_arcilator_wrapper)
        allow(runner).to receive(:build_runtime_library!)

        expect(RHDL::Codegen::CIRCT::Tooling).to receive(:prepare_arc_mlir_from_circt_mlir).with(
          hash_including(
            mlir_path: core_mlir,
            top: 'gb'
          )
        ).and_return(
          success: true,
          arc_mlir_path: File.join(build_dir, 'arc', 'gb.arc.mlir'),
          flatten_cleanup: { success: true }
        )
        expect(RHDL::Codegen::CIRCT::Tooling).to receive(:finalize_arc_mlir_for_arcilator!).with(
          hash_including(arc_mlir_path: File.join(build_dir, 'arc', 'gb.arc.mlir'))
        )

        runner.send(:build_simulation)
      end
    end
  end

  describe '#run_arcilator!' do
    it 'builds the arcilator invocation through shared CIRCT tooling' do
      Dir.mktmpdir('rhdl_gameboy_arc_run_cmd') do |dir|
        arc_mlir = File.join(dir, 'gameboy.hwseq.mlir')
        state_path = File.join(dir, 'gameboy_state.json')
        ll_path = File.join(dir, 'gameboy_arc.ll')
        log_path = File.join(dir, 'arcilator.log')
        File.write(arc_mlir, 'hw.module @gameboy() { hw.output }')

        runner = described_class.allocate
        allow(runner).to receive(:observe_flags).and_return([])
        allow(runner).to receive(:arcilator_split_funcs_threshold).and_return(nil)

        expect(RHDL::Codegen::CIRCT::Tooling).to receive(:arcilator_command).with(
          mlir_path: arc_mlir,
          state_file: state_path,
          out_path: ll_path,
          extra_args: ['--async-resets-as-sync']
        ).and_return(['true'])

        runner.send(:run_arcilator!, arc_mlir_path: arc_mlir, state_path: state_path, ll_path: ll_path, log_path: log_path)
      end
    end
  end

  describe 'wrapper ABI generation' do
    def minimal_state_info_for(specs, module_name:)
      {
        module_name: module_name,
        state_size: 4096,
        signals: specs.each_with_index.each_with_object({}) do |((key, spec), idx), result|
          next if spec[:required] == false

          result[key] = {
            name: spec.fetch(:name),
            offset: idx * 8,
            bits: 8,
            type: spec.fetch(:preferred_type).to_s
          }
        end
      }
    end

    it 'emits the standard ABI sim_create signature and JIT entrypoint for the imported wrapper top' do
      Dir.mktmpdir('rhdl_gameboy_arc_wrapper_abi') do |dir|
        wrapper_path = File.join(dir, 'arc_wrapper.cpp')
        runner = described_class.allocate
        runner.instance_variable_set(:@import_report, {
                                       'mixed_import' => { 'top_name' => 'gb' },
                                       'import_wrapper' => { 'class_name' => 'Gameboy', 'module_name' => 'gameboy' }
                                     })
        runner.instance_variable_set(:@requested_top, nil)

        runner.send(
          :write_arcilator_wrapper,
          wrapper_path: wrapper_path,
          state_info: minimal_state_info_for(described_class::WRAPPER_SIGNAL_SPECS, module_name: 'gameboy')
        )

        wrapper_source = File.read(wrapper_path)
        expect(wrapper_source).to include('void* sim_create(const char* json, size_t json_len, unsigned int sub_cycles, char** err_out)')
        expect(wrapper_source).to include('SimContext* ctx = static_cast<SimContext*>(sim_create(nullptr, 0u, 0u, nullptr));')
        expect(wrapper_source).to include('int runner_run(void* sim, unsigned int cycles, unsigned char key_data, int key_ready, unsigned int mode, RunnerRunResult* result_out)')
      end
    end

    it 'emits the standard ABI sim_create signature and JIT entrypoint for the raw core top' do
      Dir.mktmpdir('rhdl_gameboy_arc_core_abi') do |dir|
        wrapper_path = File.join(dir, 'arc_wrapper.cpp')
        runner = described_class.allocate
        runner.instance_variable_set(:@import_report, {
                                       'mixed_import' => { 'top_name' => 'gb' }
                                     })
        runner.instance_variable_set(:@requested_top, 'gb')

        runner.send(
          :write_arcilator_wrapper,
          wrapper_path: wrapper_path,
          state_info: minimal_state_info_for(described_class::CORE_SIGNAL_SPECS, module_name: 'gb')
        )

        wrapper_source = File.read(wrapper_path)
        expect(wrapper_source).to include('void* sim_create(const char* json, size_t json_len, unsigned int sub_cycles, char** err_out)')
        expect(wrapper_source).to include('SimContext* ctx = static_cast<SimContext*>(sim_create(nullptr, 0u, 0u, nullptr));')
        expect(wrapper_source).to include('int runner_run(void* sim, unsigned int cycles, unsigned char key_data, int key_ready, unsigned int mode, RunnerRunResult* result_out)')
      end
    end
  end

  describe '#load_shared_library' do
    it 'requires the shared runner ABI from the loaded library' do
      runner = described_class.allocate
      runner.instance_variable_set(:@joystick_state, 0xFF)

      runtime = instance_double(
        RHDL::Sim::Native::ABI::Simulator,
        runner_supported?: false,
        close: true
      )

      expect(RHDL::Sim::Native::MLIR::Arcilator::Runtime).to receive(:open).with(
        lib_path: '/tmp/libgameboy_arc.dylib',
        signal_widths_by_name: {},
        signal_widths_by_idx: nil,
        backend_label: 'Game Boy Arcilator'
      ).and_return(runtime)
      expect(runtime).to receive(:close)

      expect do
        runner.send(:load_shared_library, '/tmp/libgameboy_arc.dylib')
      end.to raise_error(RuntimeError, /runner ABI/)
    end

    it 'rejects a shared library with the wrong runner kind' do
      runner = described_class.allocate
      runner.instance_variable_set(:@joystick_state, 0xFF)

      runtime = instance_double(
        RHDL::Sim::Native::ABI::Simulator,
        runner_supported?: true,
        runner_kind: :apple2,
        raw_context: Object.new,
        close: true
      )

      expect(RHDL::Sim::Native::MLIR::Arcilator::Runtime).to receive(:open).with(
        lib_path: '/tmp/libgameboy_arc.dylib',
        signal_widths_by_name: {},
        signal_widths_by_idx: nil,
        backend_label: 'Game Boy Arcilator'
      ).and_return(runtime)
      expect(runtime).to receive(:close)

      expect do
        runner.send(:load_shared_library, '/tmp/libgameboy_arc.dylib')
      end.to raise_error(RuntimeError, /expected :gameboy/i)
    end
  end

  describe 'ABI signal width metadata' do
    it 'caches ABI widths from the state-file signal table in input/output order' do
      runner = described_class.allocate
      state_info = {
        signals: {
          reset: { bits: 1, type: 'input' },
          joystick: { bits: 8, type: 'input' },
          lcd_on: { bits: 1, type: 'output' },
          ignored_wide: { bits: 128, type: 'output' }
        }
      }

      runner.send(:cache_abi_signal_widths!, state_info)

      expect(runner.instance_variable_get(:@abi_signal_widths_by_name)).to eq(
        'reset' => 1,
        'joystick' => 8,
        'lcd_on' => 1
      )
      expect(runner.instance_variable_get(:@abi_signal_widths_by_idx)).to eq([1, 8, 1])
    end
  end
end
