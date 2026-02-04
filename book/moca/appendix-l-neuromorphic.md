# Appendix L: Neuromorphic Implementation

*Companion appendix to [Chapter 12: Neuromorphic Computing](12-neuromorphic-computing.md)*

## Overview

This appendix provides RHDL implementations of neuromorphic components, from individual neurons to small spiking neural networks with STDP learning.

## Leaky Integrate-and-Fire Neuron

```ruby
class LifNeuron < SimComponent
  input :clk
  input :reset

  # Synaptic inputs (weighted current)
  input :synaptic_current, width: 16  # Fixed-point Q8.8

  # Parameters (configurable)
  input :threshold, width: 16         # Spike threshold
  input :leak_rate, width: 8          # Leak factor (0-255)
  input :refractory_period, width: 8  # Cycles after spike

  # Outputs
  output :spike                       # Spike event
  output :membrane_potential, width: 16

  # Internal state
  wire :potential, width: 16
  wire :refractory_counter, width: 8

  behavior do
    on_posedge(:clk) do
      if reset.high?
        potential <= 0
        refractory_counter <= 0
        spike <= 0
      else
        if refractory_counter.to_i > 0
          # In refractory period - no integration
          refractory_counter <= refractory_counter.to_i - 1
          spike <= 0
        else
          # Leaky integration
          # V(t+1) = V(t) * (1 - leak) + I(t)
          leaked = (potential.to_i * (256 - leak_rate.to_i)) >> 8
          new_potential = leaked + synaptic_current.to_i

          # Clamp to valid range
          new_potential = [[new_potential, 0].max, 65535].min

          if new_potential >= threshold.to_i
            # Fire spike and reset
            spike <= 1
            potential <= 0
            refractory_counter <= refractory_period.to_i
          else
            spike <= 0
            potential <= new_potential
          end
        end
      end

      membrane_potential <= potential
    end
  end
end
```

## Synapse with STDP

```ruby
class StdpSynapse < SimComponent
  input :clk
  input :reset

  # Spike inputs
  input :pre_spike     # Pre-synaptic spike
  input :post_spike    # Post-synaptic spike

  # Learning parameters
  input :a_plus, width: 8    # LTP learning rate
  input :a_minus, width: 8   # LTD learning rate
  input :tau_plus, width: 8  # LTP time constant
  input :tau_minus, width: 8 # LTD time constant

  # Weight bounds
  input :w_min, width: 16
  input :w_max, width: 16

  # Outputs
  output :weight, width: 16
  output :weighted_spike, width: 16

  # Internal traces
  wire :pre_trace, width: 16   # Eligibility trace for pre
  wire :post_trace, width: 16  # Eligibility trace for post

  behavior do
    on_posedge(:clk) do
      if reset.high?
        weight <= 32768  # Start at midpoint
        pre_trace <= 0
        post_trace <= 0
      else
        # Decay traces
        new_pre_trace = (pre_trace.to_i * (256 - tau_plus.to_i)) >> 8
        new_post_trace = (post_trace.to_i * (256 - tau_minus.to_i)) >> 8

        current_weight = weight.to_i

        # Pre-synaptic spike
        if pre_spike.high?
          # Boost pre trace
          new_pre_trace = [new_pre_trace + 256, 65535].min

          # LTD: Pre after post weakens synapse
          if post_trace.to_i > 0
            delta = (a_minus.to_i * post_trace.to_i) >> 8
            current_weight = [current_weight - delta, w_min.to_i].max
          end
        end

        # Post-synaptic spike
        if post_spike.high?
          # Boost post trace
          new_post_trace = [new_post_trace + 256, 65535].min

          # LTP: Post after pre strengthens synapse
          if pre_trace.to_i > 0
            delta = (a_plus.to_i * pre_trace.to_i) >> 8
            current_weight = [current_weight + delta, w_max.to_i].min
          end
        end

        pre_trace <= new_pre_trace
        post_trace <= new_post_trace
        weight <= current_weight
      end
    end

    # Combinational: weighted output
    always do
      if pre_spike.high?
        weighted_spike <= weight
      else
        weighted_spike <= 0
      end
    end
  end
end
```

## Neuron Array

```ruby
class NeuronArray < SimComponent
  input :clk
  input :reset

  NUM_NEURONS = 16

  # Input spikes (one bit per input)
  input :input_spikes, width: NUM_NEURONS

  # Output spikes
  output :output_spikes, width: NUM_NEURONS

  # Global parameters
  input :threshold, width: 16
  input :leak_rate, width: 8
  input :refractory_period, width: 8

  # Instantiate neurons
  NUM_NEURONS.times do |i|
    instance :"neuron#{i}", LifNeuron
  end

  behavior do
    # Connect parameters to all neurons
    NUM_NEURONS.times do |i|
      neuron = instance_variable_get(:"@neuron#{i}")
      neuron.threshold <= threshold
      neuron.leak_rate <= leak_rate
      neuron.refractory_period <= refractory_period
      neuron.reset <= reset
      neuron.clk <= clk
    end

    always do
      spikes_out = 0
      NUM_NEURONS.times do |i|
        neuron = instance_variable_get(:"@neuron#{i}")
        spikes_out |= (neuron.spike.to_i << i)
      end
      output_spikes <= spikes_out
    end
  end
end
```

## Crossbar Synapse Array

```ruby
class SynapseCrossbar < SimComponent
  input :clk
  input :reset

  NUM_PRE = 8   # Pre-synaptic neurons
  NUM_POST = 8  # Post-synaptic neurons

  # Pre-synaptic spikes
  input :pre_spikes, width: NUM_PRE

  # Post-synaptic spikes (for STDP)
  input :post_spikes, width: NUM_POST

  # Summed currents for each post-synaptic neuron
  output :post_currents, width: NUM_POST * 16

  # Learning enable
  input :learning_enable

  # STDP parameters
  input :a_plus, width: 8
  input :a_minus, width: 8

  behavior do
    on_posedge(:clk) do
      if reset.high?
        # Initialize weights (random or fixed pattern)
        @weights = Array.new(NUM_PRE) { Array.new(NUM_POST, 128) }
        @pre_traces = Array.new(NUM_PRE, 0)
        @post_traces = Array.new(NUM_POST, 0)
      else
        # Decay traces
        @pre_traces.map! { |t| (t * 240) >> 8 }
        @post_traces.map! { |t| (t * 240) >> 8 }

        # Process pre-synaptic spikes
        NUM_PRE.times do |i|
          if (pre_spikes.to_i >> i) & 1 == 1
            @pre_traces[i] = [@pre_traces[i] + 64, 255].min

            # LTD for all post neurons with active traces
            if learning_enable.high?
              NUM_POST.times do |j|
                if @post_traces[j] > 0
                  delta = (a_minus.to_i * @post_traces[j]) >> 8
                  @weights[i][j] = [@weights[i][j] - delta, 0].max
                end
              end
            end
          end
        end

        # Process post-synaptic spikes
        NUM_POST.times do |j|
          if (post_spikes.to_i >> j) & 1 == 1
            @post_traces[j] = [@post_traces[j] + 64, 255].min

            # LTP for all pre neurons with active traces
            if learning_enable.high?
              NUM_PRE.times do |i|
                if @pre_traces[i] > 0
                  delta = (a_plus.to_i * @pre_traces[i]) >> 8
                  @weights[i][j] = [@weights[i][j] + delta, 255].min
                end
              end
            end
          end
        end
      end
    end

    # Compute synaptic currents (combinational)
    always do
      currents = 0
      NUM_POST.times do |j|
        current_sum = 0
        NUM_PRE.times do |i|
          if (pre_spikes.to_i >> i) & 1 == 1
            current_sum += @weights[i][j]
          end
        end
        current_sum = [current_sum, 65535].min
        currents |= (current_sum << (j * 16))
      end
      post_currents <= currents
    end
  end

  def initialize(name, params = {})
    super
    @weights = Array.new(NUM_PRE) { Array.new(NUM_POST, 128) }
    @pre_traces = Array.new(NUM_PRE, 0)
    @post_traces = Array.new(NUM_POST, 0)
  end
end
```

## Simple Spiking Neural Network

```ruby
class SpikingNeuralNetwork < SimComponent
  input :clk
  input :reset

  # Input layer (sensory)
  input :input_spikes, width: 8

  # Output layer
  output :output_spikes, width: 4

  # Learning control
  input :learning_enable

  # Hidden layer neurons
  4.times do |i|
    instance :"hidden#{i}", LifNeuron
  end

  # Output layer neurons
  4.times do |i|
    instance :"output#{i}", LifNeuron
  end

  # Synapse arrays
  instance :input_to_hidden, SynapseCrossbar  # 8 → 4
  instance :hidden_to_output, SynapseCrossbar # 4 → 4

  # Internal signals
  wire :hidden_spikes, width: 4
  wire :hidden_currents, width: 64  # 4 × 16-bit
  wire :output_currents, width: 64

  behavior do
    # Configure synapse arrays
    input_to_hidden.pre_spikes <= input_spikes
    input_to_hidden.learning_enable <= learning_enable

    # Collect hidden layer spikes
    always do
      h_spikes = 0
      4.times do |i|
        neuron = instance_variable_get(:"@hidden#{i}")
        h_spikes |= (neuron.spike.to_i << i)
      end
      hidden_spikes <= h_spikes
    end

    # Feed hidden spikes to second synapse array
    hidden_to_output.pre_spikes <= hidden_spikes
    hidden_to_output.learning_enable <= learning_enable

    # Connect currents to neurons
    4.times do |i|
      hidden = instance_variable_get(:"@hidden#{i}")
      hidden.synaptic_current <= input_to_hidden.post_currents
        .bits((i * 16)...((i + 1) * 16))

      output_n = instance_variable_get(:"@output#{i}")
      output_n.synaptic_current <= hidden_to_output.post_currents
        .bits((i * 16)...((i + 1) * 16))
    end

    # Collect output spikes
    always do
      o_spikes = 0
      4.times do |i|
        neuron = instance_variable_get(:"@output#{i}")
        o_spikes |= (neuron.spike.to_i << i)
      end
      output_spikes <= o_spikes
    end
  end
end
```

## Memristor Model

```ruby
class Memristor < SimComponent
  input :clk
  input :reset

  input :voltage, width: 16       # Applied voltage (signed Q8.8)
  output :current, width: 16      # Output current (signed Q8.8)
  output :resistance, width: 16   # Current resistance state

  # Memristor parameters
  input :r_on, width: 16          # Minimum resistance
  input :r_off, width: 16         # Maximum resistance
  input :mobility, width: 8       # Ion mobility factor

  # Internal state: position of boundary (0 = r_off, 65535 = r_on)
  wire :state, width: 16

  behavior do
    on_posedge(:clk) do
      if reset.high?
        state <= 32768  # Start at midpoint
      else
        # State changes based on current flow
        # Simplified linear model: dx/dt = μ × I
        current_val = current.to_i
        mobility_val = mobility.to_i

        # Signed current affects state direction
        if current_val >= 32768  # Negative current
          delta = ((65536 - current_val) * mobility_val) >> 12
          new_state = [state.to_i - delta, 0].max
        else  # Positive current
          delta = (current_val * mobility_val) >> 12
          new_state = [state.to_i + delta, 65535].min
        end

        state <= new_state
      end
    end

    # Compute resistance and current (combinational)
    always do
      # Linear interpolation between r_on and r_off
      r_on_val = r_on.to_i
      r_off_val = r_off.to_i
      state_val = state.to_i

      # R = r_on × (state/65535) + r_off × (1 - state/65535)
      r = (r_on_val * state_val + r_off_val * (65535 - state_val)) >> 16
      r = [r, 1].max  # Avoid divide by zero

      resistance <= r

      # I = V / R (Ohm's law)
      # Using fixed-point: current = (voltage << 8) / resistance
      v = voltage.to_i
      if v >= 32768
        v_signed = v - 65536
      else
        v_signed = v
      end

      i = (v_signed << 8) / r
      current <= i & 0xFFFF
    end
  end
end
```

## Sample Programs

### Pattern Recognition with STDP

```ruby
# Train a simple SNN to recognize patterns

def train_pattern_recognition
  snn = SpikingNeuralNetwork.new('snn')
  sim = Simulator.new(snn)

  # Training patterns (8-bit input, 4 classes)
  patterns = [
    { input: 0b00001111, label: 0 },  # Lower 4 bits
    { input: 0b11110000, label: 1 },  # Upper 4 bits
    { input: 0b01010101, label: 2 },  # Alternating
    { input: 0b10101010, label: 3 },  # Alternating inverse
  ]

  # Configure neuron parameters
  sim.set_input(:threshold, 200)
  sim.set_input(:leak_rate, 20)
  sim.set_input(:refractory_period, 5)
  sim.set_input(:learning_enable, 1)
  sim.set_input(:a_plus, 16)
  sim.set_input(:a_minus, 12)

  # Training loop
  100.times do |epoch|
    patterns.shuffle.each do |pattern|
      # Present input pattern as spikes
      10.times do |t|
        sim.set_input(:input_spikes, pattern[:input])
        sim.step

        # Reinforce correct output
        expected_output = 1 << pattern[:label]
        # (In real STDP, this happens through teacher signals)
      end

      # Inter-pattern pause
      5.times do
        sim.set_input(:input_spikes, 0)
        sim.step
      end
    end
  end

  # Test
  sim.set_input(:learning_enable, 0)  # Freeze weights

  patterns.each do |pattern|
    output_counts = [0, 0, 0, 0]

    20.times do
      sim.set_input(:input_spikes, pattern[:input])
      sim.step
      output = sim.get_output(:output_spikes)
      4.times { |i| output_counts[i] += (output >> i) & 1 }
    end

    predicted = output_counts.index(output_counts.max)
    puts "Pattern #{pattern[:input].to_s(2).rjust(8, '0')}: " +
         "Expected #{pattern[:label]}, Got #{predicted}"
  end
end
```

### Temporal Pattern Detection

```ruby
# Detect temporal sequences using spike timing

def temporal_pattern_detector
  # Sequence: A then B then C (within time window)
  neurons = {
    a: LifNeuron.new('a'),
    b: LifNeuron.new('b'),
    c: LifNeuron.new('c'),
    detector: LifNeuron.new('detector')
  }

  # A→detector synapse with short delay
  # B→detector synapse with medium delay
  # C→detector synapse with long delay
  # If A, B, C arrive in order, their delayed spikes coincide!

  delays = { a: 20, b: 10, c: 0 }  # Delay lines

  # Simulation would show:
  # Input sequence [A at t=0, B at t=10, C at t=20]
  # All arrive at detector at t=20 → detector fires
  #
  # Wrong sequence [C at t=0, B at t=10, A at t=20]
  # Spikes arrive at different times → no coincidence → no fire
end
```

## Performance Metrics

| Metric | LIF Neuron | STDP Synapse | Full SNN |
|--------|------------|--------------|----------|
| Gates | ~200 | ~400 | ~10K |
| Flip-flops | 40 | 80 | ~2K |
| Clock cycles/update | 1 | 1 | 1 |
| Power (estimated) | 10 µW | 20 µW | 1 mW |

## Further Reading

- Indiveri & Liu, "Memory and Information Processing in Neuromorphic Systems"
- Intel Loihi Architecture Documentation
- Merolla et al., "A million spiking-neuron integrated circuit" (TrueNorth)
- Strukov et al., "The missing memristor found"

> Return to [Chapter 12](12-neuromorphic-computing.md) for conceptual introduction.
