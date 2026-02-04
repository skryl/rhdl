# Chapter 12: Synthesis and Implementation

## Overview

You've written HDL code. Now what? **Synthesis** transforms your behavioral description into actual hardware—gates, flip-flops, and wires that can be manufactured in silicon or programmed into an FPGA.

## The Synthesis Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    SYNTHESIS FLOW                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   HDL Code                                                   │
│      │                                                       │
│      ▼                                                       │
│   ┌──────────────┐                                          │
│   │   Parsing    │  → Syntax check, build AST               │
│   └──────────────┘                                          │
│      │                                                       │
│      ▼                                                       │
│   ┌──────────────┐                                          │
│   │ Elaboration  │  → Resolve parameters, flatten hierarchy │
│   └──────────────┘                                          │
│      │                                                       │
│      ▼                                                       │
│   ┌──────────────┐                                          │
│   │  RTL Synth   │  → Convert to generic gates              │
│   └──────────────┘                                          │
│      │                                                       │
│      ▼                                                       │
│   ┌──────────────┐                                          │
│   │ Optimization │  → Minimize area/delay/power             │
│   └──────────────┘                                          │
│      │                                                       │
│      ▼                                                       │
│   ┌──────────────┐                                          │
│   │  Technology  │  → Map to target library (FPGA/ASIC)     │
│   │   Mapping    │                                          │
│   └──────────────┘                                          │
│      │                                                       │
│      ▼                                                       │
│   Gate-Level Netlist                                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## From Behavior to Gates

### Step 1: Parse and Elaborate

```verilog
// Input HDL
module adder #(parameter WIDTH=8) (
    input  [WIDTH-1:0] a, b,
    output [WIDTH-1:0] sum
);
    assign sum = a + b;
endmodule
```

Elaboration resolves `WIDTH=8` and expands the design.

### Step 2: RTL Synthesis

The `a + b` becomes a generic adder:

```
GENERIC_ADD(a[7:0], b[7:0]) → sum[7:0]
```

### Step 3: Optimization

Constant propagation, dead code elimination, logic minimization:

```
// Before optimization
assign x = a & 1'b1;  // AND with 1 is identity
assign y = b | 1'b0;  // OR with 0 is identity
assign z = c ^ c;     // XOR with self is 0

// After optimization
assign x = a;
assign y = b;
assign z = 1'b0;
```

### Step 4: Technology Mapping

Map to actual cells from the target library:

```
For FPGA (LUT-based):
  8-bit add → Chain of LUT4 + carry logic

For ASIC (standard cells):
  8-bit add → Full adder cells from PDK
```

## FPGA vs ASIC

| Aspect | FPGA | ASIC |
|--------|------|------|
| Cost per unit | High | Low (at volume) |
| NRE cost | Low | $1M-$100M+ |
| Time to first part | Hours | Months |
| Performance | Good | Best |
| Power efficiency | Lower | Higher |
| Flexibility | Reprogrammable | Fixed |
| Use case | Prototyping, low volume | Mass production |

## FPGA Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    FPGA STRUCTURE                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐                       │
│   │ CLB │──│ CLB │──│ CLB │──│ CLB │                       │
│   └──┬──┘  └──┬──┘  └──┬──┘  └──┬──┘                       │
│      │        │        │        │                           │
│   ┌──┴──┐  ┌──┴──┐  ┌──┴──┐  ┌──┴──┐                       │
│   │ CLB │──│BRAM │──│ CLB │──│ DSP │                       │
│   └──┬──┘  └──┬──┘  └──┬──┘  └──┬──┘                       │
│      │        │        │        │                           │
│                                                              │
│   CLB = Configurable Logic Block (LUTs + FFs)               │
│   BRAM = Block RAM (memory)                                 │
│   DSP = Digital Signal Processing (multiply-accumulate)     │
│                                                              │
│   Routing: Programmable interconnect between blocks          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Lookup Tables (LUTs)

The core of FPGA logic—a small truth table in memory:

```
4-input LUT can implement ANY 4-input boolean function:
- 2^4 = 16 possible input combinations
- 16 bits of configuration memory
- Configure those 16 bits = define the function

LUT4 configured as AND:
  Input: 0000 → Output: 0
  Input: 0001 → Output: 0
  ...
  Input: 1111 → Output: 1
```

## Timing Analysis

### Setup and Hold

```
┌─────────────────────────────────────────────────────────────┐
│                    TIMING CONSTRAINTS                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   CLK  ────────┐         ┌─────────                         │
│                │         │                                   │
│                └─────────┘                                   │
│                                                              │
│   DATA ──────────────────╱╲────────                         │
│                    setup │ │ hold                            │
│                    time  │ │ time                            │
│                          │ │                                 │
│                          ▼ ▼                                 │
│                                                              │
│   Setup: Data must be stable BEFORE clock edge               │
│   Hold:  Data must be stable AFTER clock edge                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Critical Path

The longest combinational delay determines maximum clock frequency:

```
FF1 → [Combinational Logic] → FF2
     ├─────────────────────┤
           Critical Path

Max Frequency = 1 / (Critical Path Delay + Setup Time)
```

### Timing Reports

```
Path: clk → reg_a → add → mux → reg_b
  Source: reg_a/Q (rise)
  Destination: reg_b/D (rise)

  Data Path Delay:    3.2 ns
  Clock Path Delay:   0.5 ns
  Setup Requirement:  0.3 ns
  ────────────────────────
  Slack:              1.0 ns  (MET)
```

## Optimization Strategies

### Area Optimization

- Resource sharing (one multiplier, time-multiplexed)
- Logic minimization (Karnaugh maps, Espresso)
- State encoding optimization

### Speed Optimization

- Pipelining (break long paths)
- Retiming (move registers for balance)
- Logic duplication (reduce fan-out)

### Power Optimization

- Clock gating (disable unused logic)
- Operand isolation (don't compute unused results)
- Voltage/frequency scaling

## The RHDL Synthesis Path

```
RHDL Component
    │
    ▼
RHDL Behavioral Simulation (Ruby)
    │
    ▼
Verilog Export (rhdl export)
    │
    ▼
Commercial Synthesis Tool (Vivado, Quartus, Yosys)
    │
    ▼
FPGA Bitstream or ASIC Netlist
```

RHDL also supports direct gate-level synthesis:

```
RHDL Component
    │
    ▼
Gate-Level IR (rhdl gates)
    │
    ▼
JSON Netlist (primitives: AND, OR, NOT, MUX, DFF)
    │
    ▼
Technology Mapping
```

## Key Takeaways

1. **Synthesis is compilation for hardware** - HDL → gates
2. **Many optimization dimensions** - Area, speed, power trade-offs
3. **Timing is everything** - Setup/hold, critical path, clock domains
4. **FPGAs vs ASICs** - Different tools, different trade-offs
5. **Understand your target** - LUTs behave differently than standard cells

> See [Appendix L](appendix-l-synthesis.md) for detailed synthesis examples, timing analysis, and FPGA implementation walkthroughs.
