# Synthesizable DSL Guide

This document provides comprehensive documentation of all RHDL DSL features for synthesizable hardware description.

## Table of Contents

1. [Overview](#overview)
2. [Port and Signal DSL](#port-and-signal-dsl)
3. [Parameter DSL](#parameter-dsl)
4. [Behavior DSL](#behavior-dsl)
5. [Sequential DSL](#sequential-dsl)
6. [Structure DSL](#structure-dsl)
7. [Memory DSL](#memory-dsl)
8. [State Machine DSL](#state-machine-dsl)
9. [Vec DSL (Hardware Arrays)](#vec-dsl-hardware-arrays)
10. [Bundle DSL (Aggregate Interfaces)](#bundle-dsl-aggregate-interfaces)
11. [Code Generation](#code-generation)

---

## Overview

RHDL provides several DSL modules for synthesizable hardware:

| DSL | Purpose | Include |
|-----|---------|---------|
| Ports | Input/output port definitions | Included by default |
| Parameter | Configurable component parameters | Included by default |
| Behavior | Combinational logic | `RHDL::DSL::Behavior` |
| Sequential | Clocked registers and state | `RHDL::DSL::Sequential` |
| Structure | Hierarchical component composition | `RHDL::DSL::Structure` |
| Memory | RAM/ROM arrays | `RHDL::DSL::Memory` |
| StateMachine | Finite state machines | `RHDL::DSL::StateMachine` |
| Vec | Hardware signal arrays | `RHDL::DSL::Vec` |
| Bundle | Grouped signal interfaces | `RHDL::DSL::Bundle` |

---

## Port and Signal DSL

### Input Ports

```ruby
input :name                      # 1-bit input
input :data, width: 8            # 8-bit input
input :addr, width: :addr_width  # Parameterized width
input :rst, default: 0           # Default value for unconnected port
```

**Parameters:**
- `name` (Symbol): Port name
- `width` (Integer or Symbol): Bit width (default: 1)
- `default` (Integer): Default value for Verilog (optional)

### Output Ports

```ruby
output :result                   # 1-bit output
output :data_out, width: 8       # 8-bit output
output :product, width: :width   # Parameterized width
```

**Parameters:**
- `name` (Symbol): Port name
- `width` (Integer or Symbol): Bit width (default: 1)

### Internal Wires

```ruby
wire :intermediate, width: 8     # 8-bit internal signal
wire :carry                      # 1-bit internal signal
wire :alu_out, width: :width     # Parameterized width
```

**Use Cases:**
- Intermediate computation results
- Inter-component connections in hierarchical designs
- Signals not exposed on external interface

### Complete Port Example

```ruby
class ALU < RHDL::Sim::Component
  input :a, width: 8
  input :b, width: 8
  input :op, width: 4
  input :cin, default: 0         # Carry-in defaults to 0

  output :result, width: 8
  output :cout                   # Carry-out
  output :zero                   # Zero flag
  output :negative               # Negative flag
  output :overflow               # Overflow flag

  wire :add_result, width: 9     # Extra bit for carry
  wire :sub_result, width: 9

  # ... behavior block
end
```

---

## Parameter DSL

### Simple Parameters

```ruby
parameter :width, default: 8
parameter :depth, default: 256
parameter :initial_value, default: 0
```

### Computed Parameters

Computed parameters use a Proc/lambda and can reference other parameters:

```ruby
parameter :width, default: 8
parameter :product_width, default: -> { @width * 2 }
parameter :addr_width, default: -> { Math.log2(@depth).ceil }
```

**Evaluation Order:**
1. Simple parameters (direct values) evaluated first
2. Computed parameters (Procs) evaluated second, with access to `@param_name`

### Using Parameters in Ports

```ruby
class Multiplier < RHDL::Sim::Component
  parameter :width, default: 8
  parameter :product_width, default: -> { @width * 2 }

  input :a, width: :width           # References :width parameter
  input :b, width: :width
  output :product, width: :product_width

  behavior do
    product <= a * b
  end
end

# Instantiation with custom parameters
mult = Multiplier.new('mult', width: 16)
# @width = 16, @product_width = 32
```

### Accessing Parameters

```ruby
behavior do
  # Access as instance variable
  mask = lit((1 << @width) - 1, width: @width)

  # Or use param() helper
  w = param(:width)
end
```

---

## Behavior DSL

The `behavior` block defines combinational logic that works for both simulation and synthesis.

### Basic Syntax

```ruby
behavior do
  output_signal <= expression
end
```

### Operators

#### Bitwise Operators

```ruby
behavior do
  and_result <= a & b      # Bitwise AND
  or_result <= a | b       # Bitwise OR
  xor_result <= a ^ b      # Bitwise XOR
  not_result <= ~a         # Bitwise NOT (inversion)
end
```

#### Arithmetic Operators

```ruby
behavior do
  sum <= a + b             # Addition (result width = max + 1)
  diff <= a - b            # Subtraction
  product <= a * b         # Multiplication (result width = a.width + b.width)
  quotient <= a / b        # Division (integer)
  remainder <= a % b       # Modulo
end
```

#### Shift Operators

```ruby
behavior do
  left <= a << 2           # Shift left by constant
  right <= a >> 3          # Shift right by constant
  dyn_shift <= a << amt    # Dynamic shift (barrel shifter)
end
```

#### Comparison Operators (return 1-bit)

```ruby
behavior do
  eq <= a == b             # Equal
  ne <= a != b             # Not equal
  lt <= a < b              # Less than
  gt <= a > b              # Greater than
  le <= a <= b             # Less or equal
  ge <= a >= b             # Greater or equal

  # Compound conditions
  in_range <= (a >= 10) & (a <= 20)
end
```

### Conditional Selection (mux)

```ruby
behavior do
  # mux(condition, when_true, when_false)
  result <= mux(sel, a, b)           # sel ? a : b

  # Nested mux for 4-to-1
  low <= mux(sel[0], b, a)
  high <= mux(sel[0], d, c)
  result <= mux(sel[1], high, low)

  # Enable pattern
  output <= mux(en, new_value, old_value)
end
```

### Case Selection (case_select)

```ruby
behavior do
  # case_select(selector, cases_hash, default: value)
  result <= case_select(op, {
    0 => a + b,              # ADD
    1 => a - b,              # SUB
    2 => a & b,              # AND
    3 => a | b,              # OR
    4 => a ^ b               # XOR
  }, default: 0)
end
```

### Literals with Explicit Width

```ruby
behavior do
  # lit(value, width: N)
  zero <= lit(0, width: 8)
  max <= lit(0xFF, width: 8)
  one_bit <= lit(1, width: 1)

  # Required for synthesis width correctness
  masked <= a & lit(0x0F, width: 8)
end
```

### Local Variables (Intermediate Wires)

```ruby
behavior do
  # local(name, expression, width: N)
  sum_full = local(:sum_full, a + b + cin, width: 9)

  # Use in subsequent expressions
  result <= sum_full[7..0]
  cout <= sum_full[8]

  # Auto-width detection
  eq = local(:eq, a == b)  # width: 1
end
```

### Bit Selection and Slicing

```ruby
behavior do
  # Single bit selection
  lsb <= a[0]              # Least significant bit
  msb <= a[7]              # Most significant bit (8-bit signal)

  # Range slicing (both directions work)
  low_nibble <= a[3..0]    # Bits 0-3
  high_nibble <= a[7..4]   # Bits 4-7
  byte <= word[15..8]      # Upper byte of 16-bit

  # Sign bit extraction
  sign <= a[7]             # For 8-bit signed
end
```

### Concatenation

```ruby
behavior do
  # signal.concat(other) - first arg becomes high bits
  combined <= high_byte.concat(low_byte)  # 16-bit result

  # Multiple concatenation
  word <= a.concat(b).concat(c).concat(d)

  # Shift left by 1 (with zero fill)
  shifted <= a[6..0].concat(lit(0, width: 1))

  # Shift right by 1 (with zero fill)
  shifted <= lit(0, width: 1).concat(a[7..1])
end
```

### Replication

```ruby
behavior do
  # signal.replicate(n) - repeat signal n times
  sign_ext <= sign_bit.replicate(8)  # 8-bit sign extension

  # Arithmetic shift right (preserve sign)
  sign = a[7]
  asr1 <= sign.concat(a[7..1])
  asr2 <= sign.replicate(2).concat(a[7..2])
end
```

### Reduction Operators

```ruby
behavior do
  # reduce_or(signal) - any bit set?
  non_zero <= reduce_or(error_flags)

  # reduce_and(signal) - all bits set?
  all_ready <= reduce_and(ready_signals)

  # reduce_xor(signal) - parity
  parity <= reduce_xor(data)
end
```

### Port Width Query

```ruby
behavior do
  # port_width(name) - get width at runtime
  w = port_width(:result)
  default_val <= lit(0, width: w)
end
```

### Complete Behavior Example (ALU)

```ruby
class ALU < RHDL::Sim::Component
  parameter :width, default: 8

  input :a, width: :width
  input :b, width: :width
  input :op, width: 4
  input :cin, default: 0

  output :result, width: :width
  output :cout
  output :zero
  output :negative
  output :overflow

  OP_ADD = 0
  OP_SUB = 1
  OP_AND = 2
  OP_OR  = 3
  OP_XOR = 4
  OP_NOT = 5
  OP_SHL = 6
  OP_SHR = 7

  behavior do
    # Local variables for intermediate results
    add_full = local(:add_full, a + b + cin, width: 9)
    add_result = add_full[7..0]
    add_cout = add_full[8]

    sub_full = local(:sub_full, a - b, width: 9)
    sub_result = sub_full[7..0]

    and_result = local(:and_result, a & b, width: 8)
    or_result = local(:or_result, a | b, width: 8)
    xor_result = local(:xor_result, a ^ b, width: 8)
    not_result = local(:not_result, ~a, width: 8)

    shl_result = local(:shl_result, a << 1, width: 8)
    shr_result = local(:shr_result, a >> 1, width: 8)

    # Operation selection
    result <= case_select(op, {
      OP_ADD => add_result,
      OP_SUB => sub_result,
      OP_AND => and_result,
      OP_OR  => or_result,
      OP_XOR => xor_result,
      OP_NOT => not_result,
      OP_SHL => shl_result,
      OP_SHR => shr_result
    }, default: add_result)

    # Carry output
    cout <= case_select(op, {
      OP_ADD => add_cout,
      OP_SHL => a[7]
    }, default: lit(0, width: 1))

    # Flags
    zero <= mux(result == lit(0, width: 8), lit(1, width: 1), lit(0, width: 1))
    negative <= result[7]
    overflow <= mux(op == OP_ADD,
      (a[7] == b[7]) & (result[7] != a[7]),
      lit(0, width: 1))
  end
end
```

---

## Sequential DSL

The `sequential` block defines clocked logic with non-blocking assignment semantics.

### Basic Syntax

```ruby
sequential clock: :clk, reset: :rst, reset_values: { output: 0 } do
  output <= expression
end
```

**Parameters:**
- `clock:` (Symbol) - Clock signal name
- `reset:` (Symbol, optional) - Reset signal name
- `reset_values:` (Hash) - Values on reset `{ signal: value }`

### D Flip-Flop

```ruby
class DFlipFlop < RHDL::Sim::SequentialComponent
  input :d
  input :clk
  input :rst
  input :en
  output :q
  output :qn

  sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
    q <= mux(en, d, q)  # Load when enabled, hold otherwise
  end

  behavior do
    qn <= ~q  # Combinational complement
  end
end
```

### Register with Parameters

```ruby
class Register < RHDL::Sim::SequentialComponent
  parameter :width, default: 8

  input :d, width: :width
  input :clk
  input :rst, default: 0
  input :en, default: 0
  output :q, width: :width

  sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
    q <= mux(en, d, q)
  end
end
```

### Counter

```ruby
class Counter < RHDL::Sim::SequentialComponent
  parameter :width, default: 8

  input :clk
  input :rst
  input :en
  input :up             # 1 = count up, 0 = count down
  input :load
  input :d, width: :width
  output :q, width: :width
  output :tc            # Terminal count
  output :zero          # Zero flag

  sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
    count_up = q + lit(1, width: 8)
    count_down = q - lit(1, width: 8)
    count_result = mux(up, count_up, count_down)

    # Priority: load > count > hold
    q <= mux(load, d, mux(en, count_result, q))
  end

  behavior do
    is_max = (q == lit(0xFF, width: 8))
    is_zero = (q == lit(0, width: 8))
    tc <= mux(up, is_max, is_zero)
    zero <= is_zero
  end
end
```

### Program Counter

```ruby
class ProgramCounter < RHDL::Sim::SequentialComponent
  parameter :width, default: 16

  input :clk
  input :rst
  input :en, default: 0
  input :load, default: 0
  input :d, width: :width
  input :inc, width: :width, default: 1
  output :q, width: :width

  sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
    inc_val = mux(inc == lit(0, width: 16), lit(1, width: 16), inc)
    next_pc = (q + inc_val)[15..0]  # Wrap at 16 bits

    # Priority: load > increment
    q <= mux(load, d, mux(en, next_pc, q))
  end
end
```

### Shift Register

```ruby
class ShiftRegister < RHDL::Sim::SequentialComponent
  parameter :width, default: 8

  input :clk
  input :rst
  input :en
  input :load
  input :dir            # 0 = right, 1 = left
  input :d_in           # Serial input
  input :d, width: :width
  output :q, width: :width
  output :serial_out

  sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
    shift_right = d_in.concat(q[7..1])
    shift_left = q[6..0].concat(d_in)
    shift_result = mux(dir, shift_left, shift_right)

    q <= mux(load, d, mux(en, shift_result, q))
  end

  behavior do
    serial_out <= mux(dir, q[7], q[0])
  end
end
```

### JK Flip-Flop

```ruby
class JKFlipFlop < RHDL::Sim::SequentialComponent
  input :j
  input :k
  input :clk
  input :rst
  input :en
  output :q
  output :qn

  sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
    # JK truth table: 00->hold, 01->reset, 10->set, 11->toggle
    jk_result = mux(j,
      mux(k, ~q, lit(1, width: 1)),        # j=1: k ? toggle : set
      mux(k, lit(0, width: 1), q))         # j=0: k ? reset : hold
    q <= mux(en, jk_result, q)
  end

  behavior do
    qn <= ~q
  end
end
```

### Non-Blocking Assignment Semantics

Sequential components use Verilog-style non-blocking assignment:

1. **Sample Phase**: All sequential components sample their inputs simultaneously
2. **Update Phase**: All sequential components update their outputs simultaneously

This prevents race conditions in chains of registers.

---

## Structure DSL

The Structure DSL enables hierarchical component composition.

### Instance Declaration

```ruby
instance :name, ComponentClass, param1: value, param2: value
```

**Examples:**
```ruby
instance :alu, ALU, width: 8
instance :pc, ProgramCounter, width: 16
instance :reg, Register, width: 8
instance :sp, StackPointer, width: 8, initial: 0xFF
```

### Port Connections

```ruby
# Signal to instance input
port :signal => [:instance, :port]

# Instance output to signal
port [:instance, :port] => :signal

# Instance to instance
port [:source_instance, :port] => [:dest_instance, :port]

# Fan-out (one signal to multiple inputs)
port :clk => [[:pc, :clk], [:acc, :clk], [:sp, :clk]]
```

### Complete Hierarchical Example

```ruby
class CPU < RHDL::Sim::Component
  # External interface
  input :clk
  input :rst
  input :instruction, width: 8
  input :operand, width: 16
  input :mem_data_in, width: 8

  output :mem_addr, width: 16
  output :mem_data_out, width: 8
  output :mem_write_en
  output :pc_out, width: 16
  output :acc_out, width: 8

  # Internal wires
  wire :alu_a, width: 8
  wire :alu_b, width: 8
  wire :alu_result, width: 8
  wire :alu_zero
  wire :dec_alu_op, width: 4

  # Sub-components
  instance :decoder, InstructionDecoder
  instance :alu, ALU, width: 8
  instance :pc, ProgramCounter, width: 16
  instance :acc, Register, width: 8

  # Decoder connections
  port :instruction => [:decoder, :instruction]
  port [:decoder, :alu_op] => :dec_alu_op

  # ALU connections
  port :alu_a => [:alu, :a]
  port :alu_b => [:alu, :b]
  port :dec_alu_op => [:alu, :op]
  port [:alu, :result] => :alu_result
  port [:alu, :zero] => :alu_zero

  # Clock and reset distribution (fan-out)
  port :clk => [[:pc, :clk], [:acc, :clk]]
  port :rst => [[:pc, :rst], [:acc, :rst]]

  # Program counter
  port [:pc, :q] => :pc_out

  # Accumulator
  port [:acc, :q] => :acc_out
  port :alu_result => [:acc, :d]

  # Combinational control logic
  behavior do
    alu_a <= acc_out
    alu_b <= mem_data_in
    mem_addr <= pc_out
    mem_data_out <= acc_out
  end
end
```

### Generated Verilog

```verilog
module cpu(
  input        clk,
  input        rst,
  input  [7:0] instruction,
  input [15:0] operand,
  input  [7:0] mem_data_in,
  output [15:0] mem_addr,
  output [7:0] mem_data_out,
  output       mem_write_en,
  output [15:0] pc_out,
  output [7:0] acc_out
);
  wire [7:0] alu_a;
  wire [7:0] alu_b;
  wire [7:0] alu_result;
  wire       alu_zero;
  wire [3:0] dec_alu_op;

  instruction_decoder decoder_inst (
    .instruction(instruction),
    .alu_op(dec_alu_op)
  );

  alu #(.WIDTH(8)) alu_inst (
    .a(alu_a),
    .b(alu_b),
    .op(dec_alu_op),
    .result(alu_result),
    .zero(alu_zero)
  );

  program_counter #(.WIDTH(16)) pc_inst (
    .clk(clk),
    .rst(rst),
    .q(pc_out)
  );

  register #(.WIDTH(8)) acc_inst (
    .clk(clk),
    .rst(rst),
    .d(alu_result),
    .q(acc_out)
  );

  assign alu_a = acc_out;
  assign alu_b = mem_data_in;
  assign mem_addr = pc_out;
  assign mem_data_out = acc_out;
endmodule
```

---

## Memory DSL

The Memory DSL provides synthesizable RAM/ROM components.

### Memory Declaration

```ruby
memory :name, depth: 256, width: 8
memory :rom, depth: 512, width: 8, initial: DATA_ARRAY
memory :readonly_mem, depth: 1024, width: 8, readonly: true
```

**Parameters:**
- `name` (Symbol): Memory array name
- `depth` (Integer): Number of entries
- `width` (Integer): Bits per entry
- `initial` (Array, optional): Initial values
- `readonly` (Boolean, optional): Mark as ROM

### Synchronous Write

```ruby
sync_write :memory, clock: :clk, enable: :we, addr: :addr, data: :din
```

**Expression-Based Enable:**
```ruby
# AND condition without intermediate wire
sync_write :mem, clock: :clk, enable: [:cs, :&, :we], addr: :addr, data: :din
```

### Asynchronous Read

```ruby
async_read :output, from: :memory, addr: :addr
async_read :output, from: :memory, addr: :addr, enable: :en
```

### Synchronous Read

```ruby
sync_read :output, from: :memory, clock: :clk, addr: :addr
sync_read :output, from: :memory, clock: :clk, addr: :addr, enable: :en
```

### Complete RAM Example

```ruby
class RAM256x8 < RHDL::Sim::Component
  include RHDL::DSL::Memory

  input :clk
  input :we
  input :addr, width: 8
  input :din, width: 8
  output :dout, width: 8

  memory :mem, depth: 256, width: 8

  sync_write :mem, clock: :clk, enable: :we, addr: :addr, data: :din
  async_read :dout, from: :mem, addr: :addr

  # Direct access methods for simulation
  def read_mem(addr)
    mem_read(:mem, addr & 0xFF)
  end

  def write_mem(addr, data)
    mem_write(:mem, addr & 0xFF, data, 8)
  end

  def load_program(program, start_addr = 0)
    program.each_with_index do |byte, i|
      write_mem(start_addr + i, byte)
    end
  end
end
```

### ROM with Initial Data

```ruby
class CharacterROM < RHDL::Sim::Component
  include RHDL::DSL::Memory

  CHARACTER_DATA = [
    0b01110, 0b10001, 0b10001, 0b11111,  # 'A' pattern
    # ... more data
  ].freeze

  input :addr, width: 9
  output :dout, width: 5

  memory :rom, depth: 512, width: 5, initial: CHARACTER_DATA

  async_read :dout, from: :rom, addr: :addr
end
```

### Dual-Port RAM

```ruby
class DualPortRAM < RHDL::Sim::Component
  include RHDL::DSL::Memory

  input :clk
  input :we_a, :we_b
  input :addr_a, :addr_b, width: 8
  input :din_a, :din_b, width: 8
  output :dout_a, :dout_b, width: 8

  memory :mem, depth: 256, width: 8

  sync_write :mem, clock: :clk, enable: :we_a, addr: :addr_a, data: :din_a
  sync_write :mem, clock: :clk, enable: :we_b, addr: :addr_b, data: :din_b
  async_read :dout_a, from: :mem, addr: :addr_a
  async_read :dout_b, from: :mem, addr: :addr_b
end
```

### Memory Read Expression in Behavior

```ruby
behavior do
  # mem_read_expr for computed addresses
  dout <= mem_read_expr(:data, sp - lit(1, width: 5), width: 8)
end
```

### Lookup Table

```ruby
lookup_table :decode do |t|
  t.input :opcode, width: 8
  t.output :addr_mode, width: 4
  t.output :alu_op, width: 4
  t.output :cycles, width: 3

  t.entry 0x00, addr_mode: 0, alu_op: 0, cycles: 7   # BRK
  t.entry 0x69, addr_mode: 1, alu_op: 0, cycles: 2   # ADC imm

  t.add_entries({
    0xA9 => { addr_mode: 1, alu_op: 13, cycles: 2 },  # LDA imm
    0xA5 => { addr_mode: 2, alu_op: 13, cycles: 3 },  # LDA zp
  })

  t.default addr_mode: 0xF, alu_op: 0xF, cycles: 0
end
```

---

## State Machine DSL

The State Machine DSL provides declarative finite state machines.

### Basic Syntax

```ruby
state_machine clock: :clk, reset: :rst do
  state :STATE_NAME, value: 0 do
    output signal: value
    transition to: :NEXT_STATE, when_cond: condition
  end

  initial_state :START_STATE
  output_state :state_output
end
```

### Transition Types

```ruby
# Unconditional
transition to: :NEXT_STATE

# Signal-based (transitions when signal == 1)
transition to: :NEXT_STATE, when_cond: :input_signal

# Proc-based (arbitrary condition)
transition to: :NEXT_STATE, when_cond: proc { in_val(:counter) > 5 }

# Delayed (after N clock cycles)
transition to: :NEXT_STATE, after: 3
```

### Complete Traffic Light Example

```ruby
class TrafficLight < RHDL::Sim::SequentialComponent
  include RHDL::DSL::StateMachine

  input :clk
  input :rst
  input :sensor
  output :red
  output :yellow
  output :green
  output :state, width: 2

  state_machine clock: :clk, reset: :rst do
    state :RED, value: 0 do
      output red: 1, yellow: 0, green: 0
      transition to: :GREEN, when_cond: :sensor
    end

    state :YELLOW, value: 1 do
      output red: 0, yellow: 1, green: 0
      transition to: :RED, after: 3
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

---

## Vec DSL (Hardware Arrays)

Vec provides hardware arrays of signals for register files and similar structures.

### Declaration

```ruby
# Internal vec
vec :registers, count: 32, width: 64

# Input vec (creates data_in_0, data_in_1, etc.)
input_vec :data_in, count: 4, width: 8

# Output vec
output_vec :data_out, count: 4, width: 8

# Parameterized
parameter :depth, default: 32
vec :memory, count: :depth, width: :width
```

### Accessing Elements

```ruby
behavior do
  # Hardware-indexed read (creates mux tree)
  result <= data_inputs[sel]

  # Constant index (elaboration time)
  first <= data_in_0
end
```

### Register File Example

```ruby
class RegisterFile < RHDL::Sim::Component
  parameter :depth, default: 32
  parameter :width, default: 32

  input :read_addr, width: 5
  input :write_addr, width: 5
  input :write_data, width: :width
  input :write_enable
  input :clk
  output :read_data, width: :width

  vec :regs, count: :depth, width: :width

  behavior do
    read_data <= regs[read_addr]  # Hardware-indexed mux
  end
end
```

### Vec Properties

```ruby
vec = component.instance_variable_get(:@regs)

vec.name          # => :regs
vec.count         # => 32
vec.element_width # => 64
vec.total_width   # => 2048 (count * element_width)
vec.index_width   # => 5 (bits needed to index)

# Iteration
vec.each { |element| puts element.get }
vec.each_with_index { |element, i| ... }

# Bulk operations
values = vec.values                    # Get all as array
vec.set_values([0x11, 0x22, 0x33])     # Set from array
```

---

## Bundle DSL (Aggregate Interfaces)

Bundle groups related signals into reusable interface types.

### Defining a Bundle

```ruby
class ValidBundle < RHDL::Sim::Bundle
  field :data, width: 8, direction: :output
  field :valid, width: 1, direction: :output
  field :ready, width: 1, direction: :input
end
```

### Using Bundles

```ruby
class Producer < RHDL::Sim::Component
  input :clk
  input :data_in, width: 8
  input :enable
  output_bundle :out_port, ValidBundle  # Flipped by default

  behavior do
    out_port_data <= data_in
    out_port_valid <= enable
  end
end

class Consumer < RHDL::Sim::Component
  input :clk
  input_bundle :in_port, ValidBundle
  output :data_out, width: 8

  behavior do
    data_out <= in_port_data
    in_port_ready <= lit(1, width: 1)  # Always ready
  end
end
```

### Direction Flipping

- `input_bundle` - Uses directions as defined (default: `flipped: false`)
- `output_bundle` - Flips directions (default: `flipped: true`)

```ruby
# Original bundle: data is :output, ready is :input
# After output_bundle flip: data becomes :input, ready becomes :output
```

### AXI-Lite Interface Example

```ruby
class AxiLiteWrite < RHDL::Sim::Bundle
  field :awaddr, width: 32, direction: :output
  field :awvalid, width: 1, direction: :output
  field :awready, width: 1, direction: :input
  field :wdata, width: 32, direction: :output
  field :wvalid, width: 1, direction: :output
  field :wready, width: 1, direction: :input
end

class AxiMaster < RHDL::Sim::Component
  output_bundle :axi, AxiLiteWrite, flipped: false  # Producer

  behavior do
    axi_awaddr <= lit(0x1000, width: 32)
    axi_awvalid <= lit(1, width: 1)
  end
end

class AxiSlave < RHDL::Sim::Component
  input_bundle :axi, AxiLiteWrite, flipped: true  # Consumer

  behavior do
    axi_awready <= lit(1, width: 1)
    axi_wready <= lit(1, width: 1)
  end
end
```

---

## Code Generation

### Verilog Export

```ruby
# Single module
verilog = MyComponent.to_verilog

# With custom module name
verilog = MyComponent.to_verilog(top_name: 'custom_name')

# Complete hierarchy (all sub-modules)
verilog = MyComponent.to_verilog_hierarchy
```

### Module Naming

Module names are automatically derived from Ruby class names:

```ruby
RHDL::HDL::ALU             # => "alu"
RHDL::HDL::DualPortRAM     # => "dual_port_ram"
MOS6502::InstructionDecoder # => "mos6502_instruction_decoder"
```

### Intermediate Representation

```ruby
# Generate IR for custom processing
ir = MyComponent.to_ir

ir.ports       # Port definitions
ir.nets        # Wire declarations
ir.regs        # Register declarations
ir.assigns     # Continuous assignments
ir.instances   # Sub-component instances
ir.processes   # Sequential processes
ir.memories    # Memory definitions
```

### FIRRTL Export

```ruby
# CIRCT FIRRTL format
firrtl = MyComponent.to_firrtl
firrtl = MyComponent.to_firrtl_hierarchy
```

---

## Best Practices

### Use Explicit Widths

```ruby
# Good - explicit width
result <= lit(0xFF, width: 8)

# Avoid - width ambiguity
result <= 0xFF
```

### Prefer DSL Over Manual Propagate

```ruby
# Good - synthesizable, exportable
behavior do
  result <= a + b
end

# Avoid - simulation only
def propagate
  out_set(:result, in_val(:a) + in_val(:b))
end
```

### Use Local Variables for Clarity

```ruby
behavior do
  # Good - named intermediates
  sum_full = local(:sum_full, a + b + cin, width: 9)
  result <= sum_full[7..0]
  cout <= sum_full[8]

  # Avoid - complex inline expressions
  result <= (a + b + cin)[7..0]
end
```

### Document Non-Synthesizable Features

```ruby
# For simulation/testing only
def read_mem(addr)
  mem_read(:mem, addr & 0xFF)
end
```

### Test Both Simulation and Synthesis

```ruby
RSpec.describe MyComponent do
  it "simulates correctly" do
    component = MyComponent.new('test')
    component.set_input(:a, 5)
    component.propagate
    expect(component.get_output(:result)).to eq(expected)
  end

  it "generates valid Verilog" do
    verilog = MyComponent.to_verilog
    expect(verilog).to include('module my_component')
  end
end
```
