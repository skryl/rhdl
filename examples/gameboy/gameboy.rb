# Game Boy RHDL Implementation
# addr_bus 1:1 port of the MiSTer Gameboy_MiSTer reference implementation
#
# Reference: https://github.com/MiSTer-devel/Gameboy_MiSTer
#
# This implementation mirrors the reference Verilog/VHDL files:
# - cpu/ - SM83/T80 CPU (Z80 variant in Mode 3)
# - ppu/ - Video/PPU subsystem (video.v, sprites.v, lcd.v)
# - apu/ - Audio/Sound subsystem (gbc_snd.vhd)
# - memory/ - Memory controllers (dpram.vhd, spram.vhd)
# - mappers/ - Memory bank controllers (mbc1-7, huc1/3, etc.)
# - dma/ - DMA controllers (hdma.v)

require_relative '../../lib/rhdl'
require_relative '../../lib/rhdl/dsl/behavior'
require_relative '../../lib/rhdl/dsl/sequential'

# Load all subcomponents (order matters for dependencies)

# CPU components (load dependencies first)
require_relative 'hdl/cpu/alu'
require_relative 'hdl/cpu/registers'
require_relative 'hdl/cpu/mcode'
require_relative 'hdl/cpu/sm83'

# PPU components
require_relative 'hdl/ppu/sprites'
require_relative 'hdl/ppu/lcd'
require_relative 'hdl/ppu/video'

# APU components (load channels before sound)
require_relative 'hdl/apu/channel_square'
require_relative 'hdl/apu/channel_wave'
require_relative 'hdl/apu/channel_noise'
require_relative 'hdl/apu/sound'

# Memory and DMA
require_relative 'hdl/memory/dpram'
require_relative 'hdl/memory/spram'
require_relative 'hdl/dma/hdma'

# Mappers
require_relative 'hdl/mappers/mappers'

# Timer and Link
require_relative 'hdl/timer'
require_relative 'hdl/link'

# Clock generator
require_relative 'hdl/speedcontrol'

# Top-level Game Boy module (requires all above)
require_relative 'hdl/gb'

module GameBoy
  VERSION = '0.1.0'

  # Game Boy Top-Level Wrapper
  # Includes GB core and SpeedControl clock generator
  #
  # This is the complete Game Boy system with internal clock generation.
  # Use this module for simulation instead of the bare GB module.
  class Gameboy < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    # Clock and reset
    input :reset
    input :clk_sys

    # Configuration
    input :joystick, width: 8
    input :is_gbc              # Game Boy Color mode
    input :is_sgb              # Super Game Boy mode

    # Cartridge interface
    output :ext_bus_addr, width: 15
    output :ext_bus_a15
    output :cart_rd
    output :cart_wr
    input :cart_do, width: 8
    output :cart_di, width: 8

    # LCD interface
    output :lcd_clkena
    output :lcd_data, width: 15
    output :lcd_data_gb, width: 2
    output :lcd_mode, width: 2
    output :lcd_on
    output :lcd_vsync

    # Audio outputs
    output :audio_l, width: 16
    output :audio_r, width: 16

    # Debug outputs (for Verilator simulation visibility)
    output :debug_pc, width: 16    # CPU Program counter
    output :debug_acc, width: 8    # CPU Accumulator

    # Internal clock enable signals
    wire :ce
    wire :ce_n
    wire :ce_2x
    wire :cart_act

    # Constant tie-offs
    wire :const_zero
    wire :const_one
    wire :const_zero_4, width: 4
    wire :const_zero_8, width: 8
    wire :const_zero_16, width: 16
    wire :const_zero_25, width: 25
    wire :const_zero_129, width: 129
    wire :const_zero_2, width: 2

    # Sub-component instances
    instance :speed_ctrl, SpeedControl
    instance :gb_core, GB

    # Clock to speed control
    port :clk_sys => [:speed_ctrl, :clk_sys]
    port :reset => [:speed_ctrl, :reset]
    port :const_zero => [:speed_ctrl, :pause]
    port :const_zero => [:speed_ctrl, :speedup]
    port :cart_act => [:speed_ctrl, :cart_act]
    port :const_zero => [:speed_ctrl, :dma_on]

    # Speed control outputs
    port [:speed_ctrl, :ce] => :ce
    port [:speed_ctrl, :ce_n] => :ce_n
    port [:speed_ctrl, :ce_2x] => :ce_2x

    # Clock to GB core
    port :clk_sys => [:gb_core, :clk_sys]
    port :reset => [:gb_core, :reset]
    port :ce => [:gb_core, :ce]
    port :ce_n => [:gb_core, :ce_n]
    port :ce_2x => [:gb_core, :ce_2x]

    # Configuration to GB
    port :joystick => [:gb_core, :joystick]
    port :is_gbc => [:gb_core, :is_gbc]
    port :is_sgb => [:gb_core, :is_sgb]
    port :const_zero => [:gb_core, :megaduck]
    port :const_zero => [:gb_core, :extra_spr_en]

    # Cartridge interface
    port [:gb_core, :ext_bus_addr] => :ext_bus_addr
    port [:gb_core, :ext_bus_a15] => :ext_bus_a15
    port [:gb_core, :cart_rd] => :cart_rd
    port [:gb_core, :cart_wr] => :cart_wr
    port :cart_do => [:gb_core, :cart_do]
    port [:gb_core, :cart_di] => :cart_di
    port :const_one => [:gb_core, :cart_oe]

    # LCD outputs
    port [:gb_core, :lcd_clkena] => :lcd_clkena
    port [:gb_core, :lcd_data] => :lcd_data
    port [:gb_core, :lcd_data_gb] => :lcd_data_gb
    port [:gb_core, :lcd_mode] => :lcd_mode
    port [:gb_core, :lcd_on] => :lcd_on
    port [:gb_core, :lcd_vsync] => :lcd_vsync

    # Audio
    port [:gb_core, :audio_l] => :audio_l
    port [:gb_core, :audio_r] => :audio_r
    port :const_zero => [:gb_core, :audio_no_pops]

    # Debug outputs
    port [:gb_core, :debug_cpu_pc] => :debug_pc
    port [:gb_core, :debug_cpu_acc] => :debug_acc

    # Unused GB inputs - tie off to defaults
    port :const_zero => [:gb_core, :real_cgb_boot]
    port :const_zero => [:gb_core, :cgb_boot_download]
    port :const_zero => [:gb_core, :dmg_boot_download]
    port :const_zero => [:gb_core, :sgb_boot_download]
    port :const_zero => [:gb_core, :ioctl_wr]
    port :const_zero_25 => [:gb_core, :ioctl_addr]
    port :const_zero_16 => [:gb_core, :ioctl_dout]
    port :const_zero => [:gb_core, :boot_gba_en]
    port :const_zero => [:gb_core, :fast_boot_en]
    port :const_zero_4 => [:gb_core, :joy_din]
    port :const_zero => [:gb_core, :gg_reset]
    port :const_zero => [:gb_core, :gg_en]
    port :const_zero_129 => [:gb_core, :gg_code]
    port :const_zero => [:gb_core, :serial_clk_in]
    port :const_one => [:gb_core, :serial_data_in]
    port :const_zero => [:gb_core, :increaseSSHeaderCount]
    port :const_zero_8 => [:gb_core, :cart_ram_size]
    port :const_zero => [:gb_core, :save_state]
    port :const_zero => [:gb_core, :load_state]
    port :const_zero_2 => [:gb_core, :savestate_number]
    port :const_zero_8 => [:gb_core, :save_state_ext_dout]
    port :const_zero_8 => [:gb_core, :savestate_cram_read_data]
    port :const_zero_8 => [:gb_core, :save_out_dout]
    port :const_one => [:gb_core, :save_out_done]
    port :const_zero => [:gb_core, :rewind_on]
    port :const_zero => [:gb_core, :rewind_active]

    behavior do
      # Constants
      const_zero <= lit(0, width: 1)
      const_one <= lit(1, width: 1)
      const_zero_2 <= lit(0, width: 2)
      const_zero_4 <= lit(0xF, width: 4)  # joy_din is active low
      const_zero_8 <= lit(0, width: 8)
      const_zero_16 <= lit(0, width: 16)
      const_zero_25 <= lit(0, width: 25)
      const_zero_129 <= lit(0, width: 129)

      # Cart activity for speed control
      cart_act <= cart_rd | cart_wr
    end
  end
end
