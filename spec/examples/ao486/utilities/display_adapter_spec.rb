# frozen_string_literal: true

require "spec_helper"

require_relative "../../../../examples/ao486/utilities/display_adapter"

RSpec.describe RHDL::Examples::AO486::DisplayAdapter do
  it "renders RISC-V style mmap header/body with debug panel for trace frames" do
    adapter = described_class.new(io_mode: :vga, debug: true)
    trace = {
      "pc_sequence" => [0x000F_FFF0, 0x000F_FFF4],
      "instruction_sequence" => [0x9090_9090, 0xBB12_34B8],
      "memory_writes" => [{ "address" => 0x0000_0200, "data" => 0x0000_0001 }],
      "memory_contents" => { "00000200" => 0xABCD_1324 },
      "vga_text_lines" => ["Starting MS-DOS C:\\>", ""]
    }

    frame = adapter.render_trace_frame(
      mode: :ir,
      sim_backend: :compiler,
      speed: 100_000,
      trace: trace,
      trace_cursor: 2,
      replay_length: 2,
      program_base_address: 0x000F_FFF0,
      boot_addr: 0x0000_0000,
      bios: true,
      bios_system: "/tmp/boot0.rom",
      bios_video: "/tmp/boot1.rom",
      disk: "/tmp/dos4.img",
      root_path: "/tmp"
    )

    expect(frame).to include("AO486 MMAP View")
    expect(frame).to include("pc=0x000ffff4")
    expect(frame).to include("|PC:000FFFF4 INST:BB1234B8")
    expect(frame).to include("|BIOS0:boot0.rom")
    expect(frame).to include("Starting MS-DOS C:\\>")
    expect(frame).to include("+--------------------------------------------------------------------------------+")
  end

  it "renders a UART viewport for live frames" do
    adapter = described_class.new(io_mode: :uart, debug: false)
    state = {
      "pc" => 0x000F_FFF0,
      "instruction" => 0x9090_9090,
      "cycles" => 12_345,
      "memory_write_count" => 3,
      "serial_output" => "HELLO\r\nFROM\r\nAO486\r\n"
    }

    frame = adapter.render_live_frame(
      mode: :ir,
      sim_backend: :jit,
      speed: 10_000,
      state: state,
      program_base_address: 0x000F_FFF0,
      boot_addr: 0x0000_0000,
      bios: false,
      bios_system: nil,
      bios_video: nil,
      disk: nil,
      root_path: "/tmp"
    )

    expect(frame).to include("AO486 UART View")
    expect(frame).to include("HELLO")
    expect(frame).to include("FROM")
    expect(frame).to include("AO486")
  end

  it "keeps viewport height stable with fixed row count padding" do
    adapter = described_class.new(io_mode: :vga, debug: false, viewport_rows: 4, viewport_width: 20)
    state = {
      "pc" => 0x000F_FFF0,
      "instruction" => 0x9090_9090,
      "cycles" => 1,
      "memory_write_count" => 0,
      "memory_contents" => {},
      "vga_text_lines" => ["LINE1"]
    }

    frame = adapter.render_live_frame(
      mode: :ir,
      sim_backend: :compiler,
      speed: 1000,
      state: state,
      program_base_address: 0x000F_FFF0,
      boot_addr: 0x0000_0000,
      bios: false,
      bios_system: nil,
      bios_video: nil,
      disk: nil,
      root_path: "/tmp"
    )

    body_lines = frame.lines.reject { |line| line.start_with?("+") || line.start_with?("|") || line.start_with?("AO486") }
    # 4 viewport rows are always present after header.
    expect(body_lines.length).to be >= 4
  end
end
