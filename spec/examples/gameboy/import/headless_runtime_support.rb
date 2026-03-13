# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'open3'
require 'rbconfig'

require_relative '../../../../examples/gameboy/utilities/import/system_importer'
require_relative '../../../../examples/gameboy/utilities/runners/headless_runner'

module GameboyImportHeadlessRuntimeSupport
  SCREEN_WIDTH = 160
  SCREEN_HEIGHT = 144
  DEFAULT_IMPORT_TOP = 'Gameboy'
  DMG_BOOT_ROM_PATH = File.expand_path('../../../../examples/gameboy/software/roms/dmg_boot.bin', __dir__)
  TRACE_DEBUG_KEYS = %i[
    gb_core_cpu_pc
    gb_core_cpu_ir
    gb_core_cpu_tstate
    gb_core_cpu_mcycle
    gb_core_cpu_addr
    gb_core_cpu_di
    gb_core_cpu_do
    gb_core_cpu_rd_n
    gb_core_cpu_wr_n
    gb_core_cpu_m1_n
  ].freeze
  VIDEO_DEBUG_KEYS = %i[
    lcd_on
    gb_core_boot_rom_enabled
    video_lcdc
    video_scy
    video_scx
  ].freeze

  def require_reference_tree!
    root = RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_REFERENCE_ROOT
    qip = RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_QIP_PATH
    skip 'GameBoy reference tree not available' unless Dir.exist?(root)
    skip 'GameBoy files.qip not available' unless File.file?(qip)
  end

  def require_tool!(cmd)
    skip "#{cmd} not available" unless HdlToolchain.which(cmd)
  end

  def require_pop_rom!
    path = File.expand_path('../../../../examples/gameboy/software/roms/pop.gb', __dir__)
    skip "POP ROM not available: #{path}" unless File.file?(path)
    path
  end

  def require_boot_rom!
    skip "DMG boot ROM not available: #{DMG_BOOT_ROM_PATH}" unless File.file?(DMG_BOOT_ROM_PATH)
    DMG_BOOT_ROM_PATH
  end

  def require_ir_compiler!
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE
  end

  def require_arcilator_aot_toolchain!
    %w[arcilator firtool circt-opt llvm-link clang++ llc].each do |tool|
      require_tool!(tool)
    end
  end

  def with_env(overrides)
    previous = {}
    overrides.each do |key, value|
      previous[key] = ENV.key?(key) ? ENV[key] : :__missing__
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
    yield
  ensure
    previous.each do |key, value|
      if value == :__missing__
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end

  def parity_leg_filter(env_key:, default_legs:, allowed_legs: nil)
    raw = ENV.fetch(env_key, '').strip
    return default_legs if raw.empty?

    allowed_legs ||= default_legs
    legs = raw.split(',').map { |value| value.strip.downcase.to_sym }.reject(&:empty?)
    unknown = legs - allowed_legs
    raise ArgumentError, "Unknown parity legs: #{unknown.join(', ')}" if unknown.any?

    legs
  end

  def import_gameboy!(out_dir:, workspace:, emit_runtime_json: true)
    importer = RHDL::Examples::GameBoy::Import::SystemImporter.new(
      output_dir: out_dir,
      workspace_dir: workspace,
      keep_workspace: true,
      clean_output: true,
      emit_runtime_json: emit_runtime_json,
      strict: true,
      progress: ->(_msg) {}
    )
    result = importer.run
    expect(result.success?).to be(true), Array(result.diagnostics).join("\n")
    result
  end

  def stable_import_dirs(prefix)
    root = ENV.fetch('RHDL_GAMEBOY_PARITY_TMP_ROOT', '/tmp')
    out_dir = File.join(root, "#{prefix}_out")
    workspace = File.join(root, "#{prefix}_ws")
    FileUtils.mkdir_p(root)
    FileUtils.rm_rf(workspace)
    [out_dir, workspace]
  end

  def build_headless_runner_for_leg(leg:, out_dir:, top: DEFAULT_IMPORT_TOP)
    case leg.to_sym
    when :staged
      RHDL::Examples::GameBoy::HeadlessRunner.new(
        mode: :verilog,
        verilog_dir: out_dir,
        top: top,
        use_staged_verilog: true
      )
    when :normalized
      RHDL::Examples::GameBoy::HeadlessRunner.new(
        mode: :verilog,
        verilog_dir: out_dir,
        top: top
      )
    when :raised
      raised_verilog = prepare_raised_verilog_export!(out_dir: out_dir, top: top)
      RHDL::Examples::GameBoy::HeadlessRunner.new(
        mode: :verilog,
        verilog_dir: raised_verilog,
        top: top
      )
    when :ir
      RHDL::Examples::GameBoy::HeadlessRunner.new(
        mode: :ir,
        sim: :compile,
        hdl_dir: out_dir,
        top: top
      )
    when :arcilator
      RHDL::Examples::GameBoy::HeadlessRunner.new(
        mode: :arcilator,
        sim: :compile,
        hdl_dir: out_dir,
        top: top
      )
    else
      raise ArgumentError, "Unknown runtime parity leg: #{leg.inspect}"
    end
  end

  def with_headless_runner(leg:, out_dir:, top: DEFAULT_IMPORT_TOP)
    if leg.to_sym == :arcilator
      with_env('RHDL_GAMEBOY_ARC_OBJECT_COMPILER' => 'llc') do
        runner = build_headless_runner_for_leg(leg: leg, out_dir: out_dir, top: top)
        yield runner
      ensure
        runner&.close if runner.respond_to?(:close)
      end
      return
    end

    runner = build_headless_runner_for_leg(leg: leg, out_dir: out_dir, top: top)
    yield runner
  ensure
    runner&.close if runner.respond_to?(:close)
  end

  def load_rom_and_reset!(headless, rom_bytes)
    headless.load_boot_rom if headless.respond_to?(:load_boot_rom)
    headless.load_rom(rom_bytes)
    headless.reset
  end

  def collect_runtime_capture(headless, rom_bytes:, trace_cycles:, trace_sample_every:, total_cycles:)
    load_rom_and_reset!(headless, rom_bytes)

    trace = []
    cycles_run = 0
    while cycles_run < trace_cycles
      step = [trace_sample_every, trace_cycles - cycles_run].min
      headless.run_steps(step)
      cycles_run += step
      trace << sampled_state(headless)
    end

    remaining = total_cycles - cycles_run
    headless.run_steps(remaining) if remaining.positive?

    {
      trace: trace,
      video: video_snapshot(headless),
      debug: runtime_debug_snapshot(headless),
      final_state: sampled_state(headless)
    }
  end

  def collect_runtime_capture_isolated(leg:, out_dir:, rom_bytes:, trace_cycles:, trace_sample_every:, total_cycles:, top: DEFAULT_IMPORT_TOP)
    root = Dir.pwd
    rom_path = File.join(ENV.fetch('RHDL_GAMEBOY_PARITY_TMP_ROOT', '/tmp'), "gameboy_parity_rom_#{Process.pid}_#{leg}.bin")
    File.binwrite(rom_path, rom_bytes.is_a?(String) ? rom_bytes : Array(rom_bytes).pack('C*'))

    script = <<~'RUBY'
      root, leg, out_dir, top, rom_path, trace_cycles, trace_sample_every, total_cycles = ARGV
      ENV['RSPEC_QUIET_OUTPUT'] = '1'
      Dir.chdir(root)
      require File.join(root, 'examples/gameboy/utilities/runners/headless_runner')
      require File.join(root, 'spec/examples/gameboy/import/headless_runtime_support')

      helper = Object.new
      helper.extend(GameboyImportHeadlessRuntimeSupport)
      rom_bytes = File.binread(rom_path)
      capture = helper.with_headless_runner(leg: leg.to_sym, out_dir: out_dir, top: top) do |headless|
        helper.collect_runtime_capture(
          headless,
          rom_bytes: rom_bytes,
          trace_cycles: Integer(trace_cycles),
          trace_sample_every: Integer(trace_sample_every),
          total_cycles: Integer(total_cycles)
        )
      end
      STDOUT.write(JSON.generate(capture))
    RUBY

    stdout, stderr, status = Open3.capture3(
      { 'RSPEC_QUIET_OUTPUT' => '1' },
      RbConfig.ruby,
      '-Ilib',
      '-e',
      script,
      root,
      leg.to_s,
      out_dir,
      top.to_s,
      rom_path,
      trace_cycles.to_s,
      trace_sample_every.to_s,
      total_cycles.to_s
    )
    raise "Isolated runtime capture failed for #{leg}:\n#{stderr}\n#{stdout}" unless status.success?

    JSON.parse(stdout, symbolize_names: true)
  ensure
    FileUtils.rm_f(rom_path) if rom_path
  end

  def prepare_raised_verilog_export!(out_dir:, top: DEFAULT_IMPORT_TOP)
    export_dir = File.join(out_dir, '.parity_raised_verilog')
    FileUtils.mkdir_p(export_dir)
    out_file = File.join(export_dir, "#{underscore_name(top.to_s)}.v")
    return out_file if File.file?(out_file)

    root = Dir.pwd
    script = <<~'RUBY'
      root, hdl_dir, top, out_file = ARGV
      ENV['RSPEC_QUIET_OUTPUT'] = '1'
      Dir.chdir(root)
      require 'fileutils'
      require File.join(root, 'examples/gameboy/utilities/runners/verilator_runner')

      runner = RHDL::Examples::GameBoy::VerilogRunner.allocate
      component_class = runner.send(:resolve_component_class, hdl_dir: hdl_dir, top: top)
      FileUtils.mkdir_p(File.dirname(out_file))
      File.write(out_file, component_class.to_verilog)
      STDOUT.write(out_file)
    RUBY

    stdout, stderr, status = Open3.capture3(
      { 'RSPEC_QUIET_OUTPUT' => '1' },
      RbConfig.ruby,
      '-Ilib',
      '-e',
      script,
      root,
      out_dir,
      top.to_s,
      out_file
    )
    raise "Raised Verilog export failed:\n#{stderr}\n#{stdout}" unless status.success? && File.file?(out_file)

    out_file
  end

  def underscore_name(value)
    text = value.to_s.gsub('::', '/')
    text = text.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
    text = text.gsub(/([a-z\d])([A-Z])/, '\1_\2')
    text.tr('-', '_').downcase
  end

  def sampled_state(headless)
    state = headless.cpu_state
    debug = runtime_debug_snapshot(headless)
    sampled_pc = debug.fetch(:gb_core_cpu_pc, nil).to_i & 0xFFFF
    sampled_pc = state[:pc].to_i & 0xFFFF if sampled_pc.zero?
    {
      pc: sampled_pc,
      tstate: debug.fetch(:gb_core_cpu_tstate, 0).to_i & 0x7,
      mcycle: debug.fetch(:gb_core_cpu_mcycle, 0).to_i & 0x7,
      addr: debug.fetch(:gb_core_cpu_addr, 0).to_i & 0xFFFF,
      rd_n: debug.fetch(:gb_core_cpu_rd_n, 0).to_i & 0x1,
      wr_n: debug.fetch(:gb_core_cpu_wr_n, 0).to_i & 0x1,
      m1_n: debug.fetch(:gb_core_cpu_m1_n, 0).to_i & 0x1,
      frame_count: headless.frame_count.to_i,
      cycles: headless.cycle_count.to_i
    }
  end

  def runtime_debug_snapshot(headless)
    raw = headless.respond_to?(:debug_state) ? headless.debug_state : {}
    raw = {} unless raw.is_a?(Hash)

    {
      lcd_on: raw.key?(:lcd_on) ? (raw[:lcd_on].to_i & 0x1) : nil,
      lcd_clkena: raw.key?(:lcd_clkena) ? (raw[:lcd_clkena].to_i & 0x1) : nil,
      lcd_vsync: raw.key?(:lcd_vsync) ? (raw[:lcd_vsync].to_i & 0x1) : nil,
      gb_core_boot_rom_enabled: raw.key?(:gb_core_boot_rom_enabled) ? (raw[:gb_core_boot_rom_enabled].to_i & 0x1) : nil,
      gb_core_cpu_pc: raw.key?(:gb_core_cpu_pc) ? (raw[:gb_core_cpu_pc].to_i & 0xFFFF) : nil,
      gb_core_cpu_ir: raw.key?(:gb_core_cpu_ir) ? (raw[:gb_core_cpu_ir].to_i & 0xFF) : nil,
      gb_core_cpu_tstate: raw.key?(:gb_core_cpu_tstate) ? (raw[:gb_core_cpu_tstate].to_i & 0x7) : nil,
      gb_core_cpu_mcycle: raw.key?(:gb_core_cpu_mcycle) ? (raw[:gb_core_cpu_mcycle].to_i & 0x7) : nil,
      gb_core_cpu_addr: raw.key?(:gb_core_cpu_addr) ? (raw[:gb_core_cpu_addr].to_i & 0xFFFF) : nil,
      gb_core_cpu_di: raw.key?(:gb_core_cpu_di) ? (raw[:gb_core_cpu_di].to_i & 0xFF) : nil,
      gb_core_cpu_do: raw.key?(:gb_core_cpu_do) ? (raw[:gb_core_cpu_do].to_i & 0xFF) : nil,
      gb_core_cpu_rd_n: raw.key?(:gb_core_cpu_rd_n) ? (raw[:gb_core_cpu_rd_n].to_i & 0x1) : nil,
      gb_core_cpu_wr_n: raw.key?(:gb_core_cpu_wr_n) ? (raw[:gb_core_cpu_wr_n].to_i & 0x1) : nil,
      gb_core_cpu_m1_n: raw.key?(:gb_core_cpu_m1_n) ? (raw[:gb_core_cpu_m1_n].to_i & 0x1) : nil,
      video_lcdc: raw.key?(:video_lcdc) ? (raw[:video_lcdc].to_i & 0xFF) : nil,
      video_scy: raw.key?(:video_scy) ? (raw[:video_scy].to_i & 0xFF) : nil,
      video_scx: raw.key?(:video_scx) ? (raw[:video_scx].to_i & 0xFF) : nil,
      video_h_cnt: raw.key?(:video_h_cnt) ? (raw[:video_h_cnt].to_i & 0xFF) : nil,
      video_v_cnt: raw.key?(:video_v_cnt) ? (raw[:video_v_cnt].to_i & 0xFF) : nil
    }.compact
  end

  def framebuffer_hash(framebuffer)
    hash = 0xcbf29ce484222325
    Array(framebuffer).flatten.each do |value|
      hash ^= (value.to_i & 0xFF)
      hash = (hash * 0x100000001b3) & 0xFFFF_FFFF_FFFF_FFFF
    end
    format('%016x', hash)
  end

  def framebuffer_nonzero_pixels(framebuffer)
    Array(framebuffer).sum { |row| Array(row).count { |pixel| pixel.to_i != 0 } }
  end

  def video_snapshot(headless)
    framebuffer = headless.read_framebuffer
    snapshot = {
      cycles: headless.cycle_count.to_i,
      frame_count: headless.frame_count.to_i,
      nonzero_pixels: framebuffer_nonzero_pixels(framebuffer),
      hash: framebuffer_hash(framebuffer)
    }
    debug = runtime_debug_snapshot(headless)
    VIDEO_DEBUG_KEYS.each do |key|
      snapshot[key] = debug[key] if debug.key?(key)
    end
    snapshot
  end

  def compare_trace_prefix(lhs, rhs, limit:)
    compare_len = [Array(lhs).length, Array(rhs).length, limit].min
    return { compare_len: compare_len, mismatch: "trace shorter than #{limit} samples" } if compare_len < limit

    compare_len.times do |idx|
      lhs_event = lhs[idx]
      rhs_event = rhs[idx]
      next if lhs_event == rhs_event

      return {
        compare_len: compare_len,
        mismatch: "index=#{idx} lhs=#{lhs_event.inspect} rhs=#{rhs_event.inspect}"
      }
    end

    { compare_len: compare_len, mismatch: nil }
  end

  def first_video_mismatch(lhs, rhs)
    return 'missing lhs video snapshot' if lhs.nil?
    return 'missing rhs video snapshot' if rhs.nil?

    %i[frame_count nonzero_pixels hash].each do |key|
      next if lhs[key] == rhs[key]

      return "#{key} mismatch lhs=#{lhs[key].inspect} rhs=#{rhs[key].inspect}"
    end

    VIDEO_DEBUG_KEYS.each do |key|
      next unless lhs.key?(key) && rhs.key?(key)
      next if lhs[key] == rhs[key]

      return "#{key} mismatch lhs=#{lhs[key].inspect} rhs=#{rhs[key].inspect}"
    end

    nil
  end

  def video_summary(video)
    parts = [
      "frames=#{video[:frame_count]}",
      "nonzero=#{video[:nonzero_pixels]}",
      "hash=#{video[:hash]}"
    ]
    VIDEO_DEBUG_KEYS.each do |key|
      next unless video.key?(key)

      parts << "#{key}=#{video[key]}"
    end
    parts.join(' ')
  end

  def record_trace_comparison!(summary_lines:, failures:, lhs_name:, lhs_trace:, rhs_name:, rhs_trace:, limit:)
    compare = compare_trace_prefix(lhs_trace, rhs_trace, limit: limit)
    if compare[:mismatch]
      failures << "#{lhs_name} vs #{rhs_name} mismatch: #{compare[:mismatch]}"
      summary_lines << "#{lhs_name} vs #{rhs_name}: mismatch (#{compare[:mismatch]})"
    else
      summary_lines << "#{lhs_name} vs #{rhs_name}: OK on first #{compare[:compare_len]} samples"
    end
  end

  def record_video_comparison!(summary_lines:, failures:, lhs_name:, lhs_video:, rhs_name:, rhs_video:)
    mismatch = first_video_mismatch(lhs_video, rhs_video)
    if mismatch
      failures << "#{lhs_name} vs #{rhs_name} video mismatch: #{mismatch}"
      summary_lines << "#{lhs_name} vs #{rhs_name} video: mismatch (#{mismatch})"
    else
      summary_lines << "#{lhs_name} vs #{rhs_name} video: OK"
    end
  end

  def trim_ruby_heap!
    GC.start(full_mark: true, immediate_sweep: true)
    GC.compact if GC.respond_to?(:compact)
  end
end
