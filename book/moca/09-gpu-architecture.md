# Chapter 9: GPU Architecture

## Overview

Graphics Processing Units (GPUs) evolved from specialized graphics hardware into general-purpose massively parallel processors. Their SIMD/SIMT execution model represents a distinct computational paradigm—thousands of simple threads executing the same program on different data.

## From Graphics to General Computing

### The Graphics Pipeline

GPUs originally implemented a fixed graphics pipeline:

```
Vertices → Transform → Rasterize → Shade → Pixels → Display

Each stage processes many elements in parallel:
- Thousands of vertices transformed simultaneously
- Millions of pixels shaded in parallel
```

### Programmable Shaders

The key insight: **shaders are data-parallel programs**.

```
// Vertex shader - runs once per vertex (millions of times)
void main() {
    gl_Position = mvp_matrix * vertex_position;
}

// Fragment shader - runs once per pixel (millions of times)
void main() {
    gl_FragColor = texture(sampler, uv) * lighting;
}
```

This led to **GPGPU** (General-Purpose computing on GPUs).

## The SIMD/SIMT Model

### SIMD: Single Instruction, Multiple Data

Traditional SIMD (like SSE/AVX):

```
┌─────────────────────────────────────────────────────────────┐
│                    SIMD EXECUTION                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   One instruction operates on multiple data elements:        │
│                                                              │
│   ADD v1, v2, v3     (vector add)                           │
│                                                              │
│   v1: [a0, a1, a2, a3]                                      │
│   v2: [b0, b1, b2, b3]                                      │
│   v3: [a0+b0, a1+b1, a2+b2, a3+b3]                          │
│                                                              │
│   All lanes execute the same operation simultaneously        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### SIMT: Single Instruction, Multiple Threads

NVIDIA's SIMT model extends SIMD:

```
┌─────────────────────────────────────────────────────────────┐
│                    SIMT EXECUTION                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   32 threads form a "warp" (or "wavefront" on AMD)          │
│                                                              │
│   Warp 0:  [T0, T1, T2, ... T31]                            │
│                                                              │
│   All 32 threads execute the same instruction,               │
│   but each thread has its own:                               │
│   - Program counter (can diverge!)                          │
│   - Registers                                                │
│   - Stack pointer                                            │
│                                                              │
│   Unlike SIMD, threads can branch independently              │
│   (at a performance cost)                                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Thread Divergence

The cost of flexibility:

```
// SIMT code with branch
if (threadIdx.x < 16) {
    result = compute_a();  // Threads 0-15
} else {
    result = compute_b();  // Threads 16-31
}

// Execution timeline:
// Cycle 1-10:  Threads 0-15 execute compute_a()
//              Threads 16-31 are masked (idle)
// Cycle 11-20: Threads 16-31 execute compute_b()
//              Threads 0-15 are masked (idle)

// 50% efficiency due to divergence!
```

## GPU Architecture Hierarchy

### The Streaming Multiprocessor (SM)

```
┌─────────────────────────────────────────────────────────────┐
│              STREAMING MULTIPROCESSOR (SM)                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐        │
│  │ CUDA    │  │ CUDA    │  │ CUDA    │  │ CUDA    │        │
│  │ Core 0  │  │ Core 1  │  │ Core 2  │  │ Core 3  │  ...   │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘        │
│       │           │           │           │                  │
│       └───────────┴───────────┴───────────┘                  │
│                       │                                      │
│                 Warp Scheduler                               │
│                       │                                      │
│         ┌─────────────┴─────────────┐                       │
│         │     Register File         │                       │
│         │     (65,536 x 32-bit)     │                       │
│         └─────────────┬─────────────┘                       │
│                       │                                      │
│         ┌─────────────┴─────────────┐                       │
│         │     Shared Memory         │                       │
│         │     (up to 96 KB)         │                       │
│         └───────────────────────────┘                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Full GPU Organization

```
┌─────────────────────────────────────────────────────────────┐
│                      GPU DIE                                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐          │
│  │ SM0 │ │ SM1 │ │ SM2 │ │ SM3 │ │ SM4 │ │ SM5 │  ...     │
│  └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘          │
│     └───────┴───────┴───────┴───────┴───────┘              │
│                         │                                    │
│              ┌──────────┴──────────┐                        │
│              │    L2 Cache         │                        │
│              │    (4-6 MB)         │                        │
│              └──────────┬──────────┘                        │
│                         │                                    │
│     ┌───────────────────┼───────────────────┐              │
│     │                   │                   │              │
│  ┌──┴──┐             ┌──┴──┐             ┌──┴──┐          │
│  │ MC0 │             │ MC1 │             │ MC2 │  ...      │
│  └──┬──┘             └──┬──┘             └──┬──┘          │
│     │                   │                   │              │
└─────┼───────────────────┼───────────────────┼──────────────┘
      │                   │                   │
   ┌──┴──┐             ┌──┴──┐             ┌──┴──┐
   │GDDR │             │GDDR │             │GDDR │
   └─────┘             └─────┘             └─────┘

   MC = Memory Controller
   Typical: 80+ SMs, 10,000+ CUDA cores, 24GB+ GDDR6
```

## Memory Hierarchy

### Memory Types and Latency

| Memory Type | Scope | Size | Latency | Bandwidth |
|------------|-------|------|---------|-----------|
| Registers | Thread | 255 per thread | 0 cycles | Highest |
| Shared Memory | Block | 96 KB/SM | ~20 cycles | Very High |
| L1 Cache | SM | 128 KB/SM | ~30 cycles | High |
| L2 Cache | GPU | 4-6 MB | ~200 cycles | Medium |
| Global Memory | GPU | 24+ GB | ~400 cycles | 1 TB/s |

### Memory Coalescing

Efficient memory access is critical:

```
// Coalesced access - GOOD
// Threads 0-31 access consecutive addresses
data[threadIdx.x] = value;

// Memory transaction: Single 128-byte request
// Addresses: 0, 4, 8, 12, ... 124
// All 32 threads served in ONE transaction


// Strided access - BAD
// Threads access every 32nd element
data[threadIdx.x * 32] = value;

// Memory transaction: 32 separate requests!
// Addresses: 0, 128, 256, 384, ...
// 32x more memory transactions
```

## Programming Model: CUDA

### Thread Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│                    CUDA THREAD HIERARCHY                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Grid (kernel launch)                                       │
│   └── Block 0                                               │
│       └── Warp 0: [Thread 0-31]                             │
│       └── Warp 1: [Thread 32-63]                            │
│       └── ...                                                │
│   └── Block 1                                               │
│       └── Warp 0: [Thread 0-31]                             │
│       └── ...                                                │
│   └── Block 2                                               │
│       └── ...                                                │
│                                                              │
│   Limits:                                                    │
│   - Max 1024 threads per block                              │
│   - Max 2^31-1 blocks per grid                              │
│   - Blocks execute in any order (no dependencies!)          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Simple CUDA Kernel

```c
// Vector addition kernel
__global__ void vector_add(float *a, float *b, float *c, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        c[i] = a[i] + b[i];
    }
}

// Launch: 256 threads per block, enough blocks for n elements
int blocks = (n + 255) / 256;
vector_add<<<blocks, 256>>>(a, b, c, n);
```

## GPU vs CPU Trade-offs

```
┌─────────────────────────────────────────────────────────────┐
│                    CPU vs GPU                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   CPU:                          GPU:                         │
│   ┌─────────────┐              ┌─────────────────────────┐  │
│   │ █████ Core  │              │ □ □ □ □ □ □ □ □ □ □ □ □ │  │
│   │ █████ Core  │              │ □ □ □ □ □ □ □ □ □ □ □ □ │  │
│   │             │              │ □ □ □ □ □ □ □ □ □ □ □ □ │  │
│   │ Cache/Ctrl  │              │ □ □ □ □ □ □ □ □ □ □ □ □ │  │
│   └─────────────┘              └─────────────────────────┘  │
│                                                              │
│   Few powerful cores           Many simple cores             │
│   Complex control              Simple control                │
│   Large caches                 Small caches per SM           │
│   Low latency                  High throughput               │
│   Branch prediction            Thread switching              │
│                                                              │
│   Best for: Serial code,       Best for: Parallel code,     │
│   branchy code, latency-       regular access patterns,      │
│   sensitive tasks              throughput-oriented tasks     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Connection to Other Models

### GPUs and Dataflow

GPUs share dataflow characteristics:
- **Data-driven execution**: Threads wait for data, not explicit synchronization
- **Spatial parallelism**: Thousands of threads compute simultaneously
- **Local communication**: Shared memory enables neighbor communication

### GPUs and Systolic Arrays

Modern GPUs include tensor cores that are essentially systolic arrays:

```
Tensor Core operation: D = A × B + C
- 4×4 matrix multiply-accumulate
- 64 FMAs per cycle per tensor core
- Systolic data flow within the tensor core

GPU = General SIMT + Specialized Systolic (Tensor Cores)
```

## Key Takeaways

1. **SIMT enables flexible parallelism** - Threads can diverge (at a cost)
2. **Memory hierarchy is critical** - Coalescing and shared memory determine performance
3. **Occupancy matters** - More warps hide memory latency
4. **Regular patterns win** - Irregular access patterns kill performance
5. **GPUs complement CPUs** - Each excels at different workloads
6. **Tensor cores blur the line** - Modern GPUs include systolic arrays for ML

> See [Appendix G](appendix-g-gpu.md) for RHDL implementation of a simplified streaming multiprocessor.
