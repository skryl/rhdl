# frozen_string_literal: true

# Apple II HDL Components
# Ruby HDL implementation based on neoapple2 reference
#
# This module provides a synthesizable Apple II implementation using RHDL.
# Components are based on Stephen A. Edwards' neoapple2 VHDL implementation.
#
# Components:
# - TimingGenerator: Clock divider and video timing generation
# - VideoGenerator: Text, LORES, and HIRES video output
# - CharacterROM: 64-character ROM for text display
# - Keyboard: PS/2 keyboard controller with US layout
# - RAM: 48KB main RAM
# - AudioPWM: PWM audio output
# - DiskII: Disk II floppy controller (read-only)
# - Apple2: Top-level integration
#
# Usage:
#   require 'examples/apple2/hdl'
#
#   # Create Apple II instance
#   apple = RHDL::Apple2::Apple2.new('apple2')
#
#   # Load ROM
#   apple.load_rom(rom_data)
#
#   # Run simulation
#   simulator = RHDL::Sim::Simulator.new(apple)
#   simulator.run(cycles)

require 'rhdl'

# Load all Apple II HDL components
require_relative 'hdl/timing_generator'
require_relative 'hdl/video_generator'
require_relative 'hdl/character_rom'
require_relative 'hdl/keyboard'
require_relative 'hdl/ram'
require_relative 'hdl/audio_pwm'
require_relative 'hdl/disk_ii'
require_relative 'hdl/apple2'

module RHDL
  module Apple2
    VERSION = '0.1.0'

    # Default clock frequency (14.31818 MHz)
    MASTER_CLOCK_HZ = 14_318_180

    # Memory map constants
    RAM_START = 0x0000
    RAM_END   = 0xBFFF
    IO_START  = 0xC000
    IO_END    = 0xC0FF
    ROM_START = 0xD000
    ROM_END   = 0xFFFF

    # I/O address constants
    KEYBOARD_ADDR    = 0xC000
    KEYBOARD_STROBE  = 0xC010
    SPEAKER_ADDR     = 0xC030
    SOFTSWITCH_ADDR  = 0xC050
    GAMEPORT_ADDR    = 0xC060
    PADDLE_ADDR      = 0xC070
    SLOT_IO_ADDR     = 0xC080

    # Soft switch bit positions
    SOFTSWITCH_TEXT   = 0
    SOFTSWITCH_MIXED  = 1
    SOFTSWITCH_PAGE2  = 2
    SOFTSWITCH_HIRES  = 3
    SOFTSWITCH_AN0    = 4
    SOFTSWITCH_AN1    = 5
    SOFTSWITCH_AN2    = 6
    SOFTSWITCH_AN3    = 7

    # Video timing constants
    HORIZONTAL_TOTAL  = 65    # 65 character times per line
    VERTICAL_TOTAL    = 262   # 262 lines per frame
    HORIZONTAL_BLANK  = 25    # Horizontal blank cycles
    VERTICAL_BLANK    = 70    # Vertical blank lines

    # Display dimensions
    TEXT_COLS         = 40
    TEXT_ROWS         = 24
    LORES_WIDTH       = 40
    LORES_HEIGHT      = 48
    HIRES_WIDTH       = 280
    HIRES_HEIGHT      = 192

    # Disk II constants
    TRACKS_PER_DISK   = 35
    BYTES_PER_TRACK   = 6656  # 0x1A00 nibblized
    PHASES_PER_TRACK  = 2

    # Helper to create a complete Apple II system
    def self.create_system(name: 'apple2', with_disk: true)
      apple = Apple2.new(name)

      if with_disk
        # Disk II would be connected to slot 6
        # disk = DiskII.new("#{name}_disk")
        # Connect to slot 6 I/O
      end

      apple
    end
  end
end
