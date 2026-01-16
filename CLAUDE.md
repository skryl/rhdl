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
│   ├── hdl/                     # HDL simulation framework
│   │   ├── simulation.rb        # Core simulation engine
│   │   ├── gates.rb             # Logic gate primitives
│   │   ├── sequential.rb        # Flip-flops, registers, counters
│   │   ├── arithmetic.rb        # Adders, ALU, comparators
│   │   ├── combinational.rb     # Multiplexers, decoders
│   │   ├── memory.rb            # RAM, ROM, register files
│   │   ├── debug.rb             # Signal probing & debugging
│   │   ├── tui.rb               # Terminal GUI
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
├── examples/                    # Demo scripts
│   ├── full_adder.rb            # Full adder example
│   ├── simulator_tui_demo.rb    # TUI demo
│   ├── circuit_diagrams.rb      # Diagram examples
│   └── mos6502/                 # MOS 6502 CPU implementation
│       ├── cpu.rb               # 6502 CPU
│       ├── alu.rb               # 6502 ALU
│       ├── assembler.rb         # 6502 assembler
│       └── ...                  # Other 6502 components
│
├── spec/                        # Test suite
│   ├── examples/mos6502/        # MOS 6502 tests (189+ tests)
│   ├── rhdl/                    # Core framework tests
│   │   └── hdl/                 # HDL component tests
│   └── support/                 # Test helpers
│
├── docs/                        # Documentation
│   ├── hdl_overview.md          # HDL framework intro
│   ├── simulation_engine.md     # Simulation infrastructure
│   ├── components.md            # Component reference
│   ├── cpu_datapath.md          # CPU architecture
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

1. Install the correct bundler version:
```bash
gem install bundler -v 2.5.18
```

2. Install dependencies:
```bash
bundle install
```

## Running Tests

### Recommended: Using bundle exec

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/some_spec.rb

# Run with documentation format
bundle exec rspec --format documentation
```

### Using rake

```bash
# Run all tests
rake spec

# Run 6502 CPU tests
rake spec_6502

# Run with documentation format
rake spec_doc
```

### Using the test runner script

```bash
# Run all tests
bin/test

# Run specific tests
bin/test spec/examples/mos6502/
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
- `examples/simulator_tui_demo.rb` - Interactive TUI demo
- `examples/circuit_diagrams.rb` - Diagram generation examples

### Running Examples

```bash
# TUI simulator demo
ruby examples/simulator_tui_demo.rb

# Diagram generation
ruby examples/circuit_diagrams.rb
```

### HDL Export

Export Ruby components to VHDL/Verilog:
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

Generate circuit diagrams:
```ruby
require 'rhdl'

# Generate component diagram
diagram = RHDL::HDL::Diagram.new(component)
diagram.render_svg("output.svg")
diagram.render_dot("output.dot")
```

Multi-level diagrams with hierarchy support are available. See `docs/diagrams.md`.

## Recent Changes

### Latest Updates (2025)
- **MOS 6502 CPU timing fixes** - Fixed RMW instruction timing for shifts
- **Multi-level diagram generation** - Hierarchical component diagrams
- **HDL export improvements** - Fixed Verilog resize and export tests
- **Apple II I/O support** - Memory-mapped I/O for Apple II bus
- **FIG Forth interpreter tests** - Threaded program execution

### Documentation

Detailed documentation is available in `/docs/`:
- Start with `hdl_overview.md` for architecture concepts
- See `components.md` for the full component reference
- Use `debugging.md` for TUI and debugging guide
