# Synthesizable DSL Guide

This document explains how to convert manual `propagate` methods to synthesizable DSL blocks.

## Overview

RHDL provides several DSL modules for synthesizable hardware:

1. **`behavior do ... end`** - Combinational logic (purely input-to-output), supports `case_of` for multi-way selection
2. **`sequential clock: :clk do ... end`** - Sequential logic (registers, state machines)
3. **`memory :name, depth:, width:`** - RAM/ROM arrays
4. **`lookup_table :name do ... end`** - Combinational ROM/decoder
5. **`state_machine clock:, reset: do ... end`** - Finite state machines

## Combinational Components

Simple combinational logic can use the `behavior` block:

```ruby
class SimpleALU < RHDL::HDL::SimComponent
  port_input :a, width: 8
  port_input :b, width: 8
  port_input :op, width: 2
  port_output :result, width: 8

  behavior do
    result <= case_of(op,
      0 => a + b,
      1 => a - b,
      2 => a & b,
      3 => a | b
    )
  end
end
```

This generates synthesizable Verilog:
```verilog
module simple_alu(
  input [7:0] a,
  input [7:0] b,
  input [1:0] op,
  output [7:0] result
);
  assign result = (op == 2'd0) ? (a + b) :
                  (op == 2'd1) ? (a - b) :
                  (op == 2'd2) ? (a & b) :
                  (a | b);
endmodule
```

## Sequential Components

For registers and state machines, use the `sequential` block:

```ruby
class DFlipFlop < RHDL::HDL::SequentialComponent
  port_input :clk
  port_input :rst
  port_input :d
  port_output :q

  sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
    q <= d
  end
end
```

This generates:
```verilog
module d_flip_flop(
  input clk,
  input rst,
  input d,
  output reg q
);
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      q <= 1'b0;
    end else begin
      q <= d;
    end
  end
endmodule
```

## Counter Example

```ruby
class Counter < RHDL::HDL::SequentialComponent
  port_input :clk
  port_input :rst
  port_input :en
  port_output :count, width: 8

  sequential clock: :clk, reset: :rst, reset_values: { count: 0 } do
    count <= mux(en, count + 1, count)
  end
end
```

## Behavior with Case Statements

For components with multiple outputs per case branch, use `case_of` inside a `behavior` block:

```ruby
class ALU8 < RHDL::HDL::SimComponent
  include RHDL::DSL::Behavior

  OP_ADD = 0x00
  OP_SUB = 0x01
  OP_AND = 0x02

  port_input :a, width: 8
  port_input :b, width: 8
  port_input :op, width: 4
  port_output :result, width: 8
  port_output :carry

  behavior do
    case_of op do |cs|
      cs.when(OP_ADD) do
        result <= a + b
        carry <= (a + b)[8]
      end
      cs.when(OP_SUB) do
        result <= a - b
        carry <= lit(0, width: 1)
      end
      cs.default do
        result <= a
        carry <= lit(0, width: 1)
      end
    end
  end
end
```

## Memory DSL

For RAM and ROM components that synthesize to BRAM:

```ruby
class RAM256x8 < RHDL::HDL::SimComponent
  include RHDL::DSL::MemoryDSL

  port_input :clk
  port_input :we
  port_input :addr, width: 8
  port_input :din, width: 8
  port_output :dout, width: 8

  # Declare memory array - synthesizes to reg array / BRAM
  memory :mem, depth: 256, width: 8

  # Synchronous write
  sync_write :mem, clock: :clk, enable: :we, addr: :addr, data: :din

  # Asynchronous read
  async_read :dout, from: :mem, addr: :addr
end
```

Generated Verilog:
```verilog
module ram256x8(
  input        clk,
  input        we,
  input  [7:0] addr,
  input  [7:0] din,
  output [7:0] dout
);
  reg [7:0] mem [0:255];

  always @(posedge clk) begin
    if (we) begin
      mem[addr] <= din;
    end
  end

  assign dout = mem[addr];
endmodule
```

## Lookup Table DSL

For combinational decoders and ROMs:

```ruby
class InstructionDecoder < RHDL::HDL::SimComponent
  include RHDL::DSL::MemoryDSL

  port_input :opcode, width: 8
  port_output :addr_mode, width: 4
  port_output :alu_op, width: 4
  port_output :cycles, width: 3

  lookup_table :decode do |t|
    t.input :opcode, width: 8
    t.output :addr_mode, width: 4
    t.output :alu_op, width: 4
    t.output :cycles, width: 3

    # Individual entries
    t.entry 0x00, addr_mode: 0, alu_op: 0, cycles: 7   # BRK
    t.entry 0x69, addr_mode: 1, alu_op: 0, cycles: 2   # ADC imm
    t.entry 0x65, addr_mode: 2, alu_op: 0, cycles: 3   # ADC zp

    # Bulk entries
    t.add_entries({
      0xA9 => { addr_mode: 1, alu_op: 13, cycles: 2 },  # LDA imm
      0xA5 => { addr_mode: 2, alu_op: 13, cycles: 3 },  # LDA zp
    })

    t.default addr_mode: 0xF, alu_op: 0xF, cycles: 0
  end
end
```

## State Machine DSL

For finite state machines:

```ruby
class TrafficLight < RHDL::HDL::SequentialComponent
  include RHDL::DSL::StateMachineDSL

  port_input :clk
  port_input :rst
  port_input :sensor
  port_output :red
  port_output :yellow
  port_output :green
  port_output :state, width: 2

  state_machine clock: :clk, reset: :rst do
    state :RED, value: 0 do
      output red: 1, yellow: 0, green: 0
      transition to: :GREEN, when_cond: :sensor
    end

    state :YELLOW, value: 1 do
      output red: 0, yellow: 1, green: 0
      transition to: :RED, after: 3  # After 3 clock cycles
    end

    state :GREEN, value: 2 do
      output red: 0, yellow: 0, green: 1
      transition to: :YELLOW, when_cond: proc { in_val(:sensor) == 0 }
    end

    initial_state :RED
    output_state :state
  end
end
```

## Migrating Existing Components

To migrate a component with `propagate` to DSL:

1. **Identify if combinational or sequential**
   - Rising edge detection = sequential
   - No internal state = combinational

2. **Extract the core logic**
   - Remove boilerplate (`in_val`, `out_set` calls)
   - Identify case statements

3. **Choose the right DSL construct**
   - Simple assignments → `behavior`
   - Clock-edge updates → `sequential`
   - Multi-way selection → `case_of` inside `behavior`
   - Memory arrays → `memory` + `sync_write` + `async_read`
   - State machines → `state_machine`

### Before (Manual):
```ruby
def propagate
  a = in_val(:a) & 0xFF
  b = in_val(:b) & 0xFF
  op = in_val(:op) & 0x03

  result = case op
  when 0 then a + b
  when 1 then a - b
  when 2 then a & b
  when 3 then a | b
  else a
  end

  out_set(:result, result & 0xFF)
end
```

### After (DSL):
```ruby
behavior do
  result <= case_of(op,
    0 => a + b,
    1 => a - b,
    2 => a & b,
    3 => a | b,
    default: a
  )
end
```

## Synthesizable Operations

For complex operations, you can use `propagate` with synthesizable patterns.
Ruby operations map directly to Verilog:

| Ruby | Verilog | Description |
|------|---------|-------------|
| `&` | `&` | Bitwise AND |
| `\|` | `\|` | Bitwise OR |
| `^` | `^` | Bitwise XOR |
| `>>` | `>>` | Shift right |
| `<<` | `<<` | Shift left |
| `? :` | `? :` | Ternary/mux |

## Best Practices

1. **Keep it simple**: Use `behavior` for simple combinational logic
2. **Use DSL for clarity**: Extended behavior blocks make complex logic readable
3. **Prefer DSL over manual propagate**: DSL blocks can be automatically exported
4. **Test both ways**: Verify simulation matches synthesized behavior
5. **Document limitations**: Note any non-synthesizable features used
