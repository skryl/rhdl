# Debugging and Signal Analysis

RHDL includes a comprehensive debugging infrastructure for HDL simulations, including signal probing, waveform capture, breakpoints, and an interactive terminal GUI.

## Signal Probing

### SignalProbe

The `SignalProbe` class records signal transitions over time for waveform analysis.

```ruby
# Create a probe attached to a wire
wire = RHDL::HDL::Wire.new("data_bus", width: 8)
probe = RHDL::HDL::SignalProbe.new(wire, name: "bus_probe")

# Signal changes are automatically recorded
wire.set(0x42)
wire.set(0xFF)

# Access recorded history
probe.history.each do |time, value|
  puts "At #{time}: 0x#{value.to_s(16)}"
end

# Get current value
puts probe.current_value

# Generate ASCII waveform
puts probe.to_waveform(width: 60)

# Enable/disable recording
probe.disable!
probe.enable!
probe.clear!
```

### WaveformCapture

The `WaveformCapture` class manages multiple probes and provides export functionality.

```ruby
capture = RHDL::HDL::WaveformCapture.new

# Add probes for signals
capture.add_probe(clock_wire, name: "clk")
capture.add_probe(data_wire, name: "data")
capture.add_probe(addr_wire, name: "addr")

# Control recording
capture.start_recording
# ... run simulation ...
capture.stop_recording

# Display text-based waveforms
puts capture.display(width: 80)

# Export to VCD format (for GTKWave)
vcd_content = capture.to_vcd(timescale: "1ns")
File.write("simulation.vcd", vcd_content)

# Clear all recorded data
capture.clear_all
```

## Breakpoints and Watchpoints

### Breakpoints

Breakpoints pause simulation when a condition is met.

```ruby
sim = RHDL::HDL::DebugSimulator.new

# Break on a custom condition
bp = sim.add_breakpoint { |sim| sim.current_cycle >= 100 }

# Check breakpoint properties
puts bp.id           # Unique identifier
puts bp.hit_count    # Number of times triggered
puts bp.enabled      # Is it enabled?

# Control breakpoint
bp.disable!
bp.enable!
bp.reset!            # Reset hit count

# Remove breakpoint
sim.remove_breakpoint(bp.id)
sim.clear_breakpoints
```

### Watchpoints

Watchpoints are specialized breakpoints that trigger on signal changes.

```ruby
# Break when signal changes
sim.watch(wire, type: :change)

# Break when signal equals a value
sim.watch(wire, type: :equals, value: 0x42)

# Break when signal doesn't equal a value
sim.watch(wire, type: :not_equals, value: 0)

# Break on rising edge (0 -> 1)
sim.watch(clock_wire, type: :rising_edge)

# Break on falling edge (1 -> 0)
sim.watch(clock_wire, type: :falling_edge)

# Break when signal is greater/less than value
sim.watch(counter_wire, type: :greater, value: 100)
sim.watch(counter_wire, type: :less, value: 10)

# Watchpoint with callback
sim.watch(wire, type: :equals, value: 0xFF) do |simulator|
  puts "Signal reached maximum value!"
end
```

## DebugSimulator

The `DebugSimulator` extends the base simulator with debugging features.

```ruby
sim = RHDL::HDL::DebugSimulator.new

# Add components
clock = RHDL::HDL::Clock.new("clk")
counter = RHDL::HDL::Counter.new("cnt", width: 8)
sim.add_clock(clock)
sim.add_component(counter)

# Connect components
RHDL::HDL::SimComponent.connect(clock, counter.inputs[:clk])

# Add probes (automatically creates SignalProbe)
sim.probe(counter, :q)       # Probe output 'q'
sim.probe(clock)             # Probe the clock wire directly

# Step control
sim.step_cycle              # Execute one full clock cycle
sim.step_half_cycle         # Execute half a clock cycle

# Run control
sim.run(100)                # Run 100 cycles
sim.pause                   # Pause simulation
sim.resume                  # Resume simulation

# Step mode
sim.enable_step_mode        # Enable step-by-step execution
sim.disable_step_mode       # Disable step mode

# Callbacks
sim.on_break = -> (sim, breakpoint) do
  puts "Breakpoint hit: #{breakpoint.id}"
  sim.pause
end

sim.on_step = -> (sim) do
  puts "Stepped to cycle #{sim.current_cycle}"
end

# Inspection
puts sim.signal_state       # Hash of all signal values
puts sim.dump_state         # Formatted state dump
puts sim.get_signal("counter.q")  # Get specific signal value

# Reset
sim.reset
```

## Terminal GUI (TUI)

The `SimulatorTUI` provides an interactive terminal interface for simulation.

### Launching the TUI

```ruby
require 'rhdl'

# Create simulator with components
sim = RHDL::HDL::DebugSimulator.new
# ... add components ...

# Create and configure TUI
tui = RHDL::HDL::SimulatorTUI.new(sim)
tui.add_component(counter)  # Add component signals to display
tui.add_component(alu)

# Run the TUI
tui.run
```

### TUI Layout

```
┌─────────────── Signals ──────────────┐┌────────────── Waveform ──────────────┐
│ counter.clk      HIGH                ││ clk  │▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄│
│ counter.rst      LOW                 ││ q    │════╳════╳════╳════╳════╳════│
│ counter.q        0x2A (42)           ││ zero │▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄│
│ counter.zero     LOW                 ││      └──────────────────────────────┘
│                                      ││                                      │
└──────────────────────────────────────┘└──────────────────────────────────────┘
┌─────────────── Console ──────────────┐┌────────── Breakpoints ───────────────┐
│ 10:23:45 Simulation started          ││ ● #1 counter.q changes (hits: 42)   │
│ 10:23:46 Stepped to cycle 1          ││ ○ #2 counter.q == 100 (hits: 0)     │
│ 10:23:47 Watch triggered: counter.q  ││                                      │
└──────────────────────────────────────┘└──────────────────────────────────────┘
 ▶ RUNNING │ T:42 C:42                                h:Help q:Quit Space:Step
```

### Keyboard Controls

| Key | Action |
|-----|--------|
| `Space` | Step one cycle |
| `n` | Step half cycle |
| `r` | Run simulation |
| `s` | Stop/pause simulation |
| `c` | Continue until breakpoint |
| `R` | Reset simulation |
| `w` | Add watchpoint (opens command mode) |
| `b` | Add breakpoint (opens command mode) |
| `j` / `↓` | Scroll signals down |
| `k` / `↑` | Scroll signals up |
| `:` | Enter command mode |
| `h` / `?` | Show help |
| `q` | Quit |

### Command Mode

Press `:` to enter command mode. Available commands:

| Command | Description |
|---------|-------------|
| `run [n]` | Run n cycles (default: 100) |
| `step` | Single step |
| `watch <signal> [type]` | Add watchpoint |
| `break [cycle]` | Add breakpoint |
| `delete <id>` | Delete breakpoint by ID |
| `clear [what]` | Clear breaks/waves/log |
| `set <signal> <value>` | Set signal value |
| `print <signal>` | Print signal value |
| `list` | List all signals |
| `export <file>` | Export VCD waveform |
| `help` | Show help |
| `quit` | Exit TUI |

### Watch Types

When adding a watchpoint, specify the type:

- `change` - Break when signal changes (default)
- `equals` - Break when signal equals specified value
- `rising_edge` - Break on 0→1 transition
- `falling_edge` - Break on 1→0 transition

Example: `:watch counter.q equals 100`

### Value Formats

When setting or printing values, multiple formats are supported:

- Decimal: `42`
- Hexadecimal: `0x2A`
- Binary: `0b101010`
- Octal: `0o52`

## VCD Export

VCD (Value Change Dump) is a standard format for waveform data that can be viewed in tools like GTKWave.

```ruby
# From WaveformCapture
vcd = capture.to_vcd(timescale: "1ns")
File.write("waveform.vcd", vcd)

# From DebugSimulator
sim.run(100)
File.write("simulation.vcd", sim.waveform.to_vcd)
```

### Viewing VCD Files

1. Install GTKWave: `apt-get install gtkwave` or `brew install gtkwave`
2. Open the VCD file: `gtkwave simulation.vcd`
3. Add signals from the signal tree to the waveform viewer

## Example: Complete Debug Session

```ruby
require 'rhdl'

# Setup simulation
sim = RHDL::HDL::DebugSimulator.new
clock = RHDL::HDL::Clock.new("clk")
counter = RHDL::HDL::Counter.new("cnt", width: 8)

sim.add_clock(clock)
sim.add_component(counter)
RHDL::HDL::SimComponent.connect(clock, counter.inputs[:clk])

counter.set_input(:rst, 0)
counter.set_input(:en, 1)
counter.set_input(:up, 1)
counter.set_input(:load, 0)

# Add probes
sim.probe(counter, :q)
sim.probe(counter, :zero)

# Add watchpoint
sim.watch(counter.outputs[:q], type: :equals, value: 50) do |s|
  puts "Halfway there!"
end

# Add breakpoint at cycle 100
sim.add_breakpoint { |s| s.current_cycle >= 100 }

# Setup break callback
sim.on_break = -> (s, bp) do
  puts "Breakpoint hit at cycle #{s.current_cycle}"
  puts s.dump_state
  s.pause
end

# Run simulation
sim.run(200)

# Export results
File.write("counter_sim.vcd", sim.waveform.to_vcd)
puts "Simulation complete. Final count: #{counter.get_output(:q)}"
```
