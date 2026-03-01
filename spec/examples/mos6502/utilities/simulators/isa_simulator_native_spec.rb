# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../examples/mos6502/utilities/simulators/isa_simulator_native'

RSpec.describe RHDL::Examples::MOS6502::ISASimulatorNative do
  before do
    skip 'Native ISA simulator not available' unless RHDL::Examples::MOS6502::NATIVE_AVAILABLE
  end

  let(:io_handler_class) do
    Class.new do
      attr_reader :reads, :writes

      def initialize
        @reads = []
        @writes = []
      end

      def io_read(addr)
        @reads << (addr & 0xFFFF)
        0xAB
      end

      def io_write(addr, value)
        @writes << [addr & 0xFFFF, value & 0xFF]
      end
    end
  end

  it 'executes a basic program and exposes register/state API' do
    cpu = described_class.new(nil)
    cpu.load_bytes([0xA9, 0x42, 0x00], 0x8000)
    cpu.poke(0xFFFC, 0x00)
    cpu.poke(0xFFFD, 0x80)

    cpu.reset
    cpu.step

    expect(cpu.a).to eq(0x42)
    expect(cpu.native?).to be(true)
    expect(cpu.halted?).to be(false)
    expect(cpu.state).to include(
      a: 0x42,
      x: cpu.x,
      y: cpu.y,
      sp: cpu.sp,
      pc: cpu.pc,
      p: cpu.p,
      cycles: cpu.cycles
    )
  end

  it 'uses io_read/io_write callbacks for disk controller addresses' do
    handler = io_handler_class.new
    cpu = described_class.new(handler)

    expect(cpu.has_io_handler?).to be(true)
    expect(cpu.read(0xC0E0)).to eq(0xAB)
    cpu.write(0xC0E0, 0x55)

    expect(handler.reads).to include(0xC0E0)
    expect(handler.writes).to include([0xC0E0, 0x55])
  end

  it 'supports keyboard, speaker, video, and rendering helpers' do
    cpu = described_class.new(nil)

    cpu.inject_key('A'.ord)
    expect(cpu.key_ready?).to be(true)
    expect(cpu.read(0xC000)).to eq(0xC1)
    cpu.read(0xC010)
    expect(cpu.key_ready?).to be(false)

    start_toggles = cpu.speaker_toggles
    cpu.read(0xC030)
    expect(cpu.speaker_toggles).to eq(start_toggles + 1)
    cpu.reset_speaker_toggles
    expect(cpu.speaker_toggles).to eq(0)

    cpu.set_video_state(true, false, false, false)
    cpu.read(0xC050) # graphics mode
    expect(cpu.video_state).to include(text: false)

    cpu.poke(0x2000, 0x7F)
    output = cpu.render_hires_braille(8, false)
    expect(output).to be_a(String)
  end
end
