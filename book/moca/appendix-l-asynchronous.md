# Appendix L: Asynchronous Implementation

*Companion appendix to [Chapter 12: Asynchronous Computing](12-asynchronous-computing.md)*

## Overview

This appendix provides RHDL implementations of asynchronous circuit primitives and complete self-timed systems.

---

## Core Primitives

### Muller C-Element

The fundamental asynchronous gate:

```ruby
module RHDL::Async
  # Muller C-element: output changes only when inputs agree
  class CElement < SimComponent
    input :a
    input :b
    output :c

    # Internal state (C-element has memory)
    wire :state, width: 1

    behavior do
      if a == 1 && b == 1
        state <= 1
        c <= 1
      elsif a == 0 && b == 0
        state <= 0
        c <= 0
      else
        c <= state  # Hold previous value
      end
    end
  end

  # Generalized C-element with N inputs
  class CElementN < SimComponent
    parameter :n, default: 2

    input :inputs, width: n
    output :c

    wire :state, width: 1

    behavior do
      if inputs == (2**n - 1)  # All ones
        state <= 1
        c <= 1
      elsif inputs == 0        # All zeros
        state <= 0
        c <= 0
      else
        c <= state             # Hold
      end
    end
  end
end
```

### Asymmetric C-Element

C-element with different set/reset thresholds:

```ruby
module RHDL::Async
  # Asymmetric C-element: m-of-n to set, k-of-n to reset
  class AsymmetricCElement < SimComponent
    parameter :n, default: 3    # Number of inputs
    parameter :m, default: 2    # Threshold to set (m-of-n)
    parameter :k, default: 1    # Threshold to reset (k-of-n zeros)

    input :inputs, width: n
    output :c

    wire :state, width: 1
    wire :ones_count, width: 4

    behavior do
      # Count ones in input
      count = 0
      n.times { |i| count += inputs[i] }
      ones_count <= count

      if ones_count >= m
        state <= 1
        c <= 1
      elsif ones_count <= (n - k)
        state <= 0
        c <= 0
      else
        c <= state
      end
    end
  end
end
```

---

## Dual-Rail Logic

### Dual-Rail Encoding

```ruby
module RHDL::Async::DualRail
  # Dual-rail encoded value
  # rail0=1, rail1=0 => DATA0
  # rail0=0, rail1=1 => DATA1
  # rail0=0, rail1=0 => NULL (spacer)
  # rail0=1, rail1=1 => INVALID

  class DualRailValue < SimComponent
    input :rail0
    input :rail1
    output :valid      # Data is present (not NULL)
    output :value      # The encoded value (when valid)
    output :is_null    # NULL spacer present

    behavior do
      is_null <= (rail0 == 0) && (rail1 == 0)
      valid <= (rail0 ^ rail1) == 1  # Exactly one rail high
      value <= rail1                  # rail1 carries the data bit
    end
  end

  # Dual-rail inverter (swap rails)
  class DualRailInverter < SimComponent
    input :in_rail0
    input :in_rail1
    output :out_rail0
    output :out_rail1

    behavior do
      out_rail0 <= in_rail1  # Swap!
      out_rail1 <= in_rail0
    end
  end

  # Dual-rail AND gate (NCL TH22)
  class DualRailAnd < SimComponent
    input :a_rail0, :a_rail1
    input :b_rail0, :b_rail1
    output :c_rail0, :c_rail1

    # Output is DATA0 if either input is DATA0
    # Output is DATA1 if both inputs are DATA1
    # Output is NULL if both inputs are NULL

    instance :c0_elem, CElement   # For rail0
    instance :c1_elem, CElement   # For rail1

    # c_rail0 = 1 when (a=0 OR b=0) AND not NULL
    # c_rail1 = 1 when (a=1 AND b=1)

    wire :either_zero

    behavior do
      either_zero <= a_rail0 | b_rail0

      # C-element for output rail0: set when either input is 0
      # Reset when both inputs are NULL
    end

    port :either_zero => [:c0_elem, :a]
    port :either_zero => [:c0_elem, :b]  # Simplified for demo

    port [:a_rail1, :b_rail1] => [:c1_elem, :a]  # Both must be 1
  end

  # Dual-rail OR gate (NCL TH12)
  class DualRailOr < SimComponent
    input :a_rail0, :a_rail1
    input :b_rail0, :b_rail1
    output :c_rail0, :c_rail1

    # Output is DATA1 if either input is DATA1
    # Output is DATA0 if both inputs are DATA0

    behavior do
      # rail1 (true) when either input is true
      c_rail1 <= a_rail1 | b_rail1

      # rail0 (false) when both inputs are false
      c_rail0 <= a_rail0 & b_rail0
    end
  end
end
```

### Dual-Rail Full Adder

```ruby
module RHDL::Async::DualRail
  # NCL Full Adder using dual-rail encoding
  class DualRailFullAdder < SimComponent
    # Inputs (dual-rail encoded)
    input :a_rail0, :a_rail1
    input :b_rail0, :b_rail1
    input :cin_rail0, :cin_rail1

    # Outputs (dual-rail encoded)
    output :sum_rail0, :sum_rail1
    output :cout_rail0, :cout_rail1

    # Completion detection
    output :complete

    behavior do
      # Extract values (when valid)
      a_valid = (a_rail0 ^ a_rail1)
      b_valid = (b_rail0 ^ b_rail1)
      cin_valid = (cin_rail0 ^ cin_rail1)

      all_valid = a_valid & b_valid & cin_valid
      all_null = (a_rail0 | a_rail1 | b_rail0 | b_rail1 |
                  cin_rail0 | cin_rail1) == 0

      if all_valid == 1
        # Compute sum and carry
        a_val = a_rail1
        b_val = b_rail1
        cin_val = cin_rail1

        sum_val = a_val ^ b_val ^ cin_val
        cout_val = (a_val & b_val) | (a_val & cin_val) | (b_val & cin_val)

        # Encode outputs
        sum_rail0 <= sum_val == 0 ? 1 : 0
        sum_rail1 <= sum_val
        cout_rail0 <= cout_val == 0 ? 1 : 0
        cout_rail1 <= cout_val

        complete <= 1
      elsif all_null
        # NULL spacer propagates
        sum_rail0 <= 0
        sum_rail1 <= 0
        cout_rail0 <= 0
        cout_rail1 <= 0
        complete <= 0
      end
      # Otherwise hold (intermediate state)
    end
  end
end
```

---

## Handshake Circuits

### Four-Phase Handshake Controller

```ruby
module RHDL::Async
  # Four-phase bundled-data handshake controller
  class FourPhaseController < SimComponent
    input :req_in       # Request from sender
    output :ack_out     # Acknowledge to sender

    output :req_out     # Request to receiver
    input :ack_in       # Acknowledge from receiver

    output :latch_en    # Enable data latch

    # States
    IDLE = 0
    LATCHING = 1
    REQUESTING = 2
    COMPLETING = 3

    wire :state, width: 2

    behavior do
      case state
      when IDLE
        if req_in == 1
          latch_en <= 1        # Capture data
          state <= LATCHING
        end

      when LATCHING
        latch_en <= 0
        req_out <= 1           # Forward request
        state <= REQUESTING

      when REQUESTING
        if ack_in == 1
          ack_out <= 1         # Acknowledge sender
          state <= COMPLETING
        end

      when COMPLETING
        if req_in == 0
          ack_out <= 0
          req_out <= 0
          state <= IDLE
        end
      end
    end
  end

  # Two-phase handshake controller (transition signaling)
  class TwoPhaseController < SimComponent
    input :req_in
    output :ack_out

    output :req_out
    input :ack_in

    output :latch_en

    wire :req_in_prev
    wire :ack_in_prev
    wire :phase   # Alternates 0/1

    behavior do
      # Detect transitions
      req_transition = req_in ^ req_in_prev
      ack_transition = ack_in ^ ack_in_prev

      if req_transition == 1
        latch_en <= 1      # Capture on any transition
        req_out <= ~phase  # Toggle request
      else
        latch_en <= 0
      end

      if ack_transition == 1
        ack_out <= ~phase  # Toggle acknowledge
        phase <= ~phase
      end

      req_in_prev <= req_in
      ack_in_prev <= ack_in
    end
  end
end
```

### Asynchronous FIFO

```ruby
module RHDL::Async
  # Asynchronous FIFO stage (micropipeline element)
  class FifoStage < SimComponent
    parameter :width, default: 8

    input :data_in, width: width
    input :req_in
    output :ack_out

    output :data_out, width: width
    output :req_out
    input :ack_in

    instance :ctrl, FourPhaseController
    instance :latch, TransparentLatch, width: width

    port :req_in => [:ctrl, :req_in]
    port [:ctrl, :ack_out] => :ack_out
    port [:ctrl, :req_out] => :req_out
    port :ack_in => [:ctrl, :ack_in]
    port [:ctrl, :latch_en] => [:latch, :enable]
    port :data_in => [:latch, :d]
    port [:latch, :q] => :data_out
  end

  # Complete asynchronous FIFO
  class AsyncFifo < SimComponent
    parameter :width, default: 8
    parameter :depth, default: 4

    input :data_in, width: width
    input :req_in
    output :ack_out

    output :data_out, width: width
    output :req_out
    input :ack_in

    # Instantiate pipeline stages
    # (Simplified - real implementation would use generate)
    instance :stage0, FifoStage, width: width
    instance :stage1, FifoStage, width: width
    instance :stage2, FifoStage, width: width
    instance :stage3, FifoStage, width: width

    # Chain stages together
    port :data_in => [:stage0, :data_in]
    port :req_in => [:stage0, :req_in]
    port [:stage0, :ack_out] => :ack_out

    port [:stage0, :data_out] => [:stage1, :data_in]
    port [:stage0, :req_out] => [:stage1, :req_in]
    port [:stage1, :ack_out] => [:stage0, :ack_in]

    port [:stage1, :data_out] => [:stage2, :data_in]
    port [:stage1, :req_out] => [:stage2, :req_in]
    port [:stage2, :ack_out] => [:stage1, :ack_in]

    port [:stage2, :data_out] => [:stage3, :data_in]
    port [:stage2, :req_out] => [:stage3, :req_in]
    port [:stage3, :ack_out] => [:stage2, :ack_in]

    port [:stage3, :data_out] => :data_out
    port [:stage3, :req_out] => :req_out
    port :ack_in => [:stage3, :ack_in]
  end
end
```

---

## NCL Threshold Gates

NULL Convention Logic threshold gates:

```ruby
module RHDL::Async::NCL
  # THmn gate: output high when m of n inputs are high
  # Output low when all inputs are low
  # Otherwise hold

  class TH22 < SimComponent  # 2-of-2 = AND
    input :a, :b
    output :c

    wire :state

    behavior do
      if (a == 1) && (b == 1)
        state <= 1
        c <= 1
      elsif (a == 0) && (b == 0)
        state <= 0
        c <= 0
      else
        c <= state
      end
    end
  end

  class TH12 < SimComponent  # 1-of-2 = OR
    input :a, :b
    output :c

    wire :state

    behavior do
      if (a == 1) || (b == 1)
        state <= 1
        c <= 1
      elsif (a == 0) && (b == 0)
        state <= 0
        c <= 0
      else
        c <= state
      end
    end
  end

  class TH23 < SimComponent  # 2-of-3 = MAJORITY
    input :a, :b, :c_in
    output :c

    wire :state
    wire :count, width: 2

    behavior do
      count <= a + b + c_in

      if count >= 2
        state <= 1
        c <= 1
      elsif count == 0
        state <= 0
        c <= 0
      else
        c <= state
      end
    end
  end

  class TH33 < SimComponent  # 3-of-3 = 3-input AND
    input :a, :b, :c_in
    output :c

    wire :state

    behavior do
      if (a == 1) && (b == 1) && (c_in == 1)
        state <= 1
        c <= 1
      elsif (a == 0) && (b == 0) && (c_in == 0)
        state <= 0
        c <= 0
      else
        c <= state
      end
    end
  end

  # THmn with weight (some inputs count more)
  class TH23W2 < SimComponent  # 2-of-3 where first input has weight 2
    input :a, :b, :c_in   # a has weight 2
    output :c

    wire :state
    wire :weighted_count, width: 3

    behavior do
      weighted_count <= (a * 2) + b + c_in

      if weighted_count >= 2
        state <= 1
        c <= 1
      elsif weighted_count == 0
        state <= 0
        c <= 0
      else
        c <= state
      end
    end
  end
end
```

---

## Completion Detection

```ruby
module RHDL::Async
  # Completion detector for dual-rail encoded word
  class CompletionDetector < SimComponent
    parameter :width, default: 8

    input :rails0, width: width   # All rail0 signals
    input :rails1, width: width   # All rail1 signals

    output :complete              # All bits have valid data
    output :is_null               # All bits are NULL

    behavior do
      # Each bit is valid when exactly one rail is high
      all_valid = 1
      all_null = 1

      width.times do |i|
        bit_valid = rails0[i] ^ rails1[i]
        bit_null = (rails0[i] == 0) && (rails1[i] == 0)

        all_valid = all_valid & bit_valid
        all_null = all_null & bit_null
      end

      complete <= all_valid
      is_null <= all_null
    end
  end

  # Tree-based completion for large words
  class CompletionTree < SimComponent
    parameter :width, default: 32

    input :rails0, width: width
    input :rails1, width: width

    output :complete
    output :is_null

    # Use C-elements in a tree structure
    # For width=32: log2(32)=5 levels

    behavior do
      # Level 0: OR each dual-rail pair
      level0 = Array.new(width)
      width.times { |i| level0[i] = rails0[i] | rails1[i] }

      # Reduction tree with C-elements
      current = level0
      while current.length > 1
        next_level = []
        (current.length / 2).times do |i|
          # C-element: both must be 1 for output 1
          next_level << (current[2*i] & current[2*i + 1])
        end
        if current.length.odd?
          next_level << current.last
        end
        current = next_level
      end

      complete <= current[0]
      is_null <= (rails0 | rails1) == 0
    end
  end
end
```

---

## Asynchronous ALU

```ruby
module RHDL::Async
  # Quasi-delay-insensitive ALU using dual-rail encoding
  class AsyncAlu < SimComponent
    parameter :width, default: 8

    # Dual-rail inputs
    input :a_rails0, width: width
    input :a_rails1, width: width
    input :b_rails0, width: width
    input :b_rails1, width: width
    input :op_rails0, width: 3     # Operation select (dual-rail)
    input :op_rails1, width: 3

    # Dual-rail outputs
    output :result_rails0, width: width
    output :result_rails1, width: width
    output :complete

    # Operations
    OP_ADD = 0
    OP_SUB = 1
    OP_AND = 2
    OP_OR  = 3
    OP_XOR = 4

    behavior do
      # Check if all inputs are valid
      a_valid = check_valid(a_rails0, a_rails1, width)
      b_valid = check_valid(b_rails0, b_rails1, width)
      op_valid = check_valid(op_rails0, op_rails1, 3)

      if a_valid && b_valid && op_valid
        # Decode inputs
        a = decode_dual_rail(a_rails0, a_rails1, width)
        b = decode_dual_rail(b_rails0, b_rails1, width)
        op = decode_dual_rail(op_rails0, op_rails1, 3)

        # Compute result
        result = case op
                 when OP_ADD then a + b
                 when OP_SUB then a - b
                 when OP_AND then a & b
                 when OP_OR  then a | b
                 when OP_XOR then a ^ b
                 else 0
                 end

        # Encode output
        encode_dual_rail(result, width, result_rails0, result_rails1)
        complete <= 1
      elsif all_null?(a_rails0, a_rails1, b_rails0, b_rails1,
                      op_rails0, op_rails1)
        # Propagate NULL
        result_rails0 <= 0
        result_rails1 <= 0
        complete <= 0
      end
      # Otherwise hold (intermediate state)
    end

    private

    def check_valid(rails0, rails1, w)
      valid = 1
      w.times { |i| valid &= (rails0[i] ^ rails1[i]) }
      valid
    end

    def decode_dual_rail(rails0, rails1, w)
      val = 0
      w.times { |i| val |= (rails1[i] << i) }
      val
    end

    def encode_dual_rail(val, w, out0, out1)
      w.times do |i|
        bit = (val >> i) & 1
        out0[i] <= bit == 0 ? 1 : 0
        out1[i] <= bit
      end
    end
  end
end
```

---

## GALS Wrapper

Globally Asynchronous, Locally Synchronous wrapper:

```ruby
module RHDL::Async
  # GALS wrapper: converts synchronous module to async interface
  class GalsWrapper < SimComponent
    parameter :width, default: 8

    # Asynchronous interface
    input :data_in, width: width
    input :req_in
    output :ack_out

    output :data_out, width: width
    output :req_out
    input :ack_in

    # Synchronous module interface
    output :sync_clk
    output :sync_data_in, width: width
    input :sync_data_out, width: width
    output :sync_valid_in
    input :sync_valid_out

    # Local clock generator (ring oscillator)
    instance :osc, RingOscillator
    instance :clk_gate, ClockGate

    # Input synchronizer (metastability hardened)
    instance :in_sync, Synchronizer, width: width + 1
    instance :out_sync, Synchronizer, width: width + 1

    # Handshake to pulse converter
    wire :input_pulse
    wire :output_pulse
    wire :gated_clk

    behavior do
      # Gate clock when no activity
      clk_gate.enable <= req_in | (~ack_out)
      gated_clk <= clk_gate.clk_out

      # Generate input pulse on request edge
      input_pulse <= req_in & (~req_in_prev)

      # Synchronize input to local clock domain
      if input_pulse == 1
        sync_data_in <= data_in
        sync_valid_in <= 1
      else
        sync_valid_in <= 0
      end

      # Capture synchronous output
      if sync_valid_out == 1
        data_out <= sync_data_out
        req_out <= 1
      end

      # Acknowledge when output consumed
      if ack_in == 1
        req_out <= 0
        ack_out <= 1
      elsif req_in == 0
        ack_out <= 0
      end
    end

    port [:osc, :out] => [:clk_gate, :clk_in]
    port [:clk_gate, :clk_out] => :sync_clk
  end

  # Simple ring oscillator for local clock
  class RingOscillator < SimComponent
    parameter :stages, default: 5  # Must be odd

    output :out

    # Chain of inverters
    behavior do
      # In real hardware: chain of inverters with delay
      # In simulation: toggle output
      out <= ~out
    end
  end

  # Clock gating cell
  class ClockGate < SimComponent
    input :clk_in
    input :enable
    output :clk_out

    wire :enable_latched

    behavior do
      # Latch enable on falling edge to prevent glitches
      if clk_in == 0
        enable_latched <= enable
      end

      clk_out <= clk_in & enable_latched
    end
  end
end
```

---

## Sample Programs

### Asynchronous Counter

```ruby
# Test asynchronous ripple counter
describe "Async Counter" do
  it "counts with handshaking" do
    counter = RHDL::Async::AsyncCounter.new(width: 4)
    sim = Simulator.new(counter)

    # Send count pulses
    10.times do |i|
      # Request
      counter.set_input(:req, 1)
      sim.run_until { counter.get_output(:ack) == 1 }

      # Complete handshake
      counter.set_input(:req, 0)
      sim.run_until { counter.get_output(:ack) == 0 }

      expect(counter.get_output(:count)).to eq(i + 1)
    end
  end
end
```

### Pipeline Processing

```ruby
# Asynchronous pipeline demonstration
describe "Async Pipeline" do
  it "processes data without clock" do
    pipe = RHDL::Async::AsyncFifo.new(width: 8, depth: 4)
    sim = Simulator.new(pipe)

    # Feed data
    data_in = [0x12, 0x34, 0x56, 0x78]
    data_out = []

    # Producer: send data
    data_in.each do |val|
      pipe.set_input(:data_in, val)
      pipe.set_input(:req_in, 1)
      sim.run_until { pipe.get_output(:ack_out) == 1 }
      pipe.set_input(:req_in, 0)
      sim.run_until { pipe.get_output(:ack_out) == 0 }
    end

    # Consumer: receive data
    4.times do
      sim.run_until { pipe.get_output(:req_out) == 1 }
      data_out << pipe.get_output(:data_out)
      pipe.set_input(:ack_in, 1)
      sim.run_until { pipe.get_output(:req_out) == 0 }
      pipe.set_input(:ack_in, 0)
    end

    expect(data_out).to eq(data_in)
  end
end
```

---

## Further Resources

- Sparsø & Furber, *Principles of Asynchronous Circuit Design* (textbook)
- Sutherland, "Micropipelines" (1989 Turing Award lecture)
- Martin, "Asynchronous VLSI" (Caltech course notes)
- NULL Convention Logic patents and papers

> Return to [Chapter 12](12-asynchronous-computing.md) for conceptual introduction.
