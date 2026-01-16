# HDL Simulation Engine

The simulation engine provides the core infrastructure for simulating digital circuits at the gate level.

## Core Classes

### SignalValue

Represents a signal value with support for multi-bit values and special states.

```ruby
# Create signal values
val = RHDL::HDL::SignalValue.new(0x42, width: 8)
val.to_i      # => 66
val.to_s      # => "01000010"
val[0]        # => 0 (LSB)
val[6]        # => 1
val.zero?     # => false

# Special values
unknown = RHDL::HDL::SignalValue::X  # Unknown/uninitialized
high_z = RHDL::HDL::SignalValue::Z   # High impedance (tri-state)
```

### Wire

Wires carry signals between components and support change notifications.

```ruby
wire = RHDL::HDL::Wire.new("data_bus", width: 8)

# Set and get values
wire.set(0x42)
wire.get       # => 66
wire.bit(0)    # => 0

# Change notifications
wire.on_change { |new_val| puts "Changed to #{new_val}" }
wire.set(0x43)  # Prints: "Changed to 01000011"
```

### Clock

Special wire for clock signals with edge detection.

```ruby
clk = RHDL::HDL::Clock.new("sys_clk", period: 10)

clk.tick           # Toggle clock
clk.rising_edge?   # Check for 0->1 transition
clk.falling_edge?  # Check for 1->0 transition
clk.cycle_count    # Number of complete cycles
```

## SimComponent Base Class

All components inherit from `SimComponent`:

```ruby
class MyComponent < RHDL::HDL::SimComponent
  def setup_ports
    # Define ports here
    input :a, width: 8
    input :b, width: 8
    output :result, width: 8
    signal :temp, width: 16  # Internal signal
  end

  def propagate
    # Compute outputs from inputs
    a = in_val(:a)
    b = in_val(:b)
    out_set(:result, (a + b) & 0xFF)
  end
end
```

### Port Methods

| Method | Description |
|--------|-------------|
| `input(name, width: 1)` | Define an input port |
| `output(name, width: 1)` | Define an output port |
| `signal(name, width: 1)` | Define an internal signal |
| `in_val(name)` | Get input value as integer |
| `out_set(name, value)` | Set output value |
| `set_input(name, value)` | Set input from external source |
| `get_output(name)` | Get output value |

### Component Connection

Connect components by linking wires:

```ruby
# Method 1: Direct connection
RHDL::HDL::SimComponent.connect(source.outputs[:y], dest.inputs[:a])

# Method 2: Manual wiring
source.outputs[:y].on_change { |val| dest.set_input(:a, val.to_i) }
```

## SequentialComponent Base Class

For clocked components:

```ruby
class MyRegister < RHDL::HDL::SequentialComponent
  def setup_ports
    input :d, width: 8
    input :clk
    input :rst
    input :en
    output :q, width: 8
  end

  def propagate
    if rising_edge?
      if in_val(:rst) == 1
        @state = 0
      elsif in_val(:en) == 1
        @state = in_val(:d)
      end
    end
    out_set(:q, @state)
  end
end
```

### Edge Detection

| Method | Description |
|--------|-------------|
| `rising_edge?` | Returns true on 0->1 clock transition |
| `falling_edge?` | Returns true on 1->0 clock transition |

**Note**: Edge detection methods update internal state and should only be called once per propagate cycle.

## Simulator Class

Manages multiple components and clocks:

```ruby
sim = RHDL::HDL::Simulator.new

# Add components
sim.add_component(alu)
sim.add_component(reg)

# Add clocks
sim.add_clock(clk)

# Run simulation
sim.run(100)  # Run for 100 clock cycles

# Single step
sim.step      # Propagate all components once

# Access state
sim.time          # Current simulation time
sim.components    # Array of all components
```

### Simulation Loop

The `run` method:
1. Toggles clock (high)
2. Propagates all components until stable
3. Toggles clock (low)
4. Propagates all components until stable
5. Repeats for N cycles

### Convergence

The simulator iteratively propagates until outputs stabilize:

```ruby
def propagate_all
  max_iterations = 1000
  iterations = 0
  begin
    changed = false
    @components.each do |c|
      old_outputs = c.outputs.transform_values { |w| w.get }
      c.propagate
      new_outputs = c.outputs.transform_values { |w| w.get }
      changed ||= old_outputs != new_outputs
    end
    iterations += 1
  end while changed && iterations < max_iterations
end
```

## Event-Driven Simulation

Wires support change callbacks for event-driven simulation:

```ruby
# Input changes trigger propagation
def input(name, width: 1)
  wire = Wire.new("#{@name}.#{name}", width: width)
  @inputs[name] = wire
  wire.on_change { |_| propagate }  # Auto-propagate on input change
  wire
end
```

This means changing an input automatically propagates through connected logic.

## Debugging

Components have an `inspect` method for debugging:

```ruby
alu = RHDL::HDL::ALU.new("alu", width: 8)
alu.set_input(:a, 10)
alu.set_input(:b, 5)
alu.set_input(:op, RHDL::HDL::ALU::OP_ADD)
alu.propagate

puts alu.inspect
# => #<RHDL::HDL::ALU alu in:(a=10, b=5, op=0, cin=0) out:(result=15, cout=0, zero=0, negative=0, overflow=0)>
```

## Performance Considerations

1. **Minimize propagation calls**: Group input changes before propagating
2. **Use hierarchical design**: Encapsulate complex logic in subcomponents
3. **Avoid deep combinational chains**: They require more iterations to converge
4. **Cache frequently accessed values**: Store intermediate results in internal signals

## Example: Building a Counter

```ruby
class Counter4Bit < RHDL::HDL::SequentialComponent
  def initialize(name = nil)
    @state = 0
    super(name)
  end

  def setup_ports
    input :clk
    input :rst
    input :en
    output :count, width: 4
    output :overflow
  end

  def propagate
    if rising_edge?
      if in_val(:rst) == 1
        @state = 0
      elsif in_val(:en) == 1
        @state = (@state + 1) & 0xF
      end
    end
    out_set(:count, @state)
    out_set(:overflow, @state == 0xF ? 1 : 0)
  end
end

# Usage
counter = Counter4Bit.new("cnt")
counter.set_input(:rst, 0)
counter.set_input(:en, 1)

16.times do
  counter.set_input(:clk, 0)
  counter.propagate
  counter.set_input(:clk, 1)
  counter.propagate
  puts "Count: #{counter.get_output(:count)}"
end
```
