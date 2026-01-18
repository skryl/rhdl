# RHDL (Ruby Hardware Description Language)

RHDL is a Domain Specific Language (DSL) for designing hardware using Ruby's flexible syntax and exporting to synthesizable Verilog. It provides Ruby developers with a comfortable environment to create hardware designs leveraging Ruby's metaprogramming capabilities.

## Features

- **Component DSLs**: Ruby-based DSLs for combinational, sequential, memory, and state machine components
- **Verilog Export**: Generate synthesizable Verilog from Ruby definitions
- **HDL Simulation**: Gate-level simulation with signal propagation
- **Component Library**: Gates, flip-flops, registers, ALU, memory, and more
- **Gate-Level Synthesis**: Lower components to primitive gate netlists (AND, OR, XOR, NOT, MUX, DFF)
- **Diagram Generation**: Multi-level circuit diagrams with SVG, PNG, and DOT output

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
class SimpleALU < RHDL::HDL::SimComponent
  port_input :a, width: 8
  port_input :b, width: 8
  port_input :op, width: 2
  port_output :result, width: 8

  behavior do
    result <= case_of(op,
      0 => a + b,
      1 => a - b,
      2 => a & b,
      3 => a | b
    )
  end
end
```

#### Sequential Logic

```ruby
class Counter < RHDL::HDL::SequentialComponent
  port_input :clk
  port_input :rst
  port_input :en
  port_output :count, width: 8

  sequential clock: :clk, reset: :rst, reset_values: { count: 0 } do
    count <= mux(en, count + 1, count)
  end
end
```

#### Memory Components

```ruby
class RAM256x8 < RHDL::HDL::SimComponent
  include RHDL::DSL::MemoryDSL

  port_input :clk
  port_input :we
  port_input :addr, width: 8
  port_input :din, width: 8
  port_output :dout, width: 8

  memory :mem, depth: 256, width: 8
  sync_write :mem, clock: :clk, enable: :we, addr: :addr, data: :din
  async_read :dout, from: :mem, addr: :addr
end
```

#### State Machines

```ruby
class TrafficLight < RHDL::HDL::SequentialComponent
  include RHDL::DSL::StateMachineDSL

  port_input :clk
  port_input :rst
  port_input :sensor
  port_output :red, :yellow, :green

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

### Exporting to Verilog

```ruby
require 'rhdl'

# Export a component to Verilog
component = MyComponent.new
verilog_code = RHDL::Export::Verilog.export(component)

# Or use rake tasks
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

## MOS 6502 CPU Example

The `examples/mos6502/` directory contains a complete behavior simulation of the MOS 6502 microprocessor, demonstrating RHDL's capabilities for complex hardware designs.

### Features

- **Full 6502 implementation**: All official instructions and addressing modes
- **Clock-cycle accurate**: Proper timing for all operations
- **Two-pass assembler**: Write programs in 6502 assembly
- **BCD arithmetic**: Full decimal mode support

### Quick Example

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

### Apple II Bus Emulation

The 6502 implementation includes Apple II-style I/O bus support for running unmodified Apple II binaries:

- **Keyboard**: Memory-mapped at $C000 with strobe at $C010
- **Speaker**: Click toggle at $C030
- **Video switches**: Text/graphics modes, page selection, hi-res mode
- **RAM/ROM regions**: Full 64KB address space

```ruby
require_relative 'examples/mos6502/apple2_bus'

bus = MOS6502::Apple2Bus.new
cpu = MOS6502::CPU.new(bus: bus)

# Simulate keyboard input
bus.key_press('A')

# Run program
cpu.run
```

See [Apple II I/O](docs/apple2_io.md) for details.

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
│   └── mos6502/        # MOS 6502 CPU with Apple II support
├── export/             # Generated output files
│   ├── verilog/        # Generated Verilog
│   └── gates/          # Gate-level JSON netlists
└── docs/               # Documentation
```

## Documentation

Detailed documentation is available in the `docs/` directory:

| Document | Description |
|----------|-------------|
| [HDL Overview](docs/hdl_overview.md) | Introduction to the HDL framework |
| [Synthesizable DSL Guide](docs/synthesizable_dsl.md) | DSL reference for synthesizable components |
| [Components Reference](docs/components.md) | Complete reference for all HDL components |
| [Export Guide](docs/export.md) | Verilog and gate-level export |
| [Sample CPU](docs/sample_cpu.md) | 8-bit sample CPU reference |
| [MOS 6502](docs/mos6502.md) | MOS 6502 implementation |
| [Debugging Guide](docs/debugging.md) | Signal probing, breakpoints, and TUI |
| [Diagram Generation](docs/diagrams.md) | Multi-level circuit diagrams |
| [Simulation Engine](docs/simulation_engine.md) | Core simulation infrastructure |
| [Apple II I/O](docs/apple2_io.md) | Apple II bus emulation |

## Rake Tasks

```bash
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
