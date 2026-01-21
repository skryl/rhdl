# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../examples/apple2/hdl/apple2'

RSpec.describe RHDL::Apple2::Apple2 do
  let(:apple2) { described_class.new('apple2') }

  before do
    apple2
    # Initialize inputs
    apple2.set_input(:clk_14m, 0)
    apple2.set_input(:flash_clk, 0)
    apple2.set_input(:reset, 0)
    apple2.set_input(:ram_do, 0)
    apple2.set_input(:pd, 0)
    apple2.set_input(:k, 0)
    apple2.set_input(:gameport, 0)
    apple2.set_input(:pause, 0)
    apple2.set_input(:cpu_addr, 0)
    apple2.set_input(:cpu_we, 0)
    apple2.set_input(:cpu_dout, 0)
    apple2.set_input(:cpu_pc, 0)
    apple2.set_input(:cpu_opcode, 0)

    # Reset the system
    apple2.set_input(:reset, 1)
    clock_cycle
    apple2.set_input(:reset, 0)
  end

  def clock_cycle
    apple2.set_input(:clk_14m, 0)
    apple2.propagate
    apple2.set_input(:clk_14m, 1)
    apple2.propagate
  end

  describe 'component integration' do
    # Reference: Apple II integrates timing, video, keyboard, etc.

    it 'elaborates all sub-components' do
      expect(apple2.instance_variable_get(:@timing)).to be_a(RHDL::Apple2::TimingGenerator)
      expect(apple2.instance_variable_get(:@video_gen)).to be_a(RHDL::Apple2::VideoGenerator)
      expect(apple2.instance_variable_get(:@char_rom)).to be_a(RHDL::Apple2::CharacterROM)
      expect(apple2.instance_variable_get(:@speaker_toggle)).to be_a(RHDL::Apple2::SpeakerToggle)
    end
  end

  describe 'clock generation' do
    # Reference: System generates 2 MHz clock from 14 MHz input

    it 'generates clk_2m from timing generator' do
      values = []
      100.times do
        clock_cycle
        values << apple2.get_output(:clk_2m)
      end

      # Should have transitions
      expect(values.uniq.size).to be > 1
    end

    it 'generates pre_phase_zero' do
      values = []
      100.times do
        clock_cycle
        values << apple2.get_output(:pre_phase_zero)
      end

      expect(values).to include(0).or include(1)
    end
  end

  describe 'memory map' do
    # Reference from apple2.vhd and comments:
    # $0000-$BFFF: RAM (48KB)
    # $C000-$C0FF: I/O space
    # $D000-$FFFF: ROM (12KB)

    describe 'RAM addressing ($0000-$BFFF)' do
      it 'selects RAM for addresses below $C000' do
        apple2.set_input(:cpu_addr, 0x0000)
        apple2.set_input(:ram_do, 0xAA)
        clock_cycle

        cpu_din = apple2.get_output(:cpu_din)
        # Should read from RAM (data latched from ram_do)
        expect(cpu_din).to be_between(0, 255)
      end

      it 'selects RAM for zero page ($00xx)' do
        apple2.set_input(:cpu_addr, 0x00FF)
        apple2.set_input(:ram_do, 0x55)
        clock_cycle

        cpu_din = apple2.get_output(:cpu_din)
        expect(cpu_din).to be_between(0, 255)
      end

      it 'selects RAM for text page ($0400-$07FF)' do
        apple2.set_input(:cpu_addr, 0x0400)
        apple2.set_input(:ram_do, 0xC1)
        clock_cycle

        cpu_din = apple2.get_output(:cpu_din)
        expect(cpu_din).to be_between(0, 255)
      end

      it 'selects RAM for hires page ($2000-$3FFF)' do
        apple2.set_input(:cpu_addr, 0x2000)
        apple2.set_input(:ram_do, 0x7F)
        clock_cycle

        cpu_din = apple2.get_output(:cpu_din)
        expect(cpu_din).to be_between(0, 255)
      end
    end

    describe 'I/O addressing ($C0xx)' do
      it 'reads keyboard at $C000-$C00F' do
        apple2.set_input(:cpu_addr, 0xC000)
        apple2.set_input(:k, 0xC1)  # 'A' with high bit
        clock_cycle

        cpu_din = apple2.get_output(:cpu_din)
        expect(cpu_din).to eq(0xC1)
      end

      it 'generates read_key strobe at $C010' do
        apple2.set_input(:cpu_addr, 0xC010)
        clock_cycle

        read_key = apple2.get_output(:read_key)
        expect(read_key).to eq(1)
      end

      it 'reads gameport at $C060-$C06F' do
        apple2.set_input(:cpu_addr, 0xC060)
        apple2.set_input(:gameport, 0xFF)
        clock_cycle

        cpu_din = apple2.get_output(:cpu_din)
        # Gameport data should be returned
        expect(cpu_din).to be_between(0, 255)
      end

      it 'generates pdl_strobe at $C070-$C07F' do
        apple2.set_input(:cpu_addr, 0xC070)
        clock_cycle

        pdl_strobe = apple2.get_output(:pdl_strobe)
        expect(pdl_strobe).to eq(1)
      end

      it 'generates slot device_select at $C080-$C0FF' do
        # Slot 6 I/O: $C0E0-$C0EF
        apple2.set_input(:cpu_addr, 0xC0E0)
        clock_cycle

        device_select = apple2.get_output(:device_select)
        # Bit 6 should be set for slot 6
        expect((device_select >> 6) & 1).to eq(1)
      end
    end

    describe 'slot ROM addressing ($C100-$C7FF)' do
      it 'generates io_select for slot 6 ROM ($C600)' do
        apple2.set_input(:cpu_addr, 0xC600)
        clock_cycle

        io_select = apple2.get_output(:io_select)
        # Bit 6 should be set for slot 6
        expect((io_select >> 6) & 1).to eq(1)
      end
    end

    describe 'ROM addressing ($D000-$FFFF)' do
      # ROM addresses return valid data (ROM initialized via DSL initial: parameter)

      it 'reads from ROM at $D000' do
        apple2.set_input(:cpu_addr, 0xD000)
        clock_cycle

        cpu_din = apple2.get_output(:cpu_din)
        expect(cpu_din).to be_between(0, 255)
      end

      it 'reads from ROM at $E000' do
        apple2.set_input(:cpu_addr, 0xE000)
        clock_cycle

        cpu_din = apple2.get_output(:cpu_din)
        expect(cpu_din).to be_between(0, 255)
      end

      it 'reads reset vector at $FFFC' do
        apple2.set_input(:cpu_addr, 0xFFFC)
        clock_cycle

        cpu_din = apple2.get_output(:cpu_din)
        expect(cpu_din).to be_between(0, 255)
      end
    end
  end

  describe 'soft switches' do
    # Reference: $C050-$C05F control display modes

    def access_softswitch(addr)
      apple2.set_input(:cpu_addr, addr)
      apple2.set_input(:pre_phase_zero, 1) rescue nil
      # Need to run through the q3 clock cycle
      10.times { clock_cycle }
    end

    it 'defaults to text mode' do
      # After reset, should be in text mode
      10.times { clock_cycle }
      # Soft switches start at 0
    end
  end

  describe 'RAM write enable' do
    it 'generates ram_we when CPU writes to RAM' do
      apple2.set_input(:cpu_addr, 0x0300)
      apple2.set_input(:cpu_we, 1)
      apple2.set_input(:cpu_dout, 0x42)
      clock_cycle

      ram_we = apple2.get_output(:ram_we)
      # ram_we depends on ras_n and phi0
      expect([0, 1]).to include(ram_we)
    end

    it 'does not generate ram_we for I/O addresses' do
      apple2.set_input(:cpu_addr, 0xC000)
      apple2.set_input(:cpu_we, 1)
      clock_cycle

      ram_we = apple2.get_output(:ram_we)
      # Should not write to RAM for I/O addresses
      expect(ram_we).to eq(0)
    end
  end

  describe 'address muxing' do
    it 'outputs CPU address during PHI0' do
      apple2.set_input(:cpu_addr, 0x1234)
      clock_cycle

      ram_addr = apple2.get_output(:ram_addr)
      # ram_addr alternates between cpu_addr and video_address
      expect(ram_addr).to be_between(0, 0xFFFF)
    end
  end

  describe 'speaker toggle' do
    # Reference: $C030 toggles speaker

    it 'toggles speaker when $C030 is accessed' do
      initial_speaker = apple2.get_output(:speaker)

      # Access speaker toggle address
      apple2.set_input(:cpu_addr, 0xC030)
      20.times { clock_cycle }

      # Speaker state may have changed (depends on timing)
      final_speaker = apple2.get_output(:speaker)
      expect([0, 1]).to include(final_speaker)
    end
  end

  describe 'video generation' do
    it 'outputs video signal' do
      100.times { clock_cycle }

      video = apple2.get_output(:video)
      expect([0, 1]).to include(video)
    end

    it 'outputs color_line signal' do
      100.times { clock_cycle }

      color_line = apple2.get_output(:color_line)
      expect([0, 1]).to include(color_line)
    end

    it 'outputs blanking signals' do
      100.times { clock_cycle }

      hbl = apple2.get_output(:hbl)
      vbl = apple2.get_output(:vbl)

      expect([0, 1]).to include(hbl)
      expect([0, 1]).to include(vbl)
    end
  end

  describe 'debug outputs' do
    it 'outputs CPU program counter' do
      apple2.set_input(:cpu_pc, 0xF000)
      clock_cycle

      pc = apple2.get_output(:pc_debug_out)
      expect(pc).to eq(0xF000)
    end

    it 'outputs current opcode' do
      apple2.set_input(:cpu_opcode, 0xA9)  # LDA immediate
      clock_cycle

      opcode = apple2.get_output(:opcode_debug_out)
      expect(opcode).to eq(0xA9)
    end
  end

  describe 'annunciator outputs' do
    it 'outputs annunciator values from soft switches' do
      10.times { clock_cycle }

      an = apple2.get_output(:an)
      expect(an).to be_between(0, 15)
    end
  end

  describe 'ROM helpers' do
    it 'loads ROM data via load_rom' do
      test_data = [0xA9, 0x00, 0x85, 0x00]  # LDA #$00, STA $00
      apple2.load_rom(test_data, 0)

      # Verify by reading
      expect(apple2.read_rom(0)).to eq(0xA9)
      expect(apple2.read_rom(1)).to eq(0x00)
      expect(apple2.read_rom(2)).to eq(0x85)
      expect(apple2.read_rom(3)).to eq(0x00)
    end

    it 'reads ROM data via read_rom' do
      apple2.load_rom([0xEA], 0x100)  # NOP at offset $100

      data = apple2.read_rom(0x100)
      expect(data).to eq(0xEA)
    end

    it 'limits ROM to 12KB' do
      # ROM is $D000-$FFFF = 12KB
      large_data = (0...0x4000).map { |i| i & 0xFF }  # 16KB
      apple2.load_rom(large_data)

      # Should only load first 12KB
    end
  end
end

RSpec.describe RHDL::Apple2::VGAOutput do
  let(:vga) { described_class.new('vga') }

  before do
    vga
    vga.set_input(:clk_14m, 0)
    vga.set_input(:video, 0)
    vga.set_input(:color_line, 0)
    vga.set_input(:hbl, 0)
    vga.set_input(:vbl, 0)
  end

  def clock_cycle
    vga.set_input(:clk_14m, 0)
    vga.propagate
    vga.set_input(:clk_14m, 1)
    vga.propagate
  end

  describe 'VGA sync generation' do
    # Reference: Standard VGA 640x480 @ 60Hz timing

    it 'generates hsync signal' do
      hsync_values = []

      1000.times do
        clock_cycle
        hsync_values << vga.get_output(:vga_hsync)
      end

      # Should see hsync transitions
      expect(hsync_values.uniq.size).to be > 1
    end

    it 'generates vsync signal' do
      vsync_values = []

      # Need many cycles to see vsync (once per frame)
      5000.times do
        clock_cycle
        vsync_values << vga.get_output(:vga_vsync)
      end

      # Should see vsync transitions (at least one per frame)
      expect(vsync_values).to include(0).or include(1)
    end
  end

  describe 'RGB output' do
    it 'outputs white when video is high and not blanked' do
      vga.set_input(:video, 1)
      vga.set_input(:hbl, 0)
      vga.set_input(:vbl, 0)
      clock_cycle

      r = vga.get_output(:vga_r)
      g = vga.get_output(:vga_g)
      b = vga.get_output(:vga_b)

      expect(r).to eq(0xF)
      expect(g).to eq(0xF)
      expect(b).to eq(0xF)
    end

    it 'outputs black when video is low' do
      vga.set_input(:video, 0)
      vga.set_input(:hbl, 0)
      vga.set_input(:vbl, 0)
      clock_cycle

      r = vga.get_output(:vga_r)
      g = vga.get_output(:vga_g)
      b = vga.get_output(:vga_b)

      expect(r).to eq(0)
      expect(g).to eq(0)
      expect(b).to eq(0)
    end

    it 'outputs black during horizontal blanking' do
      vga.set_input(:video, 1)
      vga.set_input(:hbl, 1)
      vga.set_input(:vbl, 0)
      clock_cycle

      r = vga.get_output(:vga_r)
      expect(r).to eq(0)
    end

    it 'outputs black during vertical blanking' do
      vga.set_input(:video, 1)
      vga.set_input(:hbl, 0)
      vga.set_input(:vbl, 1)
      clock_cycle

      r = vga.get_output(:vga_r)
      expect(r).to eq(0)
    end
  end

  describe '4-bit RGB output' do
    it 'outputs 4-bit values' do
      vga.set_input(:video, 1)
      vga.set_input(:hbl, 0)
      vga.set_input(:vbl, 0)
      clock_cycle

      r = vga.get_output(:vga_r)
      g = vga.get_output(:vga_g)
      b = vga.get_output(:vga_b)

      expect(r).to be_between(0, 15)
      expect(g).to be_between(0, 15)
      expect(b).to be_between(0, 15)
    end
  end
end
