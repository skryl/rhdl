# Chapter 4: Dataflow Computation

## Overview

Most programming languages are **control-flow**: a program counter marches through instructions, deciding what to execute next. But there's another model: **dataflow**, where computation happens when data arrives. No program counter. No sequential execution. Operations fire the instant their inputs are ready.

This isn't just theory—it's how hardware naturally works. Every RHDL design is a dataflow program.

## Control Flow vs. Data Flow

### The Control Flow Model

Traditional programs have explicit sequencing:

```python
# Control flow (Python)
x = a + b      # Step 1
y = c * d      # Step 2
z = x + y      # Step 3 (depends on 1 and 2)
```

Even though steps 1 and 2 are independent, they execute sequentially. The CPU has a program counter that advances through instructions one by one.

```
┌─────────────────────────────────────────┐
│         CONTROL FLOW EXECUTION          │
├─────────────────────────────────────────┤
│                                         │
│   PC ──▶ [Fetch] ──▶ [Decode] ──▶ [Execute]
│          ▲                              │
│          │ next instruction             │
│          └──────────────────────────────┘
│                                         │
│   Time: ───────────────────────────────▶│
│         x=a+b   y=c*d   z=x+y          │
│                                         │
└─────────────────────────────────────────┘
```

### The Dataflow Model

In dataflow, operations are **nodes** and data flows along **edges**:

```
┌─────────────────────────────────────────┐
│          DATAFLOW EXECUTION             │
├─────────────────────────────────────────┤
│                                         │
│   a ──┐        c ──┐                    │
│       ├──[+]──┐    ├──[*]──┐            │
│   b ──┘       │    │       │            │
│               └────┴──[+]──▶ z          │
│       x               y                 │
│                                         │
│   + and * fire simultaneously!          │
│   Second + fires when both arrive       │
│                                         │
└─────────────────────────────────────────┘
```

**Key insight:** There's no program counter. The `+` node computing `x` fires when `a` and `b` arrive. The `*` node fires when `c` and `d` arrive. These happen in parallel. The final `+` fires when both `x` and `y` are ready.

## Why Hardware is Naturally Dataflow

### Combinational Logic

Every combinational circuit is dataflow. When you write RHDL, you're describing a dataflow graph:

```
      a ──┐
          ├──[Adder]──┐
      b ──┘           │
                      ├──[Adder]──▶ z
      c ──┐           │
          ├──[Mult]───┘
      d ──┘
```

The hardware **is** the dataflow graph. No control needed—data flows through combinational logic at the speed of electrons. The `+` and `*` operations fire simultaneously when their inputs are ready.

### Signals as Data Tokens

In dataflow terminology:
- **Signals** are wires carrying data tokens
- **Components** are nodes that consume and produce tokens
- **Connections** are edges in the dataflow graph

> See [Appendix E](appendix-e-dataflow.md) for RHDL implementations of dataflow components.

## Dataflow Architectures

### Static Dataflow

In **static dataflow**, each edge can hold at most one token at a time:

```
┌─────────────────────────────────────────┐
│          STATIC DATAFLOW                │
├─────────────────────────────────────────┤
│                                         │
│   ●──────────[Node]──────────●          │
│   token                      token      │
│                                         │
│   Rule: Node fires only when:           │
│   - All inputs have exactly one token   │
│   - Output edge is empty                │
│                                         │
└─────────────────────────────────────────┘
```

This is **exactly** how RHDL combinational logic works! Each wire has one value at a time.

### Dynamic Dataflow

**Dynamic dataflow** allows multiple tokens on edges, using tags to match:

```
┌─────────────────────────────────────────┐
│          DYNAMIC DATAFLOW               │
├─────────────────────────────────────────┤
│                                         │
│   [a,1] [a,2] ──[Node]── [b,1] [b,2]   │
│   tagged tokens         tagged tokens   │
│                                         │
│   Tokens with same tag processed        │
│   together; different tags pipelined    │
│                                         │
└─────────────────────────────────────────┘
```

This enables **pipelining**—multiple computations in flight simultaneously.

### Token Matching

The key operation in dataflow machines is **token matching**:

```
     Inputs arrive:          Matching:           Fire:
        a₁                   a₁ ─┐
        b₁                   b₁ ─┼─▶ [Node] ─▶ c₁
        a₂                   a₂ ─┤
        b₂                   b₂ ─┴─▶ [Node] ─▶ c₂

     Wait for matching pairs before firing
```

In RHDL with clock edges, this matching happens at clock boundaries—all signals sample simultaneously.

## Dataflow in RHDL

RHDL naturally expresses dataflow computation:

### Pure Combinational Dataflow

Without clocks, changes propagate instantly through the dataflow graph. This is **pure dataflow**—no state, no sequencing.

### Clocked Dataflow (Synchronous)

Adding registers creates **synchronous dataflow** where clock edges advance tokens through a pipeline. Each stage holds its value until the next clock.

### Dataflow Patterns

Common dataflow patterns map directly to hardware:

| Pattern | Description | Hardware |
|---------|-------------|----------|
| **Map** | Apply function to each token | Combinational logic |
| **Filter** | Pass tokens matching condition | Mux + valid logic |
| **Reduce** | Accumulate stream to single value | Register + adder |
| **Fork** | Duplicate token to multiple outputs | Wire fanout |
| **Join** | Combine tokens from multiple inputs | AND of valid signals |

> See [Appendix E](appendix-e-dataflow.md) for complete RHDL implementations of all dataflow patterns.

## Historical Dataflow Machines

### MIT Tagged-Token Dataflow (1970s-80s)

Arvind and colleagues at MIT built several dataflow computers:

```
┌─────────────────────────────────────────┐
│      MIT TAGGED-TOKEN ARCHITECTURE      │
├─────────────────────────────────────────┤
│                                         │
│  ┌──────────┐    ┌──────────┐          │
│  │  Token   │───▶│ Matching │          │
│  │  Queue   │    │   Unit   │          │
│  └──────────┘    └────┬─────┘          │
│                       │                 │
│                       ▼                 │
│  ┌──────────┐    ┌──────────┐          │
│  │   ALU    │◀───│  Fetch   │          │
│  │ Cluster  │    │   Unit   │          │
│  └────┬─────┘    └──────────┘          │
│       │                                 │
│       └──────────▶ Token Queue         │
│                    (results)            │
│                                         │
└─────────────────────────────────────────┘
```

**Key innovation:** Tokens carry tags indicating which computation they belong to, enabling massive parallelism.

### Manchester Dataflow Machine (1981)

First working tagged-token dataflow computer:
- 20+ processing elements
- I-structure memory for arrays
- Showed dataflow could work at scale

### Why Dataflow Machines Faded

Pure dataflow computers lost to von Neumann machines because:
1. **Token matching overhead** - Finding matching tokens is expensive
2. **Memory access patterns** - Random access doesn't match dataflow
3. **Sequential code** - Most software is written sequentially
4. **Cache effectiveness** - Von Neumann caches work well

But dataflow ideas survived in:
- **Hardware description languages** (RHDL, Verilog)
- **Stream processing** (GPUs, TPUs)
- **Reactive programming** (RxJS, Akka Streams)

## Modern Dataflow

### GPUs as Dataflow Engines

Modern GPUs are essentially dataflow machines:

```
┌─────────────────────────────────────────┐
│           GPU DATAFLOW MODEL            │
├─────────────────────────────────────────┤
│                                         │
│   Data ──▶ [SM₀] ──┐                    │
│        ──▶ [SM₁] ──┼──▶ Results         │
│        ──▶ [SM₂] ──┤                    │
│        ──▶ [SM₃] ──┘                    │
│                                         │
│   Thousands of cores, data-parallel     │
│   Same operation on different data      │
│                                         │
└─────────────────────────────────────────┘
```

### FPGAs: Spatial Dataflow

FPGAs implement **spatial dataflow**—the dataflow graph is physically laid out:

```
┌─────────────────────────────────────────┐
│           FPGA AS DATAFLOW              │
├─────────────────────────────────────────┤
│                                         │
│   ┌───┐    ┌───┐    ┌───┐    ┌───┐    │
│   │ + │───▶│ * │───▶│ + │───▶│ R │    │
│   └───┘    └───┘    └───┘    └───┘    │
│                                         │
│   The graph IS the hardware             │
│   Data flows spatially through fabric   │
│                                         │
└─────────────────────────────────────────┘
```

This is exactly what RHDL synthesis produces!

### Streaming Accelerators

Modern ML accelerators use dataflow for matrix operations:

```
    Weight      Input
    Stream      Stream
       │          │
       ▼          ▼
     ┌────────────────┐
     │  Systolic      │
     │  Array         │◀── Dataflow through array
     │  (Ch. 6)       │
     └───────┬────────┘
             │
             ▼
         Output Stream
```

## Hands-On Exercises

### Exercise 1: Dataflow Graph

Draw the dataflow graph for:
```
result = (a + b) * (c - d) + (e * f)
```

Identify which operations can execute in parallel.

### Exercise 2: Pipeline Latency

Given a 3-stage pipeline with operations taking 1, 2, and 1 cycles respectively:
- What is the latency (time for one item)?
- What is the throughput (items per cycle)?
- How many items can be "in flight"?

### Exercise 3: Dataflow Filter

Design a filter component that passes only even numbers. What signals do you need? How do you compute the valid output?

> Implement your solution using the patterns in [Appendix E](appendix-e-dataflow.md).

## Key Takeaways

1. **Dataflow has no program counter** - Operations fire when inputs arrive
2. **Hardware IS dataflow** - RHDL designs are dataflow graphs
3. **Parallelism is automatic** - Independent operations execute simultaneously
4. **Tokens carry data** - Valid signals indicate token presence
5. **Synchronous = clocked dataflow** - Clock edges synchronize token flow

## Further Reading

- *Dataflow Architectures* by Arvind and Culler - Classic survey
- *The Manchester Dataflow Machine* - First working implementation
- *Spatial Computing* papers - Modern FPGA dataflow

> See [Appendix E](appendix-e-dataflow.md) for formal dataflow semantics and advanced RHDL patterns.
