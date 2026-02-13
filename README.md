```
    ____  __  ______  __
   / __ \/ / / / __ \/ /
  / /_/ / /_/ / / / / /
 / _, _/ __  / /_/ / /___
/_/ |_/_/ /_/_____/_____/

  Ruby Hardware Description Language
```

# RHDL

RHDL is a Domain Specific Language (DSL) for designing hardware using Ruby's flexible syntax and exporting to synthesizable Verilog. It provides Ruby developers with a comfortable environment to create hardware designs leveraging Ruby's metaprogramming capabilities.

Demo: [Web Simulator](https://skryl.github.io/rhdl)

## Features

- **Component DSLs**: Ruby-based DSLs for combinational, sequential, memory, and state machine components
- **Verilog Export**: Generate synthesizable Verilog from Ruby definitions
- **HDL Simulation**: Gate-level simulation with signal propagation
- **Component Library**: Gates, flip-flops, registers, ALU, memory, and more
- **Gate-Level Synthesis**: Lower components to primitive gate netlists (AND, OR, XOR, NOT, MUX, DFF)
- **Diagram Generation**: Multi-level circuit diagrams with SVG, PNG, and DOT output

## Documentation

| Document | Description |
|----------|-------------|
| [Overview](docs/overview.md) | Introduction to the HDL framework |
| [CLI Reference](docs/cli.md) | Command line interface reference |
| [DSL Guide](docs/dsl.md) | DSL reference for synthesizable components |
| [Components](docs/components.md) | Complete reference for all HDL components |
| [Simulation](docs/simulation.md) | Core simulation engine infrastructure |
| [Export](docs/export.md) | Verilog and gate-level export |
| [Gate-Level Backend](docs/gate_level_backend.md) | Gate-level synthesis and simulation |
| [Diagrams](docs/diagrams.md) | Multi-level circuit diagrams |
| [Debugging](docs/debugging.md) | Signal probing, breakpoints, and TUI |
| [8-bit CPU](docs/8bit_cpu.md) | Sample 8-bit CPU reference |
| [MOS 6502](docs/mos6502_cpu.md) | MOS 6502 CPU implementation |
| [Apple II](docs/apple2.md) | Apple II emulation |
| [Game Boy](docs/gameboy.md) | Game Boy (DMG/GBC/SGB) emulation |
| [RISC-V](docs/riscv.md) | RISC-V RV32I CPU implementation |
| [Web Simulator](docs/web_simulator.md) | Browser simulator (WASM + VCD + Apple II runner) |
| [Web Architecture](docs/web_architecture.md) | Web app runtime architecture and module layout |

## Web Simulator

RHDL includes a browser-based simulator with WASM backends, live VCD tracing, Apple II runner tooling, memory dump workflows, and component/source exploration.

- Demo: [https://skryl.github.com/rhdl](https://skryl.github.com/rhdl)
- Docs: [Web Simulator Guide](docs/web_simulator.md)
- Architecture: [Web App Architecture](docs/web_architecture.md)

![Web simulator](docs/screenshots/2026-02-09-14.52.47.gif)

## Quick Start

### Installation

```bash
gem install bundler -v '~> 2.5'
bundle install
```

### Defining Components with the DSL

RHDL provides several DSL constructs for synthesizable hardware:

#### Combinational Logic

```ruby
class SimpleALU < RHDL::Sim::Component
  input :a, width: 8
  input :b, width: 8
  input :op, width: 2
  output :result, width: 8

  behavior do
    result <= case_select(op, {
      0 => a + b,
      1 => a - b,
      2 => a & b,
      3 => a | b
    }, default: 0)
  end
end
```

#### Sequential Logic

```ruby
class Counter < RHDL::Sim::SequentialComponent
  input :clk
  input :rst
  input :en
  output :count, width: 8

  sequential clock: :clk, reset: :rst, reset_values: { count: 0 } do
    count <= mux(en, count + 1, count)
  end
end
```

#### Memory Components

```ruby
class RAM256x8 < RHDL::Sim::Component
  include RHDL::DSL::Memory

  input :clk
  input :we
  input :addr, width: 8
  input :din, width: 8
  output :dout, width: 8

  memory :mem, depth: 256, width: 8
  sync_write :mem, clock: :clk, enable: :we, addr: :addr, data: :din
  async_read :dout, from: :mem, addr: :addr
end
```

#### State Machines

```ruby
class TrafficLight < RHDL::Sim::SequentialComponent
  include RHDL::DSL::StateMachine

  input :clk
  input :rst
  input :sensor
  output :red
  output :yellow
  output :green

  state_machine clock: :clk, reset: :rst do
    state :RED, value: 0 do
      output red: 1, yellow: 0, green: 0
      transition to: :GREEN, when_cond: :sensor
    end

    state :YELLOW, value: 1 do
      output red: 0, yellow: 1, green: 0
      transition to: :RED, after: 3
    end

    state :GREEN, value: 2 do
      output red: 0, yellow: 0, green: 1
      transition to: :YELLOW, when_cond: proc { in_val(:sensor) == 0 }
    end

    initial_state :RED
  end
end
```

#### Hierarchical Components

Build complex components from sub-components using `instance`, `wire`, and `port`:

```ruby
class MyDatapath < RHDL::Sim::Component
  input :clk
  input :rst
  input :a, width: 8
  input :b, width: 8
  output :result, width: 8

  # Internal wire
  wire :alu_out, width: 8

  # Sub-component instances
  instance :alu, ALU, width: 8
  instance :reg, Register, width: 8

  # Port connections
  port :a => [:alu, :a]
  port :b => [:alu, :b]
  port [:alu, :result] => :alu_out
  port :alu_out => [:reg, :d]
  port :clk => [:reg, :clk]
  port :rst => [:reg, :rst]
  port [:reg, :q] => :result
end
```

### Exporting to Verilog

```ruby
require 'rhdl'

# Export a component to Verilog
component = MyComponent.new
verilog_code = RHDL::Export.verilog(component)

# Or use the class method
verilog_code = MyComponent.to_verilog

# Batch export with rake
# rake hdl:export       - Export all DSL components
# rake hdl:verilog      - Export Verilog files
```

**Generated Verilog example:**

```verilog
module simple_alu(
  input [7:0] a,
  input [7:0] b,
  input [1:0] op,
  output [7:0] result
);
  assign result = (op == 2'd0) ? (a + b) :
                  (op == 2'd1) ? (a - b) :
                  (op == 2'd2) ? (a & b) :
                  (a | b);
endmodule
```

### Simulation

```ruby
require 'rhdl'

# Create an ALU
alu = RHDL::HDL::ALU.new("my_alu", width: 8)
alu.set_input(:a, 10)
alu.set_input(:b, 5)
alu.set_input(:op, RHDL::HDL::ALU::OP_ADD)
alu.propagate

puts alu.get_output(:result)  # => 15
```

## Examples

RHDL includes four comprehensive example implementations demonstrating the framework's capabilities for building complex hardware systems.

| Example | Type | CPU | Description |
|---------|------|-----|-------------|
| [MOS 6502](docs/mos6502_cpu.md) | Processor | 8-bit | Classic 1970s microprocessor |
| [Apple II](docs/apple2.md) | Computer | 6502 | Complete 1977 personal computer |
| [Game Boy](docs/gameboy.md) | Console | SM83 | Nintendo handheld (DMG/GBC/SGB) |
| [RISC-V](docs/riscv.md) | Processor | 32-bit | Modern RISC instruction set |

### MOS 6502 CPU

Complete behavior simulation of the MOS 6502 with all 56 instructions, 13 addressing modes, and BCD arithmetic.

```
+-----------------------------------------------------------+
|                      MOS6502::CPU                          |
+-----------------------------------------------------------+
|  +-----------------------------------------------------+  |
|  |                     Datapath                         |  |
|  |  +-------+  +-------+  +-------+  +-------------+   |  |
|  |  | A(8b) |  | X(8b) |  | Y(8b) |  | Status(8b)  |   |  |
|  |  +-------+  +-------+  +-------+  | N V - B D I Z C|  |
|  |  +--------+  +-------+           +-------------+   |  |
|  |  | PC(16b)|  | SP(8b)|                             |  |
|  |  +--------+  +-------+                             |  |
|  |  +-------------------------------------------------+  |
|  |  |              ALU (14 operations)                |  |
|  |  +-------------------------------------------------+  |
|  +-----------------------------------------------------+  |
|  +-----------------------------------------------------+  |
|  |         Control Unit (26-state FSM)                 |  |
|  +-----------------------------------------------------+  |
|  +-----------------------------------------------------+  |
|  |      Instruction Decoder (151 opcodes)              |  |
|  +-----------------------------------------------------+  |
+-----------------------------------------------------------+
```

**CLI Options:**
```bash
rhdl examples mos6502 --demo           # Run demo program
rhdl examples mos6502 --karateka       # Play Karateka game
```

**Quick Example:**
```ruby
require_relative 'examples/mos6502/cpu'

cpu = MOS6502::CPU.new
cpu.assemble_and_load(<<~ASM, 0x8000)
  LDA #$42      ; Load 0x42 into accumulator
  STA $00       ; Store to zero page
  BRK           ; Break
ASM
cpu.reset
cpu.run
puts cpu.status_string  # A:42 X:00 Y:00 SP:FD PC:8006
```

### Apple II

Complete Apple II emulation with video modes, keyboard, speaker, and Disk II controller.

```
+-----------------------------------------------------------------------+
|                           Apple II System                              |
+-----------------------------------------------------------------------+
|  +-----------+     +----------+     +--------------------------+      |
|  |  MOS 6502 |     |  Timing  |     |     Video Generator      |      |
|  |    CPU    |<--->|Generator |---->|  - Text (40x24)          |      |
|  |   1 MHz   |     |  14 MHz  |     |  - Lo-res (40x48)        |      |
|  +-----------+     +----------+     |  - Hi-res (280x192)      |      |
|        |                            +--------------------------+      |
|  +-----+--------------------------------------------------+           |
|  |                   Address/Data Bus                      |           |
|  +--+--------+--------+--------+--------+---------+-------+           |
|     |        |        |        |        |         |                   |
|  +--+--+  +--+--+  +--+--+  +--+--+  +--+---+  +--+--+                |
|  | 48KB|  | 12KB|  | I/O |  |Disk |  |Key- |  |Speak|                |
|  | RAM |  | ROM |  | Page|  | II  |  |board|  | er  |                |
|  +-----+  +-----+  +-----+  +-----+  +-----+  +-----+                |
+-----------------------------------------------------------------------+
```

**CLI Options:**
```bash
rhdl examples apple2 --appleiigo              # Run with AppleIIGo ROM
rhdl examples apple2 --karateka --hires       # Play Karateka in hi-res
rhdl examples apple2 --appleiigo --disk g.dsk # Load disk image
rhdl examples apple2 --demo                   # Run demo program
```

### Game Boy

Nintendo Game Boy emulation based on MiSTer reference, supporting DMG, GBC, and SGB modes.

```
+-----------------------------------------------------------------------+
|                          Game Boy System                               |
+-----------------------------------------------------------------------+
|  +---------+    +-------+    +---------------------------+            |
|  |  SM83   |    | Timer |    |      PPU (Video)          |            |
|  |  CPU    |<-->|Counter|--->|  - Background layer       |            |
|  | 4.19MHz |    +-------+    |  - Window layer           |            |
|  +----+----+                 |  - 40 sprites (8x8/8x16)  |            |
|       |                      |  - 160x144 LCD            |            |
|  +----+--------------------------------------------------+            |
|  |                  Address/Data Bus                      |            |
|  +--+------+------+------+------+------+------+----------+            |
|     |      |      |      |      |      |      |                       |
|  +--+-+  +-+-+  +-+-+  +-+-+  +-+-+  +-+-+  +-+----+                  |
|  |ROM |  |VRAM|  |WRAM|  |OAM |  |HRAM|  |I/O|  | APU  |              |
|  |0-8M|  |8KB |  |8KB |  |160B|  |127B|  |   |  | 4ch  |              |
|  +----+  +---+  +----+  +----+  +----+  +---+  +------+              |
+-----------------------------------------------------------------------+
```

**CLI Options:**
```bash
rhdl examples gameboy --rom cpu_instrs.gb     # Run test ROM
rhdl examples gameboy --demo                  # Run demo display
rhdl examples gameboy --rom game.gb --gbc     # Force GBC mode
rhdl examples gameboy --rom game.gb --audio   # Enable audio
```

### RISC-V RV32I

Modern 32-bit RISC-V processor with single-cycle and 5-stage pipelined implementations.

**Single-Cycle Datapath:**
```
+-----------------------------------------------------------------------+
|                    RV32I Single-Cycle Datapath                         |
+-----------------------------------------------------------------------+
|  +------+    +------+    +-------+    +-------+                       |
|  |  PC  |--->| Inst |--->|Decoder|--->|Control|                       |
|  | Reg  |    | Mem  |    |       |    |Signals|                       |
|  +--+---+    +------+    +-------+    +---+---+                       |
|     |                                     |                            |
|  +--+-------------------------------------+--+                         |
|  |              Datapath Muxes               |                         |
|  +--+--------+-------------------+-----------+                         |
|     |        |                   |                                     |
|  +--+--+  +--+--+            +---+--+    +------+                      |
|  | PC  |  | Reg |  rs1/rs2   | ALU  |--->| Data |                      |
|  |+4/Br|  |File |----------->|      |    | Mem  |                      |
|  +-----+  |32x32|            +------+    +------+                      |
|           +--+--+                |           |                         |
|              ^                   v           v                         |
|              +--------[ Write Back ]<--------+                         |
+-----------------------------------------------------------------------+
```

**5-Stage Pipeline:**
```
+------+    +------+    +------+    +------+    +------+
|  IF  |--->|  ID  |--->|  EX  |--->| MEM  |--->|  WB  |
+------+    +------+    +------+    +------+    +------+
 Fetch      Decode      Execute     Memory     Write
 Inst       Regs/Imm    ALU/Br      Access     Back
```

**Usage:**
```ruby
require_relative 'examples/riscv/hdl/ir_harness'

harness = RHDL::Examples::RISCV::IRHarness.new(backend: :jit, allow_fallback: false)
harness.load_program([
  0x00500093,  # addi x1, x0, 5
  0x00A00113,  # addi x2, x0, 10
  0x002081B3,  # add x3, x1, x2
])
harness.reset!
harness.run_cycles(10)
puts "x3 = #{harness.read_reg(3)}"  # => 15
```

See each example's documentation for complete details on architecture, instruction sets, and CLI options.

## Project Structure

```
rhdl/
├── lib/rhdl/           # Core library
│   ├── dsl.rb          # HDL DSL for component definitions
│   ├── export/         # Verilog export backends
│   ├── simulation/     # Simulation engine
│   ├── hdl/            # HDL component library
│   │   ├── gates.rb, sequential.rb, arithmetic.rb, ...
│   │   └── cpu/        # HDL CPU implementation
│   ├── debug/          # Signal probing & debugging
│   ├── tui/            # Terminal GUI
│   └── diagram/        # Diagram rendering
├── examples/           # Example implementations
│   ├── mos6502/        # MOS 6502 CPU (8-bit, 189+ tests)
│   ├── apple2/         # Apple II computer emulation
│   ├── gameboy/        # Game Boy (DMG/GBC/SGB)
│   └── riscv/          # RISC-V RV32I CPU (single + pipelined)
├── export/             # Generated output files
│   ├── verilog/        # Generated Verilog
│   └── gates/          # Gate-level JSON netlists
└── docs/               # Documentation
```

## Command Line Interface

RHDL provides a comprehensive CLI for common operations. See [CLI Reference](docs/cli.md) for complete documentation.

```bash
# Interactive TUI debugger
rhdl tui sequential/counter              # Debug a counter component
rhdl tui RHDL::HDL::ALU --signals inputs # Debug ALU, show only inputs
rhdl tui --list                          # List available components

# Diagram generation
rhdl diagram --all                       # Generate all diagrams
rhdl diagram RHDL::HDL::ALU --format svg # Single component diagram

# Verilog export
rhdl export --all                        # Export all components
rhdl export --lang verilog --out ./out RHDL::HDL::Counter

# Gate-level synthesis
rhdl gates --export                      # Export to JSON netlists
rhdl gates --stats                       # Show synthesis statistics

# Apple II emulator
rhdl apple2 --demo                       # Run demo mode
rhdl apple2 --build                      # Build mini monitor ROM
```

## Execution Backends

RHDL provides multiple simulation backends with different performance/flexibility tradeoffs:

### Behavioral Simulation (Ruby)

Pure Ruby execution at the behavior block level. Best for development and debugging.

```ruby
sim = RHDL::Sim::Simulator.new
sim.add_component(alu)
sim.add_clock(clk)
sim.run(100)  # 100 clock cycles
```

### Gate-Level (Netlist) Simulation

Simulates primitive gate netlists (AND, OR, XOR, NOT, MUX, DFF). Four backend options:

| Backend | Speed | Startup | Use Case |
|---------|-------|---------|----------|
| Ruby SimCPU | 22K iter/s | Immediate | Development, small circuits |
| Rust Interpreter | 427K iter/s (20x) | Immediate | Functional verification |
| Rust JIT (Cranelift) | 50-100M gates/s | 0.1-0.5s | Fast interactive simulation |
| Rust Compiler (SIMD) | 100M+ gates/s | 1-2s | Maximum throughput, batch testing |

The compiler supports AVX2/AVX512 for 256-512 parallel test vectors.

```ruby
ir = RHDL::Codegen::Netlist::Lower.from_components([alu])
sim = RHDL::Codegen::Netlist::NetlistSimulator.new(ir, backend: :interpreter, lanes: 64)
sim.poke('a', 0xFF)
sim.evaluate
result = sim.peek('y')
```

### IR-Level Simulation (Word-Level)

Word-level bytecode simulation for complex designs like CPUs:

| Backend | Speed | Startup | Use Case |
|---------|-------|---------|----------|
| Interpreter | 60K cycles/s | Immediate | Interactive CPU debugging |
| JIT (Cranelift) | 600K cycles/s (10x) | 0.1-0.5s | Moderate simulations |
| AOT Compiler | 2.3M cycles/s (38x) | 0.5-2s | Long simulations, games |

```ruby
sim = RHDL::Codegen::IR::IrSimulator.new(ir_json, backend: :jit)
sim.compile
sim.run_ticks(1_000_000)
```

### Verilog Export & External Simulation

Export components to Verilog for synthesis or simulation with industry-standard tools:

```ruby
# Export component to Verilog
verilog_code = RHDL::Codegen.verilog(component)
File.write('alu.v', verilog_code)
```

**External simulators:**

| Tool | Speed | Use Case |
|------|-------|----------|
| iverilog | ~100K cycles/s | Functional verification, golden reference |
| Verilator | ~5.7M cycles/s | High-performance simulation, benchmarking |

```bash
# Compile and run with iverilog
iverilog -o sim alu.v testbench.v && vvp sim

# Compile with Verilator for maximum performance
verilator --cc alu.v --exe testbench.cpp
```

When iverilog is installed, RHDL automatically runs gate-level verification tests comparing synthesized Verilog against behavioral simulation.

### Building Native Extensions

```bash
rake native:build    # Build all Rust extensions
rake native:check    # Check availability
```

All backends include automatic fallback to Ruby when native extensions aren't available.

See [Simulation](docs/simulation.md) and [Gate-Level Backend](docs/gate_level_backend.md) for complete details.

## Performance Benchmarks

RHDL includes benchmarking tasks to measure simulation performance across backends:

```bash
rake bench:mos6502[cycles]    # Benchmark MOS 6502 CPU
rake bench:apple2[cycles]     # Benchmark Apple II full system
rake bench:gameboy[frames]    # Benchmark GameBoy with Prince of Persia
rake bench:gates              # Benchmark gate-level simulation
```

**Sample Results (1M cycles):**

| System | JIT | Compiler | Verilator | Compiler Speedup |
|--------|-----|----------|-----------|------------------|
| MOS 6502 | 0.23M/s | 1.58M/s | ~5.6M/s | 6.8x vs JIT |
| Apple II | 0.06M/s | 0.28M/s | ~5.6M/s | 4.8x vs JIT |
| GameBoy | - | 1.27 MHz | ~5.8 MHz | 30% real-time |

**Backend Selection Guide:**
- **< 100K cycles**: Use JIT (fast startup)
- **100K - 1M cycles**: Use JIT or Compiler
- **> 1M cycles**: Use Compiler or Verilator
- **Maximum speed**: Use Verilator (requires installation)

See [Performance Guide](docs/performance.md) for detailed benchmarks and optimization tips.

## Rake Tasks

```bash
# Testing
rake spec                # Run all tests
rake pspec               # Run tests in parallel

# Verilog export
rake hdl:export          # Export DSL components to Verilog
rake hdl:verilog         # Export Verilog files
rake hdl:clean           # Clean generated HDL files

# Gate-level synthesis
rake gates:export        # Export all 53 components to JSON netlists
rake gates:stats         # Show gate-level synthesis statistics
rake gates:clean         # Clean gate-level output

# Diagrams
rake diagrams:generate   # Generate component diagrams (SVG, DOT, TXT)
rake diagrams:clean      # Clean generated diagrams

# All outputs
rake generate_all        # Generate all outputs
rake clean_all           # Clean all generated files
```

## Component Library

| Category | Components |
|----------|------------|
| **Gates** | AND, OR, XOR, NOT, NAND, NOR, XNOR, Buffer, Tristate |
| **Flip-flops** | DFlipFlop, TFlipFlop, JKFlipFlop, SRFlipFlop, SRLatch |
| **Registers** | Register, ShiftRegister, Counter, ProgramCounter, StackPointer |
| **Arithmetic** | HalfAdder, FullAdder, RippleCarryAdder, Subtractor, Multiplier, Divider, ALU |
| **Combinational** | Mux2/4/8/N, Demux, Decoder, Encoder, BarrelShifter, ZeroDetect |
| **Memory** | RAM, DualPortRAM, ROM, RegisterFile, Stack, FIFO |

## License

MIT License
