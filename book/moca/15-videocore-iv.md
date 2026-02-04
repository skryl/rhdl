# Chapter 15: The VideoCore IV

## Overview

The VideoCore IV, designed by Broadcom and used in the Raspberry Pi 1/2/3, is one of the best-documented GPUs available. Its relative simplicity and open documentation make it an ideal case study for understanding GPU architecture in practice.

## Historical Context

```
Timeline:
2006: Broadcom designs VideoCore IV for mobile phones
2012: Raspberry Pi launches with BCM2835 (VideoCore IV)
2014: Broadcom releases partial documentation
2016: Community reverse-engineering fills in gaps
2019: Raspberry Pi 4 moves to VideoCore VI
```

The Raspberry Pi's educational mission led to unprecedented GPU documentation, making VideoCore IV uniquely suited for study.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    VIDEOCORE IV                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    3D Pipeline                        │   │
│  │  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐       │   │
│  │  │ PTB │→│ PSE │→│ FEP │→│ QPU │→│ TLB │       │   │
│  │  └─────┘  └─────┘  └─────┘  └─────┘  └─────┘       │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              QPU Slice (x3)                           │   │
│  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐                    │   │
│  │  │QPU0 │ │QPU1 │ │QPU2 │ │QPU3 │  (4 QPUs/slice)   │   │
│  │  └─────┘ └─────┘ └─────┘ └─────┘                    │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────┐  ┌─────────┐  ┌─────────────────────────┐     │
│  │   VPM   │  │   TMU   │  │      L2 Cache           │     │
│  │ (48 KB) │  │ (Texture│  │       (128 KB)          │     │
│  └─────────┘  │  Unit)  │  └─────────────────────────┘     │
│               └─────────┘                                    │
│                      │                                       │
│                ┌─────┴─────┐                                │
│                │  Memory   │                                │
│                │ Interface │                                │
│                └───────────┘                                │
│                                                              │
└─────────────────────────────────────────────────────────────┘

PTB = Primitive Tile Binner
PSE = Primitive Setup Engine
FEP = Front-End Pipeline
QPU = Quad Processing Unit
TLB = Tile Buffer
VPM = Vertex Pipe Memory
TMU = Texture Memory Unit
```

## The Quad Processing Unit (QPU)

The heart of VideoCore IV is the QPU - a 16-way SIMD processor:

### QPU Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SINGLE QPU                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │              Register Files                         │     │
│  │  ┌─────────────┐  ┌─────────────┐                  │     │
│  │  │ Accumulators│  │  R0-R31     │ (32 × 16 × 32b) │     │
│  │  │   r0-r5     │  │ (per-elem)  │                  │     │
│  │  └─────────────┘  └─────────────┘                  │     │
│  └────────────────────────────────────────────────────┘     │
│                                                              │
│  ┌─────────────┐     ┌─────────────┐                        │
│  │   ADD ALU   │     │   MUL ALU   │   Two ALUs!            │
│  │ (add, sub,  │     │ (mul, fmul, │                        │
│  │  logic, etc)│     │  v8 ops)    │                        │
│  └─────────────┘     └─────────────┘                        │
│         │                   │                                │
│         └─────────┬─────────┘                                │
│                   ▼                                          │
│  ┌────────────────────────────────────────────────────┐     │
│  │            16-Element Vector                        │     │
│  │   [e0][e1][e2][e3][e4][e5][e6][e7]...             │     │
│  │   [e8][e9][e10][e11][e12][e13][e14][e15]          │     │
│  └────────────────────────────────────────────────────┘     │
│                                                              │
│  Each instruction operates on 16 elements in parallel        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Key QPU Features

| Feature | Specification |
|---------|---------------|
| Vector width | 16 elements |
| Element size | 32 bits (int or float) |
| ALUs per QPU | 2 (ADD + MUL) |
| Accumulators | 6 (r0-r5) |
| General registers | 32 (A file) + 32 (B file) |
| Clock speed | 250-400 MHz |
| Peak throughput | 24 GFLOPS (all 12 QPUs) |

## Instruction Format

VideoCore IV uses a 64-bit instruction word:

```
┌─────────────────────────────────────────────────────────────┐
│                 64-bit Instruction Word                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  63    56 55    52 51    48 47    44 43          32         │
│  ┌──────┬────────┬────────┬────────┬─────────────┐         │
│  │ sig  │ unpack │ pm     │ pack   │ cond_add    │         │
│  └──────┴────────┴────────┴────────┴─────────────┘         │
│                                                              │
│  31    26 25    20 19    14 13     6 5           0         │
│  ┌──────┬────────┬────────┬────────┬─────────────┐         │
│  │op_add│ raddr_a│ raddr_b│ op_mul │ waddr_mul   │         │
│  └──────┴────────┴────────┴────────┴─────────────┘         │
│                                                              │
│  sig     = Signal bits (branch, load, etc.)                 │
│  op_add  = ADD ALU operation                                 │
│  op_mul  = MUL ALU operation                                 │
│  raddr_* = Register read addresses                           │
│  waddr_* = Register write addresses                          │
│  cond_*  = Conditional execution                             │
│  pack    = Result packing mode                               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Dual-Issue Execution

Both ALUs execute in parallel every cycle:

```
// Single instruction, dual operations
add r0, r1, r2 ; mul r3, r4, r5

// Timeline:
// Cycle 1: ADD computes r1+r2, MUL computes r4*r5
// Cycle 2: Results written to r0 and r3

// This is NOT superscalar - it's explicit dual-issue
// Programmer must schedule both operations
```

## Memory Architecture

### Vertex Pipe Memory (VPM)

The VPM is a 48KB scratchpad shared between QPUs:

```
┌─────────────────────────────────────────────────────────────┐
│                    VPM (48 KB)                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Organized as 16 × 64 × 32-bit words                  │   │
│  │                                                        │   │
│  │  Row 0:  [w0 ][w1 ][w2 ]...[w63]                      │   │
│  │  Row 1:  [w0 ][w1 ][w2 ]...[w63]                      │   │
│  │  ...                                                   │   │
│  │  Row 15: [w0 ][w1 ][w2 ]...[w63]                      │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  Access modes:                                               │
│  - Horizontal: Read/write row (64 words)                    │
│  - Vertical: Read/write column (16 words)                   │
│  - DMA: Transfer to/from main memory                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Memory Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│                  MEMORY HIERARCHY                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   QPU Registers          ~1 cycle                           │
│        │                                                     │
│        ▼                                                     │
│   Accumulators (r0-r5)   ~1 cycle                           │
│        │                                                     │
│        ▼                                                     │
│   VPM (48 KB)            ~3 cycles                          │
│        │                                                     │
│        ▼                                                     │
│   TMU Cache              ~10 cycles                         │
│        │                                                     │
│        ▼                                                     │
│   L2 Cache (128 KB)      ~50 cycles                         │
│        │                                                     │
│        ▼                                                     │
│   Main Memory (SDRAM)    ~200-400 cycles                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Programming the VideoCore IV

### Assembly Example: Vector Add

```asm
# Vector addition: C = A + B
# Each QPU processes 16 elements per iteration

.global vc4_vector_add
vc4_vector_add:
    # Load uniforms (parameters)
    mov r0, unif        # r0 = address of A
    mov r1, unif        # r1 = address of B
    mov r2, unif        # r2 = address of C
    mov r3, unif        # r3 = count / 16

    # Configure VPM for reading
    ldi vr_setup, 0x00001a00

loop:
    # Load 16 elements from A via TMU
    mov tmu0_s, r0
    add r0, r0, 64      ; advance A pointer

    # Load 16 elements from B via TMU
    mov tmu0_s, r1
    add r1, r1, 64      ; advance B pointer

    # Wait for TMU loads
    ldtmu0              # r4 = A[i:i+16]
    mov r5, r4
    ldtmu0              # r4 = B[i:i+16]

    # Add vectors
    fadd r5, r5, r4     # r5 = A + B

    # Store result to VPM
    mov vpm, r5

    # DMA write to memory
    mov vw_setup, 0x00001a00
    mov vw_addr, r2
    add r2, r2, 64      ; advance C pointer

    # Loop control
    sub r3, r3, 1
    brr.nz -, loop
    nop ; delay slot
    nop ; delay slot
    nop ; delay slot

    # Signal done
    mov irq, 1
    thrend
    nop
    nop
```

### Comparison with Modern GPUs

| Feature | VideoCore IV | NVIDIA (Modern) | Ratio |
|---------|--------------|-----------------|-------|
| SIMD width | 16 | 32 (warp) | 0.5x |
| Shader cores | 12 QPUs | 1000s of cores | ~100x |
| Memory | 256MB-1GB shared | 8-24GB dedicated | ~20x |
| Bandwidth | ~6 GB/s | ~1000 GB/s | ~170x |
| TDP | ~3W | 200-450W | ~100x |
| Transistors | ~25M | ~50B | ~2000x |

## Tile-Based Rendering

VideoCore IV uses tile-based deferred rendering (TBDR):

```
┌─────────────────────────────────────────────────────────────┐
│              TILE-BASED RENDERING                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Pass 1: Binning                                           │
│   ┌─────────────────────────────────────────────────────┐   │
│   │  Screen divided into 64x64 pixel tiles              │   │
│   │                                                      │   │
│   │  ┌────┬────┬────┬────┐                              │   │
│   │  │ T0 │ T1 │ T2 │ T3 │  Primitives sorted into     │   │
│   │  ├────┼────┼────┼────┤  per-tile lists              │   │
│   │  │ T4 │ T5 │ T6 │ T7 │                              │   │
│   │  └────┴────┴────┴────┘                              │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                              │
│   Pass 2: Rendering                                          │
│   ┌─────────────────────────────────────────────────────┐   │
│   │  Each tile rendered independently:                   │   │
│   │                                                      │   │
│   │  For each tile:                                      │   │
│   │    1. Load tile into on-chip buffer (4KB)           │   │
│   │    2. Render all primitives in tile                  │   │
│   │    3. Write completed tile to memory                 │   │
│   │                                                      │   │
│   │  Advantage: Depth buffer stays on-chip!              │   │
│   │  (Huge memory bandwidth savings)                     │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## QPU Scheduling

12 QPUs share resources through time-multiplexing:

```
┌─────────────────────────────────────────────────────────────┐
│                  QPU SCHEDULING                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   4 QPUs share one "slice" with:                            │
│   - 1 instruction fetch unit                                 │
│   - 1 TMU (texture unit)                                    │
│   - 1 SFU (special function unit)                           │
│                                                              │
│   Timeline (one slice):                                      │
│   ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐        │
│   │QPU0 │QPU1 │QPU2 │QPU3 │QPU0 │QPU1 │QPU2 │QPU3 │        │
│   └─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘        │
│   ← 4 cycles round-robin →│                                 │
│                                                              │
│   Each QPU gets 1/4 of the compute resources                │
│   But: Latency hiding through thread switching!             │
│                                                              │
│   When QPU stalls (TMU, VPM), scheduler switches            │
│   to another ready QPU                                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Special Function Unit (SFU)

The SFU handles transcendental functions:

| Function | Instruction | Latency |
|----------|-------------|---------|
| Reciprocal | `mov r0, recip(r1)` | 2 cycles |
| Reciprocal sqrt | `mov r0, rsqrt(r1)` | 2 cycles |
| Log2 | `mov r0, log2(r1)` | 2 cycles |
| Exp2 | `mov r0, exp2(r1)` | 2 cycles |

## Why VideoCore IV Matters

1. **Accessible complexity** - Complex enough to be interesting, simple enough to understand
2. **Real silicon** - Actually manufactured and deployed in millions of devices
3. **Open documentation** - Unlike most GPUs, specs are publicly available
4. **Educational value** - Demonstrates key GPU concepts without overwhelming detail
5. **GPGPU capable** - Can run compute shaders, not just graphics

## Comparison with MOS 6502

| Aspect | MOS 6502 | VideoCore IV |
|--------|----------|--------------|
| Year | 1975 | 2006 |
| Transistors | ~3,500 | ~25M |
| Architecture | Sequential | SIMD parallel |
| Registers | 3 (A, X, Y) | 64 per thread |
| Clock | 1-2 MHz | 250-400 MHz |
| Memory | 64 KB | 256MB-1GB |
| Purpose | General CPU | Graphics + compute |

Both demonstrate important principles at appropriate scales for their eras.

## Key Takeaways

1. **SIMD is explicit** - Programmer must think in 16-element vectors
2. **Dual-issue requires planning** - Must schedule both ALUs for peak performance
3. **Memory hierarchy dominates** - VPM and TMU usage critical for performance
4. **Tile-based rendering saves bandwidth** - Key innovation for mobile GPUs
5. **Thread switching hides latency** - QPUs cooperate to hide memory delays
6. **Simplicity enables understanding** - 12 QPUs is manageable to comprehend

> See [Appendix O](appendix-o-videocore.md) for RHDL implementation of a simplified QPU and assembly examples.
