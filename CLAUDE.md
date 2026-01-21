# Claude Code Instructions

## Project Overview

**RHDL (Ruby Hardware Description Language)** is a Domain Specific Language (DSL) for designing hardware using Ruby's syntax. It provides:

- Gate-level HDL simulation with signal propagation
- MOS 6502 and custom 8-bit CPU implementations
- HDL export to Verilog
- Interactive terminal GUI for debugging
- Diagram generation (SVG, PNG, DOT formats)

## Repository Structure

```
rhdl/
├── lib/rhdl/                    # Core library
│   ├── dsl.rb                   # Ruby DSL for component definitions
│   ├── synth.rb                 # Synthesis expression tree loader
│   ├── synth/                   # Synthesis expression tree building
│   │   ├── expr.rb              # Base expression class with operators
│   │   ├── literal.rb           # Literal values
│   │   ├── binary_op.rb         # Binary operations (+, -, &, |, etc.)
│   │   ├── unary_op.rb          # Unary operations (~, reduction ops)
│   │   ├── mux.rb               # Conditional mux expressions
│   │   ├── concat.rb            # Concatenation
│   │   ├── slice.rb             # Bit slicing
│   │   ├── signal_proxy.rb      # Signal references
│   │   ├── output_proxy.rb      # Output assignment proxies
│   │   └── context.rb           # Synthesis evaluation context
│   ├── codegen.rb               # Code generation infrastructure
│   ├── codegen/                 # Code generation backends
│   │   ├── behavior/            # RTL/Verilog codegen
│   │   │   ├── ir.rb            # Behavior intermediate representation
│   │   │   ├── lower.rb         # Behavior lowering
│   │   │   └── verilog.rb       # Verilog code generation
│   │   ├── circt/               # CIRCT toolchain
│   │   │   └── firrtl.rb        # FIRRTL code generation
│   │   └── structure/           # Gate-level synthesis
│   │       ├── primitives.rb    # Gate primitives (AND, OR, XOR, NOT, MUX, DFF)
│   │       ├── ir.rb            # Gate-level intermediate representation
│   │       ├── lower.rb         # HDL to gate-level lowering (53 components)
│   │       ├── toposort.rb      # Topological sorting
│   │       ├── sim_cpu.rb       # CPU gate-level simulation
│   │       └── sim_gpu.rb       # GPU gate-level simulation
│   ├── sim.rb                   # Simulation engine loader
│   ├── sim/                     # Core simulation engine (RHDL::Sim module)
│   │   ├── component.rb         # Component base class
│   │   ├── simulator.rb         # Main simulator
│   │   ├── wire.rb              # Wire/signal implementation
│   │   ├── clock.rb             # Clock signal
│   │   ├── value_proxy.rb       # Computed value proxy
│   │   ├── signal_proxy.rb      # Input signal proxy
│   │   ├── output_proxy.rb      # Output signal proxy
│   │   ├── behavior_context.rb  # Simulation behavior context
│   │   └── ...                  # Other simulation infrastructure
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
│   ├── hdl/                     # HDL components (component definitions ONLY)
│   │   ├── gates.rb             # Logic gate primitives
│   │   ├── sequential.rb        # Flip-flops, registers, counters
│   │   ├── arithmetic.rb        # Adders, ALU, comparators
│   │   ├── combinational.rb     # Multiplexers, decoders
│   │   ├── memory.rb            # RAM, ROM, register files
│   │   └── cpu/                 # HDL CPU implementation
│   │       ├── cpu.rb           # Declarative CPU (combines all components)
│   │       ├── harness.rb       # Behavioral simulation wrapper
│   │       ├── datapath.rb      # Synthesizable CPU datapath
│   │       └── instruction_decoder.rb # Instruction decoder
│   ├── diagram/                 # Diagram module
│   │   ├── component.rb         # Component diagram generation
│   │   ├── hierarchy.rb         # Hierarchical diagrams
│   │   ├── netlist.rb           # Netlist diagrams
│   │   ├── gate_level.rb        # Gate-level diagrams
│   │   ├── render_svg.rb        # SVG rendering
│   │   ├── render_dot.rb        # Graphviz DOT format
│   │   ├── renderer.rb          # ASCII/Unicode circuit renderer
│   │   ├── svg_renderer.rb      # SVG diagram renderer
│   │   └── methods.rb           # Extension methods for components
│   └── cli/                     # CLI infrastructure
│       ├── cli.rb               # CLI task loader
│       ├── config.rb            # Shared configuration
│       ├── task.rb              # Base task class
│       └── tasks/               # Task implementations
│           ├── diagram_task.rb  # Diagram generation
│           ├── export_task.rb   # Verilog export
│           ├── gates_task.rb    # Gate-level synthesis
│           ├── tui_task.rb      # TUI debugger
│           ├── apple2_task.rb   # Apple II emulator
│           ├── native_task.rb   # Native Rust extension
│           ├── deps_task.rb     # Dependency management
│           ├── benchmark_task.rb # Benchmarking
│           └── generate_task.rb # Combined generation
│
├── examples/                    # Example implementations
│   ├── mos6502/                 # MOS 6502 behavior CPU
│   │   ├── cpu.rb               # 6502 CPU
│   │   ├── alu.rb               # 6502 ALU
│   │   ├── control_unit.rb      # State machine
│   │   ├── datapath.rb          # CPU datapath
│   │   ├── assembler.rb         # 6502 assembler
│   │   └── ...                  # Other 6502 components
│   └── mos6502/                # MOS 6502 synthesizable CPU
│       └── ...                  # Synthesizable 6502 components
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
│   ├── mos6502.md               # MOS 6502 implementation
│   ├── debugging.md             # Debug/TUI guide
│   ├── diagrams.md              # Diagram generation
│   ├── hdl_export.md            # Verilog export
│   ├── gate_level_backend.md    # Gate-level synthesis details
│   └── apple2_io.md             # Apple II I/O support
│
├── export/                      # Generated exports (all output files)
│   ├── verilog/                 # Generated Verilog files
│   └── gates/                   # Gate-level synthesis JSON netlists
│       ├── arithmetic/          # ALU, adders, multiplier, divider
│       ├── combinational/       # Mux, demux, decoders, encoders
│       ├── sequential/          # Registers, counters, flip-flops
│       ├── gates/               # Logic gate primitives
│       └── cpu/                 # CPU components (SynthDatapath)
│
└── diagrams/                    # Generated circuit diagrams
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
- `parallel_tests ~> 4.0` - Parallel test execution (dev/test)
- `benchmark-ips ~> 2.12` - Benchmarking (dev/test)

### Optional System Dependencies

- `iverilog` - Icarus Verilog for gate-level simulation tests
  - Install on Ubuntu/Debian: `apt-get install iverilog`
  - Install on macOS: `brew install icarus-verilog`
  - When installed, enables iverilog simulation tests that verify gate-level synthesis matches behavior simulation

### Installation

1. Install bundler (use version 2.x, avoid 4.x which has known issues):
```bash
gem install bundler -v '~> 2.5'
```

2. Install all dependencies and generate binstubs:
```bash
bundle install
```

The `.bundle/config` file configures Bundler to automatically generate binstubs in `bin/` during installation. This eliminates the need for a separate setup step.

3. (Optional) Install system dependencies:
```bash
bundle exec rake deps:install
```

4. Verify installation:
```bash
./bin/rake --version
```

**Note:** If binstubs are not generated (e.g., `.bundle/config` is missing), you can manually generate them:
```bash
bundle binstubs rake rspec parallel_tests
```

## Running Tests

Always use `bundle exec` to run tests to ensure correct gem versions.

### Parallel Testing (Recommended)

The test suite supports parallel execution for faster test runs (~40% faster with 16 cores):

```bash
# Run all tests in parallel (auto-detects CPU count)
bundle exec rake pspec

# Run with specific number of processes
bundle exec rake parallel:spec_n[8]

# Run 6502 tests in parallel
bundle exec rake parallel:spec_6502

# Run HDL tests in parallel
bundle exec rake parallel:spec_hdl

# Record runtimes for optimal load balancing
bundle exec rake parallel:prepare

# Run with runtime-based balancing
bundle exec rake parallel:spec_balanced
```

### Serial Testing

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
| Behavior CPU | 47 tests passing |
| HDL CPU | 22 tests passing |
| HDL Components | All passing |

Key test files:
- `spec/examples/mos6502/instructions_spec.rb` - All 6502 instructions (129 tests)
- `spec/examples/mos6502/algorithms_spec.rb` - Bubble sort, Fibonacci, etc.
- `spec/rhdl/hdl/cpu_spec.rb` - HDL CPU unit tests
- `spec/rhdl/hdl/gates_spec.rb` - Logic gate tests

### Gate-Level Simulation Tests

When iverilog is installed, additional tests run that verify gate-level synthesis matches behavior simulation:

1. Gate-level IR is converted to structure Verilog
2. A testbench generates test vectors from behavior simulation
3. iverilog compiles and runs the structure simulation
4. Results are compared against expected behavior outputs

These tests are conditional (`if: HdlToolchain.iverilog_available?`) and automatically skip when iverilog is not installed.

## Development Notes

### Key Entry Points

- `lib/rhdl.rb` - Main library entry point
- `examples/mos6502/cpu.rb` - MOS 6502 CPU implementation

### Rake Tasks

The project includes rake tasks for development operations. CLI operations are done via the `rhdl` binary.

```bash
# Setup development environment (generates binstubs)
rake setup

# Check/install test dependencies (iverilog, etc.)
rake deps:install
rake deps:check

# Run gate-level simulation benchmark
rake bench:gates

# Benchmark tests and show slowest N tests (default 20)
rake benchmark:tests[30]

# Benchmark 6502 tests only
rake benchmark:tests_6502

# Benchmark HDL tests only
rake benchmark:tests_hdl

# Detailed per-file timing analysis
rake benchmark:timing

# Quick benchmark by test category
rake benchmark:quick

# Build native ISA simulator (Rust)
rake native:build

# Check native extension status
rake native:check

# Clean native extension build artifacts
rake native:clean
```

### CLI Binary (`rhdl`)

All CLI operations are done via the `rhdl` binary:

```bash
# Generate circuit diagrams
rhdl diagram --all

# Export components to Verilog
rhdl export --all

# Gate-level synthesis
rhdl gates --export
rhdl gates --simcpu
rhdl gates --stats
rhdl gates --clean

# TUI debugger
rhdl tui

# Apple II emulator
rhdl apple2 --appleiigo --disk game.dsk --hires
rhdl apple2 --karateka  # Quick start with Karateka

# Disk image utilities
rhdl disk info disk.dsk
rhdl disk convert disk.dsk
rhdl disk memdump disk.dsk --rom appleiigo.rom

# Combined operations
rhdl generate    # Generate all output files
rhdl clean       # Clean all generated files
rhdl regenerate  # Clean and regenerate
```

**Note:** Binstubs are automatically generated by `bundle install` via `.bundle/config`. If needed, run `bundle binstubs rake rspec parallel_tests` manually.

### HDL Export

Export Ruby DSL components to Verilog:
```ruby
require 'rhdl'

# Export to Verilog
component = MyComponent.new
verilog_code = RHDL::Export::Verilog.export(component)
```

Generated files are placed in `/export/verilog/` directory.

### Gate-Level Synthesis

Lower HDL components to primitive gate netlists (AND, OR, XOR, NOT, MUX, DFF):
```ruby
require 'rhdl/hdl'
require 'rhdl/export'

# Create a component
alu = RHDL::HDL::ALU.new('alu', width: 8)

# Lower to gate-level IR
ir = RHDL::Export::Structure::Lower.from_components([alu], name: 'alu')

# Export to JSON netlist
File.write('alu.json', ir.to_json)

# Get statistics
puts "Gates: #{ir.gates.length}, DFFs: #{ir.dffs.length}"
```

The gate-level synthesis supports 53 HDL components including:
- **Gates**: AND, OR, XOR, NOT, NAND, NOR, XNOR, Buffer, Tristate
- **Arithmetic**: Adder, Subtractor, Multiplier, Divider, ALU, Comparator
- **Sequential**: D/T/JK/SR flip-flops, Register, Counter, ProgramCounter
- **Combinational**: Mux2/4/8, Demux, Decoder, Encoder, BarrelShifter
- **CPU**: InstructionDecoder, SynthDatapath (hierarchical composition)

Generated netlists are placed in `/export/gates/` directory.

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

### Latest Updates (January 2025)
- **Class-level hierarchical DSL** - Components use `instance`, `wire`, and `port` methods
  - Replaced block-based `structure do ... end` with class-level declarations
  - `instance :name, ComponentClass, params` - Instantiate sub-components
  - `wire :signal_name, width: N` - Define internal wires (signals)
  - `port :signal => [:component, :port]` - Connect signals to sub-component ports
  - Supports fan-out: `port :clk => [[:comp1, :clk], [:comp2, :clk]]`
  - Generates Verilog module instantiations automatically
  - Naming aligns with Verilog: `wire` for internal signals, `port` for connections
- **Parallel test execution** - Test suite runs ~40% faster with parallel_tests gem
  - New rake tasks: `pspec`, `parallel:spec`, `parallel:spec_6502`, `parallel:spec_hdl`
  - Runtime-based load balancing with `parallel:prepare` and `parallel:spec_balanced`
  - Auto-detects CPU count for optimal parallelization
- **Gate-level synthesis** - Complete gate-level lowering for 53 HDL components
  - Primitive gates: AND, OR, XOR, NOT, MUX, BUF, CONST, DFF
  - Complex components: Multiplier (array), Divider (restoring), ALU
  - Hierarchical synthesis for SynthDatapath CPU (505 gates, 24 DFFs)
  - JSON netlist export with statistics
- **Export directory consolidation** - All output now in `/export/` directory
  - `/export/verilog/` - Generated Verilog files
  - `/export/gates/` - Gate-level JSON netlists
- **New rake tasks** - `gates:export`, `gates:simcpu`, `gates:stats`, `gates:clean`

### Previous Updates (2025)
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

### CLI Task Classes

**All rake and CLI task logic MUST live in task classes in `lib/rhdl/cli/tasks/`.** The Rakefile and CLI binary both call into these shared task classes.

**Task class location and structure:**
- Task classes live in `lib/rhdl/cli/tasks/*.rb`
- Each task class inherits from `RHDL::CLI::Task`
- Tasks are registered in `lib/rhdl/cli.rb` via `require_relative`
- The `run` method dispatches based on `options` hash

**Existing task classes:**
- `DiagramTask` - Diagram generation (`cli:diagrams:*`)
- `ExportTask` - HDL/Verilog export (`cli:hdl:*`)
- `GatesTask` - Gate-level synthesis (`cli:gates:*`)
- `TuiTask` - TUI debugger (`cli:tui:*`)
- `Apple2Task` - Apple II emulator (`cli:apple2:*`)
- `NativeTask` - Native Rust extension (`native:*`)
- `DepsTask` - Dependency management (`dev:deps:*`)
- `BenchmarkTask` - Benchmarking (`dev:bench:*`, `dev:benchmark:*`)
- `GenerateTask` - Combined generation tasks

**Adding a new task:**
1. Create a new class in `lib/rhdl/cli/tasks/my_task.rb`
2. Inherit from `RHDL::CLI::Task`
3. Implement `run` method that dispatches on `options`
4. Register in `lib/rhdl/cli.rb` with `require_relative`
5. Add rake task in `Rakefile` that calls `RHDL::CLI::Tasks::MyTask.new(options).run`
6. Write tests in `spec/rhdl/cli/tasks/my_task_spec.rb`

**Example task class:**
```ruby
# lib/rhdl/cli/tasks/my_task.rb
module RHDL
  module CLI
    module Tasks
      class MyTask < Task
        def run
          if options[:build]
            build
          elsif options[:clean]
            clean
          else
            build
          end
        end

        def build
          puts_header "Building..."
          # Implementation
        end

        def clean
          # Implementation
        end
      end
    end
  end
end
```

**Example rake task:**
```ruby
# In Rakefile
namespace :my do
  desc "Build my thing"
  task :build do
    load_cli_tasks
    RHDL::CLI::Tasks::MyTask.new(build: true).run
  end
end
```

### Debug and Test Scripts

All debug and temporary test scripts should be written as rake tasks. Do not create standalone debug scripts at the top level of the repository.

**Examples:**
```bash
# Run gate-level benchmark
rake dev:bench:gates

# Run specific test suite
rake dev:spec_6502

# Generate diagrams for debugging
rake cli:diagrams:generate
```

If you need to add a new debug or test script:
1. Add it as a task class in `lib/rhdl/cli/tasks/`
2. Add a rake task in `Rakefile` that calls into the task class
3. Namespace appropriately (e.g., `dev:`, `cli:`, `native:`)
4. Include a description using `desc` so it appears in `rake -T`

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

**HDL directory organization:**
- The `lib/rhdl/hdl/` directory should only contain component definitions
- Non-component utilities (diagram rendering, export tools, etc.) belong in their own top-level directories (e.g., `diagram/`, `export/`)
- Component mixins and extension methods should be defined outside `hdl/` and included into components from hdl.rb

### HDL Component Guidelines

**All new components MUST use the declarative DSL only.** Do not override `initialize` to manually instantiate sub-components - the `SimComponent` base class handles this automatically.

**Declarative DSL methods:**
- `input :name, width: N` - Define input port
- `output :name, width: N` - Define output port
- `wire :name, width: N` - Define internal signal
- `instance :name, ComponentClass, params` - Declare sub-component
- `port :signal => [:instance, :port]` - Connect signal to instance port
- `behavior do ... end` - Define combinational logic

**Example component using only declarative DSL:**
```ruby
class MyDatapath < SimComponent
  # Ports - the ONLY interface to the component
  input :clk
  input :a, width: 8
  input :b, width: 8
  output :result, width: 8

  # Internal signals
  wire :alu_out, width: 8

  # Sub-components (automatically instantiated, private to component)
  instance :alu, ALU, width: 8
  instance :reg, Register, width: 8

  # Connections
  port :a => [:alu, :a]
  port :b => [:alu, :b]
  port [:alu, :result] => :alu_out
  port :alu_out => [:reg, :d]
  port :clk => [:reg, :clk]
  port [:reg, :q] => :result
end
```

**Key points:**
- The `instance` DSL automatically creates instance variables (`@alu`, `@reg`) and populates `@subcomponents`
- **Do NOT use `attr_reader` to expose sub-components** - all interaction must be through ports
- Components should be fully encapsulated - external code uses `set_input`/`get_output` only
- Never override `initialize` unless absolutely necessary for non-DSL functionality
- The DSL supports both simulation and Verilog export automatically
