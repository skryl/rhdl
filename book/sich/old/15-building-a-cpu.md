# Chapter 8: Building a CPU

## Overview

Hands-on construction of a complete 8-bit CPU from components we've built.

## Key Concepts

### Our CPU Architecture

**Specifications:**
- 8-bit data bus
- 16-bit address bus (64KB addressable)
- 3 general-purpose registers: A, X, Y
- Status register: N, Z, C, V flags
- Stack pointer
- Program counter

**Instruction Set:**
| Opcode | Mnemonic | Description |
|--------|----------|-------------|
| 0x00 | NOP | No operation |
| 0x10 | LDA # | Load A immediate |
| 0x11 | LDA a | Load A absolute |
| 0x20 | STA a | Store A absolute |
| 0x30 | ADD # | Add immediate to A |
| 0x31 | ADD a | Add memory to A |
| 0x40 | SUB # | Subtract immediate |
| 0x50 | AND # | AND immediate |
| 0x60 | JMP | Jump absolute |
| 0x70 | BEQ | Branch if zero |
| 0x71 | BNE | Branch if not zero |
| 0xFF | HLT | Halt |

### Building the Datapath

```ruby
class CPU8Datapath < SimComponent
  # Clock and reset
  input :clk
  input :reset

  # Memory interface
  output :mem_addr, width: 16
  output :mem_data_out, width: 8
  input :mem_data_in, width: 8
  output :mem_write

  # Internal signals
  wire :pc, width: 16
  wire :ir, width: 8
  wire :a_reg, width: 8
  wire :x_reg, width: 8
  wire :y_reg, width: 8
  wire :flags, width: 4  # N, Z, C, V

  # Sub-components
  instance :alu, ALU, width: 8
  instance :pc_reg, Register, width: 16
  instance :a_register, Register, width: 8
  # ... more components
end
```

### The Control Unit

State machine that orchestrates execution:

```ruby
class ControlUnit < SimComponent
  input :clk
  input :reset
  input :opcode, width: 8
  input :flags, width: 4

  output :state, width: 4
  output :pc_inc
  output :pc_load
  output :ir_load
  output :reg_write
  output :alu_op, width: 3
  output :mem_read
  output :mem_write

  # States
  FETCH1 = 0  # PC -> Address bus
  FETCH2 = 1  # Memory -> IR
  DECODE = 2
  EXECUTE = 3
  # More states for multi-byte instructions
end
```

### Multi-Cycle Execution

Each instruction takes multiple clock cycles:

**LDA #immediate (2 bytes, 4 cycles):**
1. FETCH1: Put PC on address bus
2. FETCH2: Read opcode into IR, increment PC
3. FETCH3: Put PC on address bus
4. EXECUTE: Read operand, load into A, increment PC

**ADD absolute (3 bytes, 6 cycles):**
1. FETCH opcode
2. FETCH low byte of address
3. FETCH high byte of address
4. Read from computed address
5. Add to A
6. Store result, update flags

### Connecting It All

```ruby
class CPU8 < SimComponent
  input :clk
  input :reset
  output :mem_addr, width: 16
  output :mem_data_out, width: 8
  input :mem_data_in, width: 8
  output :mem_write
  output :halted

  instance :datapath, CPU8Datapath
  instance :control, ControlUnit

  # Wire control signals to datapath
  port :clk => [[:datapath, :clk], [:control, :clk]]
  port :reset => [[:datapath, :reset], [:control, :reset]]
  port [:datapath, :opcode] => [:control, :opcode]
  port [:control, :alu_op] => [:datapath, :alu_op]
  # ... more connections
end
```

### Testing the CPU

Write test programs:

```ruby
# Simple addition test
program = [
  0x10, 0x05,       # LDA #5
  0x30, 0x03,       # ADD #3
  0x20, 0x80, 0x00, # STA $0080
  0xFF              # HLT
]

# Verify A = 8, memory[0x80] = 8
```

## Hands-On Project: Complete CPU

Build and test the full CPU with:
1. All specified instructions
2. Memory interface
3. Test programs that verify each instruction

## Exercises

1. Add a stack and implement CALL/RET
2. Implement indirect addressing
3. Add an interrupt input

---

## Notes and Ideas

- Step-by-step assembly of components
- Waveform traces showing each instruction
- Common bugs and how to debug them
- Diagram: complete CPU block diagram with signal flow
- Comparison: how our CPU differs from real 8-bit CPUs
