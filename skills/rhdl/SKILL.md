---
name: rhdl
description: >
  RHDL hardware description language DSL reference. Use when writing
  RHDL components, porting Verilog/VHDL to RHDL, or answering questions
  about available DSL features, port declarations, behavior blocks,
  sequential logic, memory, state machines, vectors, bundles, or codegen.
user-invocable: true
argument-hint: "[component description or question]"
---

# RHDL DSL Reference

RHDL is a Ruby-based hardware description language. Components are Ruby
classes that declare ports, behavior, sequential logic, memory, and
hierarchical structure using DSL macros. The same definition drives both
Ruby simulation and Verilog/FIRRTL synthesis.

---

## Base Classes

| Class | Use |
|-------|-----|
| `RHDL::HDL::Component` | Combinational components (no clock) |
| `RHDL::HDL::SequentialComponent` | Clocked/sequential components |

Both live in `RHDL::Sim::` and are aliased into `RHDL::HDL::`.

---

## DSL Modules (include as needed)

| Module | Purpose | Required for |
|--------|---------|--------------|
| `RHDL::DSL::Behavior` | `behavior` blocks, combinational logic | Almost everything |
| `RHDL::DSL::Sequential` | `sequential` blocks, clocked logic | SequentialComponent |
| `RHDL::DSL::Memory` | `memory`, `sync_write`, `async_read`, `sync_read`, `lookup_table` | RAM/ROM/FIFO |
| `RHDL::DSL::StateMachine` | `state_machine` blocks | FSMs |
| `RHDL::DSL::Structure` | `instance`, `port` (hierarchical composition) | Auto-included |
| `RHDL::DSL::Vec` | `vec`, `input_vec`, `output_vec` | Register arrays |
| `RHDL::DSL::Bundle` | `input_bundle`, `output_bundle` | Bus interfaces |

---

## Port & Signal Declarations

```ruby
# Parameters (resolved at instantiation time)
parameter :width, default: 8
parameter :depth, default: -> { 2 ** @addr_width }  # Computed

# Ports
input  :clk                       # 1-bit input
input  :data, width: 8            # Multi-bit input
input  :data, width: :width       # Parameter-referenced width
input  :a, :b, width: 8           # Multiple ports, same width
output :result, width: 32         # Output port

# Internal signals (wires)
wire :temp, width: 16

# Vec (array of signals/ports)
vec        :regs, count: 32, width: 32    # Internal array
input_vec  :data_in, count: 8, width: 8   # Array of inputs
output_vec :data_out, count: 8, width: 8  # Array of outputs
```

---

## Behavior Blocks (Combinational Logic)

Use `behavior do ... end` for combinational logic. Available in both
`Component` and `SequentialComponent`.

### Assignment

```ruby
behavior do
  result <= a + b          # Continuous assignment to output/wire
end
```

### Inline locals (eliminate intermediate wires)

```ruby
behavior do
  sum = local(:sum, a + b + c_in, width: 9)
  result <= sum[7..0]
  carry  <= sum[8]
end
```

### Literals with explicit width

```ruby
lit(0, width: 8)           # 8-bit zero
lit(0xFF, width: 8)        # 8-bit constant
```

### Mux (2-way select)

```ruby
result <= mux(enable, a + b, a)     # if enable then a+b else a
```

Nest for priority: `mux(c1, v1, mux(c2, v2, v3))`

### if_else

```ruby
result <= if_else(cond, then_val, else_val)
```

### case_select (lookup table -- single output)

```ruby
result <= case_select(op, {
  0x00 => a + b,
  0x01 => a - b,
  0x02 => a & b,
  0x03 => a | b,
}, default: 0)
```

### case_of (multi-output dispatch)

```ruby
case_of(state) do |c|
  c.when(0) do
    led   <= lit(1, width: 1)
    count <= count + 1
  end
  c.when(1) do
    led   <= lit(0, width: 1)
    count <= 0
  end
  c.default do
    led   <= lit(0, width: 1)
    count <= count
  end
end
```

### if_chain (priority-encoded multi-output)

```ruby
if_chain do |ic|
  ic.when_cond(reset) do
    state <= 0
    count <= 0
  end
  ic.when_cond(enable) do
    state <= next_state
    count <= count + 1
  end
  ic.else_do do
    state <= state
    count <= count
  end
end
```

### Expressions & Operators

Arithmetic: `+`, `-`, `*`, `/`, `%`
Bitwise: `&`, `|`, `^`, `~`
Shift: `<<`, `>>`
Comparison: `==`, `!=`, `<`, `>`, `<=`, `>=`
Bit select: `signal[3]`
Bit slice: `signal[7..0]`
Concatenation: `cat(high, low)` or `signal.concat(other)`
Replication: `signal.replicate(4)`

### Memory reads in behavior

```ruby
data <= mem_read_expr(:ram, addr, width: 8)
```

---

## Sequential Blocks (Clocked Logic)

Use `sequential` on `SequentialComponent`. Outputs listed in
`reset_values` become registers; everything else is combinational.

```ruby
class Counter < RHDL::HDL::SequentialComponent
  include RHDL::DSL::Behavior
  include RHDL::DSL::Sequential

  input :clk, :rst, :enable
  output :count, width: 8

  sequential clock: :clk, reset: :rst, reset_values: { count: 0 } do
    count <= mux(enable, count + 1, count)
  end
end
```

All behavior-block helpers (`mux`, `case_select`, `case_of`, `if_chain`,
`local`, `lit`, `cat`, etc.) work inside sequential blocks too.

### Simulation API for sequential components

```ruby
comp.sample_inputs     # Phase 1: latch inputs
comp.update_outputs    # Phase 2: compute next state
comp.propagate         # Both phases combined
comp.read_reg(:count)  # Read internal register
comp.write_reg(:count, 42) # Write for test setup
```

---

## Memory DSL

### Simple memory with separate ports

```ruby
include RHDL::DSL::Memory

memory :ram, depth: 256, width: 8
sync_write :ram, clock: :clk, enable: :we, addr: :wr_addr, data: :din
async_read :dout, from: :ram, addr: :rd_addr

# Enable can be an expression:
sync_write :ram, clock: :clk, enable: [:cs, :&, :we], addr: :addr, data: :din
```

### Multi-port memory (block form)

```ruby
memory :mem, depth: 8192, width: 8 do |m|
  m.write_port     clock: :clock_a, enable: :wren_a, addr: :address_a, data: :data_a
  m.sync_read_port clock: :clock_a, addr: :address_a, output: :q_a
  m.write_port     clock: :clock_b, enable: :wren_b, addr: :address_b, data: :data_b
  m.sync_read_port clock: :clock_b, addr: :address_b, output: :q_b
end
```

### Lookup table (ROM)

```ruby
lookup_table :decode_rom do |t|
  t.input  :opcode, width: 4
  t.output :alu_op, width: 3
  t.output :reg_write, width: 1
  t.entry 0x0, alu_op: 0, reg_write: 1
  t.entry 0x1, alu_op: 1, reg_write: 1
  t.default     alu_op: 0, reg_write: 0
end
```

### Memory in behavior blocks

```ruby
behavior do
  data <= mem_read_expr(:ram, addr, width: 8)
end
```

### Simulation API

```ruby
comp.mem_read(:ram, addr)
comp.mem_write(:ram, addr, data, width)
comp.initialize_memories
comp.load_initial_contents
```

---

## State Machine DSL

```ruby
include RHDL::DSL::StateMachine

state_machine clock: :clk, reset: :rst do
  state :IDLE, value: 0 do
    output red: 1, green: 0
    transition to: :ACTIVE, when_cond: :trigger
  end

  state :ACTIVE, value: 1 do
    output red: 0, green: 1
    transition to: :DONE, after: 10    # Counter-based auto-transition
  end

  state :DONE, value: 2 do
    output red: 0, green: 0
    transition to: :IDLE               # Unconditional
  end

  initial_state :IDLE
  output_state :state, width: 2        # Width auto-calculated if omitted
end
```

---

## Hierarchical Structure

### Declare instances and connections

```ruby
instance :alu, ALU, width: 8           # Parameterized
instance :reg_file, RegisterFile

# Signal-to-port
port :a => [:alu, :a]

# Port-to-signal
port [:alu, :result] => :alu_out

# Instance-to-instance
port [:alu, :result] => [:reg_file, :d]

# Fan-out (one signal to many ports)
port :clk => [[:alu, :clk], [:reg_file, :clk]]
```

---

## Bundle DSL (Bus Interfaces)

```ruby
class MemBus < RHDL::Sim::Bundle
  field :addr,  width: 32, direction: :output
  field :data,  width: 32, direction: :inout
  field :read,  width: 1,  direction: :output
  field :write, width: 1,  direction: :output
  field :ready, width: 1,  direction: :input
end

class Controller < RHDL::HDL::Component
  input_bundle  :mem, MemBus               # Flattened: mem_addr, mem_data, ...
  output_bundle :mem, MemBus, flipped: true # Directions flipped
end
```

---

## Code Generation

```ruby
MyComponent.to_verilog                    # Single module
MyComponent.to_verilog_hierarchy          # All sub-modules included
MyComponent.to_ir                         # RHDL IR
MyComponent.to_flat_ir                    # Flattened IR (no hierarchy)
MyComponent.to_circt                      # CIRCT FIRRTL
MyComponent.to_circt_hierarchy            # FIRRTL with sub-modules
MyComponent.to_schematic                  # Schematic bundle
MyComponent.verilog_module_name           # Inferred module name
MyComponent.collect_submodule_classes     # All sub-module classes
```

---

## Simulation API (Testing)

### Combinational (Component)

```ruby
comp = MyComponent.new
comp.set_input(:a, 0x10)
comp.set_input(:b, 0x20)
comp.propagate
expect(comp.get_output(:result)).to eq(0x30)
```

### Sequential (SequentialComponent)

```ruby
comp = MyCounter.new
comp.set_input(:clk, 0)
comp.set_input(:rst, 1)
comp.propagate              # Reset
comp.set_input(:rst, 0)

# Clock cycle: low→high edge
comp.set_input(:clk, 0); comp.propagate
comp.set_input(:clk, 1); comp.propagate

expect(comp.get_output(:count)).to eq(1)
```

---

## Canonical Component Template

```ruby
require_relative '<path>/lib/rhdl'
require_relative '<path>/lib/rhdl/dsl/behavior'
require_relative '<path>/lib/rhdl/dsl/sequential'
require_relative '<path>/lib/rhdl/dsl/memory'

module RHDL
  module Examples
    module MySystem
      class MyComponent < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential
        include RHDL::DSL::Memory   # Only if using memory

        # 1. Parameters
        parameter :width, default: 8

        # 2. Ports
        input :clk, :rst
        input :data_in, width: :width
        output :data_out, width: :width

        # 3. Internal wires (only for cross-block or sub-component signals)
        wire :internal_bus, width: :width

        # 4. Memory (if needed)
        memory :ram, depth: 256, width: :width
        sync_write :ram, clock: :clk, enable: :we, addr: :addr, data: :data_in

        # 5. Combinational logic
        behavior do
          data_out <= mem_read_expr(:ram, addr, width: 8)
        end

        # 6. Sequential logic
        sequential clock: :clk, reset: :rst, reset_values: { state: 0 } do
          state <= mux(enable, state + 1, state)
        end
      end
    end
  end
end
```

---

## Boilerplate Reduction Tips

1. **`local()` over `wire`** -- Use `local(:name, expr, width:)` inside
   behavior/sequential blocks for intermediates. Reserve `wire` for
   signals shared across blocks or sub-component connections.

2. **`case_select` for dispatch** -- Large opcode/command dispatch tables
   map to a single `case_select` hash instead of nested if/elsif chains.

3. **`case_of` for multi-output** -- When one selector drives several
   outputs, use `case_of` once instead of parallel `case_select` trees.

4. **`cat` + slicing for packed fields** -- `cat(hi, lo)` to pack,
   `signal[hi..lo]` to extract. Avoid manual shift/mask arithmetic.

5. **`vec` for register arrays** -- `vec :gpr, count: 32, width: 32`
   instead of 32 individual port declarations.

6. **Bundles for bus interfaces** -- Define once, reuse across components.

7. **`memory` DSL for storage** -- RAM, ROM, FIFO backing stores.
   Multi-port block form for dual-port memories.

8. **`state_machine` for FSMs** -- Declarative states/transitions instead
   of hand-coded next-state logic with mux chains.

9. **`parameter` for reuse** -- Parameterize width/depth so one class
   serves multiple instantiations.

10. **Ruby metaprogramming** -- For repetitive dispatch (e.g., instruction
    decoders with 100+ cases), generate `case_select` branches
    programmatically from data tables instead of writing each by hand.

---

## File Organization

```
examples/<system>/
  hdl/             # RHDL component definitions
    <top>.rb       # Top-level component
    constants.rb   # Shared constants
    harness.rb     # Test harness
    <sub>/         # Sub-component directories
  utilities/
    runners/       # Simulation backends (ruby, IR, netlist, verilator)
    tasks/         # Executable tasks
    renderers/     # Output visualization
  bin/<system>     # CLI entry point
  software/        # Optional: ROM images, bootloaders

spec/examples/<system>/
  hdl/             # Unit tests (mirrors hdl/ structure)
  integration/     # Integration/program tests
```
