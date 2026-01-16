# RHDL HDL Framework Overview

The RHDL HDL (Hardware Description Language) framework provides a Ruby-based simulation environment for digital circuits. It supports gate-level simulation up through complex components like CPUs.

## Architecture

```
lib/rhdl/hdl/
├── simulation.rb      # Core simulation engine
├── gates.rb           # Logic gate primitives
├── sequential.rb      # Flip-flops, registers, counters
├── arithmetic.rb      # Adders, ALU, comparators
├── combinational.rb   # Multiplexers, decoders, encoders
├── memory.rb          # RAM, ROM, register files
├── cpu.rb             # CPU module entry point
└── cpu/
    ├── datapath.rb    # CPU datapath implementation
    └── adapter.rb     # Behavioral CPU interface adapter
```

## Key Concepts

### Signal Values

Signals in the HDL can represent:
- **Binary values**: 0 or 1 for single-bit, multi-bit integers for buses
- **Unknown (X)**: Represents uninitialized or conflicting values
- **High-impedance (Z)**: Represents disconnected or tri-state outputs

### Wires

Wires connect components and propagate signal changes:

```ruby
wire = RHDL::HDL::Wire.new("my_signal", width: 8)
wire.set(0x42)
wire.get  # => 66
wire.bit(0)  # => 0 (LSB)
wire.bit(6)  # => 1
```

### Components

All components inherit from `SimComponent` and implement:
- `setup_ports` - Define inputs, outputs, and internal signals
- `propagate` - Compute outputs from inputs

```ruby
class MyGate < RHDL::HDL::SimComponent
  def setup_ports
    input :a
    input :b
    output :y
  end

  def propagate
    out_set(:y, in_val(:a) & in_val(:b))
  end
end
```

### Clocked Components

Sequential components use `SequentialComponent` base class:

```ruby
class MyRegister < RHDL::HDL::SequentialComponent
  def setup_ports
    input :d, width: 8
    input :clk
    input :en
    output :q, width: 8
  end

  def propagate
    if rising_edge? && in_val(:en) == 1
      @state = in_val(:d)
    end
    out_set(:q, @state)
  end
end
```

## Simulation Flow

1. **Create components** with their ports defined
2. **Connect components** by linking output wires to input wires
3. **Set inputs** on the top-level component
4. **Propagate** to compute outputs
5. **Clock** sequential components to update state

### Example: Simple Circuit

```ruby
# Create an AND gate
and_gate = RHDL::HDL::AndGate.new("my_and")

# Set inputs
and_gate.set_input(:a0, 1)
and_gate.set_input(:a1, 1)

# Propagate to compute output
and_gate.propagate

# Read output
and_gate.get_output(:y)  # => 1
```

### Example: Clocked Register

```ruby
reg = RHDL::HDL::Register.new("my_reg", width: 8)

# Set data and enable
reg.set_input(:d, 0x42)
reg.set_input(:en, 1)
reg.set_input(:rst, 0)

# Clock cycle (low then high)
reg.set_input(:clk, 0)
reg.propagate
reg.set_input(:clk, 1)
reg.propagate

# Read output
reg.get_output(:q)  # => 0x42
```

## Using the Simulator

The `Simulator` class manages multiple components:

```ruby
sim = RHDL::HDL::Simulator.new

# Add components
alu = RHDL::HDL::ALU.new("alu", width: 8)
reg = RHDL::HDL::Register.new("reg", width: 8)
sim.add_component(alu)
sim.add_component(reg)

# Add clock
clk = RHDL::HDL::Clock.new("clk")
sim.add_clock(clk)

# Run for N cycles
sim.run(100)
```

## Component Categories

| Category | Components |
|----------|------------|
| **Gates** | AND, OR, XOR, NOT, NAND, NOR, XNOR, Buffer, Tristate |
| **Bitwise** | BitwiseAnd, BitwiseOr, BitwiseXor, BitwiseNot |
| **Flip-flops** | DFlipFlop, TFlipFlop, JKFlipFlop, SRFlipFlop, SRLatch |
| **Registers** | Register, RegisterLoad, ShiftRegister, Counter, ProgramCounter, StackPointer |
| **Arithmetic** | HalfAdder, FullAdder, RippleCarryAdder, Subtractor, AddSub, Comparator, Multiplier, Divider, IncDec, ALU |
| **Combinational** | Mux2, Mux4, Mux8, MuxN, Demux2, Demux4, Decoder2to4, Decoder3to8, DecoderN, Encoder4to2, Encoder8to3, ZeroDetect, SignExtend, ZeroExtend, BarrelShifter, BitReverse, PopCount, LZCount |
| **Memory** | RAM, DualPortRAM, ROM, RegisterFile, Stack, FIFO |

## Next Steps

- See [Components Reference](components.md) for detailed component documentation
- See [CPU Datapath](cpu_datapath.md) for CPU implementation details
- See [Simulation Engine](simulation_engine.md) for advanced simulation topics
