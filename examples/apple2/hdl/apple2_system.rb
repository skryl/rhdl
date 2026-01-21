# frozen_string_literal: true

# Apple II System with integrated CPU
# This is the complete Apple II with CPU6502 integrated as a subcomponent

require 'rhdl/hdl'
require_relative 'apple2'
require_relative 'cpu6502'

module RHDL
  module Apple2
    class Apple2System < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      # Clock inputs
      input :clk_14m                     # 14.31818 MHz master clock
      input :flash_clk                   # ~2 Hz flashing character clock
      input :reset

      # RAM interface (external RAM)
      output :ram_addr, width: 16
      output :ram_we
      output :d, width: 8               # Data to RAM
      input :ram_do, width: 8           # Data from RAM

      # Peripheral data input
      input :pd, width: 8

      # Video outputs
      output :video
      output :color_line
      output :hbl
      output :vbl

      # Keyboard interface
      input :k, width: 8
      output :read_key

      # Audio
      output :speaker

      # Gameport
      input :gameport, width: 8
      output :pdl_strobe
      output :stb

      # Slot I/O
      output :io_select, width: 8
      output :device_select, width: 8

      # Annunciators
      output :an, width: 4

      # Debug outputs
      output :pc_debug, width: 16
      output :opcode_debug, width: 8
      output :a_debug, width: 8
      output :x_debug, width: 8
      output :y_debug, width: 8

      # Pause control
      input :pause

      # Subcomponents
      instance :apple2, Apple2
      instance :cpu, CPU6502

      # Internal wires
      wire :cpu_addr, width: 16
      wire :cpu_we
      wire :cpu_dout, width: 8
      wire :cpu_din, width: 8
      wire :cpu_enable
      wire :q3
      wire :pre_phi0

      # Connect Apple2 clock and control
      port :clk_14m => [:apple2, :clk_14m]
      port :flash_clk => [:apple2, :flash_clk]
      port :reset => [:apple2, :reset]

      # Connect Apple2 RAM interface
      port [:apple2, :ram_addr] => :ram_addr
      port [:apple2, :ram_we] => :ram_we
      port [:apple2, :d] => :d
      port :ram_do => [:apple2, :ram_do]

      # Connect Apple2 peripherals
      port :pd => [:apple2, :pd]
      port :k => [:apple2, :k]
      port :gameport => [:apple2, :gameport]
      port :pause => [:apple2, :pause]

      # Connect Apple2 video outputs
      port [:apple2, :video] => :video
      port [:apple2, :color_line] => :color_line
      port [:apple2, :hbl] => :hbl
      port [:apple2, :vbl] => :vbl

      # Connect Apple2 control outputs
      port [:apple2, :read_key] => :read_key
      port [:apple2, :speaker] => :speaker
      port [:apple2, :pdl_strobe] => :pdl_strobe
      port [:apple2, :stb] => :stb
      port [:apple2, :io_select] => :io_select
      port [:apple2, :device_select] => :device_select
      port [:apple2, :an] => :an

      # Get internal timing signals from Apple2 for CPU clocking
      port [:apple2, :clk_2m] => :q3
      port [:apple2, :pre_phase_zero] => :pre_phi0

      # Connect CPU inputs
      port :q3 => [:cpu, :clk]
      port :cpu_enable => [:cpu, :enable]
      port :reset => [:cpu, :reset]
      port :cpu_din => [:cpu, :di]

      # Connect CPU outputs
      port [:cpu, :addr] => :cpu_addr
      port [:cpu, :we] => :cpu_we
      port [:cpu, :do_out] => :cpu_dout

      # Connect CPU to Apple2
      port :cpu_addr => [:apple2, :cpu_addr]
      port :cpu_we => [:apple2, :cpu_we]
      port :cpu_dout => [:apple2, :cpu_dout]
      port [:apple2, :cpu_din] => :cpu_din

      # Connect debug outputs from CPU
      port [:cpu, :debug_pc] => :pc_debug
      port [:cpu, :debug_opcode] => :opcode_debug
      port [:cpu, :debug_a] => :a_debug
      port [:cpu, :debug_x] => :x_debug
      port [:cpu, :debug_y] => :y_debug
      port [:cpu, :debug_pc] => [:apple2, :cpu_pc]
      port [:cpu, :debug_opcode] => [:apple2, :cpu_opcode]

      # NMI and IRQ always inactive for basic Apple II
      wire :nmi_n
      wire :irq_n
      wire :so_n

      # Connect interrupt signals to CPU
      port :nmi_n => [:cpu, :nmi_n]
      port :irq_n => [:cpu, :irq_n]
      port :so_n => [:cpu, :so_n]

      behavior do
        # CPU enable: not pause and not pre_phase_zero (matches reference)
        cpu_enable <= ~pause & ~pre_phi0

        # Tie off interrupt inputs (active low, so 1 = inactive)
        nmi_n <= lit(1, width: 1)
        irq_n <= lit(1, width: 1)
        so_n <= lit(1, width: 1)
      end

      # Helper to load ROM
      def load_rom(data)
        @apple2.load_rom(data)
      end
    end
  end
end
