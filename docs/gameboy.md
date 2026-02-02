# Game Boy Emulation

The `examples/gameboy/` directory contains a comprehensive Game Boy emulation system based on the MiSTer Gameboy_MiSTer reference implementation. It supports the original DMG (Dot Matrix Game), Game Boy Color (GBC), and Super Game Boy (SGB) modes.

## Overview

The Game Boy emulation consists of:

- **HDL Components** (`examples/gameboy/hdl/`): Cycle-accurate hardware models
- **SM83 CPU**: Z80 variant CPU core with full instruction set
- **PPU**: Pixel Processing Unit with background, window, and sprite rendering
- **APU**: Audio Processing Unit with 4 sound channels
- **Memory Controllers**: MBC1, MBC2, MBC3, MBC5 mapper support
- **Multiple Backends**: HDL, IR-level, and Verilator simulation

## Quick Start

### Running the Emulator

```bash
# Run with test ROM
rhdl examples gameboy --rom cpu_instrs.gb

# Run demo display
rhdl examples gameboy --demo

# Enable audio output
rhdl examples gameboy --rom game.gb --audio
```

### Command Line Options

```
Usage: rhdl examples gameboy [options] [rom.gb]

Options:
  --rom FILE            Load ROM file
  --demo                Run built-in demo display
  --gbc                 Force Game Boy Color mode
  --sgb                 Force Super Game Boy mode
  --audio               Enable audio output
  --debug               Show CPU state in status line
  --sim BACKEND         Simulation backend: ruby, jit, compile
  --dry-run             Initialize but don't run
```

## Architecture

### System Block Diagram

```
+-----------------------------------------------------------------------------+
|                           Game Boy System                                    |
+-----------------------------------------------------------------------------+
|                                                                             |
|  +-----------+     +----------+     +---------------------------+           |
|  |   SM83    |     |  Timer   |     |      PPU (Video)          |           |
|  |   CPU     |<--->| Counter  |---->|  - Background layer       |           |
|  | 4.19 MHz  |     +----------+     |  - Window layer           |           |
|  +-----+-----+                      |  - 40 sprites (8x8/8x16)  |           |
|        |                            |  - 160x144 LCD output     |           |
|        v                            +---------------------------+           |
|  +-----+------------------------------------------------+                   |
|  |                     Address/Data Bus                 |                   |
|  +--+--------+--------+--------+--------+--------+------+                   |
|     |        |        |        |        |        |                          |
|  +--+--+  +--+--+  +--+--+  +--+--+  +--+--+  +--+--+                       |
|  | ROM |  | VRAM|  | WRAM|  | OAM |  | HRAM|  | I/O |                       |
|  |0-8MB|  | 8KB |  | 8KB |  |160B |  |127B |  |Regs |                       |
|  +-----+  +-----+  +-----+  +-----+  +-----+  +-----+                       |
|                                                                             |
|  +-----------+     +-----------+     +-----------+                          |
|  |    APU    |     |   Link    |     |  Joypad   |                          |
|  | 4 Channel |     |   Port    |     | 8 Buttons |                          |
|  +-----------+     +-----------+     +-----------+                          |
|                                                                             |
+-----------------------------------------------------------------------------+
```

### Memory Map

| Address Range | Size | Description |
|---------------|------|-------------|
| $0000-$00FF | 256B | Boot ROM (when enabled) |
| $0000-$3FFF | 16KB | ROM Bank 0 (fixed) |
| $4000-$7FFF | 16KB | ROM Bank 1-N (switchable) |
| $8000-$9FFF | 8KB | Video RAM (VRAM) |
| $A000-$BFFF | 8KB | Cartridge RAM (if present) |
| $C000-$CFFF | 4KB | Work RAM Bank 0 |
| $D000-$DFFF | 4KB | Work RAM Bank 1-7 (GBC) |
| $E000-$FDFF | | Echo RAM (mirrors $C000-$DDFF) |
| $FE00-$FE9F | 160B | OAM (Object Attribute Memory) |
| $FEA0-$FEFF | | Unusable |
| $FF00-$FF7F | 128B | I/O Registers |
| $FF80-$FFFE | 127B | High RAM (HRAM) |
| $FFFF | 1B | Interrupt Enable Register |

### Interrupt Vectors

| Address | Description |
|---------|-------------|
| $0040 | V-Blank interrupt |
| $0048 | LCD STAT interrupt |
| $0050 | Timer interrupt |
| $0058 | Serial interrupt |
| $0060 | Joypad interrupt |

## CPU: SM83

The SM83 is a modified Z80 processor, sometimes called the "LR35902" or "Game Boy CPU".

### Registers

```
+---+---+   +---+---+   +---+---+   +---+---+
| A | F |   | B | C |   | D | E |   | H | L |
+---+---+   +---+---+   +---+---+   +---+---+
   AF          BC          DE          HL

+-------+   +-------+
|  SP   |   |  PC   |
+-------+   +-------+
  Stack     Program
 Pointer    Counter
```

### Flags Register (F)

| Bit | Name | Description |
|-----|------|-------------|
| 7 | Z | Zero flag |
| 6 | N | Subtract flag |
| 5 | H | Half-carry flag |
| 4 | C | Carry flag |
| 3-0 | - | Always 0 |

### Instruction Set

The SM83 supports 245 opcodes plus 256 CB-prefixed opcodes:

| Category | Instructions |
|----------|--------------|
| Load | LD, LDH, PUSH, POP |
| Arithmetic | ADD, ADC, SUB, SBC, INC, DEC, DAA, CPL |
| Logic | AND, OR, XOR, CP |
| Rotate/Shift | RLCA, RRCA, RLA, RRA, RLC, RRC, RL, RR, SLA, SRA, SRL, SWAP |
| Bit | BIT, SET, RES |
| Jump | JP, JR, CALL, RET, RETI, RST |
| Misc | NOP, HALT, STOP, DI, EI, SCF, CCF |

### Timing

| Clock | Frequency | Description |
|-------|-----------|-------------|
| Main | 4.194304 MHz | Master clock (DMG) |
| Main (GBC 2x) | 8.388608 MHz | Double-speed mode |
| M-cycle | ~1.05 MHz | Machine cycle (4 T-states) |
| Frame | ~59.7 Hz | Display refresh rate |

## PPU (Pixel Processing Unit)

### Video Modes

| Mode | Duration | Description |
|------|----------|-------------|
| 0 | 204 cycles | H-Blank |
| 1 | 4560 cycles | V-Blank (10 lines) |
| 2 | 80 cycles | OAM Search |
| 3 | 172 cycles | Drawing |

### Display Specifications

| Parameter | DMG | GBC |
|-----------|-----|-----|
| Resolution | 160x144 | 160x144 |
| Colors | 4 shades | 32,768 colors |
| BG Palettes | 1 | 8 |
| Sprite Palettes | 2 | 8 |
| Sprites | 40 total, 10/line | 40 total, 10/line |
| Sprite Size | 8x8 or 8x16 | 8x8 or 8x16 |
| Tile Size | 8x8 pixels | 8x8 pixels |
| BG Map | 32x32 tiles | 32x32 tiles |

### LCD Control Register ($FF40 - LCDC)

| Bit | Name | Description |
|-----|------|-------------|
| 7 | LCD Enable | 0=Off, 1=On |
| 6 | Window Tile Map | 0=$9800, 1=$9C00 |
| 5 | Window Enable | 0=Off, 1=On |
| 4 | BG/Window Tile Data | 0=$8800, 1=$8000 |
| 3 | BG Tile Map | 0=$9800, 1=$9C00 |
| 2 | Sprite Size | 0=8x8, 1=8x16 |
| 1 | Sprite Enable | 0=Off, 1=On |
| 0 | BG/Window Enable | 0=Off, 1=On (DMG) |

## APU (Audio Processing Unit)

The Game Boy APU produces sound through 4 channels:

### Channel 1: Square Wave with Sweep

```
+-------------+     +--------+     +--------+     +-----+
| Sweep Unit  |---->| Square |---->| Volume |---->| Mix |
| NR10        |     | Wave   |     | NR12   |     |     |
+-------------+     +--------+     +--------+     +-----+
                    | Duty   |
                    | NR11   |
                    +--------+
```

### Channel 2: Square Wave

```
+--------+     +--------+     +-----+
| Square |---->| Volume |---->| Mix |
| Wave   |     | NR22   |     |     |
| NR21   |     +--------+     +-----+
+--------+
```

### Channel 3: Programmable Wave

```
+--------+     +--------+     +-----+
| Wave   |---->| Volume |---->| Mix |
| RAM    |     | NR32   |     |     |
| $FF30+ |     +--------+     +-----+
+--------+
```

### Channel 4: Noise

```
+--------+     +--------+     +-----+
| LFSR   |---->| Volume |---->| Mix |
| NR43   |     | NR42   |     |     |
+--------+     +--------+     +-----+
```

### Audio Registers

| Register | Address | Description |
|----------|---------|-------------|
| NR10 | $FF10 | Channel 1 sweep |
| NR11 | $FF11 | Channel 1 duty/length |
| NR12 | $FF12 | Channel 1 volume envelope |
| NR13 | $FF13 | Channel 1 frequency low |
| NR14 | $FF14 | Channel 1 frequency high/control |
| NR21 | $FF16 | Channel 2 duty/length |
| NR22 | $FF17 | Channel 2 volume envelope |
| NR23 | $FF18 | Channel 2 frequency low |
| NR24 | $FF19 | Channel 2 frequency high/control |
| NR30 | $FF1A | Channel 3 enable |
| NR31 | $FF1B | Channel 3 length |
| NR32 | $FF1C | Channel 3 volume |
| NR33 | $FF1D | Channel 3 frequency low |
| NR34 | $FF1E | Channel 3 frequency high/control |
| NR41 | $FF20 | Channel 4 length |
| NR42 | $FF21 | Channel 4 volume envelope |
| NR43 | $FF22 | Channel 4 polynomial counter |
| NR44 | $FF23 | Channel 4 control |
| NR50 | $FF24 | Master volume |
| NR51 | $FF25 | Channel panning |
| NR52 | $FF26 | Sound enable |

## Memory Bank Controllers (MBC)

The Game Boy uses memory bank controllers for cartridges larger than 32KB.

### MBC1

The most common early mapper supporting up to 2MB ROM and 32KB RAM.

| Mode | ROM Banks | RAM Banks |
|------|-----------|-----------|
| Mode 0 | 128 (2MB) | 1 (8KB) |
| Mode 1 | 32 (512KB) | 4 (32KB) |

**Registers:**
- $0000-$1FFF: RAM Enable (write $0A to enable)
- $2000-$3FFF: ROM Bank (5 bits)
- $4000-$5FFF: RAM Bank / Upper ROM bits
- $6000-$7FFF: Mode Select

### MBC2

Simpler mapper with built-in 512x4-bit RAM.

| Feature | Specification |
|---------|---------------|
| ROM | Up to 256KB (16 banks) |
| RAM | 512x4 bits (built-in) |

### MBC3

Adds Real-Time Clock support.

| Feature | Specification |
|---------|---------------|
| ROM | Up to 2MB (128 banks) |
| RAM | Up to 32KB (4 banks) |
| RTC | Seconds, Minutes, Hours, Days |

### MBC5

Most advanced standard mapper.

| Feature | Specification |
|---------|---------------|
| ROM | Up to 8MB (512 banks) |
| RAM | Up to 128KB (16 banks) |
| Rumble | Optional motor support |

## HDL Components

### GB (`examples/gameboy/hdl/gb.rb`)

Top-level Game Boy system integrating all components.

**Key Inputs:**
- `clk_sys` - System clock
- `ce` - 4MHz clock enable
- `ce_2x` - 8MHz clock enable (GBC double speed)
- `reset` - System reset
- `is_gbc` - Game Boy Color mode
- `is_sgb` - Super Game Boy mode
- `joystick` - Button input
- `cart_do` - Cartridge data

**Key Outputs:**
- `lcd_data` - 15-bit LCD pixel data
- `lcd_clkena` - LCD clock enable
- `audio_l`, `audio_r` - 16-bit stereo audio

### SM83 (`examples/gameboy/hdl/cpu/sm83.rb`)

The SM83 CPU core with microcode-driven execution.

**Features:**
- Complete instruction set implementation
- T-state and M-cycle accurate timing
- Interrupt handling (IME, IE, IF)
- HALT and STOP modes
- Debug outputs for all registers

### Video (`examples/gameboy/hdl/ppu/video.rb`)

Pixel Processing Unit handling all display modes.

**Features:**
- Background and window layers
- Sprite rendering with priority
- Mode transitions (OAM, Draw, H-Blank, V-Blank)
- DMA transfer support
- GBC color palette support

### Sound (`examples/gameboy/hdl/apu/sound.rb`)

Master audio processor coordinating all channels.

**Channels:**
- `channel_square.rb` - Square wave (x2)
- `channel_wave.rb` - Programmable wave
- `channel_noise.rb` - Noise generator

### Timer (`examples/gameboy/hdl/timer.rb`)

Timer and divider counter.

**Registers:**
- DIV ($FF04) - Divider (increments at 16384 Hz)
- TIMA ($FF05) - Timer counter
- TMA ($FF06) - Timer modulo
- TAC ($FF07) - Timer control

### Mappers (`examples/gameboy/hdl/mappers/`)

Memory bank controller implementations.

- `mbc1.rb` - MBC1 mapper
- `mbc2.rb` - MBC2 mapper
- `mbc3.rb` - MBC3 mapper with RTC
- `mbc5.rb` - MBC5 mapper with rumble

## Simulation Backends

### HDL Mode (Default)

Cycle-accurate simulation using RHDL HDL components.

```bash
rhdl examples gameboy --sim ruby --rom game.gb
```

### IR Mode

Gate-level intermediate representation simulation.

```bash
rhdl examples gameboy --sim jit --rom game.gb
```

### Verilator Mode

High-performance Verilator-compiled simulation.

```bash
rhdl examples gameboy --sim verilator --rom game.gb
```

## Display Rendering

### LCD Renderer

The LCD renderer supports multiple output modes:

**ASCII Mode:**
```ruby
renderer = LcdRenderer.new(chars_wide: 80)
puts renderer.render_ascii(framebuffer)
```

**Braille Mode (High Resolution):**
```ruby
renderer = LcdRenderer.new(chars_wide: 80, invert: false)
puts renderer.render_braille(framebuffer)
```

## Joypad Input

| Button | Bit | Action |
|--------|-----|--------|
| Right | 0 | Direction |
| Left | 1 | Direction |
| Up | 2 | Direction |
| Down | 3 | Direction |
| A | 0 | Button |
| B | 1 | Button |
| Select | 2 | Button |
| Start | 3 | Button |

## File Structure

```
examples/gameboy/
+-- bin/
|   +-- gb                      # Main emulator executable
+-- hdl/                        # HDL components
|   +-- cpu/
|   |   +-- sm83.rb             # SM83 CPU core
|   |   +-- alu.rb              # ALU
|   |   +-- registers.rb        # Register file
|   |   +-- mcode.rb            # Microcode generator
|   +-- ppu/
|   |   +-- video.rb            # PPU controller
|   |   +-- lcd.rb              # LCD timing
|   |   +-- sprites.rb          # Sprite renderer
|   +-- apu/
|   |   +-- sound.rb            # Audio master
|   |   +-- channel_square.rb   # Square wave channel
|   |   +-- channel_wave.rb     # Wave channel
|   |   +-- channel_noise.rb    # Noise channel
|   +-- memory/
|   |   +-- dpram.rb            # Dual-port RAM
|   |   +-- spram.rb            # Single-port RAM
|   +-- mappers/
|   |   +-- mappers.rb          # Mapper switcher
|   |   +-- mbc1.rb             # MBC1
|   |   +-- mbc2.rb             # MBC2
|   |   +-- mbc3.rb             # MBC3
|   |   +-- mbc5.rb             # MBC5
|   +-- dma/
|   |   +-- hdma.rb             # DMA engines
|   +-- gb.rb                   # Top-level GB core
|   +-- timer.rb                # Timer/counter
|   +-- link.rb                 # Serial link
|   +-- speedcontrol.rb         # GBC speed control
+-- utilities/
|   +-- gameboy_hdl.rb          # HDL runner
|   +-- gameboy_ir.rb           # IR runner
|   +-- gameboy_verilator.rb    # Verilator runner
|   +-- lcd_renderer.rb         # Display rendering
|   +-- speaker.rb              # Audio output
+-- software/
|   +-- roms/                   # Test ROMs
+-- gameboy.rb                  # Main loader
+-- demo_display.rb             # Demo program
```

## Game Boy Color Features

When running in GBC mode (`--gbc`):

- **Double Speed Mode**: CPU can run at 8MHz
- **Extra VRAM**: Second VRAM bank ($8000-$9FFF bank 1)
- **Extra WRAM**: 7 additional work RAM banks
- **Color Palettes**: 8 BG palettes, 8 sprite palettes (4 colors each)
- **HDMA**: High-speed DMA for VRAM
- **Infrared**: IR communication port

## Super Game Boy Features

When running in SGB mode (`--sgb`):

- **Border**: Custom border graphics
- **Palettes**: 4 customizable palettes
- **Multiplayer**: Up to 4 controllers
- **Sound Effects**: SNES audio mixing

## References

- [Pan Docs](https://gbdev.io/pandocs/) - Comprehensive Game Boy documentation
- [Game Boy CPU Manual](http://marc.rawer.de/Gameboy/Docs/GBCPUman.pdf)
- [MiSTer Gameboy_MiSTer](https://github.com/MiSTer-devel/Gameboy_MiSTer) - Reference implementation
- [RGBDS Documentation](https://rgbds.gbdev.io/)

## See Also

- [MOS 6502 CPU](mos6502_cpu.md) - 6502 implementation
- [Apple II Emulation](apple2.md) - Apple II system
- [Simulation Backends](simulation.md) - Performance options
- [DSL Reference](dsl.md) - RHDL DSL documentation
