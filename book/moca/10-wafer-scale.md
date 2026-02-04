# Chapter 10: Wafer-Scale Computing

*When a single die is the entire wafer*

---

## The Audacious Idea

What if, instead of cutting a wafer into hundreds of small chips, you kept the *entire wafer* as one massive processor?

```
Traditional Approach:
┌─────────────────────────────────────────────────────────────┐
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐   │
│  │Die│ │Die│ │Die│ │Die│ │Die│ │Die│ │Die│ │Die│ │Die│   │
│  └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘   │
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐   │
│  │Die│ │Die│ │Die│ │Die│ │Die│ │Die│ │Die│ │Die│ │Die│   │
│  └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘   │
│        Cut into individual chips, package separately        │
└─────────────────────────────────────────────────────────────┘

Wafer-Scale Approach:
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│                    ONE GIANT CHIP                           │
│                                                             │
│     Hundreds of thousands of cores on single wafer          │
│                                                             │
│     Massive on-chip SRAM (no external memory!)              │
│                                                             │
│     Petabytes/s of interconnect bandwidth                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
         Don't cut it. Use the whole wafer.
```

This is **wafer-scale integration (WSI)**—building the largest possible chips by using an entire silicon wafer as a single device.

---

## Why Wafer Scale?

### The Memory Wall

Modern AI workloads are bottlenecked by memory bandwidth, not compute:

```
Traditional Architecture:
┌────────────────┐
│   Processor    │
│   (compute)    │◄──────┐
└────────────────┘       │
        ▲                │  Memory bandwidth
        │                │  bottleneck!
┌───────┴────────┐       │
│   DRAM/HBM     │───────┘
│   (off-chip)   │
└────────────────┘

Time breakdown for large models:
  Compute:              10%
  Waiting for memory:   90%  ◄── The problem!
```

### The Communication Wall

Multi-chip systems have another bottleneck:

```
Multi-Chip Cluster:
┌─────┐   ┌─────┐   ┌─────┐   ┌─────┐
│Chip0│   │Chip1│   │Chip2│   │Chip3│
└──┬──┘   └──┬──┘   └──┬──┘   └──┬──┘
   │         │         │         │
═══╧═════════╧═════════╧═════════╧═══  PCIe/NVLink
                                       (relatively slow)

Communication latency comparison:
  - Cross-chip: microseconds
  - On-chip: nanoseconds
  - Ratio: ~1,000× slower!
```

### Wafer-Scale Solution: Everything On-Chip

```
Wafer-Scale Processor:
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   Massive SRAM distributed across cores                     │
│                                                             │
│   Memory bandwidth: 10-20+ PB/s (vs ~TB/s for packages)    │
│                                                             │
│   All communication is on-chip!                             │
│                                                             │
└─────────────────────────────────────────────────────────────┘

Result: Memory bandwidth is NOT the bottleneck
```

---

## Architectural Challenges

### 1. Manufacturing Defects

No wafer is perfect. A 300mm wafer will have defects:

```
┌─────────────────────────────────────┐
│  ●  ○  ○  ○  ○  ○  ○  ○  ○  ○  ●   │
│  ○  ○  ○  ○  ●  ○  ○  ○  ○  ○  ○   │
│  ○  ○  ○  ○  ○  ○  ○  ○  ○  ○  ○   │
│  ○  ○  ○  ●  ○  ○  ○  ○  ○  ○  ○   │
│  ○  ○  ○  ○  ○  ○  ○  ●  ○  ○  ○   │
│  ○  ○  ○  ○  ○  ○  ○  ○  ○  ○  ○   │
│  ○  ●  ○  ○  ○  ○  ○  ○  ○  ○  ○   │
└─────────────────────────────────────┘
        ● = defective area
        ○ = working area

Traditional: discard dies with defects
Wafer-scale: must work AROUND defects
```

**Solutions:**
- Redundant rows/columns of processing elements
- Configurable routing to bypass defective units
- Graceful degradation (partial functionality)

### 2. Power Delivery

A wafer-scale chip may consume 15-30+ kW:

```
Power Challenges:
┌─────────────────────────────────────┐
│                                     │
│   Current: 1000s of amps           │
│   Voltage drop across wafer        │
│   IR drop = big problem            │
│                                     │
└─────────────────────────────────────┘

Solutions:
  - Multiple power connections around perimeter
  - On-chip voltage regulation
  - Careful power grid design
  - Advanced packaging with dense power delivery
```

### 3. Heat Dissipation

```
Heat Density Challenge:
┌─────────────────────────────────────┐
│   ████████████████████████████████  │
│   ████████████████████████████████  │  All this
│   ████████████████████████████████  │  generates
│   ████████████████████████████████  │  HEAT
│   ████████████████████████████████  │
└─────────────────────────────────────┘
         ↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓

Solutions:
  - Advanced liquid cooling
  - Water-cooled cold plates
  - Thermal paste and heat spreaders
  - Careful activity spreading across wafer
```

### 4. Testing and Yield

```
Test Challenge:
  - Can't test before dicing
  - Must test on-wafer or post-assembly
  - Need built-in self-test (BIST)
  - Scan chains must work around defects
```

---

## Tile-Based Architecture

Wafer-scale designs use a regular **tiled** structure:

```
┌─────────────────────────────────────────────────────────────┐
│                         TILE                                 │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                 PROCESSING ELEMENT                   │    │
│  │  ┌─────────┐  ┌─────────────────┐  ┌─────────────┐  │    │
│  │  │ Compute │  │    Local        │  │   Router    │  │    │
│  │  │ Core    │  │    SRAM         │  │             │  │    │
│  │  │         │  │                 │  │  N S E W   │  │    │
│  │  │ ALU/FPU │  │  (weights,      │  │             │  │    │
│  │  │         │  │   activations)  │  │             │  │    │
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
- **Compute core**: Optimized for target workload (ML, HPC, etc.)
- **Local SRAM**: Memory distributed to avoid bottleneck
- **Router**: Connects to neighboring tiles

### Why Tiled Design?

1. **Regularity**: Design once, replicate many times
2. **Scalability**: Add more tiles for more compute
3. **Defect tolerance**: Replace bad tiles with spares
4. **Predictable timing**: Uniform structure simplifies design
5. **Easier verification**: Verify one tile, trust replication

---

## Network-on-Chip (NoC)

### 2D Mesh Topology

The most common wafer-scale network topology:

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

Each router is typically a 5×5 crossbar:

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

Wafer-scale architectures naturally support **dataflow execution**:

```
Traditional (von Neumann):
  Program counter advances through instructions
  Data fetched from memory as needed

Wafer-Scale (Dataflow):
  Data flows through a grid of processing elements
  Each PE executes when inputs arrive
  No program counter—execution is data-driven
```

### Spatial Mapping

Neural networks map directly to the physical fabric:

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

With spatial mapping, the entire network processes simultaneously:

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

A wafer this large *will* have defects. Solutions:

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

## Historical Context

### Early Attempts

| Year | Project | Outcome |
|------|---------|---------|
| 1980s | Trilogy Systems | Failed (yield, cooling) |
| 1989 | Anamartic | Limited success |
| 1990s | Various research | Incremental progress |

**Why early attempts failed:**
- Insufficient defect handling
- Heat dissipation challenges
- Packaging technology limitations
- No compelling application

### Modern Success Factors

What changed to enable modern wafer-scale computing:

1. **Better defect handling** - Redundancy and routing around faults
2. **Advanced cooling** - Liquid cooling capable of 15+ kW
3. **NoC maturity** - Decades of research into on-chip networks
4. **AI workloads** - Ideal fit for dataflow and spatial computing
5. **Advanced packaging** - Better power delivery and heat removal

> See [Chapter 28 - The Cerebras WSE](28-cerebras.md) for a detailed case study of modern wafer-scale implementation.

---

## When Wafer-Scale Excels

| Workload | Wafer-Scale Advantage |
|----------|----------------------|
| Large sparse models | On-chip memory hides latency |
| Low-batch inference | No batching needed for throughput |
| Models that fit in on-chip SRAM | Zero external memory bottleneck |
| Communication-heavy workloads | On-chip fabric is 1000× faster |

### When Traditional Approaches Win

| Workload | Traditional Advantage |
|----------|----------------------|
| Models larger than on-chip SRAM | External memory capacity |
| Highly optimized dense workloads | Mature software ecosystem |
| Multi-tenant/shared systems | Better resource sharing |
| Cost-sensitive deployments | Lower capital expense |

---

## NoC Design Principles

What makes wafer-scale networks work at extreme scale?

### 1. Regularity

```
Every tile is identical:
  Same PE, same router, same connections

Benefits:
  - Design once, replicate N times
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

Simplicity enables massive scale!
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

## RHDL Implementation

See [Appendix J](appendix-j-wafer-scale.md) for complete implementations:

```ruby
# Wafer-scale mesh router
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
- **Hundreds of thousands of cores**: Each with local SRAM and a router
- **2D mesh NoC**: Simple, scalable, deterministic
- **Dataflow execution**: Data flows through the network spatially
- **Massive on-chip memory**: No external memory bottleneck
- **Petabytes/s bandwidth**: Orders of magnitude beyond packaged chips
- **Static mapping**: Compiler places workload across tiles
- **Defect tolerance**: Spare rows/columns, configurable routing
- **Ideal for AI**: Large sparse models, low-latency inference

---

## Exercises

1. Calculate the hop count for a packet traveling corner-to-corner on a 1000×1000 mesh
2. Implement XY routing decision logic in RHDL
3. Design a credit-based flow control mechanism
4. Compare bandwidth: N tiles × local links vs. external memory bus
5. Analyze why sparse models benefit from wafer-scale architecture

---

## Further Reading

- Dally & Towles, "Principles and Practices of Interconnection Networks" (2003)
- IEEE JSSC retrospective on Wafer-Scale Integration
- Research papers on Networks-on-Chip design

---

*Previous: [Chapter 09 - GPU Architecture](09-gpu-architecture.md)*

*Next: [Chapter 11 - Vector Processing](11-vector-processing.md)*

*Appendix: [Appendix J - Wafer-Scale Implementation](appendix-j-wafer-scale.md)*
