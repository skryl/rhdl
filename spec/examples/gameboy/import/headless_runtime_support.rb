# frozen_string_literal: true

require 'json'

require_relative '../../../../examples/gameboy/utilities/import/system_importer'
require_relative '../../../../examples/gameboy/utilities/runners/headless_runner'

module GameboyImportHeadlessRuntimeSupport
  SCREEN_WIDTH = 160
  SCREEN_HEIGHT = 144
  DEFAULT_IMPORT_TOP = 'Gameboy'
  DMG_BOOT_ROM_PATH = File.expand_path('../../../../examples/gameboy/software/roms/dmg_boot.bin', __dir__)

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

  def parity_leg_filter(env_key:, default_legs:)
    raw = ENV.fetch(env_key, '').strip
    return default_legs if raw.empty?

    legs = raw.split(',').map { |value| value.strip.downcase.to_sym }.reject(&:empty?)
    unknown = legs - default_legs
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
      RHDL::Examples::GameBoy::HeadlessRunner.new(
        mode: :verilog,
        hdl_dir: out_dir,
        top: top
      )
    when :ir
      RHDL::Examples::GameBoy::HeadlessRunner.new(
        mode: :ir,
        sim: :compile,
        hdl_dir: out_dir,
        top: top
      )
    else
      raise ArgumentError, "Unknown runtime parity leg: #{leg.inspect}"
    end
  end

  def with_headless_runner(leg:, out_dir:, top: DEFAULT_IMPORT_TOP)
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
      final_state: sampled_state(headless)
    }
  end

  def sampled_state(headless)
    state = headless.cpu_state
    {
      pc: state[:pc].to_i & 0xFFFF,
      a: state[:a].to_i & 0xFF,
      f: state[:f].to_i & 0xFF,
      sp: state[:sp].to_i & 0xFFFF,
      frame_count: headless.frame_count.to_i,
      cycles: headless.cycle_count.to_i
    }
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
    {
      cycles: headless.cycle_count.to_i,
      frame_count: headless.frame_count.to_i,
      nonzero_pixels: framebuffer_nonzero_pixels(framebuffer),
      hash: framebuffer_hash(framebuffer)
    }
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

    nil
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
