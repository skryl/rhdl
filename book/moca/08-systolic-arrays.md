# Chapter 8: Systolic Arrays

## Overview

What if computation flowed through hardware like blood through the heart? **Systolic arrays** are regular grids of processing elements where data pulses rhythmically through the structure. They're massively parallel, elegantly simple, and power the matrix operations in modern AI accelerators like Google's TPU.

## The Systolic Concept

### Why "Systolic"?

The name comes from the heart's systole—the rhythmic contraction that pumps blood:

```
┌─────────────────────────────────────────┐
│         SYSTOLIC BLOOD FLOW             │
├─────────────────────────────────────────┤
│                                         │
│   Heart contracts → Blood pulses out    │
│                                         │
│   ●──▶──●──▶──●──▶──●──▶──●            │
│         arteries                        │
│                                         │
│   Data flows similarly through array:   │
│                                         │
│   ●──▶──[PE]──▶──[PE]──▶──[PE]──▶──●   │
│         processing elements             │
│                                         │
└─────────────────────────────────────────┘
```

H.T. Kung coined the term at CMU in 1978. The key insight: instead of fetching data from memory repeatedly, let data flow through a network of processing elements, being used multiple times as it passes.

### The Memory Wall Problem

Traditional computing has a bottleneck:

```
┌─────────────────────────────────────────┐
│        THE MEMORY WALL                  │
├─────────────────────────────────────────┤
│                                         │
│   Memory    ◄─────────────►    CPU      │
│   [DRAM]        slow bus       [fast]   │
│                                         │
│   Bandwidth: ~100 GB/s                  │
│   CPU speed: ~1000 GFLOPS               │
│                                         │
│   CPU starves waiting for data!         │
│                                         │
└─────────────────────────────────────────┘
```

Systolic arrays address this by **reusing data** as it flows:

```
┌─────────────────────────────────────────┐
│        SYSTOLIC DATA REUSE              │
├─────────────────────────────────────────┤
│                                         │
│   Data enters once, used many times:    │
│                                         │
│   a ──▶──[PE]──▶──[PE]──▶──[PE]──▶     │
│           │        │        │           │
│           use1     use2     use3        │
│                                         │
│   3 operations, 1 memory fetch!         │
│                                         │
└─────────────────────────────────────────┘
```

## Matrix Multiplication

### The Core Operation

Matrix multiply is the most common operation in:
- Neural networks (every layer)
- Graphics (transformations)
- Scientific computing (linear algebra)

```
C = A × B

┌───────────┐   ┌───────────┐   ┌───────────┐
│ a₀₀ a₀₁  │   │ b₀₀ b₀₁  │   │ c₀₀ c₀₁  │
│ a₁₀ a₁₁  │ × │ b₁₀ b₁₁  │ = │ c₁₀ c₁₁  │
└───────────┘   └───────────┘   └───────────┘

c₀₀ = a₀₀×b₀₀ + a₀₁×b₁₀
c₀₁ = a₀₀×b₀₁ + a₀₁×b₁₁
...
```

Each output element is a **dot product** of a row and column.

### Systolic Matrix Multiply

A 2×2 systolic array for matrix multiplication:

```
┌─────────────────────────────────────────┐
│      SYSTOLIC MATRIX MULTIPLY           │
├─────────────────────────────────────────┤
│                                         │
│        b₀₀  b₀₁                         │
│         ↓    ↓                          │
│   a₀₀ →[PE₀₀]→[PE₀₁]→                   │
│         ↓    ↓                          │
│   a₀₁ →[PE₁₀]→[PE₁₁]→                   │
│         ↓    ↓                          │
│                                         │
│   Each PE: accumulate += a_in × b_in    │
│            pass a_in right              │
│            pass b_in down               │
│                                         │
└─────────────────────────────────────────┘
```

**Timing (data enters staggered):**
```
Cycle 0:  a₀₀ enters PE₀₀, b₀₀ enters PE₀₀
Cycle 1:  a₀₁ enters PE₀₀, a₀₀ moves to PE₀₁
          b₀₁ enters PE₀₁, b₀₀ moves to PE₁₀
Cycle 2:  Data continues flowing...
Cycle 3:  All PEs have accumulated their results
```

### Processing Element

```
┌─────────────────────────────────────────┐
│     MATRIX MULTIPLY PE                  │
├─────────────────────────────────────────┤
│                                         │
│        b_in                             │
│          ↓                              │
│    ┌─────┴─────┐                        │
│    │           │                        │
│  a_in ──▶  [×] ──▶ (+) ──▶ accumulator  │
│    │           ↑                        │
│    │     ┌─────┘                        │
│    ↓     │                              │
│   a_out  b_out                          │
│                                         │
│   Each cycle:                           │
│     acc += a_in × b_in                  │
│     a_out = a_in (delayed)              │
│     b_out = b_in (delayed)              │
│                                         │
└─────────────────────────────────────────┘
```

## RHDL Implementation

Systolic arrays map elegantly to RHDL's component-based design:

### Key Components

| Component | Function |
|-----------|----------|
| **SystolicPE** | Single processing element with MAC and data pass-through |
| **SystolicArray2x2** | 2×2 array connecting 4 PEs with proper data flow |
| **SystolicInputStager** | Generates staggered input timing for matrix operands |
| **ConvolutionPE** | Processing element for 1D convolution/FIR filters |

### Hardware Complexity

| Component | Multipliers | Adders | Registers |
|-----------|-------------|--------|-----------|
| SystolicPE | 1 | 1 | 3 (acc + a_reg + b_reg) |
| 2×2 Array | 4 | 4 | 12 |
| N×N Array | N² | N² | 3N² |

> See [Appendix G](appendix-g-systolic.md) for complete RHDL implementations of all systolic components.

## Other Systolic Algorithms

### Convolution

1D convolution for signal processing:

```
y[n] = Σ h[k] × x[n-k]

      h[0]    h[1]    h[2]
        ↓       ↓       ↓
x[n] →[PE]──→[PE]──→[PE]──→ y[n]
        +       +       +
        ↓       ↓       ↓
      (accumulate)
```

> See [Appendix G](appendix-g-systolic.md) for convolution PE implementation.

### Sorting

Odd-even transposition sort:

```
┌─────────────────────────────────────────┐
│      SYSTOLIC SORTING                   │
├─────────────────────────────────────────┤
│                                         │
│   Data:  5  2  8  1  9  3               │
│                                         │
│   [Compare-Exchange] cells:             │
│                                         │
│   5  2  8  1  9  3   (initial)          │
│   2  5  1  8  3  9   (odd phase)        │
│   2  1  5  3  8  9   (even phase)       │
│   1  2  3  5  8  9   (odd phase)        │
│                                         │
│   O(n) time with O(n) PEs               │
│                                         │
└─────────────────────────────────────────┘
```

### LU Decomposition

For solving linear systems:

```
     Column inputs
         ↓
Row → [Pivot] → [Eliminate] → [Eliminate]
         ↓           ↓            ↓
        [0]   → [Eliminate] → [Eliminate]
                     ↓            ↓
                    [0]    → [Eliminate]
```

## Google TPU

### TPU Architecture

Google's Tensor Processing Unit uses a massive systolic array:

```
┌─────────────────────────────────────────┐
│      GOOGLE TPU v1 (2016)               │
├─────────────────────────────────────────┤
│                                         │
│   ┌─────────────────────────────────┐   │
│   │    256 × 256 Systolic Array     │   │
│   │                                 │   │
│   │    ┌──┬──┬──┬──┬──┬──┬──┐      │   │
│   │    │PE│PE│PE│PE│PE│PE│..│      │   │
│   │    ├──┼──┼──┼──┼──┼──┼──┤      │   │
│   │    │PE│PE│PE│PE│PE│PE│..│      │   │
│   │    ├──┼──┼──┼──┼──┼──┼──┤      │   │
│   │    │..│..│..│..│..│..│..│      │   │
│   │    └──┴──┴──┴──┴──┴──┴──┘      │   │
│   │                                 │   │
│   │    65,536 MAC units             │   │
│   │    92 trillion ops/second       │   │
│   └─────────────────────────────────┘   │
│                                         │
│   Peak: 92 TOPS (8-bit)                 │
│   Power: 40W                            │
│   Efficiency: 2.3 TOPS/W                │
│                                         │
└─────────────────────────────────────────┘
```

### Why Systolic for AI?

Neural network inference is mostly matrix multiplication:

```
Layer output = activation(W × input + b)
                         ↑
                    matrix multiply
```

Systolic arrays provide:
- High throughput for matrix ops
- Regular, predictable data flow
- Efficient power usage
- Easy to scale (just add more PEs)

## Design Trade-offs

### Array Size

| Size | Utilization | Flexibility |
|------|-------------|-------------|
| Small (4×4) | High for small matrices | Can't do large ops efficiently |
| Large (256×256) | Low for small matrices | Handles large ops well |
| Reconfigurable | Medium | Best of both |

### Data Flow Patterns

**Weight stationary:** Weights stay in PEs, activations flow
**Output stationary:** Partial sums stay, weights and activations flow
**Row stationary:** Best energy efficiency for CNN layers

### Precision

| Precision | Accuracy | Performance |
|-----------|----------|-------------|
| FP32 | Highest | 1× |
| FP16 | High | 2× |
| INT8 | Good for inference | 4× |
| INT4 | Acceptable | 8× |

Modern TPUs support mixed precision for optimal trade-offs.

## Hands-On Exercises

### Exercise 1: Trace Matrix Multiply

For A = [[1,2],[3,4]] and B = [[5,6],[7,8]]:

Trace data through a 2×2 systolic array cycle by cycle. What are the intermediate accumulator values?

### Exercise 2: 3×3 Systolic Array

Extend the RHDL implementation to a 3×3 array. How many cycles does it take to complete a 3×3 × 3×3 multiplication?

### Exercise 3: Convolution Array

Implement a 5-tap FIR filter using systolic PEs:
```
y[n] = Σ h[k] × x[n-k]  for k = 0 to 4
```

## Key Takeaways

1. **Data reuse is key** - Fetch once, use many times
2. **Regular structure** - Easy to design, verify, and manufacture
3. **Massive parallelism** - All PEs work simultaneously
4. **Matches matrix ops** - Perfect for neural networks
5. **Power efficient** - Local communication, no global memory bus

## Further Reading

- *Why Systolic Architectures?* by H.T. Kung (1982) - The original paper
- *Google TPU papers* - Modern systolic AI accelerators
- *Spatial Architecture* papers - FPGA systolic implementations

> See [Appendix G](appendix-g-systolic.md) for more algorithms and larger RHDL implementations.
