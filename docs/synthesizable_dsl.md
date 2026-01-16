# Synthesizable DSL Guide

This document explains how to convert manual `propagate` methods to synthesizable DSL blocks.

## Overview

RHDL provides three types of behavior blocks:

1. **`behavior do ... end`** - Combinational logic (purely input-to-output)
2. **`sequential clock: :clk do ... end`** - Sequential logic (registers, state machines)
3. **`case_of(selector, { ... })`** - Multi-way selection

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

## Complex Case Statements

For components with many cases (like a full ALU), use `case_of`:

```ruby
class ALU8 < RHDL::HDL::SimComponent
  OP_ADD = 0x00
  OP_SUB = 0x01
  OP_AND = 0x02
  OP_OR  = 0x03
  OP_XOR = 0x04
  OP_SHL = 0x05
  OP_SHR = 0x06
  OP_INC = 0x07
  OP_DEC = 0x08

  port_input :a, width: 8
  port_input :b, width: 8
  port_input :op, width: 4
  port_output :result, width: 8
  port_output :zero

  behavior do
    result <= case_of(op,
      OP_ADD => a + b,
      OP_SUB => a - b,
      OP_AND => a & b,
      OP_OR  => a | b,
      OP_XOR => a ^ b,
      OP_SHL => a << 1,
      OP_SHR => a >> 1,
      OP_INC => a + 1,
      OP_DEC => a - 1,
      default: a
    )

    zero <= (result == 0)
  end
end
```

## Limitations

Not all propagate logic can be converted to the DSL:

### Cannot Use DSL For:
1. **Internal state arrays** (like Memory components) - require memory inference
2. **Complex BCD arithmetic** - needs helper functions
3. **Multi-cycle state machines** - need explicit state register modeling
4. **Large lookup tables** - better as ROM inference

### These Require Manual `propagate`:
- MOS 6502 ControlUnit (complex state machine with ~30 states)
- Memory components (internal array state)
- Instruction decoders with 256+ opcodes

## Memory Components

Memory requires special handling for synthesis (BRAM inference):

```ruby
class SyncRAM < RHDL::HDL::SimComponent
  port_input :clk
  port_input :we
  port_input :addr, width: 8
  port_input :din, width: 8
  port_output :dout, width: 8

  # Memory declaration - maps to reg array in Verilog
  memory :mem, depth: 256, width: 8

  # Synchronous write
  sequential clock: :clk do
    when_set(:we) do
      mem[addr] <= din
    end
  end

  # Async read
  behavior do
    dout <= mem[addr]
  end
end
```

Note: Memory DSL support is planned but not yet implemented.

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
   - Multi-way selection → `case_of`

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
