# Appendix E: Hardware Description Languages

## Overview

Understanding HDLs: Verilog, VHDL, SystemVerilog, and how RHDL fits in.

## Key Concepts

### What is an HDL?

A Hardware Description Language:
- Describes circuit structure and behavior
- Can be simulated (verify design)
- Can be synthesized (produce real hardware)
- Not a programming language (but looks like one)

### Why Not Just Use Schematics?

- Modern chips have billions of transistors
- Text is version-controllable
- Abstraction enables complexity
- Reusable libraries

### Verilog Basics

The most common HDL in industry:

```verilog
module counter (
    input wire clk,
    input wire reset,
    output reg [7:0] count
);

always @(posedge clk) begin
    if (reset)
        count <= 8'b0;
    else
        count <= count + 1;
end

endmodule
```

**Key Concepts:**
- `module`: Like a class
- `wire`: Continuous connection
- `reg`: Value holder (not necessarily a register!)
- `always @(posedge clk)`: Triggered on clock edge
- `<=`: Non-blocking assignment (for sequential)
- `=`: Blocking assignment (for combinational)

### VHDL Basics

More verbose, common in aerospace/defense:

```vhdl
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity counter is
    Port ( clk : in STD_LOGIC;
           reset : in STD_LOGIC;
           count : out STD_LOGIC_VECTOR(7 downto 0));
end counter;

architecture Behavioral of counter is
    signal count_reg : unsigned(7 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                count_reg <= (others => '0');
            else
                count_reg <= count_reg + 1;
            end if;
        end if;
    end process;

    count <= std_logic_vector(count_reg);
end Behavioral;
```

### SystemVerilog

Modern evolution of Verilog:
- Better type system
- Classes and OOP for testbenches
- Assertions and coverage
- Industry standard for verification

### RHDL: Ruby as an HDL

Why Ruby for hardware design?

**Advantages:**
- Familiar to software engineers
- True metaprogramming
- Interactive exploration (REPL)
- No special tools needed to start
- Export to real Verilog

**The RHDL Approach:**

```ruby
class Counter < SimComponent
  input :clk
  input :reset
  output :count, width: 8

  behavior do
    on rising_edge(clk) do
      if reset
        count <= 0
      else
        count <= count + 1
      end
    end
  end
end
```

### Synthesis vs Simulation

**Simulation:**
- Test your design works correctly
- Can use any language constructs
- No physical constraints

**Synthesis:**
- Convert HDL to actual gates
- Restricted subset of language
- Tool maps to target technology (FPGA, ASIC)

**Synthesizable Code Rules:**
- No unbounded loops
- No dynamic memory
- No floating point (usually)
- Deterministic behavior
- Sensitivity lists must be complete

### Testbenches

Verifying your design:

```ruby
describe Counter do
  it "counts up on clock edges" do
    counter = Counter.new('test_counter')
    sim = Simulator.new(counter)

    sim.set_input(:reset, 1)
    sim.clock_tick
    expect(sim.get_output(:count)).to eq(0)

    sim.set_input(:reset, 0)
    10.times do |i|
      sim.clock_tick
      expect(sim.get_output(:count)).to eq(i + 1)
    end
  end
end
```

### RHDL to Verilog Export

RHDL designs export to standard Verilog:

```ruby
counter = Counter.new('my_counter')
verilog = RHDL::Export::Verilog.export(counter)
File.write('counter.v', verilog)
```

This generated Verilog can be:
- Simulated with industry tools (ModelSim, Verilator)
- Synthesized to FPGA (Xilinx Vivado, Intel Quartus)
- Used in ASIC design flows

## Hands-On Project: RHDL to Verilog

1. Design a UART transmitter in RHDL
2. Export to Verilog
3. Verify with Verilator
4. (Optional) Run on FPGA

## Exercises

1. Compare RHDL and Verilog for the same design
2. Identify non-synthesizable constructs
3. Write a self-checking testbench

---

## Notes and Ideas

- Side-by-side RHDL/Verilog/VHDL comparison
- Common synthesis errors and what they mean
- Brief history: Verilog from Gateway, VHDL from DoD
- Modern alternatives: Chisel, Clash, Amaranth
- Why Ruby? Metaprogramming power for generating hardware
