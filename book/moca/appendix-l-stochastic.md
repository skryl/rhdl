# Appendix L: Stochastic Implementation

*Companion appendix to [Chapter 12: Stochastic Computing](12-stochastic-computing.md)*

## Overview

This appendix provides RHDL implementations of stochastic computing primitives, from random number generators to complete stochastic neural networks.

---

## Random Number Generation

### Linear Feedback Shift Register (LFSR)

```ruby
module RHDL::Stochastic
  # Galois LFSR for pseudo-random bit generation
  class LFSR < SimComponent
    parameter :width, default: 16
    parameter :taps, default: [16, 15, 13, 4]  # x^16 + x^15 + x^13 + x^4 + 1
    parameter :seed, default: 1

    input :clk
    input :reset
    output :bit          # Single random bit
    output :value, width: width  # Full register value

    wire :state, width: width

    behavior do
      on_rising_edge(:clk) do
        if reset == 1
          state <= seed
        else
          # Galois LFSR: XOR taps into LSB, shift right
          feedback = 0
          taps.each { |t| feedback ^= (state >> (t - 1)) & 1 }

          state <= (state >> 1) | (feedback << (width - 1))
        end
      end

      bit <= state[0]
      value <= state
    end
  end

  # Multiple uncorrelated LFSRs
  class LFSRBank < SimComponent
    parameter :count, default: 4
    parameter :width, default: 16

    input :clk
    input :reset
    output :bits, width: count

    # Different polynomials for each LFSR
    POLYNOMIALS = [
      [16, 15, 13, 4],    # x^16 + x^15 + x^13 + x^4 + 1
      [16, 14, 13, 11],   # x^16 + x^14 + x^13 + x^11 + 1
      [16, 12, 3, 1],     # x^16 + x^12 + x^3 + x + 1
      [16, 15, 10, 3],    # x^16 + x^15 + x^10 + x^3 + 1
    ]

    # Instantiate LFSRs with different seeds and taps
    behavior do
      count.times do |i|
        # Each LFSR instance would be created here
        # Using different polynomial and seed
      end
    end
  end
end
```

### Stochastic Number Generator (SNG)

```ruby
module RHDL::Stochastic
  # Convert binary value to stochastic bit stream
  class StochasticNumberGenerator < SimComponent
    parameter :width, default: 8  # Binary input precision

    input :clk
    input :value, width: width    # Binary value [0, 2^width - 1]
    output :stream                # Stochastic output bit

    instance :lfsr, LFSR, width: width, seed: 12345

    wire :random_value, width: width

    port :clk => [:lfsr, :clk]
    port [:lfsr, :value] => :random_value

    behavior do
      # Compare input with random number
      # P(stream = 1) = value / 2^width
      stream <= (random_value < value) ? 1 : 0
    end
  end

  # Bipolar SNG: value in [-1, 1] mapped to [0, 2^width]
  class BipolarSNG < SimComponent
    parameter :width, default: 8

    input :clk
    input :value, width: width    # Unsigned, represents (x + 1) / 2
    output :stream

    instance :sng, StochasticNumberGenerator, width: width

    port :clk => [:sng, :clk]
    port :value => [:sng, :value]
    port [:sng, :stream] => :stream
  end
end
```

---

## Stochastic Arithmetic

### Multiplication

```ruby
module RHDL::Stochastic
  # Unipolar multiplication: P(out) = P(a) × P(b)
  class UnipolarMultiplier < SimComponent
    input :a       # Stochastic stream
    input :b       # Stochastic stream
    output :product

    behavior do
      product <= a & b  # AND gate!
    end
  end

  # Bipolar multiplication: out = a × b where a, b ∈ [-1, 1]
  class BipolarMultiplier < SimComponent
    input :a
    input :b
    output :product

    behavior do
      product <= ~(a ^ b)  # XNOR gate
    end
  end

  # Multi-input unipolar multiplier
  class MultiMultiplier < SimComponent
    parameter :n, default: 4

    input :inputs, width: n
    output :product

    behavior do
      # AND all inputs together
      product <= inputs == ((1 << n) - 1) ? 1 : 0
    end
  end
end
```

### Addition

```ruby
module RHDL::Stochastic
  # Scaled addition: out = (a + b) / 2
  class ScaledAdder < SimComponent
    input :a
    input :b
    input :select  # Random 50% stream

    output :sum

    behavior do
      # MUX: when select=0, output a; when select=1, output b
      sum <= select == 0 ? a : b
    end
  end

  # Multi-input scaled adder
  class MultiScaledAdder < SimComponent
    parameter :n, default: 4
    parameter :sel_width, default: 2  # log2(n)

    input :inputs, width: n
    input :select, width: sel_width  # Random uniform stream

    output :sum

    behavior do
      # Select one of n inputs randomly
      idx = select % n
      sum <= (inputs >> idx) & 1
    end
  end

  # Weighted adder with stochastic mixing
  class WeightedAdder < SimComponent
    input :a
    input :b
    input :weight  # Stochastic stream encoding weight w

    output :sum    # w*a + (1-w)*b

    behavior do
      # MUX controlled by weight stream
      sum <= weight == 1 ? a : b
    end
  end
end
```

### Other Operations

```ruby
module RHDL::Stochastic
  # Bipolar subtraction: a - b
  class BipolarSubtractor < SimComponent
    input :a
    input :b
    output :difference

    behavior do
      # In bipolar, NOT negates, then multiply
      # a - b = a × (-b) when one is -1 or 1... actually:
      # XOR for subtraction in bipolar
      difference <= a ^ b
    end
  end

  # Absolute value (bipolar)
  class AbsoluteValue < SimComponent
    input :a
    output :abs_a

    # |a| = a × a in bipolar (same stream correlated)
    # But we need uncorrelated copy, so use:
    # |a| = XNOR(a, a) with decorrelation
    instance :decorr, Decorrelator

    port :a => [:decorr, :input]

    behavior do
      abs_a <= ~(a ^ decorr.output)
    end
  end

  # Square (unipolar) - trivial!
  class Square < SimComponent
    input :a
    output :squared

    # P(a ∧ a) = P(a)² when streams are independent
    # But same stream: P(a ∧ a) = P(a), not P(a)²
    # Need decorrelated copy
    instance :decorr, Decorrelator

    port :a => [:decorr, :input]

    behavior do
      squared <= a & decorr.output
    end
  end
end
```

---

## Decorrelation

```ruby
module RHDL::Stochastic
  # Simple decorrelator using delay
  class Decorrelator < SimComponent
    parameter :delay, default: 7  # Prime number works well

    input :clk
    input :input
    output :output

    wire :shift_reg, width: delay

    behavior do
      on_rising_edge(:clk) do
        shift_reg <= (shift_reg << 1) | input
      end

      output <= shift_reg[delay - 1]
    end
  end

  # Decorrelator using LFSR re-randomization
  class LFSRDecorrelator < SimComponent
    parameter :width, default: 8

    input :clk
    input :value, width: width  # Original binary value
    output :stream1
    output :stream2             # Uncorrelated stream, same probability

    instance :lfsr1, LFSR, width: width, seed: 12345
    instance :lfsr2, LFSR, width: width, seed: 67890  # Different seed

    port :clk => [[:lfsr1, :clk], [:lfsr2, :clk]]

    behavior do
      stream1 <= lfsr1.value < value ? 1 : 0
      stream2 <= lfsr2.value < value ? 1 : 0
    end
  end
end
```

---

## Complex Operations

### Division

```ruby
module RHDL::Stochastic
  # Stochastic division using JK flip-flop
  class StochasticDivider < SimComponent
    input :clk
    input :a    # Dividend (stochastic)
    input :b    # Divisor (stochastic)
    output :quotient

    wire :state

    behavior do
      on_rising_edge(:clk) do
        # JK flip-flop behavior:
        # J=a, K=b
        # When J=1, K=0: set (Q=1)
        # When J=0, K=1: reset (Q=0)
        # When J=1, K=1: toggle
        # When J=0, K=0: hold

        if a == 1 && b == 0
          state <= 1
        elsif a == 0 && b == 1
          state <= 0
        elsif a == 1 && b == 1
          state <= ~state
        end
        # else hold
      end

      quotient <= state
    end
  end
end
```

### Exponentiation

```ruby
module RHDL::Stochastic
  # Approximate e^x for small x using FSM
  class StochasticExp < SimComponent
    parameter :states, default: 16

    input :clk
    input :x      # Input stream (small positive values work best)
    output :exp_x

    wire :state, width: 4

    # FSM approximates exponential
    # State represents accumulated value
    behavior do
      on_rising_edge(:clk) do
        if x == 1
          # Increase state (bounded)
          state <= state < (states - 1) ? state + 1 : state
        else
          # Decrease state (bounded)
          state <= state > 0 ? state - 1 : state
        end
      end

      # Output probability based on state
      exp_x <= state > (states / 2) ? 1 : 0
    end
  end
end
```

### Activation Functions

```ruby
module RHDL::Stochastic
  # Stochastic tanh approximation
  class StochasticTanh < SimComponent
    input :clk
    input :x      # Bipolar input
    output :tanh_x

    # Use saturating counter (stanh)
    parameter :depth, default: 8

    wire :counter, width: 4

    behavior do
      on_rising_edge(:clk) do
        if x == 1
          counter <= counter < depth ? counter + 1 : counter
        else
          counter <= counter > 0 ? counter - 1 : counter
        end
      end

      tanh_x <= counter >= (depth / 2) ? 1 : 0
    end
  end

  # Stochastic ReLU
  class StochasticReLU < SimComponent
    input :x       # Bipolar input
    input :sign    # Sign bit stream (1 = positive)
    output :relu_x

    behavior do
      # Pass through if positive, else 0
      relu_x <= sign == 1 ? x : 0
    end
  end

  # Stochastic sigmoid using FSM
  class StochasticSigmoid < SimComponent
    parameter :depth, default: 16

    input :clk
    input :reset
    input :x       # Bipolar input
    output :sigmoid_x

    wire :state, width: 5

    behavior do
      on_rising_edge(:clk) do
        if reset == 1
          state <= depth / 2
        elsif x == 1
          state <= state < depth ? state + 1 : state
        else
          state <= state > 0 ? state - 1 : state
        end
      end

      sigmoid_x <= state > 0 ? 1 : 0
    end
  end
end
```

---

## Stochastic-Binary Conversion

```ruby
module RHDL::Stochastic
  # Convert stochastic stream to binary
  class StochasticTooBinary < SimComponent
    parameter :width, default: 8
    parameter :samples, default: 256

    input :clk
    input :reset
    input :stream      # Stochastic input
    input :valid       # Sample valid signal

    output :value, width: width
    output :done

    wire :counter, width: width + 8  # Extra bits for counting
    wire :sample_count, width: 16

    behavior do
      on_rising_edge(:clk) do
        if reset == 1
          counter <= 0
          sample_count <= 0
          done <= 0
        elsif sample_count < samples
          if valid == 1
            counter <= counter + stream
            sample_count <= sample_count + 1
          end
        else
          done <= 1
        end
      end

      # Scale counter to output width
      value <= (counter * ((1 << width) - 1)) / samples
    end
  end

  # Binary to stochastic with configurable precision
  class BinaryToStochastic < SimComponent
    parameter :width, default: 8

    input :clk
    input :reset
    input :binary_value, width: width
    input :enable

    output :stream
    output :stream_valid

    instance :lfsr, LFSR, width: width

    port :clk => [:lfsr, :clk]
    port :reset => [:lfsr, :reset]

    behavior do
      if enable == 1
        stream <= lfsr.value < binary_value ? 1 : 0
        stream_valid <= 1
      else
        stream <= 0
        stream_valid <= 0
      end
    end
  end
end
```

---

## Stochastic Neural Network

```ruby
module RHDL::Stochastic
  # Single stochastic neuron
  class StochasticNeuron < SimComponent
    parameter :n_inputs, default: 4

    input :clk
    input :inputs, width: n_inputs    # Stochastic input streams
    input :weights, width: n_inputs   # Stochastic weight streams
    input :select, width: 2           # Random selection for averaging

    output :activation

    # Multiply each input by its weight
    wire :products, width: n_inputs

    behavior do
      # Weighted sum approximation
      n_inputs.times do |i|
        products[i] <= inputs[i] & weights[i]  # Multiply
      end

      # Select one product randomly (scaled addition)
      idx = select % n_inputs
      activation <= (products >> idx) & 1
    end
  end

  # Stochastic neural network layer
  class StochasticLayer < SimComponent
    parameter :n_inputs, default: 4
    parameter :n_outputs, default: 4

    input :clk
    input :reset
    input :inputs, width: n_inputs
    input :weights, width: n_inputs * n_outputs
    input :rand_select, width: 8

    output :outputs, width: n_outputs

    behavior do
      n_outputs.times do |o|
        # Each output neuron
        weighted_sum = 0
        n_inputs.times do |i|
          weight_bit = (weights >> (o * n_inputs + i)) & 1
          input_bit = (inputs >> i) & 1
          weighted_sum += input_bit & weight_bit
        end

        # Approximate activation
        outputs[o] <= weighted_sum > (n_inputs / 2) ? 1 : 0
      end
    end
  end

  # Complete stochastic neural network
  class StochasticNetwork < SimComponent
    parameter :input_size, default: 8
    parameter :hidden_size, default: 8
    parameter :output_size, default: 4
    parameter :stream_length, default: 256

    input :clk
    input :reset
    input :start
    input :input_values, width: input_size * 8  # Binary inputs

    output :output_values, width: output_size * 8  # Binary outputs
    output :done

    # SNGs for inputs
    # Layers
    # Binary converters for outputs

    wire :cycle_count, width: 16
    wire :running

    behavior do
      on_rising_edge(:clk) do
        if reset == 1
          cycle_count <= 0
          running <= 0
          done <= 0
        elsif start == 1
          running <= 1
          cycle_count <= 0
        elsif running == 1
          cycle_count <= cycle_count + 1
          if cycle_count >= stream_length
            running <= 0
            done <= 1
          end
        end
      end
    end
  end
end
```

---

## Image Processing

```ruby
module RHDL::Stochastic
  # Stochastic 3x3 convolution kernel
  class StochasticConv3x3 < SimComponent
    input :clk
    input :pixels, width: 9    # 9 pixel streams
    input :kernel, width: 9    # 9 weight streams
    input :select, width: 4    # Random selection

    output :result

    wire :products, width: 9

    behavior do
      # Multiply each pixel by kernel weight
      9.times do |i|
        products[i] <= pixels[i] & kernel[i]
      end

      # Average (scaled sum) using random selection
      idx = select % 9
      result <= (products >> idx) & 1
    end
  end

  # Edge detection (Sobel-like)
  class StochasticEdgeDetector < SimComponent
    input :clk
    input :pixels, width: 9    # 3x3 window
    input :rand_h, width: 4    # Random for horizontal
    input :rand_v, width: 4    # Random for vertical

    output :edge

    # Sobel kernels (represented as probabilities)
    # Horizontal: [-1 0 1; -2 0 2; -1 0 1]
    # Vertical:   [-1 -2 -1; 0 0 0; 1 2 1]

    wire :gx, :gy

    behavior do
      # Simplified edge magnitude
      # Use XOR for detecting differences
      left = pixels[0] | pixels[3] | pixels[6]
      right = pixels[2] | pixels[5] | pixels[8]
      top = pixels[0] | pixels[1] | pixels[2]
      bottom = pixels[6] | pixels[7] | pixels[8]

      gx <= left ^ right
      gy <= top ^ bottom

      edge <= gx | gy
    end
  end
end
```

---

## Sample Programs

### Stochastic Multiplication Test

```ruby
# Verify stochastic multiplication accuracy
describe "Stochastic Multiplier" do
  it "approximates multiplication" do
    mult = RHDL::Stochastic::UnipolarMultiplier.new
    lfsr_a = RHDL::Stochastic::LFSR.new(seed: 12345)
    lfsr_b = RHDL::Stochastic::LFSR.new(seed: 67890)

    # Test 0.75 × 0.5 = 0.375
    a_threshold = 192  # 0.75 × 256
    b_threshold = 128  # 0.5 × 256

    ones_count = 0
    samples = 10000

    samples.times do
      lfsr_a.tick
      lfsr_b.tick

      a_bit = lfsr_a.value < a_threshold ? 1 : 0
      b_bit = lfsr_b.value < b_threshold ? 1 : 0

      mult.set_input(:a, a_bit)
      mult.set_input(:b, b_bit)
      mult.evaluate

      ones_count += mult.get_output(:product)
    end

    result = ones_count.to_f / samples
    expected = 0.375

    expect(result).to be_within(0.02).of(expected)
  end
end
```

### Neural Network Inference

```ruby
# Stochastic neural network for XOR
describe "Stochastic XOR Network" do
  it "computes XOR function" do
    # XOR requires hidden layer
    # Input layer: 2 neurons
    # Hidden layer: 2 neurons
    # Output layer: 1 neuron

    stream_length = 1000

    test_cases = [[0, 0, 0], [0, 1, 1], [1, 0, 1], [1, 1, 0]]

    test_cases.each do |a, b, expected|
      # Convert to stochastic
      a_stream = generate_stream(a * 255, stream_length)
      b_stream = generate_stream(b * 255, stream_length)

      # Process through network (simplified)
      output_count = 0
      stream_length.times do |i|
        # Hidden neurons with learned weights
        h1 = a_stream[i] & b_stream[i]  # AND
        h2 = a_stream[i] | b_stream[i]  # OR

        # Output: h2 AND NOT(h1) = XOR
        out = h2 & (~h1 & 1)
        output_count += out
      end

      result = output_count.to_f / stream_length
      expect(result).to be_within(0.1).of(expected)
    end
  end
end
```

---

## Further Resources

- Gaines, "Stochastic Computing Systems" (1969)
- Alaghi & Hayes, "Survey of Stochastic Computing" (2013)
- Brown & Card, "Stochastic Neural Computation" (2001)

> Return to [Chapter 12](12-stochastic-computing.md) for conceptual introduction.
