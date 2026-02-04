# Chapter 27: The Groq LPU

*Deterministic dataflow for AI inference*

---

## Overview

Groq's Language Processing Unit (LPU) represents perhaps the purest implementation of **deterministic dataflow** in modern hardware. While most AI accelerators embrace caches, speculation, and dynamic scheduling, Groq takes the opposite approach: every operation executes at a predetermined time, with no runtime variability.

**Key Stats (LPU Inference Engine):**
- Architecture: Temporal SIMD (TSP)
- On-chip SRAM: 230 MB
- Memory bandwidth: 80 TB/s
- Clock: ~1 GHz
- Process: 14nm
- Inference latency: Deterministic to the cycle

---

## Design Philosophy

### The Problem with Traditional Accelerators

Most AI chips (GPUs, TPUs) share these characteristics:

```
Traditional AI Accelerator:
┌─────────────────────────────────────────┐
│  ┌──────────┐    ┌──────────────────┐  │
│  │   DRAM   │◄──►│     Caches       │  │
│  │ (off-chip)│    │  (hit or miss?)  │  │
│  └──────────┘    └────────┬─────────┘  │
│                          │             │
│                          ▼             │
│               ┌──────────────────┐     │
│               │  Compute Cores   │     │
│               │  (when to run?)  │     │
│               └──────────────────┘     │
│                                        │
│  Problem: Execution time is variable   │
│  - Cache hits vs misses               │
│  - Memory contention                  │
│  - Dynamic scheduling decisions       │
└────────────────────────────────────────┘
```

This variability hurts latency-sensitive applications like real-time inference.

### Groq's Solution: Deterministic Everything

```
Groq LPU:
┌─────────────────────────────────────────┐
│                                         │
│   ┌──────────────────────────────────┐  │
│   │        230 MB SRAM               │  │
│   │     (no caches - direct access)  │  │
│   └──────────────────────────────────┘  │
│                  │                      │
│                  ▼                      │
│   ┌──────────────────────────────────┐  │
│   │     Functional Units             │  │
│   │  (execute at scheduled cycle)    │  │
│   └──────────────────────────────────┘  │
│                                         │
│   Result: If it takes 47,832 cycles,   │
│           it takes exactly 47,832      │
│           cycles. Every time.          │
│                                         │
└─────────────────────────────────────────┘
```

---

## Architecture Overview

### Temporal SIMD Processor (TSP)

The LPU uses a unique architecture called **Temporal SIMD**:

```
┌─────────────────────────────────────────────────────────────────┐
│                    GROQ LPU ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │                    Instruction Stream                     │  │
│   │           (statically scheduled by compiler)              │  │
│   └──────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼                                   │
│   ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  │
│   │  MXM   │──│  MXM   │──│  MXM   │──│  MXM   │──│  MXM   │  │
│   │ (320)  │  │ (320)  │  │ (320)  │  │ (320)  │  │ (320)  │  │
│   └────────┘  └────────┘  └────────┘  └────────┘  └────────┘  │
│       │           │           │           │           │         │
│       ▼           ▼           ▼           ▼           ▼         │
│   ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  │
│   │  VXM   │──│  VXM   │──│  VXM   │──│  VXM   │──│  VXM   │  │
│   │ (80)   │  │ (80)   │  │ (80)   │  │ (80)   │  │ (80)   │  │
│   └────────┘  └────────┘  └────────┘  └────────┘  └────────┘  │
│       │           │           │           │           │         │
│       ▼           ▼           ▼           ▼           ▼         │
│   ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  │
│   │  SXM   │──│  SXM   │──│  SXM   │──│  SXM   │──│  SXM   │  │
│   └────────┘  └────────┘  └────────┘  └────────┘  └────────┘  │
│       │           │           │           │           │         │
│       └───────────┴───────────┴───────────┴───────────┘         │
│                              │                                   │
│                              ▼                                   │
│                      Global SRAM (230MB)                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

MXM = Matrix Multiply unit (320 × 320 elements)
VXM = Vector Matrix Multiply unit
SXM = Scalar Execution Module
```

### Functional Units

| Unit | Description | Operation |
|------|-------------|-----------|
| **MXM** | Matrix-Matrix Unit | 320×320 multiply-accumulate |
| **VXM** | Vector-Matrix Unit | Vector operations, activations |
| **SXM** | Scalar Execution | Control flow, address calculation |
| **MEM** | Memory Interface | SRAM read/write |

### Data Flow

Data flows through the chip in a **pipelined, deterministic** manner:

```
Time (cycles):  0    1    2    3    4    5    6    7    8
─────────────────────────────────────────────────────────
MXM[0]:        op0  op1  op2  op3  op4  op5  op6  op7  op8
MXM[1]:             op0  op1  op2  op3  op4  op5  op6  op7
MXM[2]:                  op0  op1  op2  op3  op4  op5  op6
VXM[0]:                       op0  op1  op2  op3  op4  op5
VXM[1]:                            op0  op1  op2  op3  op4
Output:                                 r0   r1   r2   r3

Every operation at a known cycle!
```

---

## Why No Caches?

### The Cache Problem

Caches introduce unpredictability:

```
Cache Behavior:
┌─────────────────────────────────────────┐
│  Request: Read X                        │
│                                         │
│  Case 1: Cache hit                      │
│    Latency: 1-4 cycles                  │
│                                         │
│  Case 2: Cache miss                     │
│    Latency: 50-200+ cycles              │
│    (go to DRAM)                         │
│                                         │
│  You don't know which until runtime!    │
└─────────────────────────────────────────┘
```

### Groq's Approach: All SRAM

```
Groq Memory:
┌─────────────────────────────────────────┐
│  230 MB of SRAM (all on-chip)          │
│                                         │
│  Every access: same latency            │
│  No cache hierarchy                    │
│  No misses                             │
│  No speculation                        │
│                                         │
│  If model fits in 230MB → deterministic│
└─────────────────────────────────────────┘
```

Trade-off: Limited to models that fit in 230MB (or require model parallelism across multiple chips).

---

## Compiler-Scheduled Execution

### Static Scheduling

The Groq compiler does all scheduling at compile time:

```
Traditional (runtime scheduling):
┌─────────────────────────────────────────┐
│  Hardware decides at runtime:           │
│  - Which instruction to issue           │
│  - When to stall for data              │
│  - How to handle conflicts             │
│                                         │
│  Requires: Branch predictors, scoreboard│
│            Out-of-order logic, etc.    │
└─────────────────────────────────────────┘

Groq (compile-time scheduling):
┌─────────────────────────────────────────┐
│  Compiler decides everything:           │
│  - Cycle N: MXM executes op A          │
│  - Cycle N+1: VXM executes op B        │
│  - Cycle N+2: Result written to SRAM   │
│                                         │
│  Hardware just follows the schedule!    │
└─────────────────────────────────────────┘
```

### Compilation Flow

```
┌─────────────────┐
│  PyTorch/TF    │  Standard ML framework
│    Model        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Graph         │  Extract computation graph
│   Extraction    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Scheduling    │  Assign every operation
│   & Placement   │  to a specific cycle
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Code Gen      │  Generate instruction stream
│                 │  with exact timing
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   LPU Binary    │  Load and run
└─────────────────┘
```

### Time as the Program Counter

In traditional CPUs, a program counter tracks execution position:

```
Traditional CPU:
  PC = 0x1000 → fetch instruction
  PC = 0x1004 → fetch next instruction
  ...
  (PC advances based on control flow)

Groq LPU:
  Cycle 0 → MXM[0] executes op[0]
  Cycle 1 → MXM[0] executes op[1], MXM[1] executes op[0]
  Cycle 2 → ...

  Time IS the program counter!
```

---

## Determinism Benefits

### 1. Predictable Latency

```
Inference Latency:
┌─────────────────────────────────────────┐
│                                         │
│  GPU (with caches/scheduling):          │
│    Run 1: 47ms                          │
│    Run 2: 52ms  (cache cold)            │
│    Run 3: 48ms                          │
│    Run 4: 89ms  (memory contention)     │
│                                         │
│  Groq LPU:                              │
│    Run 1: 12ms                          │
│    Run 2: 12ms                          │
│    Run 3: 12ms                          │
│    Run 4: 12ms                          │
│                                         │
│  Variance: 0                            │
│                                         │
└─────────────────────────────────────────┘
```

### 2. Maximum Utilization

No stalls means near-100% utilization:

```
Utilization:
┌─────────────────────────────────────────┐
│                                         │
│  GPU typical utilization: 30-60%        │
│    (waiting for memory, scheduling)     │
│                                         │
│  Groq LPU utilization: 80-95%+          │
│    (only unused when model doesn't fit) │
│                                         │
└─────────────────────────────────────────┘
```

### 3. Simpler Hardware

No need for complex control logic:

```
What Groq doesn't need:
  - Branch predictors
  - Cache hierarchies
  - Out-of-order execution
  - Scoreboarding
  - Dynamic scheduling
  - Speculation recovery

Result: More silicon for compute!
```

---

## Use Cases

### Ideal Workloads

| Use Case | Why Groq Fits |
|----------|---------------|
| Real-time inference | Predictable latency |
| Streaming applications | Consistent throughput |
| Financial trading | Low, deterministic latency |
| Voice assistants | Fast response required |
| Content moderation | High-volume, low-latency |

### Limitations

| Limitation | Reason |
|------------|--------|
| Model size ≤ 230MB | No external memory |
| Training | Designed for inference |
| Dynamic workloads | Static scheduling |
| Batch-optimized models | Optimized for single-stream |

---

## Comparison with Other Accelerators

```
                    Groq        GPU         TPU
                    ────        ───         ───
Scheduling         Static     Dynamic     Dynamic
Memory            SRAM only  HBM+Cache   HBM+Cache
Latency          Deterministic Variable   Variable
Utilization       Very high  Moderate     High
Batch needed        No         Yes        Yes
Model size limit   230MB      Large       Large
```

---

## Programming Model

### User Perspective

Users write standard PyTorch/TensorFlow code:

```python
import torch
from groq import GroqModel

# Standard PyTorch model
model = torch.nn.Sequential(
    torch.nn.Linear(1024, 2048),
    torch.nn.ReLU(),
    torch.nn.Linear(2048, 1024)
)

# Compile for Groq
groq_model = GroqModel.compile(model)

# Inference (deterministic!)
for input_batch in inputs:
    output = groq_model(input_batch)
    # Same latency every time
```

### What the Compiler Does

```
User's model                    Groq schedule
─────────────                   ─────────────
Linear(1024, 2048)      →      Cycles 0-127: MXM operations
ReLU()                  →      Cycles 128-191: VXM operations
Linear(2048, 1024)      →      Cycles 192-319: MXM operations

Total: 320 cycles (at 1GHz = 320ns)
Every. Single. Time.
```

---

## Historical Context

### Dataflow Heritage

Groq builds on decades of dataflow research:

| Era | System | Contribution |
|-----|--------|--------------|
| 1970s | MIT Tagged-Token | Dynamic dataflow |
| 1980s | Manchester Machine | First working dataflow |
| 1990s | TRIPS, WaveScalar | Spatial dataflow |
| 2010s | Groq | Deterministic temporal dataflow |

### Why Now?

Several factors enabled Groq's approach:
1. **AI workloads**: Regular, predictable computation graphs
2. **Compiler advances**: Better static scheduling algorithms
3. **SRAM density**: Enough on-chip memory for real models
4. **Inference focus**: Training can tolerate variability

---

## Summary

- **Deterministic execution**: Every cycle scheduled at compile time
- **No caches**: 230MB SRAM with uniform latency
- **Static scheduling**: Compiler handles all timing
- **Time as program counter**: Cycle number determines operation
- **High utilization**: No stalls, no waiting
- **Predictable latency**: Same time every run
- **Ideal for inference**: Real-time, low-latency applications

---

## Exercises

1. Calculate the theoretical throughput of a 320×320 MXM at 1GHz
2. Compare latency variance between Groq and a GPU for the same model
3. Design a simple static scheduler for a small computation graph
4. Analyze when model parallelism becomes necessary on Groq
5. Explain why training is harder to make deterministic than inference

---

## Further Reading

- Groq, "Groq Architecture White Paper"
- "Deterministic Dataflow Architectures" survey
- "Static Scheduling for AI Accelerators" (compiler techniques)

---

*Previous: [Chapter 26 - The Transputer](26-transputer.md)*

*Next: [Chapter 28 - The Cerebras WSE](28-cerebras.md)*
