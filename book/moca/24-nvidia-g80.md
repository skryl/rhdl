# Chapter 24: The NVIDIA G80

*The GPU That Launched the GPGPU Revolution (2006)*

---

## Introduction

In November 2006, NVIDIA released the GeForce 8800 GTX, powered by the G80 architecture. This wasn't just another graphics card—it was the first GPU designed from the ground up with general-purpose computing in mind. The G80 introduced **unified shaders**, replacing the separate vertex and pixel shader units of previous generations with a single, flexible streaming multiprocessor design.

More importantly, the G80 was the first GPU to support **CUDA** (Compute Unified Device Architecture), NVIDIA's parallel computing platform that would transform GPUs from specialized graphics processors into general-purpose parallel computers.

```
+------------------------------------------------------------------+
|                         NVIDIA G80                                |
|                    (GeForce 8800 GTX, 2006)                       |
+------------------------------------------------------------------+
|                                                                   |
|   +-----------------------------------------------------------+   |
|   |                    Thread Processor Array                  |   |
|   |  +-------+  +-------+  +-------+  +-------+  +-------+    |   |
|   |  |  TPC  |  |  TPC  |  |  TPC  |  |  TPC  |  |  TPC  |    |   |
|   |  +-------+  +-------+  +-------+  +-------+  +-------+    |   |
|   |  +-------+  +-------+  +-------+                          |   |
|   |  |  TPC  |  |  TPC  |  |  TPC  |     (8 TPCs total)       |   |
|   |  +-------+  +-------+  +-------+                          |   |
|   +-----------------------------------------------------------+   |
|                              |                                    |
|   +-----------------------------------------------------------+   |
|   |                    L2 Cache (256 KB)                       |   |
|   +-----------------------------------------------------------+   |
|                              |                                    |
|   +--------+  +--------+  +--------+  +--------+  +--------+      |
|   | DRAM 0 |  | DRAM 1 |  | DRAM 2 |  | DRAM 3 |  | DRAM 4 |      |
|   +--------+  +--------+  +--------+  +--------+  +--------+      |
|                    384-bit Memory Interface                       |
|                        (86.4 GB/s)                                |
+------------------------------------------------------------------+
```

---

## Historical Context

### Before G80: The Fixed-Function Era

Prior to the G80, GPUs had separate, specialized units:

- **Vertex Shaders**: Transform 3D vertices, compute lighting
- **Pixel Shaders**: Calculate final pixel colors, texturing
- **Fixed-Function Units**: Rasterization, triangle setup

This separation created **load imbalancing**. A vertex-heavy scene would leave pixel shaders idle, and vice versa. The G80 solved this with **unified shaders**—a pool of identical processors that could execute either vertex or pixel programs.

### The Birth of GPGPU

Before CUDA, researchers used **graphics APIs** (OpenGL, DirectX) to perform general computation:

1. Encode data as textures
2. Write "shaders" that computed on pixels
3. Read results back from framebuffer

This was awkward and limited. CUDA provided a proper programming model:

```c
// CUDA kernel - runs on thousands of threads
__global__ void vectorAdd(float *a, float *b, float *c, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        c[i] = a[i] + b[i];
    }
}
```

---

## Architecture Overview

### The Streaming Multiprocessor (SM)

The G80 organized computation around **Streaming Multiprocessors**, each containing:

```
+--------------------------------------------------+
|                Streaming Multiprocessor           |
+--------------------------------------------------+
|  +--------------------------------------------+  |
|  |           Instruction Cache                |  |
|  +--------------------------------------------+  |
|                      |                           |
|  +--------------------------------------------+  |
|  |              MT Issue                       |  |
|  |    (Multithreaded Instruction Unit)        |  |
|  +--------------------------------------------+  |
|       |         |         |         |            |
|  +--------+ +--------+ +--------+ +--------+     |
|  |  SP 0  | |  SP 1  | |  SP 2  | |  SP 3  |     |
|  +--------+ +--------+ +--------+ +--------+     |
|  +--------+ +--------+ +--------+ +--------+     |
|  |  SP 4  | |  SP 5  | |  SP 6  | |  SP 7  |     |
|  +--------+ +--------+ +--------+ +--------+     |
|       (8 Streaming Processors per SM)            |
|                                                  |
|  +--------------------------------------------+  |
|  |     Shared Memory / L1 Cache (16 KB)       |  |
|  +--------------------------------------------+  |
|  +--------------------------------------------+  |
|  |         Register File (8192 x 32-bit)      |  |
|  +--------------------------------------------+  |
+--------------------------------------------------+
```

**Key specifications per SM:**
- 8 Streaming Processors (SP) - scalar ALUs
- 2 Special Function Units (SFU) - transcendentals
- 16 KB shared memory (software-managed cache)
- 8192 32-bit registers
- Up to 768 threads resident

### Texture Processor Clusters (TPC)

Two SMs were grouped into a **Texture Processor Cluster**:

```
+------------------------------------------+
|        Texture Processor Cluster          |
+------------------------------------------+
|  +----------------+  +----------------+   |
|  |      SM 0      |  |      SM 1      |   |
|  |   (8 SPs)      |  |   (8 SPs)      |   |
|  +----------------+  +----------------+   |
|           |                  |            |
|  +------------------------------------+   |
|  |        Texture Unit                |   |
|  |   (filtering, addressing)          |   |
|  +------------------------------------+   |
|           |                               |
|  +------------------------------------+   |
|  |        Texture Cache (L1)          |   |
|  +------------------------------------+   |
+------------------------------------------+
```

The full G80 had **8 TPCs = 16 SMs = 128 SPs**.

---

## The SIMT Execution Model

### Single Instruction, Multiple Threads

The G80 introduced **SIMT** (Single Instruction, Multiple Threads), distinct from traditional SIMD:

| Aspect | SIMD | SIMT |
|--------|------|------|
| Programming | Explicit vectors | Scalar threads |
| Divergence | Not allowed | Hardware handles |
| Memory | Uniform access | Per-thread addresses |
| Abstraction | Low-level | High-level |

### Warps: The Unit of Execution

Threads are grouped into **warps** of 32 threads:

```
+--------------------------------------------------+
|                      Warp                         |
|   (32 threads executing same instruction)         |
+--------------------------------------------------+
| T0  T1  T2  T3  T4  T5  T6  T7  ... T30 T31      |
|  |   |   |   |   |   |   |   |       |   |       |
|  v   v   v   v   v   v   v   v       v   v       |
| [ADD R1, R2, R3] executed by all 32 threads      |
+--------------------------------------------------+
```

All 32 threads in a warp execute the **same instruction**, but on different data. This is SIMD at the hardware level, but the programmer writes scalar code.

### Branch Divergence

When threads in a warp take different paths:

```c
if (threadIdx.x < 16) {
    // Path A
} else {
    // Path B
}
```

The hardware **serializes** execution:

```
Cycle 1-4:   Threads 0-15 execute Path A (16-31 masked)
Cycle 5-8:   Threads 16-31 execute Path B (0-15 masked)
```

Divergence reduces parallelism but maintains correctness.

---

## Memory Hierarchy

### Global Memory

The G80 had 768 MB of GDDR3 memory with 86.4 GB/s bandwidth:

```
+------------------+
|   Global Memory  |
|    (768 MB)      |
+------------------+
        |
   384-bit bus
   (6 channels)
        |
+------------------+
|    L2 Cache      |
|    (256 KB)      |
+------------------+
```

### Shared Memory

Each SM had 16 KB of **shared memory**—fast, software-managed scratchpad:

```c
__shared__ float tile[16][16];

// Load from global to shared (coalesced)
tile[threadIdx.y][threadIdx.x] = input[globalIdx];

__syncthreads();  // Barrier

// Compute using shared memory (fast)
float sum = 0;
for (int k = 0; k < 16; k++) {
    sum += tile[threadIdx.y][k] * weights[k];
}
```

Shared memory enabled **data reuse** without going to slow global memory.

### Memory Coalescing

The G80 required **coalesced** memory access for performance:

```
Good (coalesced):
Thread 0 → Address 0
Thread 1 → Address 4
Thread 2 → Address 8
...
→ Single memory transaction

Bad (strided):
Thread 0 → Address 0
Thread 1 → Address 128
Thread 2 → Address 256
...
→ 32 separate transactions!
```

This constraint shaped CUDA programming patterns for years.

---

## CUDA Programming Model

### Thread Hierarchy

CUDA introduced a hierarchical thread organization:

```
+--------------------------------------------------+
|                       Grid                        |
|  +------------+  +------------+  +------------+   |
|  |   Block    |  |   Block    |  |   Block    |   |
|  |  (0,0)     |  |  (1,0)     |  |  (2,0)     |   |
|  +------------+  +------------+  +------------+   |
|  +------------+  +------------+  +------------+   |
|  |   Block    |  |   Block    |  |   Block    |   |
|  |  (0,1)     |  |  (1,1)     |  |  (2,1)     |   |
|  +------------+  +------------+  +------------+   |
+--------------------------------------------------+

Each Block:
+------------------------------------------+
|  T(0,0) T(1,0) T(2,0) ... T(15,0)        |
|  T(0,1) T(1,1) T(2,1) ... T(15,1)        |
|  ...                                      |
|  T(0,15) T(1,15) T(2,15) ... T(15,15)    |
+------------------------------------------+
```

- **Grid**: All blocks for a kernel launch
- **Block**: Threads that can synchronize and share memory
- **Thread**: Individual execution unit

### Kernel Example: Matrix Multiply

```c
__global__ void matmul(float *A, float *B, float *C, int N) {
    // Shared memory tiles
    __shared__ float As[TILE][TILE];
    __shared__ float Bs[TILE][TILE];

    int row = blockIdx.y * TILE + threadIdx.y;
    int col = blockIdx.x * TILE + threadIdx.x;
    float sum = 0.0f;

    // Loop over tiles
    for (int t = 0; t < N/TILE; t++) {
        // Collaborative load into shared memory
        As[threadIdx.y][threadIdx.x] = A[row * N + t*TILE + threadIdx.x];
        Bs[threadIdx.y][threadIdx.x] = B[(t*TILE + threadIdx.y) * N + col];

        __syncthreads();

        // Compute partial dot product
        for (int k = 0; k < TILE; k++) {
            sum += As[threadIdx.y][k] * Bs[k][threadIdx.x];
        }

        __syncthreads();
    }

    C[row * N + col] = sum;
}
```

---

## RHDL Implementation

### Streaming Processor

```ruby
class StreamingProcessor < RHDL::Component
  input :clk
  input :enable
  input :opcode, width: 4
  input :src_a, width: 32
  input :src_b, width: 32
  output :result, width: 32
  output :valid

  OPCODES = {
    ADD:  0x0, SUB:  0x1, MUL:  0x2,
    AND:  0x3, OR:   0x4, XOR:  0x5,
    SHL:  0x6, SHR:  0x7, MIN:  0x8,
    MAX:  0x9, ABS:  0xA, NEG:  0xB
  }

  behavior do
    on posedge(:clk) do
      if enable
        result <= case opcode
          when OPCODES[:ADD] then src_a + src_b
          when OPCODES[:SUB] then src_a - src_b
          when OPCODES[:MUL] then src_a * src_b
          when OPCODES[:AND] then src_a & src_b
          when OPCODES[:OR]  then src_a | src_b
          when OPCODES[:XOR] then src_a ^ src_b
          when OPCODES[:SHL] then src_a << src_b[4:0]
          when OPCODES[:SHR] then src_a >> src_b[4:0]
          when OPCODES[:MIN] then (src_a < src_b) ? src_a : src_b
          when OPCODES[:MAX] then (src_a > src_b) ? src_a : src_b
          else 0
        end
        valid <= 1
      else
        valid <= 0
      end
    end
  end
end
```

### Warp Scheduler

```ruby
class WarpScheduler < RHDL::Component
  WARP_COUNT = 24
  WARP_SIZE = 32

  input :clk
  input :reset
  input :warp_ready, width: WARP_COUNT  # Bitmask of ready warps
  input :stall, width: WARP_COUNT       # Bitmask of stalled warps
  output :selected_warp, width: 5       # Current warp ID
  output :warp_valid

  wire :eligible, width: WARP_COUNT
  wire :priority_warp, width: 5

  behavior do
    # Eligible = ready AND NOT stalled
    eligible <= warp_ready & ~stall

    on posedge(:clk) do
      if reset
        selected_warp <= 0
        warp_valid <= 0
      else
        if eligible != 0
          # Round-robin among eligible warps
          found = false
          (0...WARP_COUNT).each do |i|
            warp_id = (selected_warp + 1 + i) % WARP_COUNT
            if eligible[warp_id] && !found
              selected_warp <= warp_id
              warp_valid <= 1
              found = true
            end
          end
        else
          warp_valid <= 0
        end
      end
    end
  end
end
```

### Simplified SM

```ruby
class StreamingMultiprocessor < RHDL::Component
  SP_COUNT = 8
  WARP_SIZE = 32

  input :clk
  input :reset
  input :instruction, width: 64
  input :instruction_valid
  output :busy

  # 8 Streaming Processors
  (0...SP_COUNT).each do |i|
    instance :"sp#{i}", StreamingProcessor
  end

  instance :scheduler, WarpScheduler
  instance :register_file, RegisterFile, depth: 8192, width: 32
  instance :shared_mem, SharedMemory, size: 16384  # 16 KB

  # Connect clock to all units
  (0...SP_COUNT).each do |i|
    port :clk => [:"sp#{i}", :clk]
  end
  port :clk => [:scheduler, :clk]
  port :clk => [:register_file, :clk]
  port :clk => [:shared_mem, :clk]

  behavior do
    # Instruction decode and dispatch
    on posedge(:clk) do
      if instruction_valid
        opcode = instruction[63:60]
        dst = instruction[59:50]
        src_a = instruction[49:40]
        src_b = instruction[39:30]

        # Issue to all 8 SPs (handles 8 of 32 threads per cycle)
        # Full warp completes in 4 cycles
      end
    end
  end
end
```

---

## Performance Characteristics

### G80 Specifications

| Feature | Value |
|---------|-------|
| Streaming Processors | 128 |
| Texture Units | 32 |
| Memory | 768 MB GDDR3 |
| Memory Bandwidth | 86.4 GB/s |
| Peak FP32 | 518 GFLOPS |
| TDP | 185W |
| Transistors | 681 million |
| Process | 90nm |

### Theoretical vs. Achieved Performance

```
Matrix Multiply (1024x1024 FP32):
  Theoretical: 518 GFLOPS
  Achieved:    ~350 GFLOPS (68% efficiency)

  Bottleneck: Memory bandwidth
  Solution: Tiled algorithm with shared memory
```

---

## Legacy and Impact

### The GPGPU Revolution

The G80 enabled entirely new applications:

1. **Scientific Computing**: Molecular dynamics, CFD, weather
2. **Machine Learning**: Neural network training (later)
3. **Cryptocurrency**: Bitcoin mining (2009+)
4. **Image Processing**: Real-time video encoding

### Architectural Descendants

The G80's ideas live on:

| Generation | Year | Key Addition |
|------------|------|--------------|
| G80 (Tesla) | 2006 | CUDA, unified shaders |
| GT200 | 2008 | Double precision |
| Fermi | 2010 | L1/L2 cache, ECC |
| Kepler | 2012 | Dynamic parallelism |
| Maxwell | 2014 | Energy efficiency |
| Pascal | 2016 | NVLink, HBM2 |
| Volta | 2017 | Tensor cores |
| Ampere | 2020 | Sparse tensor cores |
| Hopper | 2022 | Transformer engine |

---

## Comparison with Other Architectures

| Feature | G80 | Modern GPU | TPU v1 |
|---------|-----|------------|--------|
| Parallelism | SIMT | SIMT | Systolic |
| Programmability | High | High | Low |
| Memory Model | Explicit | Unified | Weight-stationary |
| Use Case | General | General | Inference |

---

## Key Insights

1. **Unified shaders** eliminated load imbalancing and enabled GPGPU
2. **SIMT** provides SIMD efficiency with scalar programming
3. **Shared memory** enables programmer-controlled caching
4. **Warp-based execution** amortizes control overhead
5. **Memory coalescing** is critical for bandwidth utilization
6. **Thread hierarchy** maps naturally to hardware resources

The G80 proved that GPUs could be general-purpose parallel processors. Every modern GPU, from gaming cards to AI accelerators, traces its lineage back to this 2006 breakthrough.

---

## Further Reading

- [NVIDIA CUDA Programming Guide](https://docs.nvidia.com/cuda/)
- "NVIDIA Tesla: A Unified Graphics and Computing Architecture" (IEEE Micro, 2008)
- "Programming Massively Parallel Processors" by Kirk & Hwu

---

## Appendix Reference

See [Appendix I - GPU Implementation](appendix-i-gpu.md) for complete RHDL implementations of SM components, warp schedulers, and memory systems.

---

[← Previous: The Transputer](23-transputer.md) | [Index](INDEX.md) | [Next: The RISC-V RV32I →](25-riscv.md)
