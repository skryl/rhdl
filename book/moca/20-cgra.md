# Chapter 20: Coarse-Grained Reconfigurable Arrays

*Word-level spatial computing: the middle ground between FPGAs and ASICs*

---

## Overview

While FPGAs offer bit-level reconfigurability through lookup tables, **Coarse-Grained Reconfigurable Arrays (CGRAs)** operate at the word level—with ALUs, multipliers, and registers as primitive elements. This coarser granularity trades flexibility for efficiency, making CGRAs ideal for compute-intensive loops in DSP, machine learning, and scientific computing.

---

## FPGA vs CGRA Trade-offs

```
FPGA (Fine-Grained):
┌─────────────────────────────────────────┐
│  Primitive: 4-6 input LUT              │
│  Routing: Bit-level interconnect       │
│  Configuration: Millions of bits       │
│  Flexibility: Any digital circuit      │
│  Efficiency: ~10-20× slower than ASIC  │
└─────────────────────────────────────────┘

CGRA (Coarse-Grained):
┌─────────────────────────────────────────┐
│  Primitive: ALU, Multiplier, Register  │
│  Routing: Word-level interconnect      │
│  Configuration: Thousands of bits      │
│  Flexibility: Regular dataflow loops   │
│  Efficiency: ~2-5× slower than ASIC    │
└─────────────────────────────────────────┘

ASIC:
┌─────────────────────────────────────────┐
│  Primitive: Custom logic               │
│  Routing: Fixed                        │
│  Configuration: None (hardcoded)       │
│  Flexibility: None                     │
│  Efficiency: Baseline (1×)             │
└─────────────────────────────────────────┘
```

---

## CGRA Architecture

### Basic Structure

```
┌─────────────────────────────────────────────────────────────┐
│                    CGRA TILE ARRAY                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────┐   ┌─────┐   ┌─────┐   ┌─────┐                   │
│   │ PE  │───│ PE  │───│ PE  │───│ PE  │                   │
│   │(ALU)│   │(MUL)│   │(ALU)│   │(MEM)│                   │
│   └──┬──┘   └──┬──┘   └──┬──┘   └──┬──┘                   │
│      │         │         │         │                       │
│   ┌──┴──┐   ┌──┴──┐   ┌──┴──┐   ┌──┴──┐                   │
│   │ PE  │───│ PE  │───│ PE  │───│ PE  │                   │
│   │(MUL)│   │(ALU)│   │(MEM)│   │(ALU)│                   │
│   └──┬──┘   └──┬──┘   └──┬──┘   └──┬──┘                   │
│      │         │         │         │                       │
│   ┌──┴──┐   ┌──┴──┐   ┌──┴──┐   ┌──┴──┐                   │
│   │ PE  │───│ PE  │───│ PE  │───│ PE  │                   │
│   │(ALU)│   │(MUL)│   │(ALU)│   │(MEM)│                   │
│   └─────┘   └─────┘   └─────┘   └─────┘                   │
│                                                             │
│   PE = Processing Element (word-level operations)          │
│   Configuration selects operation and routing              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Processing Element (PE)

Each PE contains:

```
┌─────────────────────────────────────────────────────────────┐
│                    PROCESSING ELEMENT                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   From North        From East                               │
│       │                 │                                   │
│       ▼                 ▼                                   │
│   ┌───────────────────────────────┐                        │
│   │         Input Muxes           │◄── Config bits         │
│   └───────────┬───────────────────┘                        │
│               │                                             │
│       ┌───────┴───────┐                                    │
│       │               │                                     │
│       ▼               ▼                                     │
│   ┌───────┐       ┌───────┐                                │
│   │  Reg  │       │  Reg  │   Local registers              │
│   └───┬───┘       └───┬───┘                                │
│       │               │                                     │
│       └───────┬───────┘                                    │
│               │                                             │
│               ▼                                             │
│   ┌───────────────────────────────┐                        │
│   │     Functional Unit           │◄── Opcode config       │
│   │  (ADD, MUL, SHIFT, etc.)     │                        │
│   └───────────┬───────────────────┘                        │
│               │                                             │
│               ▼                                             │
│   ┌───────────────────────────────┐                        │
│   │        Output Muxes           │◄── Config bits         │
│   └───────────┬───────────────────┘                        │
│               │                                             │
│       ┌───────┴───────┐                                    │
│       ▼               ▼                                     │
│   To South        To West                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Interconnect Network

CGRAs use word-level routing:

```
Nearest-Neighbor:
┌───┐   ┌───┐   ┌───┐
│PE │◄─►│PE │◄─►│PE │
└─┬─┘   └─┬─┘   └─┬─┘
  │       │       │
  ▼       ▼       ▼
┌─┴─┐   ┌─┴─┐   ┌─┴─┐
│PE │◄─►│PE │◄─►│PE │
└───┘   └───┘   └───┘

Express Lanes (for longer distances):
┌───┐           ┌───┐
│PE │══════════►│PE │
└───┘           └───┘

Diagonal Connections:
┌───┐       ┌───┐
│PE │╲     ╱│PE │
└───┘ ╲   ╱ └───┘
       ╲ ╱
       ╱ ╲
┌───┐╱     ╲┌───┐
│PE │       │PE │
└───┘       └───┘
```

---

## Configuration and Execution

### Static vs Dynamic Configuration

**Static (spatial):** Configuration loaded once, data streams through

```
Config: Fixed
       ┌───┐   ┌───┐   ┌───┐
Data ─►│ + │──►│ * │──►│ + │──► Result
       └───┘   └───┘   └───┘

Each PE configured for one operation
Data flows spatially through the array
```

**Dynamic (time-multiplexed):** Configuration changes each cycle

```
Cycle 0: PE does ADD
Cycle 1: PE does MUL
Cycle 2: PE does SHIFT
...

More flexible but requires configuration memory
```

### Modulo Scheduling

CGRAs excel at **software pipelining** of loops:

```c
// Original loop
for (i = 0; i < N; i++) {
    t1 = A[i] * B[i];
    t2 = t1 + C[i];
    D[i] = t2 >> 2;
}
```

Mapped to CGRA with II=1 (initiation interval = 1):

```
Cycle:    0    1    2    3    4    5
─────────────────────────────────────
PE0(MUL): i0   i1   i2   i3   i4   i5
PE1(ADD):      i0   i1   i2   i3   i4
PE2(SHR):           i0   i1   i2   i3

After startup, one result per cycle!
```

---

## CGRA Examples

### Samsung Reconfigurable Processor (SRP)

```
┌─────────────────────────────────────────┐
│  4×4 PE array                          │
│  Each PE: 32-bit ALU + local memory    │
│  Used in mobile SoCs for DSP           │
│  Dynamic reconfiguration               │
└─────────────────────────────────────────┘
```

### ADRES (Architecture for Dynamically Reconfigurable Embedded Systems)

```
┌─────────────────────────────────────────┐
│  VLIW core + CGRA accelerator          │
│  Tightly coupled execution             │
│  DRESC compiler for automatic mapping  │
│  Academic/research architecture         │
└─────────────────────────────────────────┘
```

### Plasticine / SambaNova

```
┌─────────────────────────────────────────┐
│  Pattern Compute Units (PCU)           │
│  Pattern Memory Units (PMU)            │
│  Hierarchical interconnect             │
│  Designed for ML workloads             │
└─────────────────────────────────────────┘
```

### CGRA in Modern AI Accelerators

Many AI accelerators use CGRA principles:

```
Typical AI CGRA:
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐                         │
│   │ MAC │─│ MAC │─│ MAC │─│ MAC │                         │
│   └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘                         │
│      │       │       │       │                             │
│   ┌──┴───────┴───────┴───────┴──┐                         │
│   │      Accumulator Tree       │                         │
│   └──────────────┬──────────────┘                         │
│                  │                                         │
│   ┌──────────────┴──────────────┐                         │
│   │      Activation Unit        │ ◄── ReLU, Sigmoid, etc. │
│   └──────────────┬──────────────┘                         │
│                  │                                         │
│   ┌──────────────┴──────────────┐                         │
│   │      Pooling Unit           │ ◄── Max, Avg            │
│   └─────────────────────────────┘                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Compilation and Mapping

### The Mapping Problem

Given a dataflow graph, find:
1. Which PE executes each operation
2. Which cycle each operation executes
3. How data routes between PEs

```
DFG (Dataflow Graph):        CGRA Mapping:
    a   b                    ┌───┐ ┌───┐
    │   │                    │ a │ │ b │
    ▼   ▼                    └─┬─┘ └─┬─┘
   ┌─────┐                     │     │
   │  +  │                     ▼     ▼
   └──┬──┘                   ┌─────────┐
      │                      │   ADD   │ PE[0,0], cycle 0
      ▼                      └────┬────┘
   ┌─────┐                        │
   │  *  │                        ▼
   └──┬──┘                   ┌─────────┐
      │                      │   MUL   │ PE[0,1], cycle 1
      ▼                      └────┬────┘
      c                           │
                                  ▼
                                  c
```

### Challenges

1. **Resource constraints:** Limited PEs and interconnect
2. **Routing conflicts:** Multiple data paths compete for wires
3. **Timing:** Operations must schedule correctly
4. **NP-hard:** Optimal mapping is computationally expensive

### Compiler Approaches

- **Simulated annealing:** Random search with cooling schedule
- **Integer linear programming (ILP):** Exact but slow
- **Modulo scheduling:** For software pipelining
- **Graph matching:** Heuristic placement

---

## CGRA vs Other Architectures

| Feature | CGRA | FPGA | GPU | CPU |
|---------|------|------|-----|-----|
| Granularity | Word | Bit | Thread | Instruction |
| Reconfiguration | Fast | Slow | Fixed | Fixed |
| Energy efficiency | High | Medium | Medium | Low |
| Programmability | Hard | Hard | Medium | Easy |
| Area efficiency | High | Low | High | Medium |
| Best for | DSP loops | Bit manipulation | Parallel compute | General |

---

## When to Use CGRAs

### Ideal Workloads

| Workload | Why CGRA Fits |
|----------|---------------|
| FIR/IIR filters | Regular dataflow, high throughput |
| Matrix operations | Systolic-style execution |
| Image processing | Streaming, predictable patterns |
| Neural network inference | Repeated MAC operations |
| Cryptography | Word-level operations |

### Poor Fit

| Workload | Why Not CGRA |
|----------|--------------|
| Irregular control flow | Hard to map branches |
| Sparse computation | Underutilizes PEs |
| Bit manipulation | FPGA better suited |
| General-purpose code | CPU more flexible |

---

## RHDL Implementation

See [Appendix T](appendix-t-cgra.md) for complete implementation:

```ruby
# CGRA Processing Element
class CGRAProcessingElement < SimComponent
  parameter :data_width, default: 32

  input :clk
  input :north_in, width: :data_width
  input :south_in, width: :data_width
  input :east_in, width: :data_width
  input :west_in, width: :data_width
  input :config, width: 16  # Operation + routing config

  output :north_out, width: :data_width
  output :south_out, width: :data_width
  output :east_out, width: :data_width
  output :west_out, width: :data_width

  instance :alu, ALU, width: data_width
  instance :reg_a, Register, width: data_width
  instance :reg_b, Register, width: data_width
  instance :mux_a, Mux4, width: data_width
  instance :mux_b, Mux4, width: data_width

  behavior do
    # Decode config bits
    # Route inputs through muxes
    # Execute ALU operation
    # Route outputs
  end
end
```

---

## Summary

- **Coarse-grained:** Word-level primitives (ALUs, multipliers)
- **Spatial computing:** Data flows through configured array
- **Energy efficient:** 2-5× slower than ASIC vs 10-20× for FPGA
- **Ideal for loops:** Software pipelining achieves high throughput
- **Hard to program:** Mapping is NP-hard, requires specialized compilers
- **Modern AI accelerators:** Many use CGRA principles
- **Middle ground:** Between FPGA flexibility and ASIC efficiency

---

## Exercises

1. Map a 4-tap FIR filter to a 2×2 CGRA with II=1
2. Calculate the speedup of CGRA vs CPU for a matrix multiply
3. Design a PE with configurable bypass paths
4. Implement modulo scheduling for a simple loop
5. Compare energy efficiency: CGRA vs FPGA for FFT

---

## Further Reading

- Mei et al., "ADRES: An Architecture with Tightly Coupled VLIW Processor and Coarse-Grained Reconfigurable Matrix"
- Prabhakar et al., "Plasticine: A Reconfigurable Architecture for Parallel Patterns"
- "A Survey on Coarse-Grained Reconfigurable Architectures" (ACM Computing Surveys)

---

*Previous: [Chapter 19 - FPGAs](19-fpga.md)*

*Next: [Chapter 21 - The MOS 6502](21-mos6502.md)*

*Appendix: [Appendix T - CGRA Implementation](appendix-t-cgra.md)*
