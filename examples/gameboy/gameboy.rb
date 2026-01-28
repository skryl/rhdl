# Game Boy RHDL Implementation
# A 1:1 port of the MiSTer Gameboy_MiSTer reference implementation
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
require_relative 'cpu/alu'
require_relative 'cpu/registers'
require_relative 'cpu/mcode'
require_relative 'cpu/sm83'

# PPU components
require_relative 'ppu/sprites'
require_relative 'ppu/lcd'
require_relative 'ppu/video'

# APU components (load channels before sound)
require_relative 'apu/channel_square'
require_relative 'apu/channel_wave'
require_relative 'apu/channel_noise'
require_relative 'apu/sound'

# Memory and DMA
require_relative 'memory/dpram'
require_relative 'memory/spram'
require_relative 'dma/hdma'

# Mappers
require_relative 'mappers/mappers'

# Timer and Link
require_relative 'timer'
require_relative 'link'

# Top-level Game Boy module (requires all above)
require_relative 'gb'

module GameBoy
  VERSION = '0.1.0'
end
