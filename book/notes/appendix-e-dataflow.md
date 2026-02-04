# Appendix E: Dataflow Architectures

*Companion appendix to [Chapter 4: Dataflow Computation](04-dataflow-computation.md)*

## Overview

This appendix provides RHDL implementations of dataflow patterns and architectures discussed in Chapter 4.

## Basic Dataflow Components

### Pure Combinational Dataflow

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

### Difference of Squares

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

### Synchronous Pipeline

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

## Dataflow Patterns

### Map (Apply Function to Stream)

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

### Filter (Select Matching Tokens)

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

# Even number filter
class EvenFilter < SimComponent
  input :data_in, width: 8
  input :valid_in
  output :data_out, width: 8
  output :valid_out

  behavior do
    is_even = ((data_in & 1) == 0)
    data_out <= data_in
    valid_out <= valid_in & is_even
  end
end
```

### Reduce (Accumulate Stream)

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

### Fork (Split Stream)

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

### Join (Synchronize Streams)

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

## Token-Based Pipeline

A complete token pipeline with valid/ready handshaking:

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

## Dataflow with Backpressure

For systems where downstream may not be ready:

```ruby
class BackpressurePipeline < SimComponent
  input :clk
  input :data_in, width: 8
  input :valid_in
  input :ready_in          # Downstream ready signal
  output :data_out, width: 8
  output :valid_out
  output :ready_out        # Upstream ready signal

  register :data_reg, width: 8
  register :valid_reg

  behavior do
    # We're ready if downstream is ready or we have no data
    ready_out <= ready_in | ~valid_reg

    on_rising_edge(clk) do
      if ready_in | ~valid_reg
        # Accept new data
        data_reg <= data_in
        valid_reg <= valid_in
      end
      # Otherwise, hold current data (backpressure)
    end

    data_out <= data_reg
    valid_out <= valid_reg
  end
end
```

## MIT Tagged-Token Style

Simplified tagged-token dataflow node:

```ruby
class TaggedTokenNode < SimComponent
  input :clk
  input :token_a, width: 16      # [tag:8][data:8]
  input :token_b, width: 16
  input :valid_a
  input :valid_b
  output :token_out, width: 16
  output :valid_out

  behavior do
    tag_a = token_a[15:8]
    tag_b = token_b[15:8]
    data_a = token_a[7:0]
    data_b = token_b[7:0]

    # Fire only when tags match
    tags_match = (tag_a == tag_b)
    both_valid = valid_a & valid_b

    # Compute result
    result_data = data_a + data_b
    token_out <= (tag_a << 8) | result_data
    valid_out <= both_valid & tags_match
  end
end
```

## Streaming Accelerator Pattern

For ML-style streaming computation:

```ruby
class StreamingMAC < SimComponent
  input :clk
  input :reset
  input :weight, width: 8
  input :activation, width: 8
  input :valid
  output :accumulator, width: 16
  output :done

  register :acc, width: 16
  register :count, width: 8

  MAC_COUNT = 8  # Accumulate 8 products

  behavior do
    on_rising_edge(clk) do
      if reset
        acc <= 0
        count <= 0
      elsif valid
        acc <= acc + (weight * activation)
        count <= count + 1
      end
    end

    accumulator <= acc
    done <= (count == MAC_COUNT)
  end
end
```

## Formal Dataflow Semantics

### Firing Rules

A dataflow node fires when:
1. All input edges have at least one token
2. All output edges have capacity (for bounded buffers)

```ruby
# Abstract dataflow node
class DataflowNode < SimComponent
  # Inputs with valid signals
  input :in1_data, width: 8
  input :in1_valid
  input :in2_data, width: 8
  input :in2_valid

  # Outputs with valid signals
  output :out_data, width: 8
  output :out_valid

  behavior do
    # Firing condition
    can_fire = in1_valid & in2_valid

    # Compute (only meaningful when firing)
    out_data <= in1_data + in2_data
    out_valid <= can_fire
  end
end
```

### Static vs Dynamic Dataflow

| Property | Static | Dynamic |
|----------|--------|---------|
| Tokens per edge | 1 | Many (tagged) |
| Parallelism | Limited | High |
| Hardware cost | Low | High (matching unit) |
| RHDL mapping | Combinational | Requires FIFO + tags |

## Further Resources

- Jack Dennis's MIT dataflow papers (1970s)
- Arvind's tagged-token architecture
- StreaMIT compiler for streaming languages

> Return to [Chapter 4](04-dataflow-computation.md) for conceptual introduction.
