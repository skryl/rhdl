# Claude Code Instructions

## Project Overview

**RHDL (Ruby Hardware Description Language)** is a Domain Specific Language (DSL) for designing hardware using Ruby's syntax. It provides:

- Gate-level HDL simulation with signal propagation
- MOS 6502 and custom 8-bit CPU implementations
- HDL export to VHDL and Verilog
- Interactive terminal GUI for debugging
- Diagram generation (SVG, PNG, DOT formats)

## Repository Structure

```
rhdl/
├── lib/rhdl/                    # Core library
│   ├── dsl.rb                   # Ruby DSL for component definitions
│   ├── export.rb                # HDL export infrastructure
│   ├── export/                  # Export backends
│   │   ├── vhdl.rb              # VHDL export
│   │   ├── verilog.rb           # Verilog export
│   │   ├── ir.rb                # Intermediate representation
│   │   └── lower.rb             # IR lowering utilities
│   ├── simulation.rb            # Simulation engine loader
│   ├── simulation/              # Core simulation engine
│   │   ├── simulator.rb         # Main simulator
│   │   ├── sim_component.rb     # Component base class
│   │   ├── wire.rb              # Wire/signal implementation
│   │   ├── clock.rb             # Clock signal
│   │   └── ...                  # Synth expressions, proxies
│   ├── debug.rb                 # Debug module loader
│   ├── debug/                   # Signal probing & debugging
│   │   ├── debug_simulator.rb   # Debug-enabled simulator
│   │   ├── signal_probe.rb      # Signal probing
│   │   ├── waveform_capture.rb  # Waveform capture
│   │   ├── breakpoint.rb        # Breakpoints
│   │   └── watchpoint.rb        # Watchpoints
│   ├── tui.rb                   # Terminal GUI loader
│   ├── tui/                     # Terminal GUI
│   │   ├── simulator_tui.rb     # Main TUI interface
│   │   ├── panel.rb             # Panel base class
│   │   ├── signal_panel.rb      # Signal display panel
│   │   ├── waveform_panel.rb    # Waveform display
│   │   └── ...                  # Other TUI components
│   ├── hdl/                     # HDL components
│   │   ├── gates.rb             # Logic gate primitives
│   │   ├── sequential.rb        # Flip-flops, registers, counters
│   │   ├── arithmetic.rb        # Adders, ALU, comparators
│   │   ├── combinational.rb     # Multiplexers, decoders
│   │   ├── memory.rb            # RAM, ROM, register files
│   │   ├── diagram.rb           # Diagram generation
│   │   └── cpu/                 # HDL CPU implementation
│   │       ├── datapath.rb      # CPU datapath
│   │       └── adapter.rb       # Behavioral/HDL adapter
│   ├── gates/                   # Gate-level primitives
│   │   ├── primitives.rb        # Gate primitives
│   │   ├── ir.rb                # Gate-level IR
│   │   └── toposort.rb          # Topological sorting
│   └── diagram/                 # Diagram module
│       ├── render_svg.rb        # SVG rendering
│       ├── render_dot.rb        # Graphviz DOT format
│       ├── gate_level.rb        # Gate-level diagrams
│       └── netlist.rb           # Netlist generation
│
├── cpu/                         # Behavioral 8-bit CPU
│   ├── cpu.rb                   # Main CPU implementation
│   ├── control_unit.rb          # Instruction decoding
│   ├── cpu_alu.rb               # ALU
│   ├── memory_unit.rb           # Memory interface
│   └── program_counter.rb       # Program counter
│
├── examples/                    # Example implementations
│   └── mos6502/                 # MOS 6502 CPU implementation
│       ├── cpu.rb               # 6502 CPU
│       ├── alu.rb               # 6502 ALU
│       ├── control_unit.rb      # State machine
│       ├── datapath.rb          # CPU datapath
│       ├── assembler.rb         # 6502 assembler
│       └── ...                  # Other 6502 components
│
├── spec/                        # Test suite
│   ├── examples/mos6502/        # MOS 6502 tests (189+ tests)
│   ├── behavioral_cpu/          # Behavioral CPU tests (47 tests)
│   ├── rhdl/                    # Core framework tests
│   │   └── hdl/                 # HDL component tests
│   └── support/                 # Test helpers
│
├── docs/                        # Documentation
│   ├── hdl_overview.md          # HDL framework intro
│   ├── simulation_engine.md     # Simulation infrastructure
│   ├── components.md            # Component reference
│   ├── cpu_datapath.md          # CPU architecture
│   ├── mos6502.md               # MOS 6502 implementation
│   ├── debugging.md             # Debug/TUI guide
│   ├── diagrams.md              # Diagram generation
│   ├── hdl_export.md            # VHDL/Verilog export
│   ├── gate_level_backend.md    # Gate-level details
│   └── apple2_io.md             # Apple II I/O support
│
├── vhdl/                        # Generated VHDL files
├── verilog/                     # Generated Verilog files
└── diagrams/                    # Generated diagrams
```

## Environment Setup

### Ruby Version

- Requires Ruby >= 2.6.0 (specified in `rhdl.gemspec`)
- Recommended: Use a Ruby version manager (rbenv, rvm, asdf)

### Dependencies

The project uses these gems:
- `parslet ~> 2.0` - Parser generator
- `activesupport ~> 7.0` - Rails utility library
- `rspec ~> 3.12` - Testing framework (dev/test)
- `rake ~> 13.0` - Build tool (dev/test)

### Installation

1. Install bundler (use version 2.x, avoid 4.x which has known issues):
```bash
gem install bundler -v '~> 2.5'
```

2. Install all dependencies:
```bash
bundle install
```

3. Verify installation:
```bash
bundle exec rake --version
```

## Running Tests

Always use `bundle exec` to run tests to ensure correct gem versions:

```bash
# Run all tests
bundle exec rake spec

# Run specific test file
bundle exec rspec spec/some_spec.rb

# Run 6502 CPU tests
bundle exec rake spec_6502

# Run with documentation format
bundle exec rake spec_doc
```

### Test Coverage

| Test Suite | Status |
|------------|--------|
| MOS 6502 CPU | 189+ tests passing |
| Behavioral CPU | 47 tests passing |
| HDL CPU | 22 tests passing |
| HDL Components | All passing |

Key test files:
- `spec/examples/mos6502/instructions_spec.rb` - All 6502 instructions (129 tests)
- `spec/examples/mos6502/algorithms_spec.rb` - Bubble sort, Fibonacci, etc.
- `spec/rhdl/hdl/cpu_spec.rb` - HDL CPU unit tests
- `spec/rhdl/hdl/gates_spec.rb` - Logic gate tests

## Development Notes

### Key Entry Points

- `lib/rhdl.rb` - Main library entry point
- `examples/mos6502/cpu.rb` - MOS 6502 CPU implementation

### Rake Tasks

The project includes rake tasks for common operations:

```bash
# Generate all component diagrams (SVG, DOT, TXT)
rake diagrams:generate

# Clean generated diagrams
rake diagrams:clean

# Export DSL components to VHDL and Verilog
rake hdl:export

# Export only VHDL
rake hdl:vhdl

# Export only Verilog
rake hdl:verilog

# Clean generated HDL files
rake hdl:clean

# Run gate-level simulation benchmark
rake bench:gates

# Generate all outputs (diagrams + HDL)
rake generate_all

# Clean all generated files
rake clean_all

# Regenerate everything (clean + generate)
rake regenerate
```

### HDL Export

Export Ruby DSL components to VHDL/Verilog:
```ruby
require 'rhdl'

# Export component to VHDL
component = MyComponent.new
vhdl_code = RHDL::Export::VHDL.export(component)

# Export to Verilog
verilog_code = RHDL::Export::Verilog.export(component)
```

Generated files are placed in `/vhdl/` and `/verilog/` directories.

### Diagram Generation

Generate circuit diagrams programmatically:
```ruby
require 'rhdl'

# Generate component diagram
component = RHDL::HDL::ALU.new('alu', width: 8)

# ASCII diagram
puts component.to_diagram

# Save SVG
component.save_svg("output.svg")

# Save DOT (Graphviz)
component.save_dot("output.dot")
```

Multi-level diagrams with hierarchy support are available. See `docs/diagrams.md`.

## Recent Changes

### Latest Updates (2025)
- **Rake task migration** - Moved scripts to rake tasks (`rake diagrams:generate`, `rake hdl:export`, `rake bench:gates`)
- **MOS 6502 CPU timing fixes** - Fixed RMW instruction timing for shifts
- **Multi-level diagram generation** - Hierarchical component diagrams
- **HDL export improvements** - Fixed Verilog resize and export tests
- **Apple II I/O support** - Memory-mapped I/O for Apple II bus
- **FIG Forth interpreter tests** - Threaded program execution

### Documentation

Detailed documentation is available in `/docs/`:
- Start with `hdl_overview.md` for architecture concepts
- See `components.md` for the full component reference
- See `mos6502.md` for MOS 6502 CPU implementation details
- Use `debugging.md` for TUI and debugging guide

## Development Guidelines

### Debug and Test Scripts

All debug and temporary test scripts should be written as rake tasks and reused when possible. Do not create standalone debug scripts at the top level of the repository.

**Examples:**
```bash
# Run gate-level benchmark
rake bench:gates

# Run specific test suite
rake spec_6502

# Generate diagrams for debugging
rake diagrams:generate
```

If you need to add a new debug or test script:
1. Add it as a rake task in `Rakefile`
2. Namespace it appropriately (e.g., `debug:`, `bench:`, `test:`)
3. Include a description using `desc` so it appears in `rake -T`

### Code Organization

Follow these conventions for file organization:

**One class/module per file:**
- Each Ruby file should contain exactly one class or module definition
- File names should match the class/module name in snake_case (e.g., `signal_probe.rb` for `SignalProbe`)
- Nested modules are acceptable within a single file when they are small and tightly coupled

**One spec per file:**
- Each spec file should test exactly one class or module
- Spec files should mirror the lib directory structure (e.g., `spec/rhdl/simulation/simulator_spec.rb` for `lib/rhdl/simulation/simulator.rb`)
- Name spec files with `_spec.rb` suffix matching the class being tested
