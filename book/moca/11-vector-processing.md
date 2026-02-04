# Chapter 11: Vector Processing

*Single instruction, multiple data: the parallel paradigm*

---

## The Vector Philosophy

What if instead of operating on single values, your processor could operate on *entire arrays* at once?

```
Scalar Processing:
┌───────────────────────────────────────────────────────┐
│  for i = 0 to 63:                                     │
│      C[i] = A[i] + B[i]    # 64 separate operations  │
│                                                       │
│  64 instruction fetches                               │
│  64 instruction decodes                               │
│  64 executions                                        │
└───────────────────────────────────────────────────────┘

Vector Processing:
┌───────────────────────────────────────────────────────┐
│  V1 = load A[0:63]         # One instruction         │
│  V2 = load B[0:63]         # One instruction         │
│  V3 = V1 + V2              # One instruction, 64 adds│
│  store V3 -> C[0:63]       # One instruction         │
│                                                       │
│  4 instruction fetches                                │
│  4 instruction decodes                                │
│  4 executions (64 ops each)                          │
└───────────────────────────────────────────────────────┘
```

Vector processing amortizes instruction fetch/decode overhead over many data elements.

---

## Why Vectors Win

### 1. Reduced Instruction Bandwidth

```
Operation: Add two 64-element arrays

Scalar: 64 × 3 = 192 instructions (load, load, add for each)
Vector: 4 instructions total

Instruction bandwidth reduction: 48×!
```

### 2. Predictable Memory Access

```
Vector memory access:
  Address:  0   1   2   3   4   5   6   7  ...
            ↓   ↓   ↓   ↓   ↓   ↓   ↓   ↓
           [A0][A1][A2][A3][A4][A5][A6][A7]...

  - Sequential, strided, or gather/scatter
  - Highly prefetchable
  - Memory system knows what's coming
```

### 3. Deep Pipelining

```
Vector pipeline for 8-element vector add:

Cycle:  1   2   3   4   5   6   7   8   9   10  11  12
───────────────────────────────────────────────────────
e0:    [F1][F2][F3][ADD][WB]
e1:        [F1][F2][F3][ADD][WB]
e2:            [F1][F2][F3][ADD][WB]
e3:                [F1][F2][F3][ADD][WB]
e4:                    [F1][F2][F3][ADD][WB]
e5:                        [F1][F2][F3][ADD][WB]
e6:                            [F1][F2][F3][ADD][WB]
e7:                                [F1][F2][F3][ADD][WB]

Pipeline always full! One result per cycle after startup.
```

### 4. No Data Hazards

Each element is independent—no inter-element dependencies:

```
V3 = V1 + V2

V1: [a₀][a₁][a₂][a₃]...    Independent!
    +   +   +   +
V2: [b₀][b₁][b₂][b₃]...    Each addition
    =   =   =   =          can proceed
V3: [c₀][c₁][c₂][c₃]...    in parallel
```

---

## Vector Architecture Components

### Vector Registers

```
┌─────────────────────────────────────────┐
│          Vector Register File           │
├─────────────────────────────────────────┤
│                                         │
│  V0: [e0][e1][e2]...[eN-1]             │
│  V1: [e0][e1][e2]...[eN-1]             │
│  V2: [e0][e1][e2]...[eN-1]             │
│  ...                                    │
│  Vn: [e0][e1][e2]...[eN-1]             │
│                                         │
│  Typical: 8-32 registers               │
│  Elements per register: 64-2048        │
│  Element width: 32 or 64 bits          │
│                                         │
└─────────────────────────────────────────┘
```

### Vector Length Register

Not all vectors are the same length. The **vector length (VL)** register controls how many elements to process:

```
VL = 10   (only process first 10 elements)

V3 = V1 + V2

V1: [a0][a1][a2][a3][a4][a5][a6][a7][a8][a9][--][--][--]...
     +   +   +   +   +   +   +   +   +   +
V2: [b0][b1][b2][b3][b4][b5][b6][b7][b8][b9][--][--][--]...
     =   =   =   =   =   =   =   =   =   =
V3: [c0][c1][c2][c3][c4][c5][c6][c7][c8][c9][unchanged]...
         ▲
         └── Only 10 elements processed
```

### Vector Mask Register

Conditional operations use a **mask register** to enable/disable elements:

```
Mask: [1][1][0][1][0][1][1][0]

V3 = V1 + V2, masked

V1: [a0][a1][a2][a3][a4][a5][a6][a7]
V2: [b0][b1][b2][b3][b4][b5][b6][b7]
V3: [c0][c1][--][c3][--][c5][c6][--]
          ▲        ▲              ▲
          └────────┴──────────────┴── Elements with mask=0 unchanged
```

### Functional Units

Vector processors have **pipelined functional units** operating on element streams:

```
┌─────────────────────────────────────────────────────────┐
│              Vector Functional Units                      │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │
│  │ Vector Add  │  │ Vector Mul  │  │ Vector Div  │      │
│  │  Pipeline   │  │  Pipeline   │  │  Pipeline   │      │
│  │  (6 stages) │  │  (7 stages) │  │ (14 stages) │      │
│  └─────────────┘  └─────────────┘  └─────────────┘      │
│                                                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │
│  │   Logical   │  │    Shift    │  │    Load/    │      │
│  │  (AND,OR)   │  │             │  │    Store    │      │
│  │  (2 stages) │  │  (4 stages) │  │  (memory)   │      │
│  └─────────────┘  └─────────────┘  └─────────────┘      │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

---

## Vector Chaining

The key to high performance: **chaining** allows the result of one vector operation to flow directly into another.

### Without Chaining

```
V2 = V0 * V1      # Wait for ALL 64 results
V4 = V2 + V3      # Then start addition

Timeline:
        Multiply all 64 elements
        ├───────────────────────────────┤
                                         Add all 64 elements
                                         ├───────────────────────────────┤

Total: (7 + 64) + (6 + 64) = 141 cycles
```

### With Chaining

```
V2 = V0 * V1      # Element 0 result ready at cycle 7
V4 = V2 + V3      # Element 0 add starts at cycle 8!

Timeline:
        Multiply
        ├───────────────────────────────────────┤
              Add (starts when first mul result ready)
              ├───────────────────────────────────────┤

Total: 7 + 6 + 64 = 77 cycles  (nearly 2× faster!)
```

Detailed chaining operation:

```
Cycle:  1  2  3  4  5  6  7  8  9  10 11 12 13 14 ...
Mult:   e0────────────────▶e0
             e1────────────────▶e1
                  e2────────────────▶e2
Add:                          e0────────▶e0
                                   e1────────▶e1
                                        e2────────▶e2

Results from multiply chain directly into add!
```

---

## Memory System

### Memory Banking

Vector loads require high bandwidth. **Memory banking** enables one element per cycle:

```
Without banking (single port):
  Cycle 1: Read A[0]
  Cycle 2: Read A[1]
  Cycle 3: Read A[2]
  ...
  64 cycles for 64 elements

With 16 banks (interleaved):
  Bank 0:  A[0], A[16], A[32], A[48]
  Bank 1:  A[1], A[17], A[33], A[49]
  Bank 2:  A[2], A[18], A[34], A[50]
  ...

  Access pattern (stride 1):
  Cycle 1: Bank 0 → A[0]
  Cycle 2: Bank 1 → A[1]
  Cycle 3: Bank 2 → A[2]
  ...

  1 word per cycle from different banks!
```

### Bank Conflicts

Certain stride patterns cause **bank conflicts**:

```
16 banks, stride 1 (optimal):
  Address:  0   1   2   3   4   5  ...
  Bank:     0   1   2   3   4   5  ...  ← No conflicts

Stride 16 (terrible):
  Address:  0  16  32  48  64  80  ...
  Bank:     0   0   0   0   0   0  ...  ← All same bank!

Stride 16 means 16× slowdown (all accesses serialized)
```

### Stride Support

Vector memory instructions support arbitrary strides:

```
; Load with stride
V1 = memory[base], stride

Examples:
  stride = 1:  Load contiguous elements
  stride = N:  Load every Nth element (column of matrix)
  stride = 0:  Load same element to all (broadcast)
```

---

## Vector Instruction Types

### Arithmetic Operations

```
V3 = V1 + V2      ; Vector-vector add
V3 = V1 * V2      ; Vector-vector multiply
V3 = V1 + S0      ; Vector-scalar add (scalar broadcast)
V3 = V1 * S0      ; Vector-scalar multiply
V3 = -V1          ; Vector negate
V3 = abs(V1)      ; Vector absolute value
```

### Comparison and Mask Operations

```
VM = V1 < V2      ; Compare, set mask bits
VM = V1 == V2     ; Equality compare
V3 = V1 + V2, VM  ; Masked operation
V3 = merge(V1, V2, VM)  ; Select elements by mask
```

### Reduction Operations

```
S0 = sum(V1)      ; Sum all elements to scalar
S0 = max(V1)      ; Maximum element
S0 = min(V1)      ; Minimum element
S0 = product(V1)  ; Product of all elements
```

### Memory Operations

```
V1 = load [A0], stride    ; Strided load
store V1 -> [A0], stride  ; Strided store
V1 = gather [A0], Vi      ; Indexed load (scatter/gather)
scatter V1 -> [A0], Vi    ; Indexed store
```

---

## Programming for Vectors

### Vectorizable Loops

```fortran
! Easily vectorizable (no dependencies)
DO I = 1, N
    C(I) = A(I) + B(I)
ENDDO

! Compiler generates:
! V1 = load A
! V2 = load B
! V3 = V1 + V2
! store V3 -> C
```

### Non-Vectorizable Loops

```fortran
! NOT vectorizable (loop-carried dependency)
DO I = 2, N
    A(I) = A(I-1) + B(I)    ! Each iteration depends on previous
ENDDO

! Element I needs result from element I-1
! Cannot run in parallel
```

### Strip Mining

For vectors longer than the hardware vector length:

```fortran
! Original: N = 1000 elements
DO I = 1, 1000
    C(I) = A(I) + B(I)
ENDDO

! Strip-mined (VL_max = 64):
DO J = 1, 1000, 64           ! Process in chunks of 64
    VL = MIN(64, 1000-J+1)   ! Handle remainder
    V1 = load A[J:J+VL-1]
    V2 = load B[J:J+VL-1]
    V3 = V1 + V2
    store V3 -> C[J:J+VL-1]
ENDDO
```

---

## Classic Example: DAXPY

The DAXPY operation (`Y = a*X + Y`) is the classic vector benchmark:

```
; Y = a*X + Y where a is scalar, X and Y are vectors
        VL = N           ; Set vector length
        V0 = load X      ; Load X vector
        V1 = V0 * S0     ; V1 = a * X (S0 = scalar a)
        V2 = load Y      ; Load Y vector
        V3 = V1 + V2     ; V3 = a*X + Y  (chained!)
        store V3 -> Y    ; Store result

With chaining:
  ~80 cycles for 64 elements

Without chaining:
  ~140 cycles for 64 elements
```

---

## Vector vs. SIMD

Modern CPUs use **SIMD** (Single Instruction Multiple Data), which is related but different:

```
Traditional Vector (variable length):
┌────────────────────────────────────────────────────────┐
│  VL register controls active elements (1 to max)       │
│  V0: [e0][e1][e2]...[eVL-1][unused][unused]...       │
│                                                        │
│  Vector length can vary at runtime                     │
└────────────────────────────────────────────────────────┘

SIMD (fixed width):
┌────────────────────────────────────────────────────────┐
│  Fixed 128/256/512-bit registers                       │
│  XMM0: [e0][e1][e2][e3]  (4 × 32-bit, always 4)      │
│                                                        │
│  Must use different instructions for different widths  │
└────────────────────────────────────────────────────────┘
```

Key differences:

| Feature | Vector | SIMD |
|---------|--------|------|
| Length | Variable (VL register) | Fixed (instruction-specific) |
| Strip mining | Hardware handles | Software must loop |
| Memory access | Strided, gather/scatter | Usually contiguous |
| Chaining | Yes | No (register-to-register) |
| Predication | Mask register | Recent: AVX-512 masking |

### Modern Scalable Vectors

ARM SVE and RISC-V V bring back variable-length vectors:

```
ARM SVE:
  - Vector length determined by hardware (128-2048 bits)
  - Same binary runs on different implementations
  - Predicate registers for masking

RISC-V V:
  - Scalable vector extension
  - LMUL: multiply effective vector length
  - Rich predication support
```

---

## Historical Impact

Vector processing defined supercomputing for decades:

| Era | Systems | Vector Length |
|-----|---------|---------------|
| 1970s | Cray-1, STAR-100 | 64-128 |
| 1980s | Cray X-MP, Cray-2 | 64-128 |
| 1990s | Cray T90, NEC SX | 64-256 |
| 2000s | Earth Simulator, SX-6 | 256+ |
| 2010s+ | Modern SIMD (AVX-512) | 8-16 |

> See [Chapter 29 - The Cray-1](29-cray1.md) for a detailed case study of the machine that defined vector processing.

---

## RHDL Implementation

See [Appendix K](appendix-k-vector.md) for complete implementation:

```ruby
# Simplified vector register file
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

# Vector ALU with chaining support
class VectorALU < SimComponent
  parameter :vector_length, default: 64
  parameter :element_width, default: 64
  parameter :pipeline_depth, default: 6

  input :clk
  input :op, width: 4
  input :a, width: vector_length * element_width
  input :b, width: vector_length * element_width
  input :vl, width: 7
  input :mask, width: vector_length

  output :result, width: vector_length * element_width
  output :chain_out, width: element_width  # For chaining
  output :chain_valid
end
```

---

## Summary

- **Vector registers**: Wide registers holding multiple elements
- **Vector length**: Variable-length operations via VL register
- **Masking**: Conditional per-element execution
- **Chaining**: Bypass network between functional units
- **Memory banking**: High bandwidth through interleaving
- **Stride support**: Flexible memory access patterns
- **Pipelining**: Deep pipelines, one result per cycle
- **Amortization**: One instruction, many operations

---

## Exercises

1. Calculate DAXPY performance with and without chaining
2. Determine bank conflicts for various stride patterns
3. Implement a vector ALU element lane
4. Design a chaining controller
5. Write strip-mined code for a 1000-element dot product
6. Compare vector masks vs. if-conversion for conditional code

---

## Further Reading

- Hennessy & Patterson, "Computer Architecture: A Quantitative Approach" (Vector chapter)
- "Vector Processing" in IEEE Micro retrospectives
- ARM SVE and RISC-V V extension specifications

---

*Previous: [Chapter 10 - Wafer-Scale Computing](10-wafer-scale.md)*

*Next: [Chapter 12 - Stochastic Computing](12-stochastic-computing.md)*

*Appendix: [Appendix K - Vector Implementation](appendix-k-vector.md)*
