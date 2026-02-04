# Chapter 26: Case Study - Cerebras WSE

*Network-on-Chip at wafer scale*

---

## The Audacious Idea

What if, instead of cutting a wafer into hundreds of small chips, you kept the *entire wafer* as one massive processor?

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

This is the **Cerebras Wafer Scale Engine (WSE)**—the largest chip ever built.

---

## Why Wafer Scale?

### The Memory Wall

Modern AI is bottlenecked by memory bandwidth, not compute:

```
GPU Architecture:
┌────────────────┐
│     GPU        │
│   (compute)    │◄──────┐
└────────────────┘       │
        ▲                │  Memory bandwidth
        │                │  bottleneck!
┌───────┴────────┐       │
│   HBM Memory   │───────┘
│    (off-chip)  │
└────────────────┘

Time breakdown for large models:
  Compute:     10%
  Waiting for memory: 90%  ◄── The problem!
```

### The Communication Wall

Multi-GPU training has another bottleneck:

```
Multi-GPU Cluster:
┌─────┐   ┌─────┐   ┌─────┐   ┌─────┐
│GPU 0│   │GPU 1│   │GPU 2│   │GPU 3│
└──┬──┘   └──┬──┘   └──┬──┘   └──┬──┘
   │         │         │         │
═══╧═════════╧═════════╧═════════╧═══  NVLink/PCIe
                                       (relatively slow)

Synchronization overhead:
  - AllReduce across GPUs: milliseconds
  - On-chip communication: nanoseconds
  - Ratio: ~1,000,000× slower!
```

### Cerebras Solution: Everything On-Chip

```
Cerebras WSE:
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   40 GB SRAM distributed across 850K cores                  │
│                                                             │
│   Memory bandwidth: 20 PB/s (vs ~3 TB/s for top GPU)       │
│                                                             │
│   No external memory access needed for most models!         │
│                                                             │
└─────────────────────────────────────────────────────────────┘

Result: Memory bandwidth is NOT the bottleneck
```

---

## WSE Architecture

### The Numbers (WSE-2)

| Specification | WSE-2 | For Comparison (A100) |
|---------------|-------|----------------------|
| Transistors | 2.6 trillion | 54 billion |
| Cores | 850,000 | 6,912 CUDA cores |
| On-chip SRAM | 40 GB | 40 MB |
| Memory bandwidth | 20 PB/s | 2 TB/s |
| Interconnect | 220 Pb/s | ~600 GB/s NVLink |
| Die size | 46,225 mm² | 826 mm² |
| Process | 7nm TSMC | 7nm TSMC |
| TDP | 15-23 kW | 400W |

### Tile-Based Architecture

The WSE is built from repeated **tiles**, each containing:

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

Each tile:
- **Tensor Core**: Optimized for ML operations (matrix multiply, activation)
- **48 KB SRAM**: Local memory for weights and activations
- **Router**: 5-port crossbar (N, S, E, W, Local)

---

## The Network-on-Chip

### 2D Mesh Topology

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

PE = Processing Element (core + SRAM + router)
```

### Router Architecture

Each router is a 5×5 crossbar with input buffering:

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

Key features:
- **Virtual channels**: Multiple logical channels per physical link
- **Credit-based flow control**: Backpressure without deadlock
- **Dimension-ordered routing (XY)**: Deterministic, deadlock-free
- **Single-cycle hop**: Ultra-low latency

### Routing Algorithm

XY routing: First route in X direction, then Y:

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

Path: (2,1) → (3,1) → (4,1) → (5,1) → (5,2) → (5,3) → (5,4)
Hops: 6
```

---

## Dataflow Execution Model

### Static Dataflow

Unlike GPUs (which schedule threads), Cerebras uses **static dataflow**:

```
Traditional (GPU):
  Program counter advances through instructions
  Data fetched from memory as needed

Cerebras (Dataflow):
  Data flows through a graph of operations
  Each PE executes when inputs arrive
  No program counter—execution is data-driven
```

### Layer-by-Layer Mapping

A neural network maps directly to the physical fabric:

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

### Pipelining

With dataflow, the entire network processes simultaneously:

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

Batches (B0, B1, ...) flow through pipeline
After warmup: one output per cycle!
```

---

## Handling Defects

A wafer this large *will* have defects. Cerebras handles them with redundancy:

### Spare Rows and Columns

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

Solution: Route around defect using spare PE
```

### Configurable Routing

The routing network can be programmed to avoid bad tiles:

```
Normal path:    A → B → C → D

If B is defective:
                A → ─┐
                     ↓
                     B' (spare)
                     ↓
                C ← ─┘ → D
```

---

## Comparison with GPU Clusters

### Single Large Model

```
Task: Train GPT-3 (175B parameters)

GPU Cluster (1000 A100s):
  - Model split across GPUs (tensor/pipeline parallelism)
  - Communication: NVLink + InfiniBand
  - Synchronization overhead: significant
  - Utilization: ~30-50% typical

Cerebras CS-2:
  - Model fits in 40GB on-chip (for many models)
  - Communication: on-chip fabric (nanoseconds)
  - No external synchronization
  - Utilization: 80-90%+ for suitable workloads
```

### When Cerebras Excels

| Workload | Cerebras Advantage |
|----------|-------------------|
| Large sparse models | On-chip memory hides latency |
| Low-batch inference | No batching needed for throughput |
| Models that fit in 40GB | Zero memory bandwidth bottleneck |
| Research iteration | Fast compile, quick experiments |

### When GPUs Win

| Workload | GPU Advantage |
|----------|--------------|
| Models > 40GB | External memory capacity |
| Dense batch training | High arithmetic intensity |
| Multi-tenant serving | Better cost sharing |
| General compute | Broader software ecosystem |

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
│   Placement     │  Map operations to tiles
│   & Routing     │  Route data between tiles
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

### Programming Model

Users don't program routers directly—the compiler handles placement:

```python
# User code (PyTorch)
class MyModel(nn.Module):
    def __init__(self):
        self.layer1 = nn.Linear(1024, 2048)
        self.layer2 = nn.Linear(2048, 1024)

    def forward(self, x):
        x = F.relu(self.layer1(x))
        x = self.layer2(x)
        return x

# Cerebras compiler automatically:
# 1. Partitions layers across tiles
# 2. Places weights in local SRAM
# 3. Routes activations between layers
# 4. Generates router configurations
```

---

## NoC Design Lessons

What makes the WSE network work at this scale?

### 1. Regularity

```
Every tile is identical:
  Same PE, same router, same connections

Benefits:
  - Design once, replicate 850K times
  - Predictable timing
  - Easy to verify
  - Manufacturing yield (defects are local)
```

### 2. Local Communication

```
Most traffic is local (to neighbors):
  - Neural nets have spatial locality
  - Layer N talks mostly to Layer N+1
  - Weights stay local to each tile

Diameter matters less when traffic is local!
```

### 3. Simple Routing

```
XY routing is deterministic:
  - No adaptive decisions needed
  - No routing tables
  - No deadlock possible
  - Predictable latency

Simplicity enables 850K routers!
```

### 4. Flow Control

```
Credit-based flow control:
  - Sender tracks receiver buffer space
  - Never send without credits
  - Backpressure propagates naturally
  - No dropped packets, no retransmission
```

---

## Historical Context

### Wafer-Scale Integration Attempts

| Year | Project | Outcome |
|------|---------|---------|
| 1980s | Trilogy Systems | Failed (yield, heat) |
| 1989 | Anamartic | Limited success |
| 2019 | Cerebras WSE-1 | First successful large-scale |
| 2021 | Cerebras WSE-2 | 2.6T transistors |
| 2024 | Cerebras WSE-3 | 4T transistors, 44GB |

What changed?
- Better defect handling (redundancy)
- Advanced cooling (water-cooled, 15kW+)
- NoC maturity (decades of research)
- AI workloads (ideal fit for dataflow)

---

## RHDL Implementation

See [Appendix Z](appendix-z-cerebras.md) for complete implementations:

```ruby
# Cerebras-style mesh router
class MeshRouter < SimComponent
  parameter :data_width, default: 256
  parameter :num_vcs, default: 4      # Virtual channels

  # Five ports: N, S, E, W, Local
  input :north_in, width: :data_width
  output :north_out, width: :data_width
  # ... (other ports)

  instance :crossbar, Crossbar5x5, width: data_width
  instance :arbiter, RoundRobinArbiter, ports: 5

  behavior do
    # XY routing decision
    # Credit management
    # Crossbar configuration
  end
end
```

---

## Summary

- **Wafer-scale**: Don't cut the wafer—use it all
- **850K cores**: Each with 48KB SRAM and a router
- **2D mesh NoC**: Simple, scalable, deterministic
- **Dataflow execution**: Data flows through the network
- **40GB on-chip**: No external memory bottleneck
- **220 Pb/s bandwidth**: Orders of magnitude beyond GPUs
- **Static mapping**: Compiler places neural network layers
- **Defect tolerance**: Spare rows/columns, configurable routing
- **Ideal for AI**: Large sparse models, low-latency inference

---

## Exercises

1. Calculate the hop count for a packet traveling corner-to-corner on a 1000×1000 mesh
2. Implement XY routing decision logic in RHDL
3. Design a credit-based flow control mechanism
4. Compare bandwidth: 850K tiles × local links vs. GPU memory bus
5. Analyze why sparse models benefit from Cerebras architecture

---

## Further Reading

- Cerebras, "Cerebras Architecture White Paper" (2019)
- Lie et al., "Cerebras: An Architecture for Accelerating Deep Learning" (Hot Chips 2019)
- Dally & Towles, "Principles and Practices of Interconnection Networks" (2003)
- "Wafer-Scale Integration" IEEE JSSC retrospective

---

*Previous: [Chapter 23 - Transputer](25-transputer.md)*

*Appendix: [Appendix Z - Cerebras Implementation](appendix-z-cerebras.md)*
