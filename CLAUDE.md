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
├── docs/                        # Documentation (13 files)
│   ├── overview.md              # HDL framework intro
│   ├── dsl.md                   # Synthesizable DSL guide
│   ├── simulation.md            # Simulation engine & backends
│   ├── components.md            # Component reference (50+ components)
│   ├── 8bit_cpu.md              # Sample 8-bit CPU architecture
│   ├── mos6502_cpu.md           # MOS 6502 implementation
│   ├── debugging.md             # Debug/TUI guide
│   ├── diagrams.md              # Diagram generation
│   ├── export.md                # Verilog export guide
│   ├── gate_level_backend.md    # Gate-level synthesis details
│   ├── cli.md                   # CLI reference
│   ├── apple2.md                # Apple II emulation
│   └── chisel_feature_gap_analysis.md  # Chisel comparison
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

1. Clone the repository and initialize submodules:
```bash
git clone <repo-url>
cd rhdl
git submodule update --init --recursive
```

2. Install bundler (use version 2.x, avoid 4.x which has known issues):
```bash
gem install bundler -v '~> 2.5'
```

3. Install all dependencies and generate binstubs:
```bash
bundle install
bundle binstubs rake rspec parallel_tests
```

4. (Optional) Install system dependencies:
```bash
./bin/rake deps:install
```

5. (Optional) Build native Rust extensions for high-performance simulation:
```bash
./bin/rake native:build
```

6. Verify installation:
```bash
./bin/rake --version
```

## Running Tests

Always use `bundle exec` to run tests to ensure correct gem versions.

### Parallel Testing (Recommended)

The test suite supports parallel execution for faster test runs (~40% faster with 16 cores):

```bash
# Run all tests in parallel (auto-detects CPU count)
bundle exec rake pspec

# Run with specific number of processes
bundle exec rake pspec:n[8]

# Run specific test suites in parallel
bundle exec rake pspec:mos6502
bundle exec rake pspec:hdl
bundle exec rake pspec:lib
bundle exec rake pspec:apple2

# Record runtimes for optimal load balancing
bundle exec rake pspec:prepare

# Run with runtime-based balancing
bundle exec rake pspec:balanced
```

### Serial Testing

```bash
# Run all tests
bundle exec rake spec

# Run specific test file
bundle exec rspec spec/some_spec.rb

# Run specific test suites
bundle exec rake spec:mos6502
bundle exec rake spec:hdl
bundle exec rake spec:lib
bundle exec rake spec:apple2
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

The project includes rake tasks for development operations. Run `bundle exec rake -T` to see all available tasks.

**Setup & Dependencies:**
```bash
rake setup              # Setup development environment (install deps + binstubs)
rake deps:install       # Check and install test dependencies (iverilog)
rake deps:check         # Check test dependencies status
```

**Testing (Serial):**
```bash
rake spec               # Run all RSpec tests
rake spec:mos6502       # Run MOS 6502 specs
rake spec:hdl           # Run HDL component specs
rake spec:lib           # Run lib/rhdl specs
rake spec:apple2        # Run Apple II specs
```

**Testing (Parallel - Recommended):**
```bash
rake pspec              # Run all tests in parallel (auto-detects CPU count)
rake pspec:n[8]         # Run with specific number of processes
rake pspec:mos6502      # Run MOS 6502 specs in parallel
rake pspec:hdl          # Run HDL specs in parallel
rake pspec:lib          # Run lib/rhdl specs in parallel
rake pspec:apple2       # Run Apple II specs in parallel
rake pspec:prepare      # Record test file runtimes for balancing
rake pspec:balanced     # Run with runtime-based grouping
```

**Benchmarking:**
```bash
rake bench              # Run gate benchmark (alias for bench:gates)
rake bench:gates        # Benchmark gate-level simulation
rake bench:apple2[N]    # Benchmark Apple2 full system IR (N cycles)
rake bench:mos6502[N]   # Benchmark MOS6502 CPU IR with memory bridging
rake bench:verilator[N] # Benchmark Verilator simulation
rake benchmark          # Benchmark tests showing 20 slowest
rake benchmark:quick    # Quick benchmark of test categories
rake benchmark:timing   # Run full test timing analysis
rake spec:bench:all[N]  # Benchmark all specs (show N slowest)
rake spec:bench:hdl[N]  # Benchmark HDL specs
rake spec:bench:mos6502[N] # Benchmark MOS 6502 specs
```

**Native Extension:**
```bash
rake native             # Build native ISA simulator (alias for native:build)
rake native:build       # Build the native ISA simulator Rust extension
rake native:check       # Check if native extension is available
rake native:clean       # Clean native extension build artifacts
```

**Build & Release:**
```bash
rake build              # Build rhdl gem into pkg directory
rake install            # Build and install gem into system gems
rake clean              # Remove any temporary products
rake clobber            # Remove any generated files
```

### CLI Binary (`rhdl`)

All CLI operations are done via the `rhdl` binary. Run `rhdl --help` or `rhdl <command> --help` for detailed options.

**Diagram Generation:**
```bash
rhdl diagram --all                    # Generate all component diagrams
rhdl diagram --all --mode gate        # Generate gate-level diagrams
rhdl diagram RHDL::HDL::ALU --level component --format svg
rhdl diagram --clean                  # Clean generated diagrams
```

**Verilog Export:**
```bash
rhdl export --all                     # Export all components to Verilog
rhdl export --all --scope lib         # Export only lib components
rhdl export RHDL::HDL::Counter --lang verilog --out ./output
rhdl export --clean                   # Clean generated Verilog
```

**Gate-Level Synthesis:**
```bash
rhdl gates                            # Export all to gate-level IR (default)
rhdl gates --export                   # Same as above
rhdl gates --simcpu                   # Export SimCPU datapath
rhdl gates --stats                    # Show synthesis statistics
rhdl gates --clean                    # Clean gate-level output
```

**TUI Debugger:**
```bash
rhdl tui RHDL::HDL::Counter           # Debug a specific component
rhdl tui sequential/counter           # Use short path
rhdl tui --list                       # List available components
rhdl tui --signals inputs --format hex  # Customize display
```

**Example Emulators:**
```bash
rhdl examples mos6502 --demo          # Run 6502 demo
rhdl examples mos6502 --karateka      # Play Karateka
rhdl examples mos6502 --mode hdl --sim compile --karateka  # HDL mode
rhdl examples apple2 --appleiigo --disk game.dsk --hires   # Apple II with disk
rhdl examples apple2 --mode netlist --sim jit --demo       # Netlist simulation
```

**Disk Utilities:**
```bash
rhdl disk info game.dsk               # Show disk image info
rhdl disk convert game.dsk -o out.bin # Convert to binary
rhdl disk memdump game.dsk -r rom.bin # Dump memory after boot
```

**Combined Operations:**
```bash
rhdl generate                         # Generate all output files
rhdl clean                            # Clean all generated files
rhdl regenerate                       # Clean and regenerate
```

**Note:** Binstubs are automatically generated by `bundle install` via `.bundle/config`. See `docs/cli.md` for complete CLI reference.

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

### Latest Updates (2025)
- **Class-level hierarchical DSL** - Components use `instance`, `wire`, and `port` methods
  - Replaced block-based `structure do ... end` with class-level declarations
  - `instance :name, ComponentClass, params` - Instantiate sub-components
  - `wire :signal_name, width: N` - Define internal wires (signals)
  - `port :signal => [:component, :port]` - Connect signals to sub-component ports
  - Supports fan-out: `port :clk => [[:comp1, :clk], [:comp2, :clk]]`
  - Naming aligns with Verilog: `wire` for internal signals, `port` for connections
- **Parallel test execution** - Test suite runs ~40% faster with parallel_tests gem
  - Rake tasks: `pspec`, `pspec:mos6502`, `pspec:hdl`, `pspec:lib`, `pspec:apple2`
  - Runtime-based load balancing with `pspec:prepare` and `pspec:balanced`
  - Auto-detects CPU count for optimal parallelization
- **Gate-level synthesis** - Complete gate-level lowering for 53 HDL components
  - Primitive gates: AND, OR, XOR, NOT, MUX, BUF, CONST, DFF
  - Complex components: Multiplier (array), Divider (restoring), ALU
  - Hierarchical synthesis for SynthDatapath CPU (505 gates, 24 DFFs)
  - JSON netlist export with statistics
- **Multiple simulation backends** - Ruby behavioral, gate-level, native Rust
  - ISA-level simulation (fastest), HDL behavioral, netlist (gate-level)
  - Simulator backends: ruby, interpret, jit, compile
- **Apple II emulation** - Full system with disk support
  - Video modes: text, lo-res, hi-res with NTSC color artifacts
  - Disk II controller with DOS 3.3 support
- **Export directory consolidation** - All output in `/export/`
  - `/export/verilog/` - Generated Verilog files
  - `/export/gates/` - Gate-level JSON netlists

### Documentation

Detailed documentation is available in `/docs/` (13 files):

**Getting Started:**
- `overview.md` - HDL framework architecture and concepts
- `cli.md` - Complete CLI reference

**Design & Implementation:**
- `dsl.md` - Comprehensive synthesizable DSL guide (ports, behaviors, Vec, Bundle)
- `components.md` - Full component reference (50+ components)
- `8bit_cpu.md` - Sample 8-bit CPU architecture
- `mos6502_cpu.md` - MOS 6502 implementation (189+ tests)

**Simulation & Testing:**
- `simulation.md` - Simulation backends (Ruby, gate-level, native Rust)
- `debugging.md` - TUI debugger, breakpoints, watchpoints, VCD export

**Synthesis & Export:**
- `export.md` - Verilog export guide
- `gate_level_backend.md` - Gate-level synthesis (53 components, 7 primitives)
- `diagrams.md` - Diagram generation (SVG, PNG, DOT)

**Advanced:**
- `apple2.md` - Apple II emulation with disk support
- `chisel_feature_gap_analysis.md` - Chisel HDL feature comparison

## Development Guidelines

### Bug Fix Workflow (Test-First)

**When a bug is reported, follow this workflow:**

1. **Do NOT immediately try to fix the bug.** Resist the urge to dive into the code.

2. **Write a failing test first** that reproduces the bug:
   - Create a test in the appropriate spec file that demonstrates the incorrect behavior
   - The test should fail with the current code, proving the bug exists
   - Keep the test focused and minimal - isolate the bug

3. **Use subagents to fix the bug:**
   - Launch a subagent to investigate and implement the fix
   - The subagent should run the test to prove the fix works
   - The test must pass before the fix is considered complete

4. **Verify the fix:**
   - Run the full test suite to ensure no regressions
   - The originally failing test should now pass

**Example workflow:**
```
User: "The ALU gives wrong results for subtraction with carry"

1. Write test in spec/rhdl/hdl/arithmetic_spec.rb:
   it "handles subtraction with carry correctly" do
     # Test case that reproduces the bug
   end

2. Run test to confirm it fails (proves bug exists)

3. Launch subagent to fix the bug and verify with passing test

4. Run full suite: bundle exec rake pspec:hdl
```

**Why test-first?**
- Proves the bug actually exists and is reproducible
- Prevents regressions - the test remains in the suite forever
- Provides clear success criteria for the fix
- Documents the expected behavior

### Signal Tracing and Debugging

**IMPORTANT: Always use VCD tracing for complex signal analysis. Do NOT write custom signal polling loops or Ruby scripts that manually sample signals - always use the built-in VCD tracing instead.**

The IR compiler includes VCD (Value Change Dump) tracing support for debugging signal-level issues. VCD tracing captures every signal change with cycle-accurate timing, which is essential for debugging:
- Interrupt handling and timing
- PPU/LCD state transitions
- Memory access patterns
- CPU instruction execution flow
- Any multi-cycle operations

```ruby
sim = runner.sim

# Configure which signals to trace - use pattern matching
sim.trace_add_signals_matching('cpu__pc')       # CPU program counter
sim.trace_add_signals_matching('cpu__a_r')      # CPU A register
sim.trace_add_signals_matching('ppu__ly')       # PPU scanline counter
sim.trace_add_signals_matching('ppu__lcdc')     # LCD control register
sim.trace_add_signals_matching('cpu_addr')      # Memory address bus
sim.trace_add_signals_matching('cpu_wren')      # Memory write enable

# Start tracing (streaming mode for large traces)
sim.trace_start_streaming('/path/to/output.vcd')

# Run simulation with capture at appropriate granularity
# For scanline-level analysis:
154.times do |scanline|
  runner.run_steps(456)  # One scanline
  sim.trace_capture
end

# For cycle-accurate analysis:
# 1000.times do
#   runner.run_steps(1)
#   sim.trace_capture
# end

# Stop and flush
sim.trace_stop
```

View VCD files in GTKWave: `gtkwave /path/to/output.vcd`

**Why VCD tracing over manual polling:**
- Captures exact signal transition timing (not sampled/aliased)
- GTKWave provides professional waveform visualization
- Can trace many signals simultaneously without performance impact
- VCD files can be shared and analyzed offline
- Supports hierarchical signal browsing

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
- **IMPORTANT: Always add a test file when creating a new source file.** Every new class or module should have a corresponding spec file.

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
