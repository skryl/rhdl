# Chapter 21: The Cray-1

*The world's first supercomputer: vector processing at its finest*

---

## Historical Context

In 1976, Seymour Cray delivered the Cray-1 to Los Alamos National Laboratory. It was the fastest computer in the world, capable of 160 MFLOPS—a staggering achievement for its time.

**Key stats:**
- Clock: 80 MHz (12.5 ns cycle)
- Peak: 160 MFLOPS
- Memory: 1-8 MW (8-64 MB)
- Power: 115 kW
- Weight: 5.5 tons
- Cost: $8.8 million (1977)

The Cray-1 defined vector processing and influenced supercomputer design for decades.

---

## Vector Processing Philosophy

### Scalar vs Vector

**Scalar (traditional):**
```
for i = 0 to 63:
    C[i] = A[i] + B[i]    # 64 separate add instructions
```

**Vector:**
```
V1 = load A[0:63]         # One instruction, 64 elements
V2 = load B[0:63]         # One instruction, 64 elements
V3 = V1 + V2              # One instruction, 64 adds
store V3 -> C[0:63]       # One instruction, 64 elements
```

Vector processing amortizes instruction fetch/decode over many data elements.

### Why Vectors Win

1. **Reduced instruction bandwidth**: 4 instructions vs 64×3
2. **Predictable memory access**: Streaming, prefetchable
3. **Deep pipelining**: Operations overlap across elements
4. **No data hazards**: Each element is independent

---

## Cray-1 Architecture

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
│                                         │
│  Scalar Registers                       │
│  ┌─────────────────────────────────┐    │
│  │  S0-S7: 64-bit scalar           │    │
│  │  T0-T63: 64-bit temporary       │    │
│  └─────────────────────────────────┘    │
│                                         │
│  Address Registers                      │
│  ┌─────────────────────────────────┐    │
│  │  A0-A7: 24-bit address          │    │
│  │  B0-B63: 24-bit temporary       │    │
│  └─────────────────────────────────┘    │
│                                         │
│  Vector Length (VL): 0-64               │
│  Vector Mask (VM): 64 bits              │
│                                         │
└─────────────────────────────────────────┘
```

### Functional Units

The Cray-1 had 12 pipelined functional units:

| Unit | Function | Pipeline Stages |
|------|----------|-----------------|
| **Vector** |||
| V0 | Integer Add | 3 |
| V1 | Logical | 2 |
| V2 | Shift | 4 |
| V3 | FP Add | 6 |
| V4 | FP Multiply | 7 |
| V5 | Reciprocal Approx | 14 |
| **Scalar** |||
| S0 | Integer Add | 3 |
| S1 | Logical | 1 |
| S2 | Shift | 2-3 |
| S3 | FP Add | 6 |
| S4 | FP Multiply | 7 |
| **Address** |||
| A0 | Address Add | 2 |

---

## Vector Chaining

The Cray-1's killer feature: **chaining** allows the result of one vector operation to feed directly into another without waiting.

### Without Chaining

```
V2 = V0 * V1      # Wait for all 64 results
V4 = V2 + V3      # Then start addition

Time: (7 + 64) + (6 + 64) = 141 cycles
```

### With Chaining

```
V2 = V0 * V1      # Element 0 result available at cycle 7
V4 = V2 + V3      # Element 0 add starts at cycle 8!

Time: 7 + 6 + 64 = 77 cycles
```

Chaining nearly doubles performance for dependent operations.

```
Cycle:  1  2  3  4  5  6  7  8  9  10 11 12 13 14 ...
Mult:   e0────────────────▶e0
             e1────────────────▶e1
                  e2────────────────▶e2
Add:                          e0────────▶e0
                                   e1────────▶e1
                                        e2────────▶e2
```

---

## Memory System

### Memory Banks

The Cray-1 had 16 memory banks with 4-cycle access time:

```
Bank 0: ████░░░░████░░░░████
Bank 1: ░████░░░░████░░░░███
Bank 2: ░░████░░░░████░░░░██
Bank 3: ░░░████░░░░████░░░░█
...
Bank 15: ███░░░░████░░░░████░

By cycling through banks, achieve 1 word per cycle!
```

### Stride and Bank Conflicts

**Stride 1 (contiguous):** Perfect bank utilization
```
Address:  0   1   2   3   4   5   6   7  ...
Bank:     0   1   2   3   4   5   6   7  ...
```

**Stride 16 (bank conflict!):** All accesses hit same bank
```
Address:  0  16  32  48  64  80  96 112  ...
Bank:     0   0   0   0   0   0   0   0  ... CONFLICT!
```

Programmers had to be aware of stride patterns.

---

## Instruction Set

### Vector Instructions

```assembly
; Vector load with stride
V1 = VM,A0,A1    ; Load V1 from memory[A0] with stride A1

; Vector arithmetic
V3 = V1 + V2     ; Vector add
V3 = V1 * V2     ; Vector multiply (FP)
V3 = V1 & V2     ; Vector AND

; Vector with scalar
V2 = V1 + S0     ; Add scalar to each element
V2 = V1 * S0     ; Multiply each element by scalar

; Vector mask operations
VM = V1 < V2     ; Compare, set mask bits
V3 = V1 + V2, VM ; Masked vector add

; Vector length
VL = A0          ; Set vector length (0-64)
```

### Example: DAXPY (Y = aX + Y)

The classic vector benchmark:

```assembly
; Y = a*X + Y where a is scalar, X and Y are vectors
        A0 = N           ; Vector length
        VL = A0          ; Set VL
        A1 = 1           ; Stride = 1
        A2 = &X          ; X base address
        A3 = &Y          ; Y base address
        S0 = a           ; Scalar multiplier

        V0 = ,A2,A1      ; Load X
        V1 = V0 * S0     ; V1 = a * X
        V2 = ,A3,A1      ; Load Y
        V3 = V1 + V2     ; V3 = a*X + Y  (chained!)
        ,A3,A1 = V3      ; Store Y
```

With chaining: ~80 cycles for 64 elements
Without: ~140 cycles

---

## The Iconic Design

### Physical Layout

The Cray-1's distinctive "C" shape wasn't just aesthetics:

```
        ┌─────────────────┐
       ╱                   ╲
      ╱    Main Frame       ╲
     │   (Logic modules)     │
     │                       │
     │    ┌───────────┐      │
     │    │ Power     │      │
      ╲   │ Supplies  │     ╱
       ╲  └───────────┘    ╱
        └─────────────────┘
              │ │ │
        ┌─────┴─┴─┴─────┐
        │   Freon       │
        │   Cooling     │
        └───────────────┘
```

- **Short wires**: C-shape minimized wire length
- **Dense packaging**: ECL logic in dense modules
- **Freon cooling**: 115 kW required serious cooling
- **Padded bench**: The "loveseats" housed power supplies

### Wire Length Matters

At 80 MHz, signals travel about 12 feet per cycle. Cray kept the longest wire path under 4 feet, enabling:
- Single-cycle register access
- Tight pipeline timing
- Consistent latencies

---

## Programming Model

### Vectorization

Compilers automatically vectorized loops:

```fortran
! Fortran (vectorizable)
DO I = 1, N
    C(I) = A(I) + B(I)
ENDDO

! Becomes one vector instruction!
```

### Loop Dependencies Break Vectorization

```fortran
! NOT vectorizable (loop-carried dependency)
DO I = 2, N
    A(I) = A(I-1) + B(I)    ! Each iteration depends on previous
ENDDO
```

### Strip Mining

For vectors longer than 64:

```fortran
! Original
DO I = 1, 1000
    C(I) = A(I) + B(I)
ENDDO

! Strip-mined
DO J = 1, 1000, 64           ! Outer loop, stride 64
    VL = MIN(64, 1000-J+1)   ! Set vector length
    ! Process 64 elements
ENDDO
```

---

## Legacy and Influence

### Descendants

- **Cray X-MP, Y-MP**: Multiple processors, more vectors
- **Cray-2**: 256 MW memory, immersion cooling
- **NEC SX series**: Continued vector tradition
- **Earth Simulator**: 640 vector nodes

### Modern Echoes

Vector processing lives on in:

| Modern | Cray-1 Equivalent |
|--------|-------------------|
| x86 AVX-512 | 512-bit vectors (8 doubles) |
| ARM SVE | Scalable vectors (128-2048 bits) |
| RISC-V V | Vector extension |
| GPU SIMT | Massive vector parallelism |

The Cray-1's philosophy—same operation on many data elements—remains central to high-performance computing.

---

## RHDL Implementation

See [Appendix U](appendix-u-cray1.md) for complete implementation:

```ruby
# Simplified Cray-1 vector register file
class VectorRegisterFile < SimComponent
  parameter :num_regs, default: 8
  parameter :vector_length, default: 64
  parameter :element_width, default: 64

  input :clk
  input :read_reg, width: 3
  input :write_reg, width: 3
  input :write_data, width: vector_length * element_width
  input :write_enable
  input :vl, width: 7  # Vector length register

  output :read_data, width: vector_length * element_width
end
```

---

## Summary

- **Vector registers**: 8 registers × 64 elements × 64 bits
- **Pipelined functional units**: 12 units, 1-14 stage pipelines
- **Chaining**: Results flow between units without stalling
- **Memory banking**: 16 banks hide memory latency
- **80 MHz from 1976**: Achieved through careful physical design
- **160 MFLOPS peak**: Defined supercomputing for a decade

---

## Exercises

1. Calculate DAXPY performance with and without chaining
2. Determine bank conflicts for various stride patterns
3. Implement a simple vector ALU with chaining
4. Compare Cray-1 vectors to modern AVX-512
5. Write strip-mined code for a 1000-element dot product

---

## Further Reading

- Cray, "The Cray-1 Computer System" (1976)
- Russell, "The Cray-1 Computer System" (CACM 1978)
- Dongarra, "Performance of Various Computers Using Standard Linear Equations Software"

---

*Next: [Chapter 22 - RISC-V RV32I](22-riscv.md)*

*Appendix: [Appendix U - Cray-1 Implementation](appendix-u-cray1.md)*
