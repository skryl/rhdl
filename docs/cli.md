# RHDL Command Line Interface

The `rhdl` command provides a unified interface for working with RHDL components, including interactive debugging, diagram generation, HDL export, gate-level synthesis, and Apple II emulation.

## Installation

After installing the gem, the `rhdl` command is available:

```bash
gem install rhdl
rhdl --help
```

For development, use `bundle exec`:

```bash
bundle exec rhdl --help
```

## Commands Overview

| Command | Description |
|---------|-------------|
| `tui` | Launch interactive TUI debugger |
| `diagram` | Generate circuit diagrams |
| `export` | Export components to Verilog |
| `gates` | Gate-level synthesis |
| `apple2` | Apple II emulator and ROM tools |

---

## TUI Command

Launch the interactive Terminal User Interface debugger for HDL components.

### Usage

```bash
rhdl tui [options] <ComponentRef>
```

### Component References

Components can be specified in two ways:

1. **Short path**: `category/component_name` (e.g., `sequential/counter`)
2. **Full class reference**: `RHDL::HDL::ClassName` (e.g., `RHDL::HDL::Counter`)

### Options

| Option | Description |
|--------|-------------|
| `--signals TYPE` | Signals to display: `all`, `inputs`, `outputs`, or comma-separated list |
| `--format FORMAT` | Signal display format: `auto`, `binary`, `hex`, `decimal`, `signed` |
| `--list` | List all available components |
| `-h, --help` | Show help |

### Examples

```bash
# Launch TUI with a counter
rhdl tui sequential/counter

# Debug an ALU, show only inputs
rhdl tui RHDL::HDL::ALU --signals inputs

# Debug with specific signals in hex format
rhdl tui arithmetic/alu_8bit --signals a,b,result --format hex

# List all available components
rhdl tui --list
```

### Keyboard Controls

| Key | Action |
|-----|--------|
| `Space` | Step one cycle |
| `n` | Step half cycle |
| `r` | Run simulation continuously |
| `s` | Stop/pause simulation |
| `R` | Reset simulation |
| `c` | Continue until breakpoint |
| `w` | Add watchpoint |
| `b` | Add breakpoint |
| `j` / `k` | Scroll signals up/down |
| `↑` / `↓` | Scroll signals up/down |
| `:` | Enter command mode |
| `h` / `?` | Show help |
| `q` | Quit |

### Command Mode

Press `:` to enter command mode. Available commands:

| Command | Description |
|---------|-------------|
| `run [n]` | Run n cycles (default: continuous) |
| `step` | Single step |
| `watch <signal> [type]` | Add watchpoint (types: `change`, `equals`, `rising_edge`, `falling_edge`) |
| `break [cycle]` | Add breakpoint at cycle |
| `delete <id>` | Delete breakpoint by ID |
| `clear [breaks\|waves\|log]` | Clear breakpoints, waveforms, or log |
| `set <signal> <value>` | Set signal value (supports `0x`, `0b`, `0o` prefixes) |
| `print <signal>` | Print signal value |
| `list` | List all signals |
| `export <file>` | Export VCD waveform file |
| `help` | Show help |
| `quit` | Exit TUI |

### TUI Layout

```
┌─────────── Signals ──────────┐┌─────────── Waveform ──────────┐
│ signal.name    value         ││ sig │▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄│
│ counter.q      0x2A (42)     ││ clk │▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄│
└──────────────────────────────┘└────────────────────────────────┘
┌─────────── Console ──────────┐┌──────── Breakpoints ──────────┐
│ 12:34:56 Simulation started  ││ ● #1 signal changes (hits: 5) │
│ 12:34:57 Breakpoint hit      ││ ○ #2 cycle == 100 (hits: 0)   │
└──────────────────────────────┘└────────────────────────────────┘
 ▶ RUNNING │ T:42 C:42                    h:Help q:Quit Space:Step
```

---

## Diagram Command

Generate circuit diagrams for HDL components in various formats.

### Usage

```bash
rhdl diagram [options] [ComponentRef]
```

### Options

| Option | Description |
|--------|-------------|
| `--all` | Generate diagrams for all components |
| `--mode MODE` | Batch mode: `component`, `hierarchical`, `gate`, or `all` |
| `--clean` | Clean all generated diagrams |
| `--level LEVEL` | Single component level: `component`, `hierarchy`, `netlist`, `gate` |
| `--depth DEPTH` | Hierarchy depth: number or `all` |
| `--bit-blasted` | Bit-blast gate-level nets |
| `--format FORMAT` | Output format: `svg`, `png`, `dot` |
| `--out DIR` | Output directory (default: `diagrams`) |
| `-h, --help` | Show help |

### Examples

```bash
# Generate all diagrams in all modes
rhdl diagram --all

# Generate only component-level diagrams
rhdl diagram --all --mode component

# Generate only gate-level diagrams
rhdl diagram --all --mode gate

# Generate diagram for a single component
rhdl diagram RHDL::HDL::ALU --level component --format svg

# Generate hierarchical diagram with full depth
rhdl diagram RHDL::HDL::CPU::Datapath --level hierarchy --depth all

# Clean generated diagrams
rhdl diagram --clean
```

### Diagram Modes

| Mode | Description |
|------|-------------|
| `component` | Simple block diagrams showing inputs/outputs |
| `hierarchical` | Detailed schematics with internal subcomponents |
| `gate` | Gate-level netlist showing primitive gates and flip-flops |

### Output Formats

| Format | Description |
|--------|-------------|
| `svg` | Scalable Vector Graphics (default) |
| `png` | Portable Network Graphics (requires Graphviz) |
| `dot` | Graphviz DOT format for custom rendering |

---

## Export Command

Export HDL components to Verilog.

### Usage

```bash
rhdl export [options] [ComponentRef]
```

### Options

| Option | Description |
|--------|-------------|
| `--all` | Export all components |
| `--scope SCOPE` | Batch scope: `all`, `lib`, or `examples` |
| `--clean` | Clean all generated HDL files |
| `--lang LANG` | Target language: `verilog` |
| `--out DIR` | Output directory |
| `--top NAME` | Override top module/entity name |
| `-h, --help` | Show help |

### Examples

```bash
# Export all components to Verilog
rhdl export --all

# Export only lib/ components
rhdl export --all --scope lib

# Export only examples/ components
rhdl export --all --scope examples

# Export a single component
rhdl export --lang verilog --out ./output RHDL::HDL::Counter

# Export with custom top module name
rhdl export --lang verilog --out ./output --top my_counter RHDL::HDL::Counter

# Clean generated files
rhdl export --clean
```

### Output Directory Structure

```
export/verilog/
├── gates/
│   ├── and_gate.v
│   ├── or_gate.v
│   └── ...
├── sequential/
│   ├── counter.v
│   ├── register.v
│   └── ...
├── arithmetic/
│   ├── alu.v
│   └── ...
└── mos6502/
    ├── mos6502_alu.v
    └── ...
```

---

## Gates Command

Gate-level synthesis - export components to primitive gate netlists (AND, OR, XOR, NOT, MUX, DFF).

### Usage

```bash
rhdl gates [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--export` | Export all components to JSON netlists (default) |
| `--simcpu` | Export SimCPU datapath components |
| `--stats` | Show gate-level synthesis statistics |
| `--clean` | Clean gate-level output |
| `-h, --help` | Show help |

### Examples

```bash
# Export all components to gate-level JSON
rhdl gates
rhdl gates --export

# Export CPU datapath components
rhdl gates --simcpu

# Show synthesis statistics
rhdl gates --stats

# Clean output
rhdl gates --clean
```

### Statistics Output

```
RHDL Gate-Level Synthesis Statistics
==================================================

Components by Gate Count:
--------------------------------------------------
  cpu/synth_datapath: 505 gates, 24 DFFs, 892 nets
  arithmetic/alu: 312 gates, 0 DFFs, 456 nets
  arithmetic/multiplier: 256 gates, 0 DFFs, 384 nets
  ...

==================================================
Total Components: 53
Total Gates: 2847
Total DFFs: 156
```

### Output Format

Each component generates two files:

1. **JSON netlist** (`component.json`): Machine-readable gate-level representation
2. **Summary** (`component.txt`): Human-readable statistics

```
export/gates/
├── arithmetic/
│   ├── alu.json
│   ├── alu.txt
│   └── ...
├── sequential/
│   ├── counter.json
│   ├── counter.txt
│   └── ...
└── cpu/
    ├── synth_datapath.json
    └── synth_datapath.txt
```

---

## Apple2 Command

Apple II emulator and ROM tools for the MOS 6502 CPU implementation.

### Usage

```bash
rhdl apple2 [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--build` | Assemble the mini monitor ROM |
| `--run` | Run emulator after build |
| `--demo` | Run emulator in demo mode (no ROM needed) |
| `--appleiigo` | Run with AppleIIGo public domain ROM |
| `--clean` | Clean ROM output files |
| `-d, --debug` | Enable debug mode |
| `-r, --rom FILE` | ROM file to load |
| `--rom-address ADDR` | ROM load address (hex) |
| `-h, --help` | Show help |

### Examples

```bash
# Run the emulator (default)
rhdl apple2

# Run in demo mode (no ROM required)
rhdl apple2 --demo

# Build the mini monitor ROM
rhdl apple2 --build

# Build ROM and immediately run
rhdl apple2 --build --run

# Run with AppleIIGo public domain ROM
rhdl apple2 --appleiigo

# Run with custom ROM
rhdl apple2 --rom my_program.bin --rom-address 8000

# Enable debug mode
rhdl apple2 --demo --debug

# Clean ROM output files
rhdl apple2 --clean
```

### Demo Mode

Demo mode runs a simple demonstration program without requiring a ROM file:

```bash
rhdl apple2 --demo
```

### Building the Mini Monitor

The mini monitor is a simple ROM that provides basic memory inspection:

```bash
rhdl apple2 --build
# Output: export/roms/mini_monitor.bin
```

---

## Available Components

Use `rhdl tui --list` to see all available components:

### Gates
- `gates/not_gate`, `gates/and_gate`, `gates/or_gate`, `gates/xor_gate`
- `gates/nand_gate`, `gates/nor_gate`, `gates/xnor_gate`
- `gates/buffer`, `gates/tristate_buffer`
- `gates/bitwise_and`, `gates/bitwise_or`, `gates/bitwise_xor`, `gates/bitwise_not`

### Sequential
- `sequential/d_flipflop`, `sequential/t_flipflop`, `sequential/jk_flipflop`
- `sequential/sr_flipflop`, `sequential/sr_latch`
- `sequential/register_8bit`, `sequential/register_16bit`, `sequential/register_load`
- `sequential/shift_register`, `sequential/counter`
- `sequential/program_counter`, `sequential/stack_pointer`

### Arithmetic
- `arithmetic/half_adder`, `arithmetic/full_adder`, `arithmetic/ripple_carry_adder`
- `arithmetic/subtractor`, `arithmetic/addsub`
- `arithmetic/comparator`, `arithmetic/multiplier`, `arithmetic/divider`
- `arithmetic/incdec`, `arithmetic/alu_8bit`, `arithmetic/alu_16bit`

### Combinational
- `combinational/mux2`, `combinational/mux4`, `combinational/mux8`, `combinational/muxn`
- `combinational/demux2`, `combinational/demux4`
- `combinational/decoder_2to4`, `combinational/decoder_3to8`, `combinational/decoder_n`
- `combinational/encoder_4to2`, `combinational/encoder_8to3`
- `combinational/zero_detect`, `combinational/sign_extend`, `combinational/zero_extend`
- `combinational/barrel_shifter`, `combinational/bit_reverse`
- `combinational/popcount`, `combinational/lzcount`

### Memory
- `memory/ram`, `memory/ram_64k`, `memory/dual_port_ram`
- `memory/rom`, `memory/register_file`
- `memory/stack`, `memory/fifo`

### CPU
- `cpu/instruction_decoder`, `cpu/accumulator`, `cpu/datapath`

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `RHDL_BENCH_LANES` | Number of SIMD lanes for gate-level benchmarks (default: 64) |
| `RHDL_BENCH_CYCLES` | Number of cycles for benchmarks (default: 100000) |

---

## See Also

- [Debugging Guide](debugging.md) - Detailed TUI and debugging documentation
- [Diagrams Guide](diagrams.md) - Diagram generation details
- [Export Guide](export.md) - Verilog export details
- [Components Reference](components.md) - Complete component documentation
