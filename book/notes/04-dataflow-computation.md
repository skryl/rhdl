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

Every combinational circuit in RHDL is dataflow:

```ruby
class DataflowExample < SimComponent
  input :a, width: 8
  input :b, width: 8
  input :c, width: 8
  input :d, width: 8
  output :z, width: 8

  behavior do
    x = a + b        # Fires when a, b change
    y = c * d        # Fires when c, d change (parallel!)
    z <= x + y       # Fires when x, y ready
  end
end
```

This synthesizes to:
```
      a ──┐
          ├──[Adder]──┐
      b ──┘           │
                      ├──[Adder]──▶ z
      c ──┐           │
          ├──[Mult]───┘
      d ──┘
```

The hardware **is** the dataflow graph. No control needed—data flows through combinational logic at the speed of electrons.

### Signals as Data Tokens

In dataflow terminology:
- **Signals** are wires carrying data tokens
- **Components** are nodes that consume and produce tokens
- **Connections** are edges in the dataflow graph

```ruby
# This RHDL code IS a dataflow graph
port :a => [:adder, :a]       # Edge from a to adder.a
port :b => [:adder, :b]       # Edge from b to adder.b
port [:adder, :sum] => :result  # Edge from adder.sum to result
```

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

### Pure Combinational Dataflow

```ruby
class PureDataflow < SimComponent
  input :x, width: 16
  input :y, width: 16
  output :result, width: 16

  # These all execute "simultaneously" in hardware
  behavior do
    a = x + y
    b = x - y
    c = a * b        # (x+y)(x-y) = x² - y²
    result <= c
  end
end
```

No clocks, no state—pure dataflow. Changes propagate instantly (in simulation, within one delta cycle).

### Clocked Dataflow (Synchronous)

```ruby
class SyncDataflow < SimComponent
  input :clk
  input :x, width: 16
  output :result, width: 16

  wire :stage1, width: 16
  wire :stage2, width: 16

  # Pipeline: data flows through registers
  behavior do
    on_rising_edge(clk) do
      stage1 <= x * x           # Stage 1: square
      stage2 <= stage1 + 1      # Stage 2: add 1
      result <= stage2 * 2      # Stage 3: double
    end
  end
end
```

Each clock edge advances tokens through the pipeline—synchronous dataflow.

### Dataflow Patterns

**Map (apply function to stream):**
```ruby
class Map < SimComponent
  input :data_in, width: 8
  input :valid_in
  output :data_out, width: 8
  output :valid_out

  behavior do
    data_out <= data_in * 2    # The function
    valid_out <= valid_in
  end
end
```

**Filter (select matching tokens):**
```ruby
class Filter < SimComponent
  input :data_in, width: 8
  input :valid_in
  output :data_out, width: 8
  output :valid_out

  behavior do
    passes = (data_in > 100)
    data_out <= data_in
    valid_out <= valid_in & passes
  end
end
```

**Reduce (accumulate stream):**
```ruby
class Reduce < SimComponent
  input :clk
  input :data_in, width: 8
  input :valid_in
  input :reset
  output :sum, width: 16

  register :accumulator, width: 16

  behavior do
    on_rising_edge(clk) do
      if reset
        accumulator <= 0
      elsif valid_in
        accumulator <= accumulator + data_in
      end
    end
    sum <= accumulator
  end
end
```

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

## RHDL Dataflow Examples

### Token-Based Pipeline

```ruby
class TokenPipeline < SimComponent
  input :clk
  input :data_in, width: 8
  input :valid_in
  output :data_out, width: 8
  output :valid_out

  # Internal pipeline registers
  register :stage1_data, width: 8
  register :stage1_valid
  register :stage2_data, width: 8
  register :stage2_valid

  behavior do
    on_rising_edge(clk) do
      # Stage 1: Double
      stage1_data <= data_in << 1
      stage1_valid <= valid_in

      # Stage 2: Add offset
      stage2_data <= stage1_data + 10
      stage2_valid <= stage1_valid
    end

    # Output
    data_out <= stage2_data
    valid_out <= stage2_valid
  end
end
```

### Dataflow Join (Synchronize Two Streams)

```ruby
class DataflowJoin < SimComponent
  input :clk
  input :a_data, width: 8
  input :a_valid
  input :b_data, width: 8
  input :b_valid
  output :sum, width: 9
  output :valid_out

  behavior do
    # Only output when both inputs valid
    both_ready = a_valid & b_valid
    sum <= a_data + b_data
    valid_out <= both_ready
  end
end
```

### Dataflow Fork (Split Stream)

```ruby
class DataflowFork < SimComponent
  input :data_in, width: 8
  input :valid_in
  output :out_a, width: 8
  output :out_b, width: 8
  output :valid_a
  output :valid_b

  behavior do
    out_a <= data_in
    out_b <= data_in
    valid_a <= valid_in
    valid_b <= valid_in
  end
end
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

### Exercise 3: RHDL Dataflow Filter

Implement a filter that passes only even numbers:
```ruby
class EvenFilter < SimComponent
  # Pass through only when (data_in & 1) == 0
end
```

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
