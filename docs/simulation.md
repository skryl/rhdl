# HDL Simulation Engine

RHDL provides multiple simulation backends at different abstraction levels, from high-level Ruby behavioral simulation to low-level native Rust gate simulation. This document covers all simulation modes and their performance characteristics.

## Table of Contents

1. [Overview](#overview)
2. [Ruby Behavioral Simulation](#ruby-behavioral-simulation)
3. [Gate-Level Simulation](#gate-level-simulation)
4. [Native Rust Extensions](#native-rust-extensions)
5. [IR-Level Simulation](#ir-level-simulation)
6. [Performance Comparison](#performance-comparison)
7. [Benchmarking](#benchmarking)

---

## Overview

RHDL supports multiple simulation backends:

| Level | Backend | Speed | Use Case |
|-------|---------|-------|----------|
| **Behavioral** | Ruby Native | Baseline | Development, debugging |
| **Gate-Level** | Ruby SimCPU | 1-10M gates/sec | Functional verification |
| **Gate-Level** | Rust Interpreter | 10-50M gates/sec | Production testing |
| **Gate-Level** | Rust JIT | 50-100M gates/sec | Long simulations |
| **Gate-Level** | Rust Compiler | 100M+ gates/sec | Maximum performance |
| **IR-Level** | Rust Interpreter | ~60K cycles/sec | CPU simulation |
| **IR-Level** | Rust JIT | ~600K cycles/sec | Interactive debugging |
| **IR-Level** | Rust Compiler | ~2.3M cycles/sec | Full system simulation |
| **Native** | Verilator | ~5.7M cycles/sec | Reference validation |

---

## Ruby Behavioral Simulation

The Ruby behavioral simulation is the primary development mode, executing component logic directly in Ruby.

### Core Classes

#### SignalValue

Represents a signal value with multi-bit support and special states:

```ruby
# Create signal values
val = RHDL::Sim::SignalValue.new(0x42, width: 8)
val.to_i      # => 66
val.to_s      # => "01000010"
val[0]        # => 0 (LSB)
val[6]        # => 1
val.zero?     # => false

# Special values
unknown = RHDL::Sim::SignalValue::X  # Unknown/uninitialized
high_z = RHDL::Sim::SignalValue::Z   # High impedance (tri-state)
```

#### Wire

Wires carry signals between components with change notifications:

```ruby
wire = RHDL::Sim::Wire.new("data_bus", width: 8)

# Set and get values
wire.set(0x42)
wire.get       # => 66
wire.bit(0)    # => 0

# Change notifications for event-driven simulation
wire.on_change { |new_val| puts "Changed to #{new_val}" }
wire.set(0x43)  # Prints: "Changed to 67"

# Dependency tracking
wire.dependency_graph = simulator.dependency_graph
wire.add_sink(downstream_wire)
```

#### Clock

Special wire for clock signals with edge detection:

```ruby
clk = RHDL::Sim::Clock.new("sys_clk", period: 10)

clk.tick           # Toggle clock
clk.rising_edge?   # Check for 0->1 transition
clk.falling_edge?  # Check for 1->0 transition
clk.cycle_count    # Number of complete cycles
```

### Component Base Class

All components inherit from `RHDL::Sim::Component`:

```ruby
class MyComponent < RHDL::Sim::Component
  input :a, width: 8
  input :b, width: 8
  output :result, width: 8
  wire :temp, width: 16  # Internal signal

  behavior do
    temp <= a + b
    result <= temp[7..0]
  end
end
```

#### Port Access Methods

| Method | Description |
|--------|-------------|
| `input(name, width: 1)` | Define an input port |
| `output(name, width: 1)` | Define an output port |
| `wire(name, width: 1)` | Define an internal signal |
| `in_val(name)` | Get input value as integer |
| `out_set(name, value)` | Set output value |
| `set_input(name, value)` | Set input from external source |
| `get_output(name)` | Get output value |

### Sequential Components

For clocked components, use `SequentialComponent`:

```ruby
class MyRegister < RHDL::Sim::SequentialComponent
  input :d, width: 8
  input :clk
  input :rst
  input :en
  output :q, width: 8

  sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
    q <= mux(en, d, q)
  end
end
```

### Two-Phase Sequential Semantics

Sequential components use Verilog-style non-blocking assignment:

**Phase 1: Sample Inputs**
```ruby
def sample_inputs
  # All sequential components sample inputs simultaneously
  @sampled_inputs = @inputs.transform_values(&:get)
  @prev_clk == 0 && in_val(:clk) == 1  # Returns true on rising edge
end
```

**Phase 2: Update Outputs**
```ruby
def update_outputs
  # All sequential components update outputs simultaneously
  @pending_outputs.each { |name, val| out_set(name, val) }
  @pending_outputs.clear
end
```

This prevents race conditions where registers see values updated by other registers in the same cycle.

### Simulator Class

The `Simulator` manages multiple components and clocks:

```ruby
sim = RHDL::Sim::Simulator.new

# Add components
sim.add_component(alu)
sim.add_component(reg)

# Add clocks
sim.add_clock(clk)

# Initialize dependency graph for event-driven simulation
sim.initialize_graph

# Run simulation
sim.run(100)  # Run for 100 clock cycles

# Single step
sim.step      # Propagate all components once

# Access state
sim.time          # Current simulation time
sim.components    # Array of all components
```

### Propagation Strategies

**Event-Driven Propagation** (default after `initialize_graph`):
- Only evaluates components marked dirty
- Marks dependent components dirty when outputs change
- Max 1000 iterations with convergence warning

**Polling Propagation** (fallback):
- Evaluates all components every iteration
- Detects output changes and repeats if needed

```ruby
def propagate_all
  max_iterations = 1000
  iterations = 0
  begin
    changed = false
    @components.each do |c|
      old_outputs = c.outputs.transform_values(&:get)
      c.propagate
      new_outputs = c.outputs.transform_values(&:get)
      changed ||= old_outputs != new_outputs
    end
    iterations += 1
  end while changed && iterations < max_iterations
end
```

### Behavior Block Execution

Behavior blocks execute in a `BehaviorContext` that provides:

```ruby
behavior do
  # Operators
  result <= a & b      # Bitwise AND
  result <= a | b      # Bitwise OR
  result <= a ^ b      # Bitwise XOR
  result <= ~a         # Bitwise NOT
  result <= a + b      # Addition
  result <= a - b      # Subtraction

  # Conditional
  result <= mux(sel, when_true, when_false)

  # Case selection
  result <= case_select(op, {
    0 => a + b,
    1 => a - b,
    2 => a & b
  }, default: 0)

  # Literals with explicit width
  result <= lit(0xFF, width: 8)

  # Local variables (intermediate wires)
  sum = local(:sum, a + b, width: 9)
  result <= sum[7..0]
  cout <= sum[8]

  # Bit selection and slicing
  result <= a[7]       # Single bit
  result <= a[7..4]    # Slice

  # Concatenation
  result <= high.concat(low)

  # Replication
  sign_ext <= sign_bit.replicate(8)
end
```

---

## Gate-Level Simulation

Gate-level simulation evaluates circuits at the primitive gate level using the netlist IR.

### Gate-Level IR

The IR represents circuits with primitive gates:

```ruby
# Gate types: AND, OR, XOR, NOT, MUX, BUF, CONST
# Sequential: DFF (D flip-flop), SRLatch

ir = RHDL::Codegen::Netlist::IR.new(name: 'alu')

# Allocate nets
a_net = ir.new_net
b_net = ir.new_net
y_net = ir.new_net

# Add gates
ir.add_gate(type: :and, inputs: [a_net, b_net], output: y_net)
ir.add_gate(type: :not, inputs: [a_net], output: not_a_net)
ir.add_gate(type: :mux, inputs: [a_net, b_net, sel_net], output: y_net)
ir.add_gate(type: :const, inputs: [], output: const_net, value: 1)

# Add flip-flops
ir.add_dff(d: d_net, q: q_net, rst: rst_net, en: en_net, reset_value: 0)

# Register ports
ir.add_input('alu.a', [a0, a1, a2, a3, a4, a5, a6, a7])
ir.add_output('alu.y', [y0, y1, y2, y3, y4, y5, y6, y7])
```

### Lowering HDL to Gates

The `Lower` class converts HDL components to gate-level IR:

```ruby
# Lower a component
alu = RHDL::HDL::ALU.new('alu', width: 8)
ir = RHDL::Codegen::Netlist::Lower.from_components([alu], name: 'alu')

puts "Gates: #{ir.gates.length}"
puts "DFFs: #{ir.dffs.length}"
puts "Nets: #{ir.net_count}"

# Export to JSON
File.write('alu.json', ir.to_json)
```

### SIMD Lanes Architecture

Gate-level simulators use a "lanes" architecture for parallel simulation:

```
Lane 0:  Test vector 0 (bit 0 of each u64)
Lane 1:  Test vector 1 (bit 1 of each u64)
...
Lane 63: Test vector 63 (bit 63 of each u64)

Net value = u64 where bit[i] = output for test vector i
```

**Advantage**: Tests 64 combinations simultaneously with no additional overhead.

### Ruby Gate Simulator (SimCPU)

Pure Ruby gate-level interpreter:

```ruby
ir = RHDL::Codegen::Netlist::Lower.from_components([component])
sim = RHDL::Codegen::Netlist::RubyNetlistSimulator.new(ir, lanes: 64)

# Set inputs (u64 bitmask per bit)
sim.poke('comp.a', [0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00])

# Evaluate combinational logic
sim.evaluate

# Read outputs
result = sim.peek('comp.y')

# Clock cycle (for sequential logic)
sim.tick

# Reset
sim.reset
```

### Gate Evaluation

Gates are evaluated in topological order:

```ruby
@schedule.each do |gate_idx|
  gate = @gates[gate_idx]
  case gate.type
  when :and  then @nets[gate.output] = @nets[gate.inputs[0]] & @nets[gate.inputs[1]]
  when :or   then @nets[gate.output] = @nets[gate.inputs[0]] | @nets[gate.inputs[1]]
  when :xor  then @nets[gate.output] = @nets[gate.inputs[0]] ^ @nets[gate.inputs[1]]
  when :not  then @nets[gate.output] = (~@nets[gate.inputs[0]]) & @lane_mask
  when :mux  then @nets[gate.output] = (@nets[gate.inputs[0]] & ~@nets[gate.inputs[2]]) |
                                        (@nets[gate.inputs[1]] & @nets[gate.inputs[2]])
  when :buf  then @nets[gate.output] = @nets[gate.inputs[0]]
  when :const then @nets[gate.output] = gate.value.zero? ? 0 : @lane_mask
  end
end
```

---

## Native Rust Extensions

RHDL provides high-performance Rust implementations for simulation backends.

### Available Extensions

| Extension | Path | Binding | Purpose |
|-----------|------|---------|---------|
| ISA Simulator | `examples/mos6502/utilities/isa_simulator_native/` | Magnus | 6502 CPU emulation |
| Netlist Interpreter | `lib/rhdl/codegen/netlist/sim/netlist_interpreter/` | Magnus | Gate interpretation |
| Netlist JIT | `lib/rhdl/codegen/netlist/sim/netlist_jit/` | Cranelift + Magnus | Gate JIT compilation |
| Netlist Compiler | `lib/rhdl/codegen/netlist/sim/netlist_compiler/` | rustc + Magnus | Gate AOT compilation |
| IR Interpreter | `lib/rhdl/codegen/ir/sim/ir_interpreter/` | Fiddle | Bytecode interpreter |
| IR JIT | `lib/rhdl/codegen/ir/sim/ir_jit/` | Cranelift + Fiddle | Bytecode JIT |
| IR Compiler | `lib/rhdl/codegen/ir/sim/ir_compiler/` | rustc + Fiddle | Bytecode AOT |

### Building Extensions

```bash
# Build all extensions
rake native:build

# Build specific extension
rake native:build[netlist_jit]

# Check availability
rake native:check

# Clean build artifacts
rake native:clean
```

### Netlist Interpreter (Rust)

Direct interpretation of gate-level netlist:

```ruby
require 'rhdl'

if RHDL::Codegen::Netlist::NETLIST_INTERPRETER_AVAILABLE
  sim = RHDL::Codegen::Netlist::NetlistInterpreter.new(ir.to_json, 64)
  sim.poke('a', 0xFF)
  sim.evaluate
  result = sim.peek('y')
end
```

**Performance**: 10-20x faster than Ruby SimCPU.

### Netlist JIT (Cranelift)

Compiles gate logic to native code at load time:

```ruby
if RHDL::Codegen::Netlist::NETLIST_JIT_AVAILABLE
  sim = RHDL::Codegen::Netlist::NetlistJit.new(ir.to_json, 64)
  # First evaluate compiles the circuit
  sim.evaluate
  # Subsequent evaluates run native code
end
```

**Performance**: Zero interpretation overhead after compilation.

### Netlist Compiler (rustc + SIMD)

Ahead-of-time compilation with SIMD vectorization:

```ruby
if RHDL::Codegen::Netlist::NETLIST_COMPILER_AVAILABLE
  sim = RHDL::Codegen::Netlist::NetlistCompiler.new(ir.to_json, 'avx2')
  sim.compile  # Generates and compiles Rust code
  sim.evaluate
end
```

**SIMD Modes**:
- `:scalar` - 64 lanes (1 × u64)
- `:avx2` - 256 lanes (4 × u64)
- `:avx512` - 512 lanes (8 × u64)
- `:auto` - Auto-detect best available

**Performance**: Fastest option for batch simulations.

### Unified Netlist Simulator

All native netlist backends are accessed through one class with automatic fallback:

```ruby
# Automatically uses best available backend
sim = RHDL::Codegen::Netlist::NetlistSimulator.new(
  ir,
  backend: :interpreter,
  lanes: 64,
  allow_fallback: true  # Falls back to Ruby if native unavailable
)

# Check which backend is in use
puts sim.backend  # :interpret, :ruby, :jit, or :compile
puts sim.native?  # true if using native extension
```

---

## IR-Level Simulation

IR-level simulation operates on word-level bytecode, providing faster simulation than gate-level for complex designs like CPUs.

### IR Structure

The behavior IR represents operations at the word level:

```ruby
ir = RHDL::Codegen::Behavior::IR.new
ir.add_signal(:a, width: 8, direction: :input)
ir.add_signal(:b, width: 8, direction: :input)
ir.add_signal(:result, width: 8, direction: :output)

ir.add_operation(:add, dest: :result, src1: :a, src2: :b)
```

### IR Interpreter (Rust + Fiddle)

Bytecode interpreter with MOS6502 and Apple II extensions:

```ruby
require 'rhdl/codegen/ir/sim/ir_simulator'

if RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE
  sim = RHDL::Codegen::IR::IrSimulator.new(
    ir_json,
    backend: :interpreter,
    allow_fallback: true,
    sub_cycles: 14  # MOS6502 cycles per instruction
  )

  sim.poke('input', 0x42)
  sim.evaluate
  sim.tick
  result = sim.peek('output')

  # Batched execution
  sim.run_ticks(1000)
end
```

**Performance**: ~60K cycles/sec for MOS6502.

### IR JIT (Cranelift)

Runtime JIT compilation of IR:

```ruby
if RHDL::Codegen::IR::JIT_AVAILABLE
  sim = RHDL::Codegen::IR::IrSimulator.new(ir_json, backend: :jit)
  sim.compile  # JIT compile
  sim.run_ticks(1_000_000)
end
```

**Performance**: ~600K cycles/sec for MOS6502.

### IR Compiler (rustc)

Ahead-of-time compilation with full optimization:

```ruby
if RHDL::Codegen::IR::COMPILER_AVAILABLE
  sim = RHDL::Codegen::IR::IrSimulator.new(ir_json, backend: :compiler)
  sim.compile  # AOT compile with rustc
  sim.run_ticks(5_000_000)
end
```

**Performance**: ~2.3M cycles/sec for MOS6502.

### ISA Simulator (Native MOS6502)

Specialized high-performance 6502 emulator:

```ruby
require 'rhdl'

if MOS6502::NATIVE_AVAILABLE
  # Internal memory only (fastest)
  cpu = MOS6502::ISASimulatorNative.new(nil)

  # With I/O handler (for Apple II peripherals)
  cpu = MOS6502::ISASimulatorNative.new(io_handler)

  cpu.load_bytes(program, 0x8000)
  cpu.poke(0xFFFC, 0x00)  # Reset vector low
  cpu.poke(0xFFFD, 0x80)  # Reset vector high
  cpu.reset

  1000.times { cpu.step }

  puts "A: #{cpu.a}, X: #{cpu.x}, Y: #{cpu.y}"
  puts "PC: 0x#{cpu.pc.to_s(16)}"
end
```

**Performance**: 15-20x faster than Ruby ISA simulator.

---

## Performance Comparison

### Gate-Level Simulators

**16-bit ALU, 10,000 iterations:**

| Backend | Time | Rate | Speedup |
|---------|------|------|---------|
| Ruby SimCPU | 0.457s | 21,898 iter/s | 1.0x |
| Rust Interpreter | 0.023s | 427,350 iter/s | 19.5x |

**Sequential Logic (8 DFFs), 10,000 iterations:**

| Backend | Time | Rate | Speedup |
|---------|------|------|---------|
| Ruby SimCPU | 0.342s | 29,238 iter/s | 1.0x |
| Rust Interpreter | 0.016s | 641,025 iter/s | 21.9x |

### IR-Level Simulators

**MOS6502 CPU, 5M cycles (Karateka game):**

| Backend | Time | Rate | Speedup vs JIT |
|---------|------|------|----------------|
| Interpreter | Skip | ~60K/s | - |
| JIT | 8.23s | 607K/s | 1.0x |
| Compiler | 2.15s | 2.33M/s | 3.8x |
| Verilator | 0.88s | 5.71M/s | 9.4x |

**Apple II Full System, 5M cycles:**

| Backend | Time | Rate | Speedup vs JIT |
|---------|------|------|----------------|
| JIT | 15.23s | 328K/s | 1.0x |
| Compiler | 4.57s | 1.09M/s | 3.3x |
| Verilator | 1.23s | 4.05M/s | 12.3x |

### ISA Simulator

**Simple loop (255 count-down):**

| Backend | Time | Speedup |
|---------|------|---------|
| Ruby ISA | 12.5ms | 1.0x |
| Native (internal) | 0.8ms | 15.6x |
| Native (I/O handler) | 0.9ms | 13.9x |

---

## Benchmarking

### Running Benchmarks

```bash
# Gate-level simulation benchmark
rake bench:gates
RHDL_BENCH_LANES=128 RHDL_BENCH_CYCLES=1000000 rake bench:gates

# MOS6502 CPU benchmark
rake bench:mos6502
rake bench:mos6502[5000000]  # 5M cycles

# Apple II full system benchmark
rake bench:apple2
rake bench:apple2[2000000]  # 2M cycles

# Verilator comparison (requires Verilator)
rake bench:verilator[1000000]

# Test suite benchmarks
rake spec:bench            # 20 slowest tests
rake spec:bench:all[50]    # 50 slowest tests
rake spec:bench:hdl[20]    # HDL tests
rake spec:bench:mos6502[20] # MOS6502 tests

# Detailed timing analysis
rake benchmark:timing       # Per-file timing
rake benchmark:quick        # Category summary
```

### Programmatic Benchmarking

```ruby
require 'benchmark'

# Gate-level benchmark
ir = RHDL::Codegen::Netlist::Lower.from_components([alu])
ruby_sim = RHDL::Codegen::Netlist::RubyNetlistSimulator.new(ir, lanes: 64)
native_sim = RHDL::Codegen::Netlist::NetlistInterpreter.new(ir.to_json, 64)

ruby_time = Benchmark.measure do
  10_000.times { ruby_sim.evaluate }
end

native_time = Benchmark.measure do
  10_000.times { native_sim.evaluate }
end

puts "Ruby: #{ruby_time.real}s"
puts "Native: #{native_time.real}s"
puts "Speedup: #{(ruby_time.real / native_time.real).round(1)}x"
```

### Benchmark Output Example

```
MOS6502 CPU IR Benchmark - Karateka Game Code
Cycles per run: 5000000
ROM: examples/mos6502/software/roms/appleiigo.rom

Generating MOS6502::CPU IR... done (0.234s)

Interpreter: SKIPPED (cycles > 100K, too slow)

JIT: initializing... loading... running 5000000 cycles... done
  Init time: 0.123s
  Run time:  8.234s
  Rate:      607,520 cycles/s (0.61M/s)
  Final PC:  0xB8F2

Compiler: initializing... loading... running 5000000 cycles... done
  Init time: 0.145s
  Run time:  2.145s
  Rate:      2,329,693 cycles/s (2.33M/s)
  Final PC:  0xB8F2

Summary
======================================
Runner           Status  Init       Run        Rate
================================================
JIT              OK      0.123s     8.234s     0.61M/s
Compiler         OK      0.145s     2.145s     2.33M/s

Performance Ratios:
  Compiler vs JIT: 3.8x
```

---

## Debugging Support

### Debug Simulator

Enhanced simulator with breakpoints and waveform capture:

```ruby
require 'rhdl/debug'

sim = RHDL::Debug::DebugSimulator.new
sim.add_component(counter)
sim.add_clock(clk)

# Signal probing
sim.probe(counter, :q)
sim.probe(clk, nil)

# Breakpoints
bp = sim.add_breakpoint { |s| s.current_cycle == 100 }
sim.on_break = ->(s, bp) {
  puts "Breakpoint hit at cycle #{s.current_cycle}"
  puts s.dump_state
}

# Watchpoints
wp = sim.watch(counter.outputs[:q], type: :equals, value: 10) do |s|
  puts "Counter reached 10!"
end

# Run with debugging
sim.run(200)

# Export waveform
File.write("waveform.vcd", sim.waveform.to_vcd)
```

### Watchpoint Types

| Type | Description |
|------|-------------|
| `:change` | Signal changes from previous value |
| `:equals` | Signal equals specified value |
| `:not_equals` | Signal not equal to value |
| `:greater` | Signal greater than value |
| `:less` | Signal less than value |
| `:rising_edge` | 0→1 transition |
| `:falling_edge` | 1→0 transition |

### Step-by-Step Execution

```ruby
sim.enable_step_mode
sim.step_cycle       # One complete clock cycle
sim.step_half_cycle  # One clock edge
sim.pause
sim.resume
```

---

## Best Practices

### Choosing a Backend

1. **Development/Debugging**: Use Ruby behavioral simulation
2. **Functional Testing**: Use Ruby SimCPU or Rust Interpreter
3. **Regression Testing**: Use Rust JIT for faster turnaround
4. **Long Simulations**: Use Rust Compiler with SIMD
5. **Reference Validation**: Use Verilator for golden comparison

### Performance Optimization

1. **Minimize propagation calls**: Group input changes before propagating
2. **Use hierarchical design**: Encapsulate complex logic in subcomponents
3. **Avoid deep combinational chains**: They require more iterations to converge
4. **Cache frequently accessed values**: Store intermediate results in internal signals
5. **Use native extensions**: 10-20x speedup for gate-level, 3-10x for IR-level
6. **Batch operations**: Use `run_ticks(n)` instead of `n.times { tick }`

### Memory Considerations

| Simulation Mode | Memory per Net | Typical Usage |
|-----------------|----------------|---------------|
| Behavioral | ~200 bytes | Small designs |
| Gate-level (Ruby) | 8 bytes (u64) | Medium designs |
| Gate-level (Rust) | 8 bytes (u64) | Large designs |
| IR-level | Variable | CPU simulation |

---

## Example: Complete Simulation Workflow

```ruby
require 'rhdl'

# 1. Create component
alu = RHDL::HDL::ALU.new('alu', width: 8)

# 2. Behavioral simulation (development)
alu.set_input(:a, 10)
alu.set_input(:b, 5)
alu.set_input(:op, 0)  # ADD
alu.propagate
puts "Behavioral result: #{alu.get_output(:result)}"

# 3. Lower to gate-level
ir = RHDL::Codegen::Netlist::Lower.from_components([alu])
puts "Gates: #{ir.gates.length}, DFFs: #{ir.dffs.length}"

# 4. Gate-level simulation (verification)
sim = RHDL::Codegen::Netlist::NetlistSimulator.new(ir, backend: :interpreter, lanes: 64)
sim.poke('alu.a', 10)
sim.poke('alu.b', 5)
sim.poke('alu.op', 0)
sim.evaluate
result = sim.peek('alu.result')
puts "Gate-level result: #{result}"

# 5. Verify equivalence
raise "Mismatch!" unless alu.get_output(:result) == result.first
puts "Behavioral and gate-level match!"
```
