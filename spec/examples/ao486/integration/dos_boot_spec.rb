# frozen_string_literal: true

require "spec_helper"

require_relative "../../../../examples/ao486/utilities/runners/headless_runner"

RSpec.describe "ao486 DOS boot integration", :slow, :no_vendor_reimport do
  DOS_PROMPT_MARKERS = ["A:\\>", "C:\\>"].freeze
  DOS_BOOT_MARKERS = [
    "Starting MS-DOS",
    "MS-DOS",
    "A:\\>",
    "C:\\>"
  ].freeze

  def int_env(name, default)
    raw = ENV[name]
    return default if raw.nil? || raw.strip.empty?

    Integer(raw.to_s.delete("_"), 0)
  rescue ArgumentError, TypeError
    default
  end

  let(:cwd) { File.expand_path("../../../../", __dir__) }
  let(:out_dir) { File.expand_path("../../../../examples/ao486/hdl", __dir__) }
  let(:vendor_root) { File.expand_path("../../../../examples/ao486/hdl/vendor/source_hdl", __dir__) }
  let(:cycle_budget) { int_env("RHDL_AO486_DOS_BOOT_CYCLES", 40_000_000) }

  def require_converted_runtime_artifacts!(out_dir:)
    top_modules = Dir.glob(File.join(out_dir, "lib", "*", "modules", "**", "ao486.rb"))
    project_entrypoints = Dir.glob(File.join(out_dir, "lib", "*.rb"))
    return if top_modules.any? && project_entrypoints.any?

    skip "converted ao486 runtime artifacts are missing under #{out_dir}; run import once and reuse those outputs"
  end

  def first_existing_path(candidates)
    Array(candidates).find { |path| File.file?(path) }
  end

  def bios_system_path
    env_override = ENV["RHDL_AO486_BIOS_SYSTEM"]
    return File.expand_path(env_override, cwd) unless env_override.nil? || env_override.strip.empty?

    first_existing_path(
      [
        File.join(cwd, "examples", "ao486", "software", "bin", "boot0.rom"),
        File.join(cwd, "examples", "ao486", "software", "images", "bochs_legacy"),
        File.join(cwd, "examples", "ao486", "reference", "sd", "bios", "bochs_legacy"),
        File.join(cwd, "examples", "ao486", "reference", "releases", "boot0.rom")
      ]
    )
  end

  def bios_video_path
    env_override = ENV["RHDL_AO486_BIOS_VIDEO"]
    return File.expand_path(env_override, cwd) unless env_override.nil? || env_override.strip.empty?

    first_existing_path(
      [
        File.join(cwd, "examples", "ao486", "software", "bin", "boot1.rom"),
        File.join(cwd, "examples", "ao486", "software", "images", "vgabios_lgpl"),
        File.join(cwd, "examples", "ao486", "reference", "sd", "vgabios", "vgabios_lgpl"),
        File.join(cwd, "examples", "ao486", "reference", "releases", "boot1.rom")
      ]
    )
  end

  def dos_image_path
    env_override = ENV["RHDL_AO486_DOS_IMAGE"]
    return File.expand_path(env_override, cwd) unless env_override.nil? || env_override.strip.empty?

    first_existing_path(
      [
        File.join(cwd, "examples", "ao486", "software", "images", "dos4.img"),
        File.join(cwd, "examples", "ao486", "software", "images", "fdboot.img"),
        File.join(cwd, "examples", "ao486", "reference", "sd", "fd_1_44m", "fdboot.img")
      ]
    )
  end

  def parse_hex_or_nil(value)
    case value
    when Integer
      value
    when String
      text = value.strip
      return nil if text.empty?
      return Integer(text, 0) if text.start_with?("0x", "-0x", "+0x")

      Integer(text, 16)
    else
      nil
    end
  rescue ArgumentError, TypeError
    nil
  end

  def normalize_hash(value)
    return {} unless value.is_a?(Hash)

    value.each_with_object({}) do |(key, entry), memo|
      memo[key.to_s] = entry
    end
  end

  def decode_serial_from_events(result)
    data = normalize_hash(result)
    events = Array(data["io_writes"]) + Array(data["events"])
    bytes = []

    events.each do |entry|
      event = normalize_hash(entry)
      kind = event.fetch("kind", "").to_s.strip.downcase
      next unless kind.empty? || kind == "io_write" || kind == "serial_tx"

      address = parse_hex_or_nil(event["address"] || event["io_write_address"] || event["port"])
      next if address.nil?
      next unless (address & 0xFFFF) == 0x03F8 || (address & 0xFFFC) == 0x03F8

      data_word = parse_hex_or_nil(event["data"] || event["value"] || event["io_write_data"]) || 0
      byteenable = parse_hex_or_nil(event["byteenable"] || event["be"] || event["mask"]) || 0x1
      length = parse_hex_or_nil(event["length"] || event["io_write_length"])
      byteenable = (1 << length) - 1 if !length.nil? && length.positive? && byteenable.zero?

      4.times do |index|
        next if (byteenable & (1 << index)).zero?

        bytes << ((data_word >> (index * 8)) & 0xFF)
      end
    end

    bytes.pack("C*").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
  rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
    bytes.pack("C*")
  end

  def serial_output(result)
    data = normalize_hash(result)
    %w[serial_output uart_output console_output log output].each do |key|
      value = data[key]
      return value.to_s if value.is_a?(String)
    end

    decode_serial_from_events(data)
  end

  def prompt_marker(serial_text)
    candidates = DOS_PROMPT_MARKERS.filter_map do |marker|
      index = serial_text.index(marker)
      next if index.nil?

      [marker, index]
    end
    candidates.min_by { |_marker, index| index }&.first
  end

  def summarized_boot(run)
    serial = serial_output(run)
    prompt = prompt_marker(serial)
    result = normalize_hash(run)
    milestones = Array(result["milestones"]).map do |entry|
      if entry.is_a?(Hash)
        meta = normalize_hash(entry)
        meta["name"] || meta["milestone"] || meta["label"] || meta["kind"]
      else
        entry.to_s
      end
    end.compact.map(&:to_s).reject(&:empty?)
    serial_markers = DOS_BOOT_MARKERS.select { |marker| serial.include?(marker) }
    serial_markers.each do |marker|
      milestone = "serial:#{marker}"
      milestones << milestone unless milestones.include?(milestone)
    end
    prompt_milestone = "prompt:#{prompt}"
    milestones << prompt_milestone unless prompt.nil? || milestones.include?(prompt_milestone)

    {
      prompt: prompt,
      milestones: milestones,
      serial_tail: serial[-256, 256] || serial
    }
  end

  def assert_progression_parity!(baseline:, candidate:, backend_label:)
    expect(candidate.fetch(:prompt)).not_to be_nil, <<~MSG
      #{backend_label} did not reach DOS prompt marker (A:\\> or C:\\>)
      baseline tail: #{baseline.fetch(:serial_tail).inspect}
      candidate tail: #{candidate.fetch(:serial_tail).inspect}
    MSG

    expect(candidate.fetch(:prompt)).to eq(baseline.fetch(:prompt)), <<~MSG
      DOS prompt mismatch for #{backend_label}
      expected prompt: #{baseline.fetch(:prompt).inspect}
      actual prompt: #{candidate.fetch(:prompt).inspect}
      baseline milestones: #{baseline.fetch(:milestones).inspect}
      candidate milestones: #{candidate.fetch(:milestones).inspect}
      baseline tail: #{baseline.fetch(:serial_tail).inspect}
      candidate tail: #{candidate.fetch(:serial_tail).inspect}
    MSG

    return if baseline.fetch(:milestones).empty? || candidate.fetch(:milestones).empty?

    expect(candidate.fetch(:milestones)).to eq(baseline.fetch(:milestones)), <<~MSG
      DOS milestone progression mismatch for #{backend_label}
      baseline milestones: #{baseline.fetch(:milestones).inspect}
      candidate milestones: #{candidate.fetch(:milestones).inspect}
      baseline tail: #{baseline.fetch(:serial_tail).inspect}
      candidate tail: #{candidate.fetch(:serial_tail).inspect}
    MSG
  end

  def run_dos_boot!(runner:, bios_system:, bios_video:, dos_image:, cycles:)
    option_sets = [
      { bios_system: bios_system, bios_video: bios_video, dos_image: dos_image, cycles: cycles },
      { bios_system_path: bios_system, bios_video_path: bios_video, dos_image_path: dos_image, cycles: cycles },
      { bios_system: bios_system, bios_video: bios_video, disk_image: dos_image, cycles: cycles },
      { bios: true, bios_system: bios_system, bios_video: bios_video, disk: dos_image, cycles: cycles },
      { bios: true, bios_system: bios_system, bios_video: bios_video, dos_image: dos_image }
    ]
    failures = []

    option_sets.each do |options|
      begin
        return runner.run_dos_boot(**options)
      rescue ArgumentError => e
        failures << e.message
      end
    end

    raise ArgumentError, "unable to call run_dos_boot with known option shapes: #{failures.uniq.join(" | ")}"
  end

  it "exposes DOS boot API on the headless runner" do
    expect(RHDL::Examples::AO486::HeadlessRunner.instance_methods(false)).to include(:run_dos_boot)
  end

  it "boots BIOS + DOS image to prompt milestone with backend progression parity", timeout: 1800 do
    skip "ao486 vendor hdl tree is unavailable" unless Dir.exist?(vendor_root)
    skip "Verilator not available" unless HdlToolchain.verilator_available?
    require_converted_runtime_artifacts!(out_dir: out_dir)

    system_bios = bios_system_path
    video_bios = bios_video_path
    dos_image = dos_image_path
    skip "missing BIOS system ROM (set RHDL_AO486_BIOS_SYSTEM)" if system_bios.nil?
    skip "missing BIOS video ROM (set RHDL_AO486_BIOS_VIDEO)" if video_bios.nil?
    skip "missing DOS image (set RHDL_AO486_DOS_IMAGE)" if dos_image.nil?

    vendor_runner = RHDL::Examples::AO486::HeadlessRunner.new(
      mode: :verilator,
      source_mode: :vendor,
      out_dir: out_dir,
      vendor_root: vendor_root,
      cwd: cwd
    )
    generated_verilator_runner = RHDL::Examples::AO486::HeadlessRunner.new(
      mode: :verilator,
      source_mode: :generated,
      out_dir: out_dir,
      vendor_root: vendor_root,
      cwd: cwd
    )

    baseline_run = run_dos_boot!(
      runner: vendor_runner,
      bios_system: system_bios,
      bios_video: video_bios,
      dos_image: dos_image,
      cycles: cycle_budget
    )
    baseline = summarized_boot(baseline_run)
    expect(baseline.fetch(:prompt)).not_to be_nil, <<~MSG
      vendor verilator baseline did not reach DOS prompt marker (A:\\> or C:\\>)
      baseline milestones: #{baseline.fetch(:milestones).inspect}
      baseline tail: #{baseline.fetch(:serial_tail).inspect}
    MSG

    backend_runners = {
      "generated_verilator" => generated_verilator_runner
    }
    if HdlToolchain.arcilator_available?
      backend_runners["generated_arcilator"] = RHDL::Examples::AO486::HeadlessRunner.new(
        mode: :arcilator,
        out_dir: out_dir,
        vendor_root: vendor_root,
        cwd: cwd
      )
    end
    if RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
      backend_runners["generated_ir_compiler"] = RHDL::Examples::AO486::HeadlessRunner.new(
        mode: :ir,
        backend: :compiler,
        allow_fallback: false,
        out_dir: out_dir,
        vendor_root: vendor_root,
        cwd: cwd
      )
    end
    if RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE
      backend_runners["generated_ir_interpreter"] = RHDL::Examples::AO486::HeadlessRunner.new(
        mode: :ir,
        backend: :interpreter,
        allow_fallback: false,
        out_dir: out_dir,
        vendor_root: vendor_root,
        cwd: cwd
      )
    end
    if RHDL::Codegen::IR::IR_JIT_AVAILABLE
      backend_runners["generated_ir_jit"] = RHDL::Examples::AO486::HeadlessRunner.new(
        mode: :ir,
        backend: :jit,
        allow_fallback: false,
        out_dir: out_dir,
        vendor_root: vendor_root,
        cwd: cwd
      )
    end

    expect(backend_runners).not_to be_empty

    backend_runners.each do |label, runner|
      run = run_dos_boot!(
        runner: runner,
        bios_system: system_bios,
        bios_video: video_bios,
        dos_image: dos_image,
        cycles: cycle_budget
      )
      summary = summarized_boot(run)
      assert_progression_parity!(
        baseline: baseline,
        candidate: summary,
        backend_label: label
      )
    rescue NotImplementedError => e
      skip "#{label} DOS boot backend is not implemented: #{e.message}"
    end
  rescue NotImplementedError => e
    skip "DOS boot API is not implemented for AO486 runners: #{e.message}"
  end
end
