# Chapter 29: The Cray-1

*The supercomputer that defined an era*

---

## Overview

In 1976, Seymour Cray delivered the Cray-1 to Los Alamos National Laboratory. It was the fastest computer in the world and would define vector supercomputing for decades. The Cray-1 wasn't just a fast computer—it was a work of engineering art, from its elegant architecture to its iconic C-shaped physical design.

**Key Stats:**
- Clock: 80 MHz (12.5 ns cycle)
- Peak performance: 160 MFLOPS
- Memory: 1-8 MW (8-64 MB)
- Vector registers: 8 × 64 elements × 64 bits
- Functional units: 12 pipelined units
- Power: 115 kW
- Weight: 5.5 tons
- Cost: $8.8 million (1977)

---

## Historical Context

### The Man Behind the Machine

Seymour Cray was already legendary when he designed the Cray-1. His previous machines:

| Year | Machine | Achievement |
|------|---------|-------------|
| 1960 | CDC 1604 | First fully transistorized computer |
| 1964 | CDC 6600 | First supercomputer (10× faster than anything) |
| 1969 | CDC 7600 | Pipelined scalar processor |
| 1976 | Cray-1 | First successful vector supercomputer |

Cray founded Cray Research in 1972 specifically to build the Cray-1.

### Design Philosophy

Seymour Cray's design principles:
1. **Simplicity**: "If you were plowing a field, which would you rather use? Two strong oxen or 1024 chickens?"
2. **Speed at all costs**: Minimize wire lengths, maximize clock speed
3. **Elegant solutions**: One right way to solve each problem
4. **Personal accountability**: Small team, hands-on design

---

## Architecture Overview

### Register Set

```
┌─────────────────────────────────────────┐
│           Cray-1 Registers              │
├─────────────────────────────────────────┤
│                                         │
│  Vector Registers (V0-V7)               │
│  ┌─────────────────────────────────┐    │
│  │  64 elements × 64 bits each     │    │
│  │  V0: [e0][e1][e2]...[e63]      │    │
│  │  V1: [e0][e1][e2]...[e63]      │    │
│  │  ...                            │    │
│  │  V7: [e0][e1][e2]...[e63]      │    │
│  └─────────────────────────────────┘    │
│       Total: 4,096 64-bit elements      │
│                                         │
│  Scalar Registers                       │
│  ┌─────────────────────────────────┐    │
│  │  S0-S7: 64-bit primary scalar   │    │
│  │  T0-T63: 64-bit backup scalar   │    │
│  └─────────────────────────────────┘    │
│                                         │
│  Address Registers                      │
│  ┌─────────────────────────────────┐    │
│  │  A0-A7: 24-bit primary address  │    │
│  │  B0-B63: 24-bit backup address  │    │
│  └─────────────────────────────────┘    │
│                                         │
│  Special Registers                      │
│  ┌─────────────────────────────────┐    │
│  │  VL: Vector Length (0-64)       │    │
│  │  VM: Vector Mask (64 bits)      │    │
│  └─────────────────────────────────┘    │
│                                         │
└─────────────────────────────────────────┘
```

### Functional Units

The Cray-1 had 12 pipelined functional units that could operate in parallel:

```
┌─────────────────────────────────────────────────────────┐
│            Cray-1 Functional Units                       │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  VECTOR UNITS:                                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │ V0: Integer │  │ V1: Logical │  │ V2: Shift   │     │
│  │     Add     │  │             │  │             │     │
│  │  (3 stages) │  │  (2 stages) │  │  (4 stages) │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │ V3: FP Add  │  │ V4: FP Mult │  │V5: Reciprocal│    │
│  │             │  │             │  │   Approx     │    │
│  │  (6 stages) │  │  (7 stages) │  │ (14 stages)  │    │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
│                                                          │
│  SCALAR UNITS:                                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │S0: Int Add  │  │ S1: Logical │  │ S2: Shift   │     │
│  │  (3 stages) │  │  (1 stage)  │  │ (2-3 stages)│     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
│  ┌─────────────┐  ┌─────────────┐                       │
│  │ S3: FP Add  │  │ S4: FP Mult │                       │
│  │  (6 stages) │  │  (7 stages) │                       │
│  └─────────────┘  └─────────────┘                       │
│                                                          │
│  ADDRESS UNIT:                                           │
│  ┌─────────────┐                                        │
│  │ A0: Address │                                        │
│  │     Add     │                                        │
│  │  (2 stages) │                                        │
│  └─────────────┘                                        │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Pipeline Details

| Unit | Function | Stages | Throughput |
|------|----------|--------|------------|
| V0 | Integer Add | 3 | 1/cycle |
| V1 | Logical (AND, OR, XOR) | 2 | 1/cycle |
| V2 | Shift | 4 | 1/cycle |
| V3 | FP Add | 6 | 1/cycle |
| V4 | FP Multiply | 7 | 1/cycle |
| V5 | Reciprocal Approximation | 14 | 1/cycle |

After pipeline startup, each unit produces **one result per cycle**.

---

## Vector Chaining

The Cray-1's breakthrough feature was **vector chaining**—allowing dependent vector operations to overlap.

### Without Chaining

```
V2 = V0 * V1      ; Must complete all 64 multiplies
V4 = V2 + V3      ; Then start all 64 adds

Cycles: (7 startup + 64 elements) + (6 startup + 64 elements)
      = 71 + 70 = 141 cycles
```

### With Chaining

```
V2 = V0 * V1      ; Element 0 result at cycle 7
V4 = V2 + V3      ; Element 0 add starts at cycle 8!

Cycle:  1  2  3  4  5  6  7  8  9  10 11 12 13 14 ...
Mult:   e0────────────────▶e0
             e1────────────────▶e1
                  e2────────────────▶e2
Add:                          e0────────▶e0
                                   e1────────▶e1
                                        e2────────▶e2

Cycles: 7 startup + 6 startup + 64 elements = 77 cycles
        Nearly 2× faster!
```

### Chaining Rules

Chaining was possible when:
1. Second instruction uses result of first as input
2. Functional units are different (no structural hazard)
3. No bank conflicts in register file

---

## Memory System

### Memory Banks

The Cray-1 used 16 memory banks to achieve high bandwidth:

```
16 Banks, 4-cycle access time:

Bank 0: ████░░░░████░░░░████░░░░  (busy cycles shown)
Bank 1: ░████░░░░████░░░░████░░░
Bank 2: ░░████░░░░████░░░░████░░
Bank 3: ░░░████░░░░████░░░░████░
...
Bank 15: ███░░░░████░░░░████░░░░█

By interleaving addresses across banks:
  Address 0 → Bank 0
  Address 1 → Bank 1
  Address 2 → Bank 2
  ...

Result: 1 word per cycle for contiguous access!
```

### Stride and Bank Conflicts

**Stride 1 (contiguous):** Perfect performance
```
Address:  0   1   2   3   4   5   6   7  ...
Bank:     0   1   2   3   4   5   6   7  ...
          All different banks → 1 word/cycle
```

**Stride 16:** Complete disaster
```
Address:  0  16  32  48  64  80  96 112 ...
Bank:     0   0   0   0   0   0   0   0 ...
          All same bank → 1 word/4 cycles!
```

Programmers learned to pad arrays to avoid stride conflicts.

---

## Instruction Set

### Vector Instructions

```assembly
; Vector Load/Store
V1 = ,A0,A1         ; Load V1 from memory[A0] with stride A1
,A0,A1 = V1         ; Store V1 to memory[A0] with stride A1

; Vector Arithmetic
V3 = V1 + V2        ; Vector integer add
V3 = V1 * V2        ; Vector FP multiply
V3 = V1 & V2        ; Vector AND
V3 = V1 ! V2        ; Vector XOR

; Vector-Scalar
V2 = V1 + S0        ; Add scalar to each element
V2 = V1 * S0        ; Multiply each element by scalar

; Vector Mask
VM = V1 < V2        ; Compare, set mask bits
V3 = V1 + V2, VM    ; Masked vector add (only where VM=1)

; Vector Length
VL = A0             ; Set vector length (1-64)
```

### DAXPY Example

The classic vector benchmark: `Y = a*X + Y`

```assembly
; Parameters: N in A0, a in S0, X base in A1, Y base in A2

        A3 = 1              ; Stride = 1
        VL = A0             ; Set vector length = N

        V0 = ,A1,A3         ; Load X vector
        V1 = V0 * S0        ; V1 = a * X (7 cycles + 64)
        V2 = ,A2,A3         ; Load Y vector (overlapped with multiply)
        V3 = V1 + V2        ; V3 = a*X + Y (CHAINED!)
        ,A2,A3 = V3         ; Store result back to Y

; With chaining: ~80 cycles for 64 elements
; Peak: 160 MFLOPS (two FP ops × 80 MHz)
```

---

## The Iconic Design

### Physical Layout

The Cray-1's distinctive C-shape wasn't aesthetics—it was engineering:

```
        ┌─────────────────────────────┐
       ╱                               ╲
      ╱      MAIN FRAME                 ╲
     │     (12 columns of modules)       │
     │                                   │
     │     ┌───────────────────┐         │
     │     │   Logic Modules   │         │
     │     │   (ECL gates)     │         │
     │     │                   │         │
     │     │   ~200,000 ICs    │         │
      ╲    └───────────────────┘        ╱
       ╲                               ╱
        └───────────┬─────────────────┘
                    │
              ┌─────┴─────┐
              │ Cooling   │
              │ (Freon)   │
              └───────────┘

Height: ~6 feet
Diameter: ~9 feet
The "bench seats" housed power supplies and blowers
```

### Why the C-Shape?

At 80 MHz, signals travel about **12 feet per cycle**. Wire length = latency.

```
Signal propagation at 80 MHz:
  Light speed: ~1 foot/ns
  Cycle time: 12.5 ns
  Maximum wire: ~12 feet

Cray's solution:
  - C-shape brings far edges closer
  - Longest wire: ~4 feet
  - Critical path: <4 feet
  - Single-cycle register access
```

### Cooling System

115 kW required serious cooling:

```
┌─────────────────────────────────────┐
│         Cooling System              │
├─────────────────────────────────────┤
│                                     │
│  Freon refrigeration:               │
│  - Freon flows through cold bars    │
│  - Cold bars contact module edges   │
│  - Heat conducted to Freon          │
│  - Freon cycled through compressor  │
│                                     │
│  Air system:                        │
│  - Forced air through modules       │
│  - Preheated to prevent condensation│
│  - Blowers in the "seats"          │
│                                     │
└─────────────────────────────────────┘
```

---

## Programming Model

### Vectorizing Compilers

Cray Fortran automatically vectorized suitable loops:

```fortran
! Vectorizable (no dependencies)
      DO 10 I = 1, N
         C(I) = A(I) + B(I)
   10 CONTINUE

! Compiler generates vector instructions automatically
```

```fortran
! NOT vectorizable (loop-carried dependency)
      DO 20 I = 2, N
         A(I) = A(I-1) + B(I)
   20 CONTINUE

! Scalar loop required
```

### Strip Mining

For arrays longer than 64 elements:

```fortran
! Original (N = 1000)
      DO 10 I = 1, 1000
         C(I) = A(I) + B(I)
   10 CONTINUE

! Compiler strip-mines automatically:
!   Loop 1: I = 1 to 64 (VL=64)
!   Loop 2: I = 65 to 128 (VL=64)
!   ...
!   Loop 16: I = 961 to 1000 (VL=40)
```

---

## Performance Analysis

### Peak vs Sustained

```
Theoretical peak: 160 MFLOPS
  (FP add + FP mult simultaneously, both producing 1/cycle)

Real-world sustained: 20-100 MFLOPS
  - Vector startup overhead
  - Memory bandwidth limits
  - Non-vectorizable code
  - Bank conflicts

Efficiency: 12-62% typical
```

### Benchmark Results (1977)

| Benchmark | MFLOPS | % Peak |
|-----------|--------|--------|
| DAXPY (N=64) | 138 | 86% |
| Matrix Multiply | 110 | 69% |
| FFT (1024) | 65 | 41% |
| Linpack | 12-25 | 8-16% |

---

## Legacy and Impact

### Direct Descendants

| Year | Machine | Improvement |
|------|---------|-------------|
| 1982 | Cray X-MP | 2-4 processors, 200+ MFLOPS each |
| 1985 | Cray-2 | 256 MW memory, immersion cooling |
| 1988 | Cray Y-MP | 8 processors, 333 MFLOPS each |
| 1995 | Cray T90 | 1.8 GFLOPS per processor |

### Modern Echoes

The Cray-1's ideas live on in:

| Modern Feature | Cray-1 Origin |
|----------------|---------------|
| x86 AVX-512 | Vector registers (512 bits) |
| ARM SVE | Scalable vectors with predication |
| RISC-V V | Vector extension with chaining |
| GPU SIMD | Massive vector parallelism |

Every time you use SIMD instructions, you're using Cray's legacy.

---

## RHDL Implementation

See [Appendix K](appendix-k-vector.md) for vector architecture implementation:

```ruby
# Cray-1 style vector register file
class CrayVectorRegFile < SimComponent
  parameter :num_regs, default: 8        # V0-V7
  parameter :vector_length, default: 64   # 64 elements
  parameter :element_width, default: 64   # 64-bit elements

  input :clk
  input :read_reg_a, width: 3
  input :read_reg_b, width: 3
  input :write_reg, width: 3
  input :write_enable
  input :vl, width: 7  # Vector length register

  # Element-at-a-time interface (for chaining)
  input :write_element, width: 6  # Which element (0-63)
  input :write_data, width: element_width

  output :read_data_a, width: element_width
  output :read_data_b, width: element_width
end

# Pipelined vector multiply unit
class CrayVectorMultiply < SimComponent
  parameter :pipeline_depth, default: 7
  parameter :element_width, default: 64

  input :clk
  input :a, width: element_width
  input :b, width: element_width
  input :valid_in

  output :result, width: element_width
  output :valid_out  # For chaining
end
```

---

## Summary

- **80 MHz in 1976**: Achieved through obsessive wire-length optimization
- **160 MFLOPS peak**: First true supercomputer performance
- **8 vector registers × 64 elements**: The canonical vector architecture
- **12 pipelined units**: Parallel execution of different operations
- **Chaining**: Revolutionary bypass that nearly doubled performance
- **16 memory banks**: High bandwidth through interleaving
- **Iconic C-shape**: Form following function (signal propagation)
- **Legacy**: Every modern SIMD instruction owes a debt to Cray

---

## Exercises

1. Calculate effective MFLOPS for DAXPY at various vector lengths
2. Determine the worst-case stride for 16 memory banks
3. Design a chaining controller that detects chain opportunities
4. Compare Cray-1 vector registers to modern AVX-512
5. Calculate power efficiency: MFLOPS/watt for Cray-1 vs modern GPU

---

## Further Reading

- Cray, "The Cray-1 Computer System" (technical report, 1976)
- Russell, "The Cray-1 Computer System" (CACM 1978)
- Murray, "The Supermen: The Story of Seymour Cray" (biography)
- Computer History Museum Cray-1 exhibit

---

*Previous: [Chapter 28 - The Cerebras WSE](28-cerebras.md)*

*Appendix: [Appendix K - Vector Implementation](appendix-k-vector.md)*
