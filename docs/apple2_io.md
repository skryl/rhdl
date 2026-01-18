# Apple II Emulation

This project includes an Apple II-style I/O bus and terminal emulator for running 6502 programs with authentic Apple II memory-mapped I/O behavior.

## Overview

The Apple II emulation consists of:

- **Apple2Bus**: Memory-mapped I/O bus with keyboard, speaker, and video soft switches
- **Apple2Harness**: Test harness for running programs with the 6502 CPU
- **Terminal Emulator**: Interactive terminal application with screen rendering

## Quick Start

### Running the Terminal Emulator

```bash
# Run built-in demo program
bin/apple2 --demo

# Run with green phosphor effect
bin/apple2 --demo --green

# Load a custom binary
bin/apple2 program.bin

# Load ROM and program
bin/apple2 --rom monitor.rom program.bin
```

### Command Line Options

```
Usage: bin/apple2 [options] [program.bin]

Options:
    -r, --rom FILE          Load ROM file (default address: $F800)
    -a, --address ADDR      Load address for program (hex, default: 0800)
        --rom-address ADDR  Load address for ROM (hex, default: F800)
    -s, --speed CYCLES      Cycles per frame (default: 10000)
    -d, --debug             Show CPU state in status line
    -g, --green             Green phosphor screen effect
        --demo              Run built-in demo program
    -h, --help              Show help message
```

## Memory Map

| Address Range | Description |
|---------------|-------------|
| $0000-$00FF | Zero Page |
| $0100-$01FF | Stack |
| $0200-$03FF | Free RAM |
| $0400-$07FF | Text Page 1 (40x24 characters) |
| $0800-$BFFF | Free RAM / Program space |
| $C000-$C0FF | I/O Page (soft switches) |
| $C100-$CFFF | Peripheral card ROM space |
| $D000-$F7FF | Applesoft BASIC / RAM |
| $F800-$FFFF | Monitor ROM |

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
| $C000 | Key data (bit 7 set if key ready) | - |
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

The bus records speaker toggles for testing purposes.

### Video Soft Switches

| Address | Effect |
|---------|--------|
| $C050 | Graphics mode (text off) |
| $C051 | Text mode (text on) |
| $C052 | Mixed mode off |
| $C053 | Mixed mode on |
| $C054 | Display page 1 |
| $C055 | Display page 2 |
| $C056 | Lo-res graphics |
| $C057 | Hi-res graphics |

## Using the Apple2Bus

### Basic Usage

```ruby
require_relative 'examples/mos6502/utilities/apple2_bus'

bus = MOS6502::Apple2Bus.new("apple2_bus")

# Load ROM at $F800
rom_bytes = File.binread("monitor.rom")
bus.load_rom(rom_bytes, base_addr: 0xF800)

# Load program into RAM at $0800
program = File.binread("program.bin")
bus.load_ram(program, base_addr: 0x0800)

# Set reset vector to program start
bus.write(0xFFFC, 0x00)  # Low byte
bus.write(0xFFFD, 0x08)  # High byte ($0800)

# Simulate keyboard input
bus.inject_key('A'.ord)

# Check video state
puts bus.video  # => {text: true, mixed: false, page2: false, hires: false}
```

### Bus Interface

| Method | Description |
|--------|-------------|
| `load_rom(bytes, base_addr:)` | Load ROM image (read-only) |
| `load_ram(bytes, base_addr:)` | Load data into RAM |
| `read(addr)` | Read byte from address |
| `write(addr, data)` | Write byte to address |
| `inject_key(ascii)` | Simulate key press |
| `reset_vector` | Get reset vector address |
| `speaker_toggles` | Count of speaker clicks |
| `video` | Current video mode state |

## Using the Apple2Harness

The harness provides a higher-level interface for running programs:

```ruby
require_relative 'examples/mos6502/utilities/apple2_harness'

runner = Apple2Harness::Runner.new

# Load ROM
rom = File.binread("apple2.rom")
runner.load_rom(rom, base_addr: 0xF800)

# Reset and run
runner.reset
runner.run_steps(10_000)  # Run 10,000 cycles

# Run until condition
cycles = runner.run_until(max_cycles: 100_000) do
  runner.bus.speaker_toggles > 0
end

# Check CPU state
state = runner.cpu_state
puts "PC: $#{state[:pc].to_s(16)}"
puts "A: $#{state[:a].to_s(16)}"
puts "Cycles: #{state[:cycles]}"
```

### Harness Interface

| Method | Description |
|--------|-------------|
| `load_rom(bytes, base_addr:)` | Load ROM image |
| `load_ram(bytes, base_addr:)` | Load program/data |
| `reset` | Reset CPU |
| `run_steps(n)` | Run n clock cycles |
| `run_until(max_cycles:) { block }` | Run until block returns true |
| `inject_key(ascii)` | Simulate key press |
| `read_screen` | Get text page as strings |
| `read_screen_array` | Get text page as 2D array |
| `cpu_state` | Get CPU registers and status |
| `halted?` | Check if CPU halted |
| `cycle_count` | Total cycles executed |

## Loading and Running Software

### Binary Files

Load raw binary files directly:

```bash
# Load at default address ($0800)
bin/apple2 myprogram.bin

# Load at specific address
bin/apple2 --address 2000 myprogram.bin
```

### ROM Images

Load ROM images (treated as read-only memory):

```bash
# Load ROM at default address ($F800)
bin/apple2 --rom monitor.rom program.bin

# Load ROM at specific address
bin/apple2 --rom bios.rom --rom-address D000 program.bin
```

### Compiling 6502 Programs

Use any 6502 assembler to create binaries. Example with `ca65` (cc65 suite):

```bash
# Assemble
ca65 program.s -o program.o

# Link with custom memory layout
ld65 -C apple2.cfg program.o -o program.bin
```

Example `apple2.cfg` linker configuration:

```
MEMORY {
    ZP:     start = $00,    size = $100, type = rw;
    RAM:    start = $0800,  size = $8800, type = rw, file = %O;
}

SEGMENTS {
    ZEROPAGE: load = ZP,  type = zp;
    CODE:     load = RAM, type = ro;
    DATA:     load = RAM, type = rw;
}
```

### Using the Built-in Assembler

For simple programs, use the RHDL 6502 assembler:

```ruby
require_relative 'examples/mos6502/utilities/assembler'

program = MOS6502::Assembler.assemble(<<~ASM, org: 0x0800)
  *= $0800

  LDA #$C1        ; 'A' with high bit
  STA $0400       ; Write to screen

  LOOP:
    LDA $C000     ; Read keyboard
    BPL LOOP      ; Wait for key
    STA $C010     ; Clear strobe
    BRK
ASM

File.binwrite("program.bin", program.pack("C*"))
```

## Testing with Apple II ROMs

### Dead Test ROM

The Apple II Dead Test ROM is used for hardware verification:

```bash
bundle exec rspec spec/apple2_deadtest_spec.rb
```

The ROM is automatically downloaded to `spec/fixtures/apple2/apple2dead.bin`.

```ruby
# Example test
RSpec.describe 'Apple ][ dead test ROM' do
  it 'beeps the speaker after reset' do
    runner = boot_deadtest
    runner.run_until(max_cycles: 50_000) { runner.bus.speaker_toggles.positive? }
    expect(runner.bus.speaker_toggles).to be > 0
  end

  it 'enters text mode via soft switches' do
    runner = boot_deadtest
    runner.run_until(max_cycles: 80_000) { runner.bus.soft_switch_accessed?(0xC051) }
    expect(runner.bus.video[:text]).to be(true)
  end
end
```

### Using Other ROMs

Any Apple II-compatible ROM can be loaded:

```ruby
runner = Apple2Harness::Runner.new

# Load Applesoft BASIC ROM
basic_rom = File.binread("applesoft.rom")
runner.load_rom(basic_rom, base_addr: 0xD000)

# Load Monitor ROM
monitor = File.binread("monitor.rom")
runner.load_rom(monitor, base_addr: 0xF800)

runner.reset
runner.run_steps(100_000)
```

## Text Page Memory Layout

The Apple II text page uses a non-linear memory layout:

```
Line 0:  $0400-$0427 (40 bytes)
Line 1:  $0480-$04A7
Line 2:  $0500-$0527
...
Line 8:  $0428-$044F
Line 9:  $04A8-$04CF
...
```

The harness provides helper methods to read the screen:

```ruby
# Get screen as array of strings
lines = runner.read_screen
puts lines[0]  # First line of text

# Get as 2D character code array
screen = runner.read_screen_array
char_code = screen[0][0]  # First character
```

## Demo Program

The built-in demo program demonstrates:

- Screen clearing
- Text output
- Keyboard input with echo
- Cursor movement

```bash
bin/apple2 --demo --debug --green
```

Press keys to see them echoed. Press Ctrl+C to exit.

## Known Limitations

- No disk controller emulation (ProDOS, DOS 3.3)
- No actual video rendering (text page memory only)
- No peripheral card support beyond basic I/O
- No cassette interface
- No game paddle/joystick support
- Monitor ROM routines (COUT, RDKEY, etc.) require actual ROM image

## File Structure

```
examples/mos6502/
├── bin/
│   └── apple2              # Terminal emulator executable
├── utilities/
│   ├── apple2_bus.rb       # Memory-mapped I/O bus
│   ├── apple2_harness.rb   # Test harness
│   └── assembler.rb        # 6502 assembler
├── software/
│   └── roms/               # ROM images
└── hdl/
    └── cpu_harness.rb      # CPU test harness
```

## See Also

- [MOS 6502](mos6502.md) - 6502 CPU implementation
- [Sample CPU](sample_cpu.md) - RHDL sample CPU
- [Debugging Guide](debugging.md) - Signal probing and debugging
