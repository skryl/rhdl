# Chapter 17: The TPU v1

## Overview

Google's Tensor Processing Unit (TPU) v1, deployed in 2015, is a purpose-built ASIC for neural network inference. Its architecture is remarkably simple: at its core is a massive 256×256 systolic array that performs matrix multiplications—the dominant operation in neural networks.

## Why Build a TPU?

In 2013, Google realized that if everyone used voice search for 3 minutes/day, they'd need to double their data center capacity just for neural network inference. CPUs and GPUs were too expensive and power-hungry.

```
┌─────────────────────────────────────────────────────────────┐
│              THE INFERENCE CRISIS                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Voice search (2013):                                       │
│   - Deep neural network for speech recognition              │
│   - ~100ms latency requirement                               │
│   - Millions of users                                        │
│                                                              │
│   Problem: 3 minutes/day × all users = 2× data centers!     │
│                                                              │
│   Solution: Custom ASIC optimized for one thing:            │
│             Matrix multiplication                            │
│                                                              │
│   Result: 15-30× better perf/watt than GPU                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                       TPU v1                                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Host Interface (PCIe Gen3 x16)                             │
│         │                                                    │
│         ▼                                                    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Weight FIFO (4 MB)                      │    │
│  │         (Double-buffered weight staging)             │    │
│  └─────────────────────┬───────────────────────────────┘    │
│                        │                                     │
│                        ▼                                     │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                                                      │    │
│  │              256 × 256 Systolic Array               │    │
│  │                                                      │    │
│  │    ┌───┬───┬───┬───┬───┬───┬───┬───┐              │    │
│  │    │MAC│MAC│MAC│MAC│MAC│MAC│MAC│MAC│ ...          │    │
│  │    ├───┼───┼───┼───┼───┼───┼───┼───┤              │    │
│  │    │MAC│MAC│MAC│MAC│MAC│MAC│MAC│MAC│              │    │
│  │    ├───┼───┼───┼───┼───┼───┼───┼───┤   256 rows   │    │
│  │    │MAC│MAC│MAC│MAC│MAC│MAC│MAC│MAC│              │    │
│  │    ├───┼───┼───┼───┼───┼───┼───┼───┤              │    │
│  │    │   │   │   │   │   │   │   │   │ ...          │    │
│  │    └───┴───┴───┴───┴───┴───┴───┴───┘              │    │
│  │                256 columns                          │    │
│  │                                                      │    │
│  │    65,536 MACs = 256 × 256                         │    │
│  │                                                      │    │
│  └─────────────────────┬───────────────────────────────┘    │
│                        │                                     │
│                        ▼                                     │
│  ┌─────────────────────────────────────────────────────┐    │
│  │           Accumulators (256 × 32-bit)               │    │
│  └─────────────────────┬───────────────────────────────┘    │
│                        │                                     │
│                        ▼                                     │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Activation Unit                         │    │
│  │         (ReLU, Sigmoid, Tanh, etc.)                 │    │
│  └─────────────────────┬───────────────────────────────┘    │
│                        │                                     │
│                        ▼                                     │
│  ┌─────────────────────────────────────────────────────┐    │
│  │         Unified Buffer (24 MB SRAM)                 │    │
│  │    (Stores activations between layers)              │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## The Systolic Array

The heart of TPU v1 is a weight-stationary systolic array:

```
┌─────────────────────────────────────────────────────────────┐
│            WEIGHT-STATIONARY SYSTOLIC ARRAY                  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Weights are loaded ONCE, activations flow through:        │
│                                                              │
│   Activations →                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │    w00    w01    w02    w03                          │   │
│   │  ┌─────┬─────┬─────┬─────┐                          │   │
│   │  │a0×w0│→    │→    │→    │→ partial sum             │   │
│ W │  │  +  │     │     │     │                          │   │
│ e │  ├─────┼─────┼─────┼─────┤                          │   │
│ i │  │  ↓  │a1×w1│→    │→    │→                         │   │
│ g │  │     │  +  │     │     │                          │   │
│ h │  ├─────┼─────┼─────┼─────┤                          │   │
│ t │  │     │  ↓  │a2×w2│→    │→                         │   │
│ s │  │     │     │  +  │     │                          │   │
│   │  ├─────┼─────┼─────┼─────┤                          │   │
│ ↓ │  │     │     │  ↓  │a3×w3│→ output                  │   │
│   │  └─────┴─────┴─────┴─────┘                          │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                              │
│   Each cycle:                                                │
│   - Activations shift right                                 │
│   - Partial sums shift down                                 │
│   - MACs compute: acc += activation × weight                │
│                                                              │
│   After 256 cycles: All matrix elements computed            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Why Weight-Stationary?

```
┌─────────────────────────────────────────────────────────────┐
│              DATA FLOW COMPARISON                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Weight-Stationary (TPU v1):                               │
│   - Weights loaded once, stay in place                      │
│   - Activations stream through                              │
│   - Best for: Batch inference (same weights, many inputs)   │
│                                                              │
│   Output-Stationary:                                         │
│   - Outputs accumulate in place                             │
│   - Weights and activations stream through                  │
│   - Best for: Training (need to accumulate gradients)       │
│                                                              │
│   Input-Stationary:                                          │
│   - Inputs stay in place                                    │
│   - Weights stream through                                   │
│   - Best for: Convolutions (reuse input activations)        │
│                                                              │
│   TPU v1 chose weight-stationary because:                   │
│   - Inference only (weights don't change)                   │
│   - Large batches amortize weight loading                   │
│   - Simpler control logic                                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Data Types

TPU v1 uses 8-bit integers for efficiency:

```
┌─────────────────────────────────────────────────────────────┐
│                   QUANTIZATION                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Training: FP32 (32-bit floating point)                    │
│   Inference: INT8 (8-bit integer)                           │
│                                                              │
│   Why INT8 works:                                           │
│   - Neural networks are robust to quantization noise        │
│   - 8-bit enough for ~1% accuracy loss                      │
│   - 4× less memory, 4× more throughput                      │
│                                                              │
│   Quantization formula:                                      │
│   int8_value = round(float_value / scale + zero_point)      │
│                                                              │
│   Example:                                                   │
│   FP32 range: [-1.0, 1.0]                                   │
│   INT8 range: [-128, 127]                                   │
│   scale = 2.0 / 256 ≈ 0.0078                               │
│                                                              │
│   MAC operation:                                            │
│   - 8-bit × 8-bit → 16-bit product                         │
│   - Accumulate in 32-bit                                    │
│   - Final output: quantized back to 8-bit                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Specifications

| Component | Specification |
|-----------|---------------|
| Systolic array | 256 × 256 = 65,536 MACs |
| Clock speed | 700 MHz |
| Peak throughput | 92 TOPS (8-bit) |
| Memory | 8 GB DDR3, 30 GB/s bandwidth |
| On-chip SRAM | 28 MB (24 MB unified buffer + 4 MB weight FIFO) |
| TDP | 40 W |
| Process | 28 nm |
| Die size | ~331 mm² |
| Interface | PCIe Gen3 x16 |

## Comparison with CPU and GPU

```
┌─────────────────────────────────────────────────────────────┐
│              PERFORMANCE COMPARISON                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Benchmark: Neural network inference (various models)      │
│                                                              │
│   │ Metric          │ Haswell CPU │ K80 GPU │ TPU v1  │    │
│   ├─────────────────┼─────────────┼─────────┼─────────┤    │
│   │ TOPS            │ 2.6         │ 2.8     │ 92      │    │
│   │ TOPS/W          │ 0.015       │ 0.01    │ 2.3     │    │
│   │ Memory (GB)     │ 256         │ 12      │ 8       │    │
│   │ TDP (W)         │ 145         │ 300     │ 40      │    │
│   │ $/inference     │ 1.0×        │ 1.0×    │ 0.1×    │    │
│   └─────────────────┴─────────────┴─────────┴─────────┘    │
│                                                              │
│   TPU v1 advantages:                                         │
│   - 30× better TOPS/W than GPU                              │
│   - 80× better TOPS/W than CPU                              │
│   - 10× lower cost per inference                            │
│                                                              │
│   TPU v1 limitations:                                        │
│   - Inference only (no training)                            │
│   - Limited model support (no sparse ops)                   │
│   - Fixed batch size optimizations                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Memory Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│                 TPU MEMORY HIERARCHY                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Level            Size        Bandwidth    Latency         │
│   ───────────────────────────────────────────────────       │
│   MAC registers    ~256 B      ∞            0 cycles        │
│   Weight FIFO      4 MB        ~700 GB/s    ~10 cycles      │
│   Unified Buffer   24 MB       ~700 GB/s    ~10 cycles      │
│   DDR3 Memory      8 GB        30 GB/s      ~100 cycles     │
│   Host (PCIe)      -           12 GB/s      ~1000 cycles    │
│                                                              │
│   Key insight: Almost no off-chip memory access!            │
│                                                              │
│   Typical neural net layer:                                  │
│   1. Load weights from DDR → Weight FIFO (once per batch)   │
│   2. Load activations from Unified Buffer                   │
│   3. Compute in systolic array                              │
│   4. Store results to Unified Buffer                        │
│                                                              │
│   Weight reuse: Load 1 MB weights, process 256 inputs       │
│   = 256 MB effective bandwidth from 1 MB load               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Programming Model

The TPU is programmed as a coprocessor:

```
Host CPU sends instructions via PCIe:

┌─────────────────────────────────────────────────────────────┐
│                 TPU INSTRUCTION SET                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   1. Read_Host_Memory                                        │
│      - DMA weights from host to Weight FIFO                 │
│                                                              │
│   2. Read_Weights                                            │
│      - Load weights from FIFO to systolic array             │
│                                                              │
│   3. MatrixMultiply/Convolve                                │
│      - Execute matrix multiply                               │
│      - Read activations from Unified Buffer                 │
│      - Write results to accumulators                        │
│                                                              │
│   4. Activate                                                │
│      - Apply activation function (ReLU, etc.)               │
│      - Write to Unified Buffer                              │
│                                                              │
│   5. Write_Host_Memory                                       │
│      - DMA results back to host                             │
│                                                              │
│   Typical sequence:                                          │
│   For each layer:                                            │
│     Read_Host_Memory(weights)                                │
│     Read_Weights                                             │
│     MatrixMultiply                                           │
│     Activate                                                 │
│   Write_Host_Memory(final_output)                           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Connection to Systolic Arrays (Chapter 8)

TPU v1 is essentially the systolic array from Chapter 8, scaled up:

```
Chapter 8 example:     TPU v1:
4×4 systolic array     256×256 systolic array
16 MACs                65,536 MACs
Academic concept       Production silicon

The principles are identical:
- Regular structure
- Local communication
- Pipelined data flow
- Weight/activation reuse
```

## Key Takeaways

1. **Domain-specific wins** - Purpose-built beats general-purpose for specific tasks
2. **Systolic arrays scale** - 256×256 is just a bigger version of 4×4
3. **Memory bandwidth matters** - 28MB on-chip SRAM avoids DDR bottleneck
4. **Quantization enables efficiency** - INT8 is sufficient for inference
5. **Weight-stationary works for inference** - Fixed weights, streaming activations
6. **Simple is powerful** - No caches, no branch prediction, just matrix multiply

> See [Appendix Q](appendix-q-tpu.md) for RHDL implementation of a simplified TPU systolic array.
