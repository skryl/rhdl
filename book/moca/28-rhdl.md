# Chapter 29: RHDL

*A Ruby-based Hardware Description Language*

---

## Overview

RHDL (Ruby Hardware Description Language) is the HDL used throughout this book. Rather than learning a new syntax, RHDL leverages Ruby as a host language—making hardware description feel like writing software while maintaining the ability to synthesize to real hardware.

This chapter examines RHDL as a case study in HDL design, covering:
- DSL design principles
- Synthesis and simulation
- Comparison with Verilog, VHDL, and Chisel

---

## Why Ruby for HDL?

### The Problem with Traditional HDLs

Verilog and VHDL were designed in the 1980s:

```verilog
// Verilog: Verbose, error-prone
module counter(
    input clk,
    input reset,
    output reg [7:0] count
);
    always @(posedge clk or posedge reset) begin
        if (reset)
            count <= 8'b0;
        else
            count <= count + 1;
    end
endmodule
```

Problems:
- Separate language from testbenches
- Limited metaprogramming
- Verbose syntax
- Easy to write unsynthesizable code

### The Ruby Approach

```ruby
# RHDL: Concise, Ruby-powered
class Counter < SimComponent
  input :clk
  input :reset
  output :count, width: 8

  behavior do
    on posedge(:clk) do
      if reset == 1
        count <= 0
      else
        count <= count + 1
      end
    end
  end
end
```

Benefits:
- Full Ruby metaprogramming
- Same language for design and test
- Familiar syntax for programmers
- Strong typing through Ruby's object system

---

## DSL Design Principles

### Declarative Component Definition

Components declare their interface:

```ruby
class ALU < SimComponent
  # Parameters (generic/configurable values)
  parameter :width, default: 8

  # Ports (interface to outside world)
  input :a, width: :width
  input :b, width: :width
  input :op, width: 4
  output :result, width: :width
  output :zero

  # Internal signals
  wire :add_result, width: :width
  wire :sub_result, width: :width
end
```

### Behavioral vs Structural

**Behavioral:** Describe what happens

```ruby
behavior do
  result <= case op
    when 0 then a + b
    when 1 then a - b
    when 2 then a & b
    when 3 then a | b
    else 0
  end
end
```

**Structural:** Instantiate and connect components

```ruby
instance :adder, Adder, width: width
instance :subtractor, Subtractor, width: width

port :a => [:adder, :a]
port :b => [:adder, :b]
port [:adder, :sum] => :add_result
```

### Hierarchy Through Composition

```ruby
class CPU < SimComponent
  input :clk
  input :reset

  # Sub-components
  instance :alu, ALU, width: 32
  instance :regfile, RegisterFile, num_regs: 32, width: 32
  instance :decoder, InstructionDecoder
  instance :pc, ProgramCounter, width: 32

  # Connect them
  port :clk => [[:alu, :clk], [:regfile, :clk], [:pc, :clk]]
  port [:decoder, :alu_op] => [:alu, :op]
  # ...
end
```

---

## Synthesis Flow

### From Ruby to Gates

```
┌─────────────────┐
│   Ruby DSL      │  class Counter < SimComponent
│   (RHDL)        │    ...
└────────┬────────┘  end
         │
         ▼
┌─────────────────┐
│  Expression     │  Builds AST of operations
│  Tree           │  (add, mux, register, etc.)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Gate-Level IR  │  AND, OR, NOT, MUX, DFF
│                 │  (7 primitive types)
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌───────┐ ┌───────┐
│Verilog│ │ JSON  │  Export formats
│       │ │Netlist│
└───────┘ └───────┘
```

### Expression Trees

RHDL builds expression trees from Ruby code:

```ruby
# Ruby code
result <= (a + b) & mask

# Becomes expression tree:
#       AND
#      /   \
#    ADD   mask
#   /   \
#  a     b
```

### Gate-Level Primitives

RHDL synthesizes to 7 primitive gates:

| Primitive | Description |
|-----------|-------------|
| AND | Logical AND |
| OR | Logical OR |
| XOR | Exclusive OR |
| NOT | Inverter |
| MUX | 2-input multiplexer |
| DFF | D flip-flop |
| CONST | Constant value |

Complex operations decompose:

```
Addition (8-bit):
  → 8 full adders
  → Each full adder: AND, XOR, OR gates
  → Total: ~40 gates

Multiplexer (4-input):
  → Tree of 2-input MUXes
  → 3 MUX primitives
```

---

## Simulation

### Behavioral Simulation

Fast simulation using Ruby execution:

```ruby
sim = Simulator.new(counter)
sim.set_input(:clk, 0)
sim.set_input(:reset, 1)
sim.step!

100.times do
  sim.set_input(:clk, 1)
  sim.step!
  sim.set_input(:clk, 0)
  sim.step!
  puts "Count: #{sim.get_output(:count)}"
end
```

### Gate-Level Simulation

After synthesis, simulate at gate level:

```ruby
# Synthesize to gates
ir = RHDL::Export::Structure::Lower.from_components([counter])

# Simulate gate-level netlist
gate_sim = RHDL::Sim::GateSimulator.new(ir)
gate_sim.run(1000)  # 1000 cycles
```

### Waveform Capture

```ruby
sim.trace_add_signals_matching('count')
sim.trace_start_streaming('counter.vcd')

100.times do
  sim.step!
  sim.trace_capture
end

sim.trace_stop
# View with: gtkwave counter.vcd
```

---

## Comparison with Other HDLs

### Verilog

```verilog
// Verilog counter
module counter(
    input clk,
    input reset,
    output reg [7:0] count
);
    always @(posedge clk or posedge reset)
        if (reset) count <= 0;
        else count <= count + 1;
endmodule
```

- **Pros:** Industry standard, tool support
- **Cons:** Verbose, limited metaprogramming

### VHDL

```vhdl
-- VHDL counter
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity counter is
    port(
        clk : in std_logic;
        reset : in std_logic;
        count : out unsigned(7 downto 0)
    );
end counter;

architecture behavioral of counter is
    signal count_reg : unsigned(7 downto 0);
begin
    process(clk, reset)
    begin
        if reset = '1' then
            count_reg <= (others => '0');
        elsif rising_edge(clk) then
            count_reg <= count_reg + 1;
        end if;
    end process;
    count <= count_reg;
end behavioral;
```

- **Pros:** Strong typing, explicit
- **Cons:** Extremely verbose

### Chisel (Scala)

```scala
// Chisel counter
class Counter extends Module {
  val io = IO(new Bundle {
    val count = Output(UInt(8.W))
  })
  val reg = RegInit(0.U(8.W))
  reg := reg + 1.U
  io.count := reg
}
```

- **Pros:** Scala metaprogramming, FIRRTL backend
- **Cons:** Scala complexity, JVM dependency

### RHDL (Ruby)

```ruby
# RHDL counter
class Counter < SimComponent
  input :clk
  input :reset
  output :count, width: 8

  behavior do
    on posedge(:clk) do
      count <= reset == 1 ? 0 : count + 1
    end
  end
end
```

- **Pros:** Ruby elegance, rapid prototyping
- **Cons:** Not industry standard, Ruby performance

---

## Metaprogramming Examples

### Parameterized Generation

```ruby
# Generate N-bit ripple carry adder
class RippleAdder < SimComponent
  parameter :width, default: 8

  input :a, width: :width
  input :b, width: :width
  input :cin
  output :sum, width: :width
  output :cout

  # Generate full adders dynamically
  width.times do |i|
    instance :"fa#{i}", FullAdder
  end

  # Wire them up
  behavior do
    carry = [cin]
    width.times do |i|
      # Connect each full adder
    end
  end
end
```

### Loop Unrolling

```ruby
# Generate pipelined multiplier stages
class PipelinedMultiplier < SimComponent
  parameter :width, default: 8
  parameter :stages, default: 4

  stages.times do |stage|
    instance :"stage#{stage}", MultiplierStage,
             width: width,
             stage_num: stage
  end
end
```

### Conditional Generation

```ruby
class FlexibleALU < SimComponent
  parameter :has_multiplier, default: false
  parameter :has_divider, default: false

  if has_multiplier
    instance :mult, Multiplier, width: width
  end

  if has_divider
    instance :div, Divider, width: width
  end
end
```

---

## Testing

### Integrated Testbenches

```ruby
RSpec.describe Counter do
  let(:counter) { Counter.new('test_counter') }
  let(:sim) { Simulator.new(counter) }

  it 'counts up on clock edges' do
    sim.set_input(:reset, 1)
    sim.clock!
    expect(sim.get_output(:count)).to eq(0)

    sim.set_input(:reset, 0)
    10.times do |i|
      sim.clock!
      expect(sim.get_output(:count)).to eq(i + 1)
    end
  end
end
```

### Property-Based Testing

```ruby
it 'never exceeds 255' do
  1000.times do
    sim.clock!
    expect(sim.get_output(:count)).to be <= 255
  end
end
```

---

## Export Formats

### Verilog Export

```ruby
verilog = RHDL::Export::Verilog.export(counter)
File.write('counter.v', verilog)
```

Produces:
```verilog
module counter(
    input clk,
    input reset,
    output [7:0] count
);
    reg [7:0] count_reg;
    always @(posedge clk)
        if (reset) count_reg <= 8'd0;
        else count_reg <= count_reg + 8'd1;
    assign count = count_reg;
endmodule
```

### JSON Netlist

```ruby
ir = RHDL::Export::Structure::Lower.from_components([counter])
File.write('counter.json', ir.to_json)
```

---

## Summary

- **Ruby DSL:** Familiar syntax, powerful metaprogramming
- **Declarative:** Components, ports, behaviors
- **Synthesizable:** Expression trees to gate-level IR
- **Simulatable:** Behavioral and gate-level simulation
- **Exportable:** Verilog and JSON netlist output
- **Testable:** Integrated with RSpec
- **Trade-off:** Ease of use vs industry tool support

---

## Exercises

1. Write an RHDL module for a 4-bit shift register
2. Use metaprogramming to generate a parameterized FIFO
3. Compare gate counts: RHDL synthesis vs Yosys
4. Export a design to Verilog and verify in Icarus
5. Write property-based tests for an ALU

---

## Further Reading

- RHDL Documentation (this repository)
- Chisel/FIRRTL papers (comparison)
- "Hardware Construction Languages" survey
- Ruby metaprogramming guides

---

*Previous: [Chapter 28 - The Cray-1](28-cray1.md)*

*Appendix: [Appendix Z - RHDL Reference](appendix-z-rhdl.md)*
