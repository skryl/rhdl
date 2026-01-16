# HDL Components Reference

This document provides detailed documentation for all HDL components.

## Logic Gates

### NotGate

Single-input inverter.

```ruby
gate = RHDL::HDL::NotGate.new
gate.set_input(:a, 0)
gate.propagate
gate.get_output(:y)  # => 1
```

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| a | Input | 1 | Input signal |
| y | Output | 1 | Inverted output |

### Buffer

Non-inverting driver.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| a | Input | 1 | Input signal |
| y | Output | 1 | Buffered output |

### AndGate

Multi-input AND gate.

```ruby
gate = RHDL::HDL::AndGate.new(nil, inputs: 3)  # 3-input AND
gate.set_input(:a0, 1)
gate.set_input(:a1, 1)
gate.set_input(:a2, 1)
gate.propagate
gate.get_output(:y)  # => 1
```

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| a0..aN | Input | 1 | Input signals |
| y | Output | 1 | AND of all inputs |

### OrGate, NandGate, NorGate, XorGate, XnorGate

Similar interface to AndGate with respective logic functions.

### TristateBuffer

Buffer with enable control for tri-state output.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| a | Input | 1 | Input signal |
| en | Input | 1 | Enable (1=active, 0=high-Z) |
| y | Output | 1 | Output (high-Z when disabled) |

## Bitwise Operations

### BitwiseAnd, BitwiseOr, BitwiseXor

Multi-bit logic operations.

```ruby
and_op = RHDL::HDL::BitwiseAnd.new(nil, width: 8)
and_op.set_input(:a, 0b11110000)
and_op.set_input(:b, 0b10101010)
and_op.propagate
and_op.get_output(:y)  # => 0b10100000
```

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| a | Input | N | First operand |
| b | Input | N | Second operand |
| y | Output | N | Result |

### BitwiseNot

Multi-bit inversion.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| a | Input | N | Input |
| y | Output | N | Bitwise NOT of input |

## Sequential Components

### DFlipFlop

D flip-flop with synchronous reset and enable.

```ruby
dff = RHDL::HDL::DFlipFlop.new
dff.set_input(:d, 1)
dff.set_input(:en, 1)
dff.set_input(:rst, 0)
# Clock cycle
dff.set_input(:clk, 0); dff.propagate
dff.set_input(:clk, 1); dff.propagate
dff.get_output(:q)  # => 1
```

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| d | Input | 1 | Data input |
| clk | Input | 1 | Clock |
| rst | Input | 1 | Synchronous reset |
| en | Input | 1 | Enable |
| q | Output | 1 | Output |
| qn | Output | 1 | Inverted output |

### TFlipFlop

Toggle flip-flop.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| t | Input | 1 | Toggle input |
| clk | Input | 1 | Clock |
| rst | Input | 1 | Synchronous reset |
| en | Input | 1 | Enable |
| q | Output | 1 | Output |
| qn | Output | 1 | Inverted output |

### JKFlipFlop

JK flip-flop with all four states.

| J | K | Action |
|---|---|--------|
| 0 | 0 | Hold |
| 0 | 1 | Reset |
| 1 | 0 | Set |
| 1 | 1 | Toggle |

### SRFlipFlop

Set-Reset flip-flop.

### Register

Multi-bit register with enable and reset.

```ruby
reg = RHDL::HDL::Register.new(nil, width: 8)
reg.set_input(:d, 0x42)
reg.set_input(:en, 1)
reg.set_input(:rst, 0)
# Clock cycle
reg.set_input(:clk, 0); reg.propagate
reg.set_input(:clk, 1); reg.propagate
reg.get_output(:q)  # => 0x42
```

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| d | Input | N | Data input |
| clk | Input | 1 | Clock |
| rst | Input | 1 | Synchronous reset |
| en | Input | 1 | Enable |
| q | Output | N | Output |

### ShiftRegister

Configurable shift register with parallel load.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| d_in | Input | 1 | Serial input |
| clk | Input | 1 | Clock |
| rst | Input | 1 | Reset |
| en | Input | 1 | Shift enable |
| dir | Input | 1 | Direction (0=right, 1=left) |
| load | Input | 1 | Parallel load enable |
| d | Input | N | Parallel load data |
| q | Output | N | Parallel output |
| d_out | Output | 1 | Serial output |

### Counter

Up/down counter with load capability.

```ruby
counter = RHDL::HDL::Counter.new(nil, width: 4)
counter.set_input(:en, 1)
counter.set_input(:up, 1)
counter.set_input(:rst, 0)
counter.set_input(:load, 0)
# Count up
10.times do
  counter.set_input(:clk, 0); counter.propagate
  counter.set_input(:clk, 1); counter.propagate
end
counter.get_output(:q)  # => 10
```

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| clk | Input | 1 | Clock |
| rst | Input | 1 | Reset |
| en | Input | 1 | Count enable |
| up | Input | 1 | Direction (1=up, 0=down) |
| load | Input | 1 | Load enable |
| d | Input | N | Load value |
| q | Output | N | Count output |
| tc | Output | 1 | Terminal count |
| zero | Output | 1 | Zero flag |

### ProgramCounter

16-bit program counter for CPU use.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| clk | Input | 1 | Clock |
| rst | Input | 1 | Reset |
| en | Input | 1 | Increment enable |
| load | Input | 1 | Load enable |
| d | Input | 16 | Load value |
| inc | Input | 16 | Increment amount |
| q | Output | 16 | PC value |

### StackPointer

8-bit stack pointer with push/pop.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| clk | Input | 1 | Clock |
| rst | Input | 1 | Reset (to 0xFF) |
| push | Input | 1 | Decrement SP |
| pop | Input | 1 | Increment SP |
| q | Output | 8 | SP value |
| empty | Output | 1 | Stack empty (SP=0xFF) |
| full | Output | 1 | Stack full (SP=0) |

## Arithmetic Components

### HalfAdder

Adds two bits.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| a | Input | 1 | First bit |
| b | Input | 1 | Second bit |
| sum | Output | 1 | Sum |
| cout | Output | 1 | Carry out |

### FullAdder

Adds two bits with carry in.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| a | Input | 1 | First bit |
| b | Input | 1 | Second bit |
| cin | Input | 1 | Carry in |
| sum | Output | 1 | Sum |
| cout | Output | 1 | Carry out |

### RippleCarryAdder

Multi-bit adder.

```ruby
adder = RHDL::HDL::RippleCarryAdder.new(nil, width: 8)
adder.set_input(:a, 100)
adder.set_input(:b, 50)
adder.set_input(:cin, 0)
adder.propagate
adder.get_output(:sum)  # => 150
```

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| a | Input | N | First operand |
| b | Input | N | Second operand |
| cin | Input | 1 | Carry in |
| sum | Output | N | Sum |
| cout | Output | 1 | Carry out |
| overflow | Output | 1 | Signed overflow |

### Subtractor

Multi-bit subtractor using 2's complement.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| a | Input | N | Minuend |
| b | Input | N | Subtrahend |
| bin | Input | 1 | Borrow in |
| diff | Output | N | Difference |
| bout | Output | 1 | Borrow out |
| overflow | Output | 1 | Signed overflow |

### Comparator

Full comparison with signed/unsigned modes.

```ruby
cmp = RHDL::HDL::Comparator.new(nil, width: 8)
cmp.set_input(:a, 50)
cmp.set_input(:b, 30)
cmp.set_input(:signed, 0)
cmp.propagate
cmp.get_output(:gt)  # => 1
cmp.get_output(:eq)  # => 0
cmp.get_output(:lt)  # => 0
```

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| a | Input | N | First operand |
| b | Input | N | Second operand |
| signed | Input | 1 | Signed comparison |
| eq | Output | 1 | Equal |
| gt | Output | 1 | Greater than |
| lt | Output | 1 | Less than |
| gte | Output | 1 | Greater or equal |
| lte | Output | 1 | Less or equal |

### Multiplier

Combinational multiplier.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| a | Input | N | First operand |
| b | Input | N | Second operand |
| product | Output | 2N | Product |

### Divider

Combinational divider.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| dividend | Input | N | Dividend |
| divisor | Input | N | Divisor |
| quotient | Output | N | Quotient |
| remainder | Output | N | Remainder |
| div_by_zero | Output | 1 | Division by zero flag |

### ALU

Full arithmetic logic unit.

```ruby
alu = RHDL::HDL::ALU.new(nil, width: 8)
alu.set_input(:a, 10)
alu.set_input(:b, 5)
alu.set_input(:op, RHDL::HDL::ALU::OP_ADD)
alu.set_input(:cin, 0)
alu.propagate
alu.get_output(:result)  # => 15
```

| Op Code | Operation |
|---------|-----------|
| 0 (OP_ADD) | Add |
| 1 (OP_SUB) | Subtract |
| 2 (OP_AND) | Bitwise AND |
| 3 (OP_OR) | Bitwise OR |
| 4 (OP_XOR) | Bitwise XOR |
| 5 (OP_NOT) | Bitwise NOT (of A) |
| 6 (OP_SHL) | Shift left |
| 7 (OP_SHR) | Shift right logical |
| 8 (OP_SAR) | Shift right arithmetic |
| 9 (OP_ROL) | Rotate left |
| 10 (OP_ROR) | Rotate right |
| 11 (OP_MUL) | Multiply (low byte) |
| 12 (OP_DIV) | Divide |
| 13 (OP_MOD) | Modulo |
| 14 (OP_INC) | Increment A |
| 15 (OP_DEC) | Decrement A |

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| a | Input | N | First operand |
| b | Input | N | Second operand |
| op | Input | 4 | Operation code |
| cin | Input | 1 | Carry in |
| result | Output | N | Result |
| cout | Output | 1 | Carry/borrow out |
| zero | Output | 1 | Zero flag |
| negative | Output | 1 | Negative flag |
| overflow | Output | 1 | Overflow flag |

## Combinational Components

### Mux2, Mux4, Mux8, MuxN

Multiplexers with various input counts.

```ruby
mux = RHDL::HDL::Mux4.new(nil, width: 8)
mux.set_input(:a, 10)
mux.set_input(:b, 20)
mux.set_input(:c, 30)
mux.set_input(:d, 40)
mux.set_input(:sel, 2)  # Select input c
mux.propagate
mux.get_output(:y)  # => 30
```

### Demux2, Demux4

Demultiplexers.

### Decoder2to4, Decoder3to8, DecoderN

Binary to one-hot decoders.

```ruby
dec = RHDL::HDL::Decoder3to8.new
dec.set_input(:a, 5)
dec.set_input(:en, 1)
dec.propagate
dec.get_output(:y5)  # => 1
dec.get_output(:y0)  # => 0
```

### Encoder4to2, Encoder8to3

Priority encoders.

### BarrelShifter

Fast multi-bit shifter.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| a | Input | N | Input value |
| shift | Input | log2(N) | Shift amount |
| dir | Input | 1 | Direction (0=left, 1=right) |
| arith | Input | 1 | Arithmetic shift |
| rotate | Input | 1 | Rotate instead of shift |
| y | Output | N | Result |

### SignExtend, ZeroExtend

Width extension operations.

### PopCount, LZCount

Bit counting operations.

## Memory Components

### RAM

Synchronous RAM with single port.

```ruby
ram = RHDL::HDL::RAM.new(nil, data_width: 8, addr_width: 8)
# Write
ram.set_input(:addr, 0x42)
ram.set_input(:din, 0xAB)
ram.set_input(:we, 1)
ram.set_input(:clk, 0); ram.propagate
ram.set_input(:clk, 1); ram.propagate
# Read
ram.set_input(:we, 0)
ram.propagate
ram.get_output(:dout)  # => 0xAB
```

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| clk | Input | 1 | Clock |
| we | Input | 1 | Write enable |
| addr | Input | addr_width | Address |
| din | Input | data_width | Data in |
| dout | Output | data_width | Data out (async read) |

Direct access methods:
- `read_mem(addr)` - Read memory directly
- `write_mem(addr, data)` - Write memory directly
- `load_program(program, start_addr)` - Load byte array

### DualPortRAM

RAM with separate read and write ports.

### ROM

Read-only memory.

```ruby
contents = [0x00, 0x11, 0x22, 0x33]
rom = RHDL::HDL::ROM.new(nil, data_width: 8, addr_width: 8, contents: contents)
rom.set_input(:addr, 2)
rom.set_input(:en, 1)
rom.propagate
rom.get_output(:dout)  # => 0x22
```

### RegisterFile

Multi-register file with 2 read ports and 1 write port.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| clk | Input | 1 | Clock |
| we | Input | 1 | Write enable |
| waddr | Input | log2(N) | Write address |
| raddr1 | Input | log2(N) | Read address 1 |
| raddr2 | Input | log2(N) | Read address 2 |
| wdata | Input | data_width | Write data |
| rdata1 | Output | data_width | Read data 1 |
| rdata2 | Output | data_width | Read data 2 |

### Stack

LIFO stack with push/pop.

### FIFO

First-in-first-out queue.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| clk | Input | 1 | Clock |
| rst | Input | 1 | Reset |
| wr_en | Input | 1 | Write enable |
| rd_en | Input | 1 | Read enable |
| din | Input | data_width | Data in |
| dout | Output | data_width | Data out |
| empty | Output | 1 | FIFO empty |
| full | Output | 1 | FIFO full |
| count | Output | addr_width+1 | Element count |
