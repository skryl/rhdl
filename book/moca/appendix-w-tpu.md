# Appendix Q: TPU Implementation

*Companion appendix to [Chapter 17: The TPU v1](17-tpu.md)*

## Overview

This appendix provides RHDL implementations of TPU v1 components, from individual MAC units to a complete systolic array with weight loading and activation functions.

## MAC Unit (Multiply-Accumulate)

The fundamental building block:

```ruby
class TpuMac < SimComponent
  input :clk
  input :reset
  input :enable

  # Data inputs
  input :weight, width: 8           # INT8 weight (stationary)
  input :activation_in, width: 8    # INT8 activation (flows right)
  input :partial_sum_in, width: 32  # Partial sum (flows down)

  # Data outputs
  output :activation_out, width: 8   # Passes activation right
  output :partial_sum_out, width: 32 # Accumulated sum down

  # Weight loading
  input :load_weight
  input :weight_data, width: 8

  # Internal registers
  wire :weight_reg, width: 8
  wire :activation_reg, width: 8

  behavior do
    on_posedge(:clk) do
      if reset.high?
        weight_reg <= 0
        activation_reg <= 0
        partial_sum_out <= 0
        activation_out <= 0
      elsif load_weight.high?
        # Load new weight (weight-stationary)
        weight_reg <= weight_data
      elsif enable.high?
        # Pipeline the activation
        activation_reg <= activation_in
        activation_out <= activation_reg

        # MAC operation: out = in + weight × activation
        # INT8 × INT8 = INT16, accumulate in INT32
        product = signed_mul_8x8(weight_reg.to_i, activation_in.to_i)
        partial_sum_out <= partial_sum_in.to_i + product
      end
    end
  end

  private

  def signed_mul_8x8(a, b)
    # Convert to signed
    a_signed = a > 127 ? a - 256 : a
    b_signed = b > 127 ? b - 256 : b
    a_signed * b_signed
  end
end
```

## Systolic Array (8×8 for demonstration)

```ruby
class TpuSystolicArray < SimComponent
  input :clk
  input :reset
  input :enable

  ROWS = 8
  COLS = 8

  # Activation inputs (one per column)
  input :activations, width: COLS * 8

  # Partial sum inputs (from previous array or zero)
  input :partial_sums_in, width: ROWS * 32

  # Outputs
  output :partial_sums_out, width: ROWS * 32

  # Weight loading interface
  input :load_weights
  input :weight_row, width: 3       # Which row to load
  input :weights_data, width: COLS * 8  # 8 weights per row

  # Instantiate MAC grid
  ROWS.times do |r|
    COLS.times do |c|
      instance :"mac_#{r}_#{c}", TpuMac
    end
  end

  # Internal wires for activation propagation
  (ROWS).times do |r|
    (COLS + 1).times do |c|
      wire :"act_#{r}_#{c}", width: 8
    end
  end

  # Internal wires for partial sum propagation
  (ROWS + 1).times do |r|
    COLS.times do |c|
      wire :"psum_#{r}_#{c}", width: 32
    end
  end

  behavior do
    # Connect activation inputs to first column
    always do
      ROWS.times do |r|
        act_wire = instance_variable_get(:"@act_#{r}_0")
        act_wire <= activations.bits((r * 8)...((r + 1) * 8))
      end
    end

    # Connect partial sum inputs to first row
    always do
      COLS.times do |c|
        psum_wire = instance_variable_get(:"@psum_0_#{c}")
        psum_wire <= partial_sums_in.bits((c * 32)...((c + 1) * 32))
      end
    end

    # Wire up the MAC grid
    ROWS.times do |r|
      COLS.times do |c|
        mac = instance_variable_get(:"@mac_#{r}_#{c}")

        # Control signals
        mac.clk <= clk
        mac.reset <= reset
        mac.enable <= enable

        # Activation flow (left to right)
        act_in = instance_variable_get(:"@act_#{r}_#{c}")
        mac.activation_in <= act_in

        act_out = instance_variable_get(:"@act_#{r}_#{c + 1}")
        # Connect MAC output to next wire
        always { act_out <= mac.activation_out }

        # Partial sum flow (top to bottom)
        psum_in = instance_variable_get(:"@psum_#{r}_#{c}")
        mac.partial_sum_in <= psum_in

        psum_out = instance_variable_get(:"@psum_#{r + 1}_#{c}")
        always { psum_out <= mac.partial_sum_out }

        # Weight loading
        mac.load_weight <= load_weights.high? && weight_row.to_i == r ? 1 : 0
        mac.weight_data <= weights_data.bits((c * 8)...((c + 1) * 8))
      end
    end

    # Collect outputs from bottom row
    always do
      result = 0
      COLS.times do |c|
        psum_wire = instance_variable_get(:"@psum_#{ROWS}_#{c}")
        result |= (psum_wire.to_i & 0xFFFFFFFF) << (c * 32)
      end
      partial_sums_out <= result
    end
  end
end
```

## Weight FIFO

```ruby
class WeightFifo < SimComponent
  input :clk
  input :reset

  DEPTH = 256  # Rows of weights
  WIDTH = 256  # Weights per row

  # Host interface
  input :host_write
  input :host_data, width: WIDTH * 8
  input :host_addr, width: 8

  # Array interface
  input :array_read
  input :array_addr, width: 8
  output :array_data, width: WIDTH * 8
  output :data_valid

  behavior do
    on_posedge(:clk) do
      if reset.high?
        @memory = Array.new(DEPTH) { Array.new(WIDTH, 0) }
        data_valid <= 0
      elsif host_write.high?
        # Load weights from host
        WIDTH.times do |i|
          @memory[host_addr.to_i][i] = host_data.bits((i * 8)...((i + 1) * 8)).to_i
        end
      elsif array_read.high?
        # Output weights to array
        data_valid <= 1
      else
        data_valid <= 0
      end
    end

    always do
      if array_read.high?
        result = 0
        WIDTH.times do |i|
          result |= (@memory[array_addr.to_i][i] & 0xFF) << (i * 8)
        end
        array_data <= result
      else
        array_data <= 0
      end
    end
  end

  def initialize(name, params = {})
    super
    @memory = Array.new(DEPTH) { Array.new(WIDTH, 0) }
  end
end
```

## Unified Buffer

```ruby
class UnifiedBuffer < SimComponent
  input :clk
  input :reset

  # 24 MB = 24 × 1024 × 1024 bytes
  # Simplified: 64K × 256-byte rows
  ROWS = 65536
  COLS = 256

  # Read port (to systolic array)
  input :read_enable
  input :read_addr, width: 16
  output :read_data, width: COLS * 8

  # Write port (from activation unit)
  input :write_enable
  input :write_addr, width: 16
  input :write_data, width: COLS * 8

  # DMA interface (to/from host)
  input :dma_read_enable
  input :dma_write_enable
  input :dma_addr, width: 16
  input :dma_write_data, width: COLS * 8
  output :dma_read_data, width: COLS * 8

  behavior do
    on_posedge(:clk) do
      if reset.high?
        @memory = {}  # Sparse representation
      elsif write_enable.high?
        store_row(write_addr.to_i, write_data)
      elsif dma_write_enable.high?
        store_row(dma_addr.to_i, dma_write_data)
      end
    end

    always do
      if read_enable.high?
        read_data <= load_row(read_addr.to_i)
      else
        read_data <= 0
      end

      if dma_read_enable.high?
        dma_read_data <= load_row(dma_addr.to_i)
      else
        dma_read_data <= 0
      end
    end
  end

  private

  def store_row(addr, data)
    @memory[addr] = COLS.times.map { |i| data.bits((i * 8)...((i + 1) * 8)).to_i }
  end

  def load_row(addr)
    row = @memory[addr] || Array.new(COLS, 0)
    result = 0
    row.each_with_index { |v, i| result |= (v & 0xFF) << (i * 8) }
    result
  end

  def initialize(name, params = {})
    super
    @memory = {}
  end
end
```

## Activation Unit

```ruby
class ActivationUnit < SimComponent
  input :clk
  input :enable

  # Input from accumulators
  input :accumulator_data, width: 256 * 32  # 256 × 32-bit accumulators

  # Activation function select
  input :activation_func, width: 2
  FUNC_NONE = 0
  FUNC_RELU = 1
  FUNC_SIGMOID = 2  # Approximation
  FUNC_TANH = 3     # Approximation

  # Quantization parameters
  input :scale, width: 16     # Output scale factor
  input :zero_point, width: 8 # Output zero point

  # Output
  output :activation_data, width: 256 * 8  # Quantized INT8 output

  behavior do
    always do
      result = 0

      256.times do |i|
        # Get 32-bit accumulator value
        acc = accumulator_data.bits((i * 32)...((i + 1) * 32)).to_i
        if acc >= 0x80000000
          acc = acc - 0x100000000  # Convert to signed
        end

        # Apply activation function
        activated = case activation_func.to_i
          when FUNC_NONE then acc
          when FUNC_RELU then [acc, 0].max
          when FUNC_SIGMOID then sigmoid_approx(acc)
          when FUNC_TANH then tanh_approx(acc)
          else acc
        end

        # Quantize to INT8
        scaled = (activated * scale.to_i) >> 16
        quantized = scaled + zero_point.to_i
        quantized = [[quantized, 0].max, 255].min  # Clamp to [0, 255]

        result |= quantized << (i * 8)
      end

      activation_data <= result
    end
  end

  private

  def sigmoid_approx(x)
    # Piecewise linear approximation
    # sigmoid(x) ≈ 0.5 + 0.25*x for |x| < 2
    if x < -4 * 65536
      0
    elsif x > 4 * 65536
      65536  # 1.0 in Q16
    else
      32768 + (x >> 2)  # 0.5 + 0.25*x
    end
  end

  def tanh_approx(x)
    # tanh(x) ≈ x for |x| < 1, ±1 otherwise
    if x < -65536
      -65536
    elsif x > 65536
      65536
    else
      x
    end
  end
end
```

## Simplified TPU Controller

```ruby
class TpuController < SimComponent
  input :clk
  input :reset

  # Host command interface
  input :command, width: 4
  input :command_valid
  input :command_param, width: 32

  CMD_NOP = 0
  CMD_LOAD_WEIGHTS = 1
  CMD_MATMUL = 2
  CMD_ACTIVATE = 3
  CMD_READ_RESULT = 4

  # Status
  output :busy
  output :done

  # Control signals to datapath
  output :weight_load_enable
  output :weight_row, width: 8
  output :array_enable
  output :activation_enable
  output :buffer_read_enable
  output :buffer_write_enable
  output :buffer_addr, width: 16

  # State machine
  wire :state, width: 4
  wire :cycle_count, width: 16
  wire :row_count, width: 8

  STATE_IDLE = 0
  STATE_LOAD_WEIGHTS = 1
  STATE_MATMUL_INIT = 2
  STATE_MATMUL_RUN = 3
  STATE_MATMUL_DRAIN = 4
  STATE_ACTIVATE = 5
  STATE_DONE = 6

  behavior do
    on_posedge(:clk) do
      if reset.high?
        state <= STATE_IDLE
        busy <= 0
        done <= 0
        cycle_count <= 0
        row_count <= 0
      else
        case state.to_i
        when STATE_IDLE
          done <= 0
          if command_valid.high?
            case command.to_i
            when CMD_LOAD_WEIGHTS
              state <= STATE_LOAD_WEIGHTS
              busy <= 1
              row_count <= 0
            when CMD_MATMUL
              state <= STATE_MATMUL_INIT
              busy <= 1
              cycle_count <= 0
            when CMD_ACTIVATE
              state <= STATE_ACTIVATE
              busy <= 1
            end
          end

        when STATE_LOAD_WEIGHTS
          weight_load_enable <= 1
          weight_row <= row_count
          row_count <= row_count.to_i + 1

          if row_count.to_i >= 255
            state <= STATE_DONE
            weight_load_enable <= 0
          end

        when STATE_MATMUL_INIT
          array_enable <= 1
          buffer_read_enable <= 1
          state <= STATE_MATMUL_RUN

        when STATE_MATMUL_RUN
          cycle_count <= cycle_count.to_i + 1

          # Run for 256 + 256 cycles (fill + drain)
          if cycle_count.to_i >= 512
            state <= STATE_MATMUL_DRAIN
          end

        when STATE_MATMUL_DRAIN
          array_enable <= 0
          buffer_read_enable <= 0
          buffer_write_enable <= 1
          state <= STATE_DONE

        when STATE_ACTIVATE
          activation_enable <= 1
          state <= STATE_DONE
          activation_enable <= 0

        when STATE_DONE
          busy <= 0
          done <= 1
          state <= STATE_IDLE
          buffer_write_enable <= 0
        end
      end
    end
  end
end
```

## Complete TPU Datapath

```ruby
class TpuDatapath < SimComponent
  input :clk
  input :reset

  # Host interface
  input :command, width: 4
  input :command_valid
  input :command_param, width: 32
  input :host_data, width: 256 * 8
  output :result_data, width: 256 * 8
  output :busy
  output :done

  # Instantiate components
  instance :controller, TpuController
  instance :weight_fifo, WeightFifo
  instance :systolic_array, TpuSystolicArray
  instance :unified_buffer, UnifiedBuffer
  instance :activation_unit, ActivationUnit

  # Connect controller
  port :clk => [:controller, :clk]
  port :reset => [:controller, :reset]
  port :command => [:controller, :command]
  port :command_valid => [:controller, :command_valid]
  port [:controller, :busy] => :busy
  port [:controller, :done] => :done

  behavior do
    # Connect weight loading
    weight_fifo.host_write <= controller.weight_load_enable
    weight_fifo.host_data <= host_data
    weight_fifo.host_addr <= controller.weight_row

    # Connect systolic array
    systolic_array.enable <= controller.array_enable
    systolic_array.load_weights <= controller.weight_load_enable
    systolic_array.weight_row <= controller.weight_row
    systolic_array.weights_data <= weight_fifo.array_data

    # Connect unified buffer
    unified_buffer.read_enable <= controller.buffer_read_enable
    unified_buffer.read_addr <= controller.buffer_addr
    systolic_array.activations <= unified_buffer.read_data

    unified_buffer.write_enable <= controller.buffer_write_enable
    unified_buffer.write_data <= activation_unit.activation_data

    # Connect activation unit
    activation_unit.enable <= controller.activation_enable
    activation_unit.accumulator_data <= systolic_array.partial_sums_out

    # Output
    result_data <= unified_buffer.dma_read_data
  end
end
```

## Sample Programs

### Matrix Multiplication

```ruby
def matrix_multiply_8x8(a, b)
  # a: 8×8 activation matrix
  # b: 8×8 weight matrix
  # Returns: 8×8 result matrix

  tpu = TpuDatapath.new('tpu')
  sim = Simulator.new(tpu)

  # 1. Load weights (B matrix)
  8.times do |row|
    weight_data = 0
    8.times do |col|
      weight_data |= (b[row][col] & 0xFF) << (col * 8)
    end
    sim.set_input(:host_data, weight_data)
    sim.set_input(:command, 1)  # CMD_LOAD_WEIGHTS
    sim.set_input(:command_param, row)
    sim.set_input(:command_valid, 1)
    sim.step
    sim.set_input(:command_valid, 0)

    # Wait for completion
    while sim.get_output(:busy) == 1
      sim.step
    end
  end

  # 2. Load activations to unified buffer
  8.times do |row|
    act_data = 0
    8.times do |col|
      act_data |= (a[row][col] & 0xFF) << (col * 8)
    end
    # DMA write to unified buffer
    # (simplified - would use DMA interface)
  end

  # 3. Execute matrix multiply
  sim.set_input(:command, 2)  # CMD_MATMUL
  sim.set_input(:command_valid, 1)
  sim.step
  sim.set_input(:command_valid, 0)

  while sim.get_output(:busy) == 1
    sim.step
  end

  # 4. Apply activation
  sim.set_input(:command, 3)  # CMD_ACTIVATE
  sim.set_input(:command_valid, 1)
  sim.step
  sim.set_input(:command_valid, 0)

  while sim.get_output(:busy) == 1
    sim.step
  end

  # 5. Read result
  result = Array.new(8) { Array.new(8, 0) }
  # (read from unified buffer via DMA)

  result
end
```

### Neural Network Layer

```ruby
def execute_dense_layer(weights, biases, activations, activation_fn)
  # Dense layer: output = activation(weights × input + bias)

  tpu = TpuDatapath.new('tpu')
  sim = Simulator.new(tpu)

  # Load weights
  load_weight_matrix(sim, weights)

  # Load activations to unified buffer
  load_activations(sim, activations)

  # Matrix multiply
  sim.set_input(:command, 2)  # MATMUL
  sim.set_input(:command_valid, 1)
  sim.step
  sim.set_input(:command_valid, 0)
  wait_until_done(sim)

  # Add bias (would be separate operation in real TPU)
  # ...

  # Apply activation function
  sim.set_input(:activation_func, activation_fn)
  sim.set_input(:command, 3)  # ACTIVATE
  sim.set_input(:command_valid, 1)
  sim.step
  sim.set_input(:command_valid, 0)
  wait_until_done(sim)

  # Read output
  read_output(sim)
end
```

## Performance Analysis

```
8×8 systolic array (this implementation):
- 64 MACs
- 1 matrix multiply per 16 cycles (8 fill + 8 drain)
- At 100 MHz: 400 million MACs/sec = 0.4 GOPS

256×256 systolic array (real TPU):
- 65,536 MACs
- 1 matrix multiply per 512 cycles
- At 700 MHz: 92 trillion MACs/sec = 92 TOPS
```

## Further Reading

- Jouppi et al., "In-Datacenter Performance Analysis of a Tensor Processing Unit"
- Google Cloud TPU Documentation
- "A Domain-Specific Architecture for Deep Neural Networks"

> Return to [Chapter 17](17-tpu.md) for architecture overview.
