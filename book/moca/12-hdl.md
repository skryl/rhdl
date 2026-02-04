# Chapter 11: Hardware Description Languages

## Overview

How do you describe a circuit that will become silicon? You can't just draw it—modern chips have billions of transistors. You need a **language**.

Hardware Description Languages (HDLs) bridge the gap between design intent and physical implementation.

## The Big Three (Plus One)

### Verilog (1984)

The most widely used HDL, especially in the US and Asia:

```verilog
module counter (
    input wire clk,
    input wire reset,
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

**Strengths:**
- C-like syntax (familiar to software engineers)
- Huge ecosystem and tool support
- Industry standard for ASIC design

**Weaknesses:**
- Many subtle gotchas (blocking vs non-blocking)
- Simulation vs synthesis mismatch
- No strong type system

### VHDL (1987)

Dominant in Europe and aerospace/defense:

```vhdl
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity counter is
    port (
        clk   : in  std_logic;
        reset : in  std_logic;
        count : out std_logic_vector(7 downto 0)
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
    count <= std_logic_vector(count_reg);
end behavioral;
```

**Strengths:**
- Strong typing catches errors early
- Very explicit—no hidden behavior
- Required for aerospace/defense contracts

**Weaknesses:**
- Extremely verbose
- Ada-like syntax unfamiliar to most
- Steep learning curve

### SystemVerilog (2005)

Modern Verilog with verification features:

```systemverilog
module counter (
    input  logic       clk,
    input  logic       reset,
    output logic [7:0] count
);
    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            count <= '0;
        else
            count <= count + 1;
    end
endmodule
```

**Additions over Verilog:**
- `logic` type (replaces `wire`/`reg` confusion)
- `always_ff`, `always_comb`, `always_latch` (intent-clear)
- Interfaces, packages, classes
- Built-in verification constructs

### Chisel (2012)

Scala-embedded DSL from UC Berkeley:

```scala
class Counter extends Module {
  val io = IO(new Bundle {
    val count = Output(UInt(8.W))
  })

  val reg = RegInit(0.U(8.W))
  reg := reg + 1.U
  io.count := reg
}
```

**Strengths:**
- Full power of Scala for metaprogramming
- Generates Verilog (tool compatibility)
- Modern software engineering practices
- Used in RISC-V development

**Weaknesses:**
- JVM dependency
- Scala learning curve
- Generated Verilog can be hard to read

## RHDL: Ruby Hardware Description Language

RHDL takes a similar approach to Chisel but in Ruby:

```ruby
class Counter < SimComponent
  input :clk
  input :reset
  output :count, width: 8

  register :count_reg, width: 8

  behavior do
    on_rising_edge(clk) do
      if reset
        count_reg <= 0
      else
        count_reg <= count_reg + 1
      end
    end

    count <= count_reg
  end
end
```

**Design philosophy:**
- Ruby's expressiveness for hardware generation
- Simulation-first development
- Export to Verilog for synthesis
- Educational focus

## Comparison

| Feature | Verilog | VHDL | Chisel | RHDL |
|---------|---------|------|--------|------|
| Typing | Weak | Strong | Strong | Dynamic |
| Verbosity | Medium | High | Low | Low |
| Metaprogramming | Limited | Limited | Full | Full |
| Learning curve | Medium | High | High | Low |
| Industry adoption | High | High | Growing | Educational |
| Simulation | External | External | External | Built-in |

## The Two Domains

HDLs describe two fundamentally different things:

### Behavior (What)

```verilog
// What should happen
always @(posedge clk)
    if (a > b)
        result <= a - b;
    else
        result <= b - a;
```

### Structure (How)

```verilog
// How it's built
comparator comp(.a(a), .b(b), .gt(a_gt_b));
subtractor sub1(.a(a), .b(b), .result(diff_ab));
subtractor sub2(.a(b), .b(a), .result(diff_ba));
mux2 mux(.sel(a_gt_b), .a(diff_ba), .b(diff_ab), .y(result));
```

Good HDL code often mixes both—behavior for clarity, structure for control.

## Synthesis vs Simulation

A critical distinction:

```
┌─────────────────────────────────────────────────────────────┐
│              SIMULATION vs SYNTHESIS                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Simulation:                                                │
│   - Runs your HDL as a program                              │
│   - All language features available                          │
│   - Can use $display, delays, file I/O                      │
│   - Tests your design                                        │
│                                                              │
│   Synthesis:                                                 │
│   - Converts HDL to gates/transistors                        │
│   - Only synthesizable subset allowed                        │
│   - No delays, no $display, no initial blocks               │
│   - Creates your chip                                        │
│                                                              │
│   Write code that works in BOTH domains!                     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Common Pitfalls

### 1. Simulation/Synthesis Mismatch

```verilog
// Works in simulation, fails in synthesis
initial begin
    count = 0;  // No initial blocks in synthesis!
end
```

### 2. Incomplete Sensitivity Lists

```verilog
// Verilog 1995 bug:
always @(a)        // Forgot b!
    y = a & b;     // Simulates wrong, synthesizes right

// Fix with @(*) or always_comb
```

### 3. Latch Inference

```verilog
// Oops, created a latch
always @(*) begin
    if (sel)
        y = a;
    // Missing else! What is y when sel=0?
end
```

## Why Learn Multiple HDLs?

1. **Job market** - Verilog and VHDL dominate industry
2. **Tool compatibility** - Different tools prefer different languages
3. **Reading others' code** - Open source uses everything
4. **Choosing the right tool** - Different projects have different needs

## Key Takeaways

1. **HDLs describe hardware, not software** - Different mental model
2. **Two domains** - Simulation and synthesis have different rules
3. **Know the classics** - Verilog and VHDL aren't going away
4. **Modern alternatives exist** - Chisel, RHDL, Amaranth, SpinalHDL
5. **Metaprogramming is powerful** - Generate hardware with code

> See [Appendix K](appendix-k-hdl.md) for side-by-side comparisons of the same circuits in Verilog, VHDL, Chisel, and RHDL.
