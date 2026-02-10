# Apple II Emulation

This project includes a comprehensive Apple II emulation system with multiple simulation backends, video modes, disk controller emulation, and an interactive terminal interface.

## Overview

The Apple II emulation consists of:

- **HDL Components** (`examples/apple2/hdl/`): Cycle-accurate hardware models
- **ISA Simulator** (`examples/mos6502/utilities/`): Fast instruction-level execution
- **Terminal Emulator** (`examples/apple2/bin/apple2`): Interactive display and keyboard
- **Disk II Controller**: Full .dsk disk image support
- **Multiple Backends**: HDL, netlist, Verilog, and compiled simulation

## Quick Start

### Running the Emulator

```bash
# Run with AppleIIGo ROM (full Apple II experience)
rhdl apple2 --appleiigo

# Run Karateka (pre-loaded memory dump, immediate gameplay)
rhdl apple2 --karateka

# Run with Karateka and hi-res display
rhdl apple2 --karateka --hires

# Run demo program
rhdl apple2 --demo

# Load custom disk image
rhdl apple2 --appleiigo --disk game.dsk

# Enable hi-res graphics with color
rhdl apple2 --appleiigo --hires --color
```

### Command Line Options

```
Usage: rhdl apple2 [options] [program.bin]

Options:
  --appleiigo           Run with AppleIIGo ROM
  --karateka            Run Karateka from memory dump
  --demo                Run built-in demo program
  -r, --rom FILE        Load ROM file (default: $F800)
  -a, --address ADDR    Load address for program (hex)
  -d, --debug           Show CPU state in status line
  -g, --green           Green phosphor screen effect
  -A, --audio           Enable audio output
  -H, --hires           Enable hi-res graphics display
  -C, --color           Enable color rendering
  --hires-width N       Set hi-res display width (default: 140)
  -s, --speed CYCLES    Cycles per frame (default: 10000)
  --disk FILE           Load .dsk disk image
  --memdump FILE        Load memory dump file
  --pc ADDR             Set initial PC (hex)
  -m, --mode MODE       Simulation mode: ruby, ir, netlist, verilog
  --sim BACKEND         Simulation backend: ruby, interpret, jit, compile
  --sub-cycles N        Sub-cycles per step (14=full, 7=2x, 2=7x speed)
  --dry-run             Initialize but don't run
```

## Architecture

### System Block Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Apple II System                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────────────────┐   │
│  │   MOS 6502  │     │   Timing    │     │      Video Generator    │   │
│  │     CPU     │◄────│  Generator  │────▶│   - Text (40x24)        │   │
│  │   1 MHz     │     │   14 MHz    │     │   - Lo-res (40x48)      │   │
│  └──────┬──────┘     └─────────────┘     │   - Hi-res (280x192)    │   │
│         │                                 └─────────────────────────┘   │
│         │                                                               │
│  ┌──────┴──────────────────────────────────────────────────────────┐   │
│  │                        Address/Data Bus                          │   │
│  └──────┬───────────────┬───────────────┬───────────────┬──────────┘   │
│         │               │               │               │              │
│  ┌──────┴──────┐ ┌──────┴──────┐ ┌──────┴──────┐ ┌──────┴──────┐      │
│  │    48KB     │ │    12KB     │ │   I/O Page  │ │   Disk II   │      │
│  │    RAM      │ │    ROM      │ │   $C000-    │ │  Controller │      │
│  │ $0000-BFFF  │ │ $D000-FFFF  │ │   $C0FF     │ │   Slot 6    │      │
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘      │
│                                                                         │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                       │
│  │  Keyboard   │ │   Speaker   │ │  Gameport   │                       │
│  │  PS/2 Input │ │   Toggle    │ │  Paddles    │                       │
│  └─────────────┘ └─────────────┘ └─────────────┘                       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Memory Map

| Address Range | Size | Description |
|---------------|------|-------------|
| $0000-$00FF | 256B | Zero Page |
| $0100-$01FF | 256B | Stack |
| $0200-$03FF | 512B | Free RAM |
| $0400-$07FF | 1KB | Text Page 1 (40x24 characters) |
| $0800-$0BFF | 1KB | Text Page 2 |
| $0C00-$1FFF | 5KB | Free RAM |
| $2000-$3FFF | 8KB | Hi-Res Page 1 (280x192) |
| $4000-$5FFF | 8KB | Hi-Res Page 2 |
| $6000-$BFFF | 24KB | Free RAM |
| $C000-$C0FF | 256B | I/O Page (soft switches) |
| $C100-$CFFF | 3.75KB | Peripheral Card ROM |
| $D000-$F7FF | 10KB | BASIC / Language Card |
| $F800-$FFFF | 2KB | Monitor ROM |

### Reset Vectors

| Address | Description |
|---------|-------------|
| $FFFA-$FFFB | NMI Vector |
| $FFFC-$FFFD | Reset Vector |
| $FFFE-$FFFF | IRQ/BRK Vector |

## I/O Page ($C000-$C0FF)

### Keyboard

| Address | Read | Write |
|---------|------|-------|
| $C000 | Key data (bit 7 = strobe) | - |
| $C010 | Clear keyboard strobe | Clear keyboard strobe |

```asm
; Reading keyboard in 6502 assembly
WAIT:
    LDA $C000     ; Read key (bit 7 = strobe)
    BPL WAIT      ; Wait if no key ready
    STA $C010     ; Clear strobe
    AND #$7F      ; Mask off strobe bit
```

### Speaker

| Address | Access |
|---------|--------|
| $C030 | Toggle speaker click (read or write) |

The speaker is toggled by any access (read or write) to $C030. Audio simulation tracks these toggles for waveform generation.

### Video Soft Switches

| Address | Read | Write | Effect |
|---------|------|-------|--------|
| $C050 | | X | Graphics mode (text off) |
| $C051 | | X | Text mode (text on) |
| $C052 | | X | Mixed mode off (full screen) |
| $C053 | | X | Mixed mode on (4 lines text at bottom) |
| $C054 | | X | Display page 1 |
| $C055 | | X | Display page 2 |
| $C056 | | X | Lo-res graphics |
| $C057 | | X | Hi-res graphics |

### Disk II Controller (Slot 6)

| Address | Description |
|---------|-------------|
| $C0E0 | Phase 0 off |
| $C0E1 | Phase 0 on |
| $C0E2 | Phase 1 off |
| $C0E3 | Phase 1 on |
| $C0E4 | Phase 2 off |
| $C0E5 | Phase 2 on |
| $C0E6 | Phase 3 off |
| $C0E7 | Phase 3 on |
| $C0E8 | Motor off |
| $C0E9 | Motor on |
| $C0EA | Select drive 1 |
| $C0EB | Select drive 2 |
| $C0EC | Q6L - Read data |
| $C0ED | Q6H - Shift register |
| $C0EE | Q7L - Read mode |
| $C0EF | Q7H - Write mode |

## Video Modes

### Text Mode (40x24)

Standard 40-column by 24-line text display using 1KB of memory.

**Memory Layout (non-linear):**
```
Line 0:  $0400-$0427 (40 bytes)
Line 1:  $0480-$04A7
Line 2:  $0500-$0527
...
Line 8:  $0428-$044F
Line 9:  $04A8-$04CF
...
Line 16: $0450-$0477
Line 17: $04D0-$04F7
...
```

**Character Encoding:**
- $00-$3F: Inverse uppercase
- $40-$7F: Flashing uppercase
- $80-$BF: Normal uppercase
- $C0-$FF: Normal lowercase (Apple IIe+)

### Lo-Res Graphics (40x48)

Color graphics mode using 40x48 pixels with 16 colors.

Each byte represents two vertically stacked pixels:
- Low nibble (bits 0-3): Top pixel color
- High nibble (bits 4-7): Bottom pixel color

**Colors:**
| Value | Color |
|-------|-------|
| 0 | Black |
| 1 | Magenta |
| 2 | Dark Blue |
| 3 | Purple |
| 4 | Dark Green |
| 5 | Gray 1 |
| 6 | Medium Blue |
| 7 | Light Blue |
| 8 | Brown |
| 9 | Orange |
| 10 | Gray 2 |
| 11 | Pink |
| 12 | Light Green |
| 13 | Yellow |
| 14 | Aqua |
| 15 | White |

### Hi-Res Graphics (280x192)

High-resolution graphics using 8KB of memory per page.

**Resolution:** 280 x 192 pixels
**Memory:** $2000-$3FFF (page 1), $4000-$5FFF (page 2)
**Bytes per line:** 40 (7 pixels per byte + 1 color bit)

**Line Address Calculation:**
```ruby
def hires_line_address(line, page = 1)
  base = (page == 1) ? 0x2000 : 0x4000
  group = line / 64
  subgroup = (line % 64) / 8
  offset = line % 8
  base + (group * 40) + (subgroup * 128) + (offset * 1024)
end
```

**Color Encoding:**
- Bit 7: Color palette select (0=green/violet, 1=orange/blue)
- Bits 0-6: Pixel data (7 pixels per byte)
- Adjacent pixels combine for artifact colors

## Simulation Backends

### Ruby Mode (Default)

Cycle-accurate simulation using Ruby-backed RHDL HDL components.

```bash
rhdl apple2 --mode ruby --appleiigo
```

**Characteristics:**
- Most accurate to real hardware
- Slowest performance
- Full visibility into internal signals

### Netlist Mode

Gate-level simulation using synthesized netlist.

```bash
rhdl apple2 --mode netlist --appleiigo
```

**Characteristics:**
- Structural simulation
- Good for verification
- Moderate performance

### Verilog Mode

Simulation using Verilator-compiled Verilog.

```bash
rhdl apple2 --mode verilog --appleiigo
```

**Characteristics:**
- Requires Verilator installation
- Very fast performance
- Good for long-running programs

### Simulation Backends

Within each mode, different backends control evaluation:

| Backend | Option | Description |
|---------|--------|-------------|
| Ruby | `--sim ruby` | Pure Ruby interpreter (default) |
| Interpret | `--sim interpret` | Rust-based interpreter |
| JIT | `--sim jit` | JIT-compiled simulation |
| Compile | `--sim compile` | AOT-compiled native code |

**Example:**
```bash
# Fast simulation with JIT backend
rhdl apple2 --mode ir --sim jit --appleiigo

# Maximum speed with compiled backend
rhdl apple2 --mode ir --sim compile --appleiigo --sub-cycles 2
```

## Disk II Controller

Full emulation of the Disk II controller for slot 6.

### Loading Disk Images

```bash
# Load .dsk image with ROM
rhdl apple2 --appleiigo --disk game.dsk
```

### Supported Formats

| Format | Extension | Size | Description |
|--------|-----------|------|-------------|
| DOS 3.3 | .dsk | 143,360 bytes | 35 tracks × 16 sectors × 256 bytes |
| ProDOS | .dsk | 143,360 bytes | Same physical format, different filesystem |

### Disk Geometry

| Parameter | Value |
|-----------|-------|
| Tracks | 35 |
| Sectors per track | 16 |
| Bytes per sector | 256 |
| Track size | 4,096 bytes |
| Total size | 143,360 bytes |
| Nibblized track | 6,448 bytes |
| Rotation speed | 300 RPM |
| Cycles per byte | ~32 (at 1 MHz) |

### Sector Interleaving

DOS 3.3 uses sector interleaving for optimal read performance:

```ruby
DOS33_INTERLEAVE = [
  0x00, 0x07, 0x0E, 0x06, 0x0D, 0x05, 0x0C, 0x04,
  0x0B, 0x03, 0x0A, 0x02, 0x09, 0x01, 0x08, 0x0F
]
```

## HDL Components

### Apple2 (`examples/apple2/hdl/apple2.rb`)

Top-level Apple II system integrating all components.

**Inputs:**
- `clk_14m` - 14.318 MHz master clock
- `flash_clk` - Cursor flash clock
- `reset` - System reset
- `ram_do` - RAM data output
- `ps2_clk`, `ps2_data` - PS/2 keyboard
- `gameport` - Game paddle input
- `pause` - Pause execution

**Outputs:**
- `video`, `color` - Video signals
- `hblank`, `vblank` - Sync signals
- `ram_we`, `ram_addr`, `ram_di` - RAM interface
- `speaker` - Audio output

### CPU6502 (`examples/apple2/hdl/cpu6502.rb`)

MOS 6502 CPU core with Apple II bus interface.

### VideoGenerator (`examples/apple2/hdl/video_generator.rb`)

Generates all video modes (text, lo-res, hi-res).

### TimingGenerator (`examples/apple2/hdl/timing_generator.rb`)

14.318 MHz timing and video sync generation.

### Keyboard (`examples/apple2/hdl/keyboard.rb`)

PS/2 keyboard interface with Apple II key mapping.

### DiskII (`examples/apple2/hdl/disk_ii.rb`)

Disk II controller emulation.

### CharacterROM (`examples/apple2/hdl/character_rom.rb`)

Built-in character generator ROM.

### RAM (`examples/apple2/hdl/ram.rb`)

48KB main memory with bank switching.

### AudioPWM (`examples/apple2/hdl/audio_pwm.rb`)

PWM audio output for speaker clicks.

## Display Renderers

### Text Renderer (`utilities/text_renderer.rb`)

ASCII text output for terminal display.

```ruby
renderer = TextRenderer.new
lines = renderer.render(screen_memory)
puts lines.join("\n")
```

### Color Renderer (`utilities/renderers/color_renderer.rb`)

ANSI color terminal output.

```bash
rhdl apple2 --appleiigo --color
```

### Braille Renderer (`utilities/braille_renderer.rb`)

High-resolution display using Unicode Braille patterns for terminals.

```bash
rhdl apple2 --appleiigo --hires
```

### Hi-Res Display

The hi-res display uses Unicode Braille characters (U+2800-U+28FF) to render 280x192 pixels in the terminal with configurable width.

```bash
# Default width (140 columns)
rhdl apple2 --karateka --hires

# Wider display
rhdl apple2 --karateka --hires --hires-width 280
```

## Ruby API

### RubyRunner (`utilities/apple2_hdl.rb`)

High-level runner for HDL simulation.

```ruby
require_relative 'examples/apple2/utilities/apple2_hdl'

runner = RHDL::Examples::Apple2::RubyRunner.new

# Load ROM
rom = File.binread("appleiigo.rom")
runner.load_rom(rom.bytes, base_addr: 0xD000)

# Load disk image
runner.load_disk("game.dsk")

# Reset and run
runner.reset
runner.run_cycles(1_000_000)

# Read screen
lines = runner.read_screen
puts lines.join("\n")

# Inject keypress
runner.inject_key('A'.ord)
```

### Apple2Bus (`examples/mos6502/utilities/apple2_bus.rb`)

Low-level memory-mapped I/O bus.

```ruby
require_relative 'examples/mos6502/utilities/apple2_bus'

bus = MOS6502::Apple2Bus.new("apple2_bus")

# Load ROM
rom = File.binread("monitor.rom")
bus.load_rom(rom.bytes, base_addr: 0xF800)

# Access memory
bus.write(0x0400, 0xC1)  # Write 'A' to screen
char = bus.read(0x0400)

# Check video state
puts bus.video  # => {text: true, mixed: false, page2: false, hires: false}

# Keyboard input
bus.inject_key('X'.ord)
key = bus.read(0xC000)
```

### Apple2Harness (`examples/mos6502/utilities/runners/apple2_harness.rb`)

Test harness for running programs.

```ruby
require_relative 'examples/mos6502/utilities/runners/apple2_harness'

runner = Apple2Harness::Runner.new

# Load ROM and program
runner.load_rom(rom_bytes, base_addr: 0xD000)
runner.load_ram(program, base_addr: 0x0800)

# Reset and run
runner.reset
cycles = runner.run_until(max_cycles: 100_000) do
  runner.bus.speaker_toggles > 10
end

# Check results
state = runner.cpu_state
puts "PC: $#{state[:pc].to_s(16)}"
puts "Cycles: #{cycles}"
```

### Disk2 (`examples/mos6502/utilities/disk2.rb`)

Disk II controller for ISA simulation.

```ruby
require_relative 'examples/mos6502/utilities/disk2'

disk = MOS6502::Disk2.new
disk.load_disk("game.dsk", drive: 0)

# Accessed via soft switches during simulation
# Motor control, phase stepping, data read/write
```

## Running Games

### Karateka

Pre-loaded memory dump for immediate gameplay:

```bash
rhdl apple2 --karateka --hires --color
```

**Controls:**
- Arrow keys: Movement
- Space: Attack/Jump
- Enter: Start

### Using ROMs

Download Apple II ROMs from legal sources:
- AppleIIGo ROM: https://a2go.applearchives.com/roms/

```bash
# Place ROM in roms directory
cp appleiigo.rom ~/.rhdl/roms/

# Run with ROM
rhdl apple2 --appleiigo --disk game.dsk
```

## Testing

### Dead Test ROM

Hardware verification ROM tests:

```bash
bundle exec rspec spec/apple2_deadtest_spec.rb
```

```ruby
RSpec.describe 'Apple ][ dead test ROM' do
  it 'beeps the speaker after reset' do
    runner = boot_deadtest
    runner.run_until(max_cycles: 50_000) { runner.bus.speaker_toggles.positive? }
    expect(runner.bus.speaker_toggles).to be > 0
  end
end
```

### Integration Tests

```bash
bundle exec rspec spec/examples/apple2/
```

## Performance Tuning

### Sub-Cycles

The `--sub-cycles` option controls simulation accuracy vs speed:

| Value | Accuracy | Speed |
|-------|----------|-------|
| 14 | Full (14 MHz) | 1x |
| 7 | Half-cycle | ~2x |
| 2 | Instruction-level | ~7x |

```bash
# Maximum speed for gameplay
rhdl apple2 --karateka --sim compile --sub-cycles 2
```

### Backend Selection

For best performance:

```bash
# Fastest: compiled backend with reduced sub-cycles
rhdl apple2 --karateka --sim compile --sub-cycles 2

# Fast with full accuracy
rhdl apple2 --karateka --sim jit

# Debugging: Ruby mode with full visibility
rhdl apple2 --karateka --mode ruby --debug
```

## File Structure

```
examples/apple2/
├── bin/
│   └── apple2              # Main emulator executable
├── hdl/                    # HDL components
│   ├── apple2.rb           # Top-level system
│   ├── cpu6502.rb          # CPU core
│   ├── video_generator.rb  # Video output
│   ├── timing_generator.rb # Clock generation
│   ├── keyboard.rb         # PS/2 keyboard
│   ├── disk_ii.rb          # Disk controller
│   ├── character_rom.rb    # Character generator
│   ├── ram.rb              # Main memory
│   └── audio_pwm.rb        # Audio output
├── utilities/              # Support utilities
│   ├── runners/ruby_runner.rb # Ruby runner
│   ├── speaker.rb          # Audio simulation
│   ├── text_renderer.rb    # ASCII display
│   ├── braille_renderer.rb # Hi-res display
│   ├── color_renderer.rb   # Color terminal
│   ├── ps2_encoder.rb      # Keyboard encoding
│   ├── ir_simulator_runner.rb
│   └── apple2_verilator.rb # Verilator integration
└── hdl.rb                  # HDL loader

examples/mos6502/utilities/
├── apple2_bus.rb           # Memory-mapped I/O
├── apple2_harness.rb       # Test harness
├── apple2_speaker.rb       # Audio simulation
└── disk2.rb                # Disk II controller
```

## Known Limitations

- **Language Card**: Basic language card support (bank switching)
- **80-Column Card**: Not implemented (Apple IIe feature)
- **Joystick/Paddle**: Basic gameport support
- **Cassette**: Not implemented
- **ProDOS Clock**: Not implemented
- **Peripheral Cards**: Slot 6 (Disk II) only

## See Also

- [MOS 6502 CPU](mos6502_cpu.md) - CPU implementation details
- [Simulation Backends](simulation.md) - Performance options
- [DSL Reference](dsl.md) - RHDL DSL documentation
- [Diagrams](diagrams.md) - Circuit visualization
