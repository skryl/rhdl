# Chapter 28: The Cerebras WSE

*The largest chip ever built*

---

## Overview

The Cerebras Wafer Scale Engine (WSE) is the most ambitious implementation of wafer-scale computing ever achieved. Rather than cutting a silicon wafer into hundreds of separate chips, Cerebras uses the *entire wafer* as a single processor—creating the largest chip ever built.

**Key Stats (WSE-2):**
- Transistors: 2.6 trillion
- Cores: 850,000
- On-chip SRAM: 40 GB
- Memory bandwidth: 20 PB/s
- Interconnect bandwidth: 220 Pb/s
- Die size: 46,225 mm² (full 300mm wafer)
- Process: 7nm TSMC
- TDP: 15-23 kW

---

## The WSE Approach

### Traditional vs Wafer-Scale

```
Traditional Approach:
┌─────────────────────────────────────────────────────────────┐
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐   │
│  │GPU│ │GPU│ │GPU│ │GPU│ │GPU│ │GPU│ │GPU│ │GPU│ │GPU│   │
│  └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘   │
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐   │
│  │GPU│ │GPU│ │GPU│ │GPU│ │GPU│ │GPU│ │GPU│ │GPU│ │GPU│   │
│  └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘   │
│        Cut into individual chips, package separately        │
└─────────────────────────────────────────────────────────────┘

Cerebras Approach:
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│                    ONE GIANT CHIP                           │
│                                                             │
│     850,000 cores connected by on-chip network              │
│                                                             │
│     40 GB SRAM (no external memory!)                        │
│                                                             │
│     220 Pb/s interconnect bandwidth                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
         Don't cut it. Use the whole wafer.
```

### Why This Matters

The key advantages:

| Aspect | Traditional Multi-GPU | Cerebras WSE |
|--------|----------------------|--------------|
| Memory bandwidth | ~3 TB/s per GPU | 20 PB/s total |
| Communication | NVLink (μs latency) | On-chip (ns latency) |
| Memory capacity | External HBM | 40GB SRAM on-chip |
| Synchronization | Explicit, expensive | Implicit, cheap |

---

## Architecture

### The Numbers Comparison

| Specification | WSE-2 | NVIDIA A100 |
|---------------|-------|-------------|
| Transistors | 2.6 trillion | 54 billion |
| Cores | 850,000 | 6,912 CUDA |
| On-chip SRAM | 40 GB | 40 MB |
| Memory bandwidth | 20 PB/s | 2 TB/s |
| Interconnect | 220 Pb/s | ~600 GB/s NVLink |
| Die size | 46,225 mm² | 826 mm² |
| Process | 7nm | 7nm |
| TDP | 15-23 kW | 400W |

The WSE-2 is approximately **56× larger** than an A100 in die area.

### Tile-Based Structure

The WSE is built from repeated **tiles**:

```
┌─────────────────────────────────────────────────────────────┐
│                         TILE                                 │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                 PROCESSING ELEMENT                   │    │
│  │  ┌─────────┐  ┌─────────────────┐  ┌─────────────┐  │    │
│  │  │ Tensor  │  │    48 KB        │  │   Router    │  │    │
│  │  │ Core    │  │    SRAM         │  │             │  │    │
│  │  │         │  │                 │  │  N S E W   │  │    │
│  │  │ FMAC    │  │  (local memory) │  │             │  │    │
│  │  └─────────┘  └─────────────────┘  └──┬──┬──┬──┬─┘  │    │
│  │       │              │                │  │  │  │    │    │
│  │       └──────────────┴────────────────┘  │  │  │    │    │
│  └──────────────────────────────────────────┼──┼──┼────┘    │
│                                             │  │  │         │
└─────────────────────────────────────────────┼──┼──┼─────────┘
                                              │  │  │
                                    To neighboring tiles
```

Each tile contains:
- **Tensor Core**: Optimized for ML operations (matrix multiply, activation)
- **48 KB SRAM**: Local memory for weights and activations
- **Router**: 5-port crossbar (North, South, East, West, Local)

### 2D Mesh Network

```
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
│ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │
│  ◄──┼──►  │  ◄──┼──►  │  ◄──┼──►  │  ◄──┼──►  │
└──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┘
   │     │     │     │     │     │     │     │
   ▼     ▼     ▼     ▼     ▼     ▼     ▼     ▼
┌──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┐
│ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │ PE  │
│  ◄──┼──►  │  ◄──┼──►  │  ◄──┼──►  │  ◄──┼──►  │
└──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┴──┬──┘
   │     │     │     │     │     │     │     │
   ...  (hundreds of rows and columns)  ...

PE = Processing Element (core + 48KB SRAM + router)
Total: ~920 rows × ~920 columns ≈ 850,000 tiles
```

---

## Router Architecture

### 5-Port Crossbar

Each tile contains a router connecting to its four neighbors plus the local core:

```
                    From North
                        │
                        ▼
                   ┌─────────┐
    From West ────►│  Input  │
                   │ Buffers │
                   │  (VCs)  │
                   └────┬────┘
                        │
              ┌─────────┴─────────┐
              │                   │
              │    5×5 Crossbar   │
              │                   │
              │  N  S  E  W  L    │
              │  ↓  ↓  ↓  ↓  ↓    │
              └───────────────────┘
                  │  │  │  │  │
                  ▼  ▼  ▼  ▼  ▼
               To: S  N  W  E  Local
```

### Routing: XY Algorithm

Deterministic XY routing—first route in X direction, then Y:

```
Source: (2, 1)          Destination: (5, 4)

     0   1   2   3   4   5   6
   ┌───┬───┬───┬───┬───┬───┬───┐
 0 │   │   │   │   │   │   │   │
   ├───┼───┼───┼───┼───┼───┼───┤
 1 │   │   │ S─┼──►┼──►┼──►│   │  ← First: go East (X)
   ├───┼───┼───┼───┼───┼───┼───┤          until X matches
 2 │   │   │   │   │   │ │ │   │
   ├───┼───┼───┼───┼───┼─▼─┼───┤
 3 │   │   │   │   │   │ │ │   │
   ├───┼───┼───┼───┼───┼─▼─┼───┤
 4 │   │   │   │   │   │ D │   │  ← Then: go South (Y)
   └───┴───┴───┴───┴───┴───┴───┘          until Y matches

Hops: 3 (East) + 3 (South) = 6 hops
Latency: 6 cycles (single-cycle hops)
```

### Key Router Features

- **Virtual channels**: Multiple logical channels per physical link
- **Credit-based flow control**: Sender tracks receiver buffer space
- **Single-cycle hop**: Ultra-low latency
- **Deadlock-free**: XY routing guarantees no cycles

---

## Dataflow Execution

### Static Dataflow Model

Unlike GPUs that schedule threads dynamically, Cerebras uses **static dataflow**:

```
GPU (Dynamic):
  Thread scheduler decides what runs
  Memory requests may stall
  Execution order uncertain

Cerebras (Static Dataflow):
  Data flows through the fabric
  Each PE executes when inputs arrive
  Spatial mapping to physical cores
```

### Layer-by-Layer Mapping

Neural network layers map directly to physical regions:

```
Neural Network:                Physical Layout:

  Input                        ┌───┬───┬───┐
    │                          │ I │ I │ I │  Input tiles
    ▼                          ├───┼───┼───┤
 ┌──────┐                      │ L1│ L1│ L1│  Layer 1
 │Layer1│                      ├───┼───┼───┤
 └──┬───┘                      │ L1│ L1│ L1│
    │                          ├───┼───┼───┤
    ▼                          │ L2│ L2│ L2│  Layer 2
 ┌──────┐                      ├───┼───┼───┤
 │Layer2│                      │ L2│ L2│ L2│
 └──┬───┘                      ├───┼───┼───┤
    │                          │ O │ O │ O │  Output tiles
    ▼                          └───┴───┴───┘
  Output

Data flows spatially through the chip!
```

### Pipeline Execution

```
Time →
       t0    t1    t2    t3    t4    t5
      ┌────┬────┬────┬────┬────┬────┐
Input │ B0 │ B1 │ B2 │ B3 │ B4 │ B5 │
      ├────┼────┼────┼────┼────┼────┤
Layer1│    │ B0 │ B1 │ B2 │ B3 │ B4 │
      ├────┼────┼────┼────┼────┼────┤
Layer2│    │    │ B0 │ B1 │ B2 │ B3 │
      ├────┼────┼────┼────┼────┼────┤
Output│    │    │    │ B0 │ B1 │ B2 │
      └────┴────┴────┴────┴────┴────┘

After pipeline fills: one batch completes per cycle
```

---

## Handling Defects

### The Yield Challenge

At 46,225 mm², defects are inevitable. A wafer will have multiple defective areas.

### Redundancy Strategy

```
┌───┬───┬───┬───┬───┬───┐
│ PE│ PE│ PE│ PE│ S │ S │  S = Spare column
├───┼───┼───┼───┼───┼───┤
│ PE│ PE│ X │ PE│   │   │  X = Defective PE
├───┼───┼───┼───┼───┼───┤
│ PE│ PE│ PE│ PE│   │   │
├───┼───┼───┼───┼───┼───┤
│ S │ S │ S │ S │   │   │  Spare row
└───┴───┴───┴───┴───┴───┘

Strategy:
  1. Test wafer to find defects
  2. Configure routing to use spare tiles
  3. Defective tiles electrically isolated
  4. Software sees uniform array
```

### Configurable Routing

The network can route around bad tiles:

```
Normal:    A → B → C → D

If B defective:
           A → ─┐
                ↓
                B' (spare)
                ↓
           C ← ─┘ → D
```

---

## Software Stack

### Compilation Flow

```
┌─────────────────┐
│  PyTorch/TF    │  User writes standard framework code
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
│   Placement     │  Map layers to tiles
│   & Routing     │  Route data between regions
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Code Gen      │  Generate per-tile programs
│                 │  Configure routers
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   WSE Binary    │  Load onto hardware
└─────────────────┘
```

### User Code Example

```python
import cerebras_pytorch as cstorch

# Standard PyTorch model
class MyModel(torch.nn.Module):
    def __init__(self):
        self.layer1 = torch.nn.Linear(1024, 2048)
        self.layer2 = torch.nn.Linear(2048, 1024)

    def forward(self, x):
        x = F.relu(self.layer1(x))
        x = self.layer2(x)
        return x

# Cerebras compiler handles:
# 1. Partitioning layers across 850K tiles
# 2. Placing weights in tile-local SRAM
# 3. Routing activations between layers
# 4. Configuring all routers
```

---

## Performance Characteristics

### When Cerebras Excels

| Workload | Why WSE Wins |
|----------|--------------|
| Large sparse models | SRAM hides latency |
| Low-batch inference | No batching needed |
| Models ≤ 40GB | Zero external memory |
| Research iteration | Fast compile, quick experiments |
| Communication-heavy | On-chip is 1000× faster |

### When GPUs Win

| Workload | Why GPU Wins |
|----------|--------------|
| Models > 40GB | External memory capacity |
| Dense batch training | High arithmetic intensity |
| Multi-tenant serving | Better resource sharing |
| General compute | Broader ecosystem |

---

## The CS-2 System

### System Integration

The WSE chip sits in the **CS-2** system:

```
┌─────────────────────────────────────────┐
│              CS-2 System                │
├─────────────────────────────────────────┤
│                                         │
│    ┌───────────────────────────────┐   │
│    │        WSE-2 Chip             │   │
│    │    (the wafer-scale chip)     │   │
│    │                               │   │
│    └───────────────────────────────┘   │
│              │                         │
│              ▼                         │
│    ┌───────────────────────────────┐   │
│    │     Cooling System            │   │
│    │   (water-cooled, 15kW+)       │   │
│    └───────────────────────────────┘   │
│                                         │
│    ┌───────────────────────────────┐   │
│    │     Power Delivery            │   │
│    │   (custom power infrastructure│   │
│    └───────────────────────────────┘   │
│                                         │
│    ┌───────────────────────────────┐   │
│    │     Host Interface            │   │
│    │   (12× 100GbE)                │   │
│    └───────────────────────────────┘   │
│                                         │
└─────────────────────────────────────────┘

Size: 26" × 26" × 15" (roughly)
Weight: ~500 lbs
Power: 15-23 kW
```

### Cluster Configurations

For larger models, multiple CS-2 systems can cluster:

```
┌────────┐   ┌────────┐   ┌────────┐
│  CS-2  │───│  CS-2  │───│  CS-2  │
└────────┘   └────────┘   └────────┘
    │            │            │
    └────────────┼────────────┘
                 │
    ┌────────────┴────────────┐
    │     MemoryX + SwarmX    │
    │   (external memory &    │
    │    interconnect tech)   │
    └─────────────────────────┘

Enables training models > 40GB
```

---

## Historical Context

### Wafer-Scale Attempts

| Year | Project | Outcome |
|------|---------|---------|
| 1980s | Trilogy Systems | Failed (yield, heat) |
| 1989 | Anamartic | Limited success |
| 2019 | Cerebras WSE-1 | First successful large-scale |
| 2021 | Cerebras WSE-2 | 2.6T transistors |
| 2024 | Cerebras WSE-3 | 4T transistors, 44GB |

### What Changed?

Why did Cerebras succeed where others failed?

1. **Better defect handling**: Redundancy and smart routing
2. **Advanced cooling**: Water-cooled systems handling 15+ kW
3. **NoC maturity**: Decades of interconnect research
4. **AI workloads**: Perfect fit for dataflow execution
5. **Advanced packaging**: Better power delivery

---

## Summary

- **2.6 trillion transistors**: Largest chip ever built
- **850,000 cores**: Each with 48KB SRAM
- **40 GB on-chip**: No external memory bottleneck
- **20 PB/s bandwidth**: 10,000× typical GPU memory bandwidth
- **2D mesh NoC**: Simple, scalable, deadlock-free
- **Dataflow execution**: Data flows spatially through fabric
- **Defect tolerance**: Spare rows/columns, configurable routing
- **Static mapping**: Compiler places layers across tiles

---

## Exercises

1. Calculate the average hop count for random traffic in the WSE mesh
2. Estimate the overhead of spare rows/columns at various defect rates
3. Design a simple defect-avoidance routing modification
4. Compare bandwidth per watt: WSE vs GPU cluster
5. Analyze when model parallelism across multiple CS-2s becomes necessary

---

## Further Reading

- Cerebras, "Cerebras Architecture White Paper" (2019)
- Lie et al., "Cerebras: An Architecture for Accelerating Deep Learning" (Hot Chips 2019)
- "Wafer-Scale Integration" IEEE JSSC retrospective

---

*Previous: [Chapter 27 - The Groq LPU](27-groq.md)*

*Next: [Chapter 29 - The Cray-1](29-cray1.md)*
