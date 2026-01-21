# frozen_string_literal: true

# Apple II Top-Level Module
# Based on Stephen A. Edwards' neoapple2 implementation
#
# This is the top-level HDL module that integrates all Apple II components:
# - MOS 6502 CPU
# - Timing generator
# - Video generator
# - Character ROM
# - RAM (48KB)
# - Keyboard controller
# - Speaker/Audio
# - Disk II controller (optional)
#
# Memory Map:
# $0000-$BFFF: RAM (48KB)
# $C000-$C0FF: I/O space
#   $C000-$C00F: Keyboard
#   $C010-$C01F: Keyboard strobe clear
#   $C030-$C03F: Speaker toggle
#   $C050-$C05F: Soft switches
#   $C060-$C06F: Gameport
#   $C070-$C07F: Paddle trigger
#   $C080-$C0FF: Slot I/O
# $C100-$CFFF: Peripheral ROM space
# $D000-$FFFF: ROM (12KB)

require 'rhdl/hdl'
require_relative 'timing_generator'
require_relative 'video_generator'
require_relative 'character_rom'
require_relative 'keyboard'
require_relative 'ram'
require_relative 'audio_pwm'
require_relative 'disk_ii'

module RHDL
  module Apple2
    class Apple2 < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential
      include RHDL::DSL::Memory

      # Clock inputs
      input :clk_14m                     # 14.31818 MHz master clock
      input :flash_clk                   # ~2 Hz flashing character clock
      input :reset

      # Clock outputs
      output :clk_2m                     # 2 MHz clock
      output :pre_phase_zero             # One 14M cycle before PHI0

      # CPU address/data bus
      output :addr, width: 16            # CPU address
      output :ram_addr, width: 16        # RAM address (muxed with video)
      output :d, width: 8                # Data to RAM
      input :ram_do, width: 8            # Data from RAM
      input :pd, width: 8                # Data from peripherals
      output :ram_we                     # RAM write enable

      # Video outputs
      output :video                      # Serial video output
      output :color_line                 # Color burst enable
      output :hbl                        # Horizontal blanking
      output :vbl                        # Vertical blanking
      output :ld194                      # Load signal

      # Keyboard interface
      input :k, width: 8                 # Keyboard data
      output :read_key                   # Keyboard read strobe

      # Annunciator outputs
      output :an, width: 4               # Annunciator outputs

      # Gameport interface
      input :gameport, width: 8          # Gameport input
      output :pdl_strobe                 # Paddle strobe (C07x read)
      output :stb                        # Strobe (C04x read)

      # Slot I/O
      output :io_select, width: 8        # Slot ROM select ($Cnxx)
      output :device_select, width: 8    # Slot I/O select ($C0nx)

      # Debug outputs
      output :pc_debug_out, width: 16    # CPU program counter
      output :opcode_debug_out, width: 8 # Current opcode

      # Audio output
      output :speaker                    # 1-bit speaker output

      # Pause control
      input :pause                       # Pause CPU execution

      # CPU interface (directly exposed as ports)
      input :cpu_addr, width: 16         # CPU address bus
      input :cpu_we                      # CPU write enable
      input :cpu_dout, width: 8          # CPU data output
      input :cpu_pc, width: 16           # CPU program counter (debug)
      input :cpu_opcode, width: 8        # CPU current opcode (debug)
      output :cpu_din, width: 8          # CPU data input

      # ROM memory (12KB: $D000-$FFFF)
      memory :main_rom, depth: 12 * 1024, width: 8, readonly: true

      # Sub-components
      instance :timing, TimingGenerator
      instance :video_gen, VideoGenerator
      instance :char_rom, CharacterROM
      instance :speaker_toggle, SpeakerToggle

      # Internal wires for clocks
      wire :clk_7m
      wire :q3
      wire :ras_n
      wire :cas_n
      wire :ax
      wire :phi0
      wire :pre_phi0
      wire :color_ref

      # Internal wires for video
      wire :video_address, width: 16
      wire :h0
      wire :va
      wire :vb
      wire :vc
      wire :v2
      wire :v4
      wire :blank
      wire :ldps_n
      wire :ld194_i
      wire :hires

      # Sequential state registers
      wire :soft_switches, width: 8
      wire :speaker_select_latch
      wire :dl, width: 8

      # Decoded soft switch signals
      wire :text_mode
      wire :mixed_mode
      wire :page2
      wire :hires_mode

      # Connect timing generator
      port :clk_14m => [:timing, :clk_14m]
      port [:timing, :clk_7m] => :clk_7m
      port [:timing, :q3] => :q3
      port [:timing, :ras_n] => :ras_n
      port [:timing, :cas_n] => :cas_n
      port [:timing, :ax] => :ax
      port [:timing, :phi0] => :phi0
      port [:timing, :pre_phi0] => :pre_phi0
      port [:timing, :color_ref] => :color_ref
      port [:timing, :video_address] => :video_address
      port [:timing, :h0] => :h0
      port [:timing, :va] => :va
      port [:timing, :vb] => :vb
      port [:timing, :vc] => :vc
      port [:timing, :v2] => :v2
      port [:timing, :v4] => :v4
      port [:timing, :hbl] => :hbl
      port [:timing, :vbl] => :vbl
      port [:timing, :blank] => :blank
      port [:timing, :ldps_n] => :ldps_n
      port [:timing, :ld194] => :ld194_i
      port :text_mode => [:timing, :text_mode]
      port :page2 => [:timing, :page2]
      port :hires => [:timing, :hires]

      # Connect video generator
      port :clk_14m => [:video_gen, :clk_14m]
      port :clk_7m => [:video_gen, :clk_7m]
      port :ax => [:video_gen, :ax]
      port :cas_n => [:video_gen, :cas_n]
      port :h0 => [:video_gen, :h0]
      port :va => [:video_gen, :va]
      port :vb => [:video_gen, :vb]
      port :vc => [:video_gen, :vc]
      port :v2 => [:video_gen, :v2]
      port :v4 => [:video_gen, :v4]
      port :blank => [:video_gen, :blank]
      port :ldps_n => [:video_gen, :ldps_n]
      port :ld194_i => [:video_gen, :ld194]
      port :flash_clk => [:video_gen, :flash_clk]
      port :text_mode => [:video_gen, :text_mode]
      port :page2 => [:video_gen, :page2]
      port :hires_mode => [:video_gen, :hires_mode]
      port :mixed_mode => [:video_gen, :mixed_mode]
      port :dl => [:video_gen, :dl]
      port [:video_gen, :hires] => :hires
      port [:video_gen, :video] => :video
      port [:video_gen, :color_line] => :color_line

      # Connect character ROM
      port :clk_14m => [:char_rom, :clk]

      # Connect speaker toggle
      port :q3 => [:speaker_toggle, :clk]
      port :speaker_select_latch => [:speaker_toggle, :toggle]
      port [:speaker_toggle, :speaker] => :speaker

      # Soft switches state
      sequential clock: :q3, reset: :reset, reset_values: {
        soft_switches: 0,
        speaker_select_latch: 0,
        dl: 0
      } do
        # RAM data latch (on rising edge of AX when CAS and RAS are low)
        dl <= mux(ax & ~cas_n & ~ras_n, ram_do, dl)

        # Soft switch updates
        softswitch_select = (cpu_addr[15..12] == lit(0xC, width: 4)) &
                            (cpu_addr[11..8] == lit(0x0, width: 4)) &
                            (cpu_addr[7..4] == lit(0x5, width: 4))

        soft_switches <= mux(pre_phi0 & softswitch_select,
          (soft_switches & ~(lit(1, width: 8) << cpu_addr[3..1])) |
          (mux(cpu_addr[0], lit(1, width: 8), lit(0, width: 8)) << cpu_addr[3..1]),
          soft_switches
        )

        # Speaker toggle
        speaker_select = (cpu_addr[15..12] == lit(0xC, width: 4)) &
                        (cpu_addr[11..8] == lit(0x0, width: 4)) &
                        (cpu_addr[7..4] == lit(0x3, width: 4))

        speaker_select_latch <= pre_phi0 & speaker_select
      end

      # Combinational logic
      behavior do
        # Clock outputs
        clk_2m <= q3
        pre_phase_zero <= pre_phi0
        ld194 <= ld194_i

        # RAM address mux (CPU or video)
        ram_addr <= mux(phi0, cpu_addr, video_address)

        # RAM write enable
        ram_we <= cpu_we & ~ras_n & phi0

        # Soft switch decoding
        text_mode <= soft_switches[0]
        mixed_mode <= soft_switches[1]
        page2 <= soft_switches[2]
        hires_mode <= soft_switches[3]
        an <= soft_switches[7..4]

        # Address decoding
        a_hi = cpu_addr[15..12]
        a_mid = cpu_addr[11..8]
        a_lo = cpu_addr[7..4]

        # ROM select: $D000-$FFFF
        rom_select = (a_hi == lit(0xD, width: 4)) |
                     (a_hi == lit(0xE, width: 4)) |
                     (a_hi == lit(0xF, width: 4))

        # RAM select: $0000-$BFFF
        ram_select = ~cpu_addr[15] | (~cpu_addr[14] & ~cpu_addr[15])

        # Keyboard select: $C000-$C00F
        keyboard_select = (a_hi == lit(0xC, width: 4)) &
                         (a_mid == lit(0x0, width: 4)) &
                         (a_lo == lit(0x0, width: 4))

        # Read key strobe: $C010-$C01F
        read_key <= (a_hi == lit(0xC, width: 4)) &
                   (a_mid == lit(0x0, width: 4)) &
                   (a_lo == lit(0x1, width: 4))

        # Gameport select: $C060-$C06F
        gameport_select = (a_hi == lit(0xC, width: 4)) &
                         (a_mid == lit(0x0, width: 4)) &
                         (a_lo == lit(0x6, width: 4))

        # Paddle strobe: $C070-$C07F
        pdl_strobe <= (a_hi == lit(0xC, width: 4)) &
                     (a_mid == lit(0x0, width: 4)) &
                     (a_lo == lit(0x7, width: 4))

        # STB: $C040-$C04F
        stb <= (a_hi == lit(0xC, width: 4)) &
              (a_mid == lit(0x0, width: 4)) &
              (a_lo == lit(0x4, width: 4))

        # Slot I/O select: $C080-$C0FF
        device_select_addr = (a_hi == lit(0xC, width: 4)) &
                            (a_mid == lit(0x0, width: 4)) &
                            (cpu_addr[7] == lit(1, width: 1))

        device_select <= mux(device_select_addr,
          lit(1, width: 8) << cpu_addr[6..4],
          lit(0, width: 8)
        )

        # Slot ROM select: $C100-$C7FF
        io_select_addr = (a_hi == lit(0xC, width: 4)) &
                        (a_mid[3] == lit(0, width: 1)) &
                        (a_mid != lit(0x0, width: 4))

        io_select <= mux(io_select_addr,
          lit(1, width: 8) << cpu_addr[10..8],
          lit(0, width: 8)
        )

        # ROM address mapping
        # $D000-$DFFF -> $0000-$0FFF
        # $E000-$EFFF -> $1000-$1FFF
        # $F000-$FFFF -> $2000-$2FFF
        rom_addr_mapped = cat((cpu_addr[13] & cpu_addr[12]), ~cpu_addr[12], cpu_addr[11..0])

        # Data input mux to CPU
        # Read from ROM with computed address
        rom_out = mem_read_expr(:main_rom, rom_addr_mapped, width: 8)
        gameport_data = cat(gameport[cpu_addr[2..0]], lit(0, width: 7))

        cpu_din <= mux(ram_select, dl,
          mux(keyboard_select, k,
            mux(gameport_select, gameport_data,
              mux(rom_select, rom_out,
                pd
              )
            )
          )
        )

        # CPU data output
        d <= cpu_dout

        # Address output
        addr <= cpu_addr

        # Debug outputs
        pc_debug_out <= cpu_pc
        opcode_debug_out <= cpu_opcode
      end

      # Simulation helpers for ROM access
      def load_rom(data, start_addr = 0)
        data.each_with_index do |byte, i|
          break if start_addr + i >= 12 * 1024
          mem_write(:main_rom, start_addr + i, byte, 8)
        end
      end

      def read_rom(addr)
        mem_read(:main_rom, addr & 0x2FFF)
      end
    end

    # VGA output adapter
    # Converts Apple II video signal to VGA timing
    class VGAOutput < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      # Inputs from Apple II
      input :clk_14m
      input :video                       # Serial video from Apple II
      input :color_line                  # Color burst enable
      input :hbl                         # Horizontal blanking
      input :vbl                         # Vertical blanking

      # VGA outputs
      output :vga_r, width: 4
      output :vga_g, width: 4
      output :vga_b, width: 4
      output :vga_hsync
      output :vga_vsync

      # Internal registers
      wire :pixel_count, width: 10
      wire :line_count, width: 10
      wire :pixel_data

      sequential clock: :clk_14m, reset_values: {
        pixel_count: 0,
        line_count: 0,
        pixel_data: 0
      } do
        # VGA timing generation
        # Standard VGA: 640x480 @ 60Hz
        # Pixel clock: 25.175 MHz

        # Simplified: use 14M clock and scale appropriately
        pixel_count <= mux(pixel_count == lit(910, width: 10),
          lit(0, width: 10),
          pixel_count + lit(1, width: 10)
        )

        line_count <= mux(pixel_count == lit(910, width: 10),
          mux(line_count == lit(524, width: 10),
            lit(0, width: 10),
            line_count + lit(1, width: 10)
          ),
          line_count
        )

        # Capture video data
        pixel_data <= video
      end

      behavior do
        # Generate sync signals
        vga_hsync <= ~((pixel_count >= lit(656, width: 10)) &
                       (pixel_count < lit(752, width: 10)))
        vga_vsync <= ~((line_count >= lit(490, width: 10)) &
                       (line_count < lit(492, width: 10)))

        # Generate RGB from monochrome video
        # White on black for text, could add color later
        active = ~hbl & ~vbl

        vga_r <= mux(active & pixel_data, lit(0xF, width: 4), lit(0, width: 4))
        vga_g <= mux(active & pixel_data, lit(0xF, width: 4), lit(0, width: 4))
        vga_b <= mux(active & pixel_data, lit(0xF, width: 4), lit(0, width: 4))
      end
    end
  end
end
