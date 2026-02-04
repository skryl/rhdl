# Appendix M: Synthesis and Implementation

## Overview

Taking your design from HDL to real hardware: synthesis, place and route, FPGAs, and ASICs.

## Key Concepts

### The Implementation Flow

```
HDL Code
    |
    v
[Synthesis] --> Gate-level netlist
    |
    v
[Technology Mapping] --> Target-specific cells
    |
    v
[Place & Route] --> Physical layout
    |
    v
[Timing Analysis] --> Verify timing constraints
    |
    v
[Bitstream/GDSII] --> Program FPGA or fabricate ASIC
```

### Synthesis

Converting HDL to gates:

**What the synthesizer does:**
1. Parse HDL code
2. Build abstract syntax tree
3. Infer hardware structures (registers, muxes, FSMs)
4. Optimize logic
5. Map to target technology

**RHDL's Gate-Level IR:**

```ruby
# High-level RHDL
class Adder < SimComponent
  input :a, width: 8
  input :b, width: 8
  output :sum, width: 8

  behavior do
    sum <= a + b
  end
end

# Synthesizes to gate-level IR:
# - 8 full adders
# - Each full adder: 2 XOR, 2 AND, 1 OR
# - Total: 16 XOR, 16 AND, 8 OR gates
```

### Gate-Level Primitives

RHDL synthesizes to these primitives:

| Primitive | Description |
|-----------|-------------|
| AND | 2-input AND gate |
| OR | 2-input OR gate |
| XOR | 2-input XOR gate |
| NOT | Inverter |
| MUX | 2:1 Multiplexer |
| BUF | Buffer |
| CONST | Constant 0 or 1 |
| DFF | D Flip-Flop |

### FPGAs

Field-Programmable Gate Arrays:

**Structure:**
- CLBs (Configurable Logic Blocks)
- Each CLB contains LUTs, flip-flops, muxes
- Programmable interconnect
- I/O blocks around perimeter
- Often includes hard blocks (multipliers, RAM, PLLs)

**LUT (Lookup Table):**
- Implements any N-input boolean function
- Typically 4-6 inputs
- Just a small memory!

**Advantages:**
- Reconfigurable
- Fast time-to-market
- Good for prototyping

**Disadvantages:**
- Slower than ASICs
- More power consumption
- Higher cost per unit

### ASICs

Application-Specific Integrated Circuits:

**Standard Cell:**
- Library of pre-designed gates
- Automatic place and route
- Most common approach

**Full Custom:**
- Hand-designed transistors
- Maximum performance
- Extreme cost and time

**Advantages:**
- Fastest possible
- Lowest power
- Lowest per-unit cost at volume

**Disadvantages:**
- High NRE (Non-Recurring Engineering) cost
- Long development time
- Can't fix bugs

### Timing Analysis

**Setup Time:**
- Data must be stable BEFORE clock edge
- Violated = wrong value captured

**Hold Time:**
- Data must remain stable AFTER clock edge
- Violated = metastability

**Critical Path:**
- Longest combinational path between registers
- Determines maximum clock frequency

```
Max Frequency = 1 / (Tcritical + Tsetup + Tskew)
```

### Optimization Techniques

**Logic Optimization:**
- Boolean simplification
- Technology mapping
- Retiming (moving registers)

**Area vs Speed vs Power:**
- Can't optimize all three
- Trade-offs everywhere
- Constraints guide the tools

### RHDL Export Flow

```ruby
# Design in RHDL
alu = RHDL::HDL::ALU.new('my_alu', width: 8)

# Export to gate-level IR
ir = RHDL::Export::Structure::Lower.from_components([alu])
puts "Gates: #{ir.gates.length}, DFFs: #{ir.dffs.length}"

# Export to Verilog (for FPGA tools)
verilog = RHDL::Export::Verilog.export(alu)
File.write('alu.v', verilog)

# The Verilog can then be:
# - Simulated: iverilog, Verilator
# - Synthesized: Vivado, Quartus
# - Verified: formal tools
```

### Real-World Implementation

**FPGA Development Flow:**
1. Write/export Verilog
2. Create constraints file (pin assignments, timing)
3. Run synthesis
4. Run place and route
5. Run timing analysis
6. Generate bitstream
7. Program FPGA
8. Debug with logic analyzer / ILA

## Hands-On Project: FPGA Implementation

Take our 8-bit CPU and:
1. Export to Verilog
2. Add I/O constraints
3. Synthesize for target FPGA
4. Analyze resource utilization
5. Run on hardware (if available)

## Exercises

1. Compare gate count for different ALU implementations
2. Analyze critical path in our CPU
3. Optimize a design for minimum area

---

## Notes and Ideas

- Show actual synthesis reports
- Visualize place and route results
- Common synthesis warnings and what they mean
- FPGA development board recommendations
- How to estimate if design will fit
- Power analysis basics
- Future: High-Level Synthesis (HLS)
