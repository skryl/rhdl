# Appendix H: Systolic Array Patterns

*Companion appendix to [Chapter 6: Systolic Arrays](06-systolic-arrays.md)*

## Overview

This appendix provides complete RHDL implementations of systolic array components for matrix operations, convolutions, and other parallel computations.

## Basic Processing Element

The fundamental building block of any systolic array:

```ruby
class SystolicPE < SimComponent
  input :clk
  input :reset
  input :a_in, width: 8
  input :b_in, width: 8
  output :a_out, width: 8
  output :b_out, width: 8
  output :result, width: 16

  register :accumulator, width: 16
  register :a_reg, width: 8
  register :b_reg, width: 8

  behavior do
    on_rising_edge(clk) do
      if reset
        accumulator <= 0
        a_reg <= 0
        b_reg <= 0
      else
        # Multiply-accumulate
        accumulator <= accumulator + (a_in * b_in)

        # Pass data through
        a_reg <= a_in
        b_reg <= b_in
      end
    end

    # Outputs
    a_out <= a_reg
    b_out <= b_reg
    result <= accumulator
  end
end
```

## 2×2 Systolic Array

A complete 2×2 matrix multiply array:

```ruby
class SystolicArray2x2 < SimComponent
  input :clk
  input :reset

  # Staggered inputs for rows and columns
  input :a0, width: 8    # Row 0 input
  input :a1, width: 8    # Row 1 input
  input :b0, width: 8    # Column 0 input
  input :b1, width: 8    # Column 1 input

  # Results
  output :c00, width: 16
  output :c01, width: 16
  output :c10, width: 16
  output :c11, width: 16

  # Instantiate 4 PEs
  instance :pe00, SystolicPE
  instance :pe01, SystolicPE
  instance :pe10, SystolicPE
  instance :pe11, SystolicPE

  # Internal wires for data flow
  wire :a00_to_01, width: 8
  wire :a10_to_11, width: 8
  wire :b00_to_10, width: 8
  wire :b01_to_11, width: 8

  # Connect clocks and resets
  port :clk => [[:pe00, :clk], [:pe01, :clk],
                [:pe10, :clk], [:pe11, :clk]]
  port :reset => [[:pe00, :reset], [:pe01, :reset],
                  [:pe10, :reset], [:pe11, :reset]]

  # Row inputs
  port :a0 => [:pe00, :a_in]
  port :a1 => [:pe10, :a_in]

  # Column inputs
  port :b0 => [:pe00, :b_in]
  port :b1 => [:pe01, :b_in]

  # Horizontal data flow (a values flow right)
  port [:pe00, :a_out] => :a00_to_01
  port :a00_to_01 => [:pe01, :a_in]
  port [:pe10, :a_out] => :a10_to_11
  port :a10_to_11 => [:pe11, :a_in]

  # Vertical data flow (b values flow down)
  port [:pe00, :b_out] => :b00_to_10
  port :b00_to_10 => [:pe10, :b_in]
  port [:pe01, :b_out] => :b01_to_11
  port :b01_to_11 => [:pe11, :b_in]

  # Results
  port [:pe00, :result] => :c00
  port [:pe01, :result] => :c01
  port [:pe10, :result] => :c10
  port [:pe11, :result] => :c11
end
```

## Input Staging

Generates the staggered input timing required for systolic matrix multiply:

```ruby
class SystolicInputStager < SimComponent
  input :clk
  input :start
  input :row0, width: 8, count: 2  # [a00, a01]
  input :row1, width: 8, count: 2  # [a10, a11]
  input :col0, width: 8, count: 2  # [b00, b10]
  input :col1, width: 8, count: 2  # [b01, b11]

  output :a0, width: 8
  output :a1, width: 8
  output :b0, width: 8
  output :b1, width: 8

  register :cycle, width: 3

  behavior do
    on_rising_edge(clk) do
      if start
        cycle <= 0
      else
        cycle <= cycle + 1
      end
    end

    # Staggered input schedule
    case cycle
    when 0
      a0 <= row0[0]  # a00
      b0 <= col0[0]  # b00
      a1 <= 0
      b1 <= 0
    when 1
      a0 <= row0[1]  # a01
      b0 <= col0[1]  # b10
      a1 <= row1[0]  # a10
      b1 <= col1[0]  # b01
    when 2
      a0 <= 0
      b0 <= 0
      a1 <= row1[1]  # a11
      b1 <= col1[1]  # b11
    else
      a0 <= 0
      a1 <= 0
      b0 <= 0
      b1 <= 0
    end
  end
end
```

## Convolution PE

Processing element for 1D convolution / FIR filters:

```ruby
class ConvolutionPE < SimComponent
  input :clk
  input :x_in, width: 8
  input :coeff, width: 8
  input :acc_in, width: 16
  output :x_out, width: 8
  output :acc_out, width: 16

  register :x_reg, width: 8

  behavior do
    on_rising_edge(clk) do
      x_reg <= x_in
    end

    x_out <= x_reg
    acc_out <= acc_in + (x_in * coeff)
  end
end
```

## N-Tap FIR Filter

Complete FIR filter using convolution PEs:

```ruby
class FIRFilter < SimComponent
  input :clk
  input :x_in, width: 8
  input :coeff0, width: 8
  input :coeff1, width: 8
  input :coeff2, width: 8
  input :coeff3, width: 8
  output :y_out, width: 16

  # Chain of convolution PEs
  instance :pe0, ConvolutionPE
  instance :pe1, ConvolutionPE
  instance :pe2, ConvolutionPE
  instance :pe3, ConvolutionPE

  wire :x0_to_1, width: 8
  wire :x1_to_2, width: 8
  wire :x2_to_3, width: 8
  wire :acc0_to_1, width: 16
  wire :acc1_to_2, width: 16
  wire :acc2_to_3, width: 16

  # Clock distribution
  port :clk => [[:pe0, :clk], [:pe1, :clk], [:pe2, :clk], [:pe3, :clk]]

  # Input and coefficients
  port :x_in => [:pe0, :x_in]
  port :coeff0 => [:pe0, :coeff]
  port :coeff1 => [:pe1, :coeff]
  port :coeff2 => [:pe2, :coeff]
  port :coeff3 => [:pe3, :coeff]

  # First PE starts with zero accumulator
  behavior do
    pe0.set_input(:acc_in, 0)
  end

  # Chain data and accumulator flow
  port [:pe0, :x_out] => :x0_to_1
  port :x0_to_1 => [:pe1, :x_in]
  port [:pe0, :acc_out] => :acc0_to_1
  port :acc0_to_1 => [:pe1, :acc_in]

  port [:pe1, :x_out] => :x1_to_2
  port :x1_to_2 => [:pe2, :x_in]
  port [:pe1, :acc_out] => :acc1_to_2
  port :acc1_to_2 => [:pe2, :acc_in]

  port [:pe2, :x_out] => :x2_to_3
  port :x2_to_3 => [:pe3, :x_in]
  port [:pe2, :acc_out] => :acc2_to_3
  port :acc2_to_3 => [:pe3, :acc_in]

  # Output from last PE
  port [:pe3, :acc_out] => :y_out
end
```

## Compare-Exchange Cell for Sorting

Used in systolic sorting networks:

```ruby
class CompareExchangeCell < SimComponent
  input :clk
  input :a_in, width: 8
  input :b_in, width: 8
  output :min_out, width: 8
  output :max_out, width: 8

  register :a_reg, width: 8
  register :b_reg, width: 8

  behavior do
    on_rising_edge(clk) do
      if a_in < b_in
        a_reg <= a_in
        b_reg <= b_in
      else
        a_reg <= b_in
        b_reg <= a_in
      end
    end

    min_out <= a_reg
    max_out <= b_reg
  end
end
```

## Data Flow Patterns

### Weight Stationary

Weights remain fixed in PEs; activations flow through:

```ruby
class WeightStationaryPE < SimComponent
  input :clk
  input :load_weight
  input :weight_in, width: 8
  input :activation_in, width: 8
  input :psum_in, width: 16
  output :activation_out, width: 8
  output :psum_out, width: 16

  register :weight, width: 8
  register :act_reg, width: 8

  behavior do
    on_rising_edge(clk) do
      if load_weight
        weight <= weight_in
      end
      act_reg <= activation_in
    end

    activation_out <= act_reg
    psum_out <= psum_in + (weight * activation_in)
  end
end
```

### Output Stationary

Partial sums accumulate in place; weights and activations flow:

```ruby
class OutputStationaryPE < SimComponent
  input :clk
  input :reset
  input :weight_in, width: 8
  input :activation_in, width: 8
  output :weight_out, width: 8
  output :activation_out, width: 8
  output :result, width: 16

  register :accumulator, width: 16
  register :w_reg, width: 8
  register :a_reg, width: 8

  behavior do
    on_rising_edge(clk) do
      if reset
        accumulator <= 0
      else
        accumulator <= accumulator + (weight_in * activation_in)
      end
      w_reg <= weight_in
      a_reg <= activation_in
    end

    weight_out <= w_reg
    activation_out <= a_reg
    result <= accumulator
  end
end
```

## Timing Analysis

### 2×2 Matrix Multiply Schedule

```
Cycle  PE00        PE01        PE10        PE11
─────  ──────────  ──────────  ──────────  ──────────
  0    a00*b00     -           -           -
  1    a01*b10     a00*b01     a10*b00     -
  2    -           a01*b11     a11*b10     a10*b01
  3    -           -           -           a11*b11
  4    C00 ready   C01 ready   C10 ready   C11 ready
```

**Latency:** N + N - 1 = 2N - 1 cycles for N×N multiply
**Throughput:** 1 result matrix per N cycles (after pipeline fills)

## Performance Metrics

| Array Size | PEs | Ops/Cycle | Latency | Throughput |
|------------|-----|-----------|---------|------------|
| 2×2 | 4 | 4 MACs | 3 cycles | 1 matrix/2 cycles |
| 4×4 | 16 | 16 MACs | 7 cycles | 1 matrix/4 cycles |
| 8×8 | 64 | 64 MACs | 15 cycles | 1 matrix/8 cycles |
| 256×256 | 65,536 | 65,536 MACs | 511 cycles | 1 matrix/256 cycles |

## Further Resources

- H.T. Kung's original systolic array papers (1978-1982)
- Google TPU architecture whitepapers
- "Eyeriss: A Spatial Architecture for Energy-Efficient Dataflow"

> Return to [Chapter 6](06-systolic-arrays.md) for conceptual introduction.
