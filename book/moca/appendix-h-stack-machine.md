# Appendix H: Stack Machine ISA

*Companion appendix to [Chapter 5: Stack Machines](05-stack-machines.md)*

## Overview

This appendix provides complete RHDL implementations of stack machine components and a full Forth-like CPU.

## Basic Stack

```ruby
class Stack < SimComponent
  input :clk
  input :push
  input :pop
  input :data_in, width: 8
  output :data_out, width: 8
  output :empty
  output :full

  DEPTH = 16

  # Stack memory and pointer
  register :memory, width: 8, count: DEPTH
  register :sp, width: 4  # Stack pointer

  behavior do
    on_rising_edge(clk) do
      if push && !full
        memory[sp] <= data_in
        sp <= sp + 1
      elsif pop && !empty
        sp <= sp - 1
      end
    end

    # Output top of stack (TOS)
    data_out <= (sp > 0) ? memory[sp - 1] : 0
    empty <= (sp == 0)
    full <= (sp == DEPTH)
  end
end
```

## Stack ALU

Full stack ALU with all standard operations:

```ruby
class StackALU < SimComponent
  input :clk
  input :op, width: 4      # Operation code
  input :push_val, width: 8
  output :tos, width: 8    # Top of stack
  output :nos, width: 8    # Next on stack

  # Operations
  OP_NOP  = 0
  OP_PUSH = 1
  OP_POP  = 2
  OP_DUP  = 3
  OP_SWAP = 4
  OP_OVER = 5
  OP_ROT  = 6
  OP_DROP = 7
  OP_ADD  = 8
  OP_SUB  = 9
  OP_MUL  = 10
  OP_AND  = 11
  OP_OR   = 12
  OP_XOR  = 13
  OP_NOT  = 14
  OP_NEG  = 15

  DEPTH = 16
  register :stack, width: 8, count: DEPTH
  register :sp, width: 4

  behavior do
    on_rising_edge(clk) do
      case op
      when OP_NOP
        # Do nothing

      when OP_PUSH
        stack[sp] <= push_val
        sp <= sp + 1

      when OP_POP, OP_DROP
        sp <= sp - 1

      when OP_DUP
        stack[sp] <= stack[sp - 1]
        sp <= sp + 1

      when OP_SWAP
        temp = stack[sp - 1]
        stack[sp - 1] <= stack[sp - 2]
        stack[sp - 2] <= temp

      when OP_OVER
        stack[sp] <= stack[sp - 2]
        sp <= sp + 1

      when OP_ROT
        # ( a b c -- b c a )
        a = stack[sp - 3]
        b = stack[sp - 2]
        c = stack[sp - 1]
        stack[sp - 3] <= b
        stack[sp - 2] <= c
        stack[sp - 1] <= a

      when OP_ADD
        stack[sp - 2] <= stack[sp - 2] + stack[sp - 1]
        sp <= sp - 1

      when OP_SUB
        stack[sp - 2] <= stack[sp - 2] - stack[sp - 1]
        sp <= sp - 1

      when OP_MUL
        stack[sp - 2] <= stack[sp - 2] * stack[sp - 1]
        sp <= sp - 1

      when OP_AND
        stack[sp - 2] <= stack[sp - 2] & stack[sp - 1]
        sp <= sp - 1

      when OP_OR
        stack[sp - 2] <= stack[sp - 2] | stack[sp - 1]
        sp <= sp - 1

      when OP_XOR
        stack[sp - 2] <= stack[sp - 2] ^ stack[sp - 1]
        sp <= sp - 1

      when OP_NOT
        stack[sp - 1] <= ~stack[sp - 1]

      when OP_NEG
        stack[sp - 1] <= -stack[sp - 1]
      end
    end

    tos <= (sp > 0) ? stack[sp - 1] : 0
    nos <= (sp > 1) ? stack[sp - 2] : 0
  end
end
```

## Complete Stack CPU

Two-stack architecture with full instruction set:

```ruby
class StackCPU < SimComponent
  input :clk
  input :reset
  input :mem_data_in, width: 8
  output :mem_addr, width: 16
  output :mem_data_out, width: 8
  output :mem_write
  output :halted

  # Registers
  register :pc, width: 16        # Program counter
  register :data_sp, width: 4    # Data stack pointer
  register :ret_sp, width: 4     # Return stack pointer
  register :state, width: 2      # FSM state

  # Stack memories
  register :data_stack, width: 8, count: 16
  register :ret_stack, width: 16, count: 16

  # Instruction set
  PUSH_LIT = 0x00   # Push literal (next byte)
  DUP      = 0x01
  DROP     = 0x02
  SWAP     = 0x03
  OVER     = 0x04
  ROT      = 0x05
  ADD      = 0x10
  SUB      = 0x11
  MUL      = 0x12
  DIV      = 0x13
  AND      = 0x14
  OR       = 0x15
  XOR      = 0x16
  NOT      = 0x17
  FETCH    = 0x20   # Memory fetch @
  STORE    = 0x21   # Memory store !
  CALL     = 0x30
  RET      = 0x31
  JMP      = 0x32
  JZ       = 0x33   # Jump if zero
  HALT     = 0xFF

  # States
  FETCH_OP = 0
  FETCH_ARG = 1
  EXECUTE = 2
  STOPPED = 3

  behavior do
    on_rising_edge(clk) do
      if reset
        pc <= 0
        data_sp <= 0
        ret_sp <= 0
        state <= FETCH_OP
      else
        case state
        when FETCH_OP
          ir <= mem_data_in
          pc <= pc + 1
          if needs_argument(mem_data_in)
            state <= FETCH_ARG
          else
            state <= EXECUTE
          end

        when FETCH_ARG
          arg <= mem_data_in
          pc <= pc + 1
          state <= EXECUTE

        when EXECUTE
          execute_instruction
          state <= (ir == HALT) ? STOPPED : FETCH_OP

        when STOPPED
          # Stay stopped
        end
      end
    end

    mem_addr <= pc
    mem_write <= 0
    halted <= (state == STOPPED)
  end

  def needs_argument(opcode)
    [PUSH_LIT, JMP, JZ, CALL].include?(opcode)
  end

  def execute_instruction
    case ir
    when PUSH_LIT
      data_stack[data_sp] <= arg
      data_sp <= data_sp + 1

    when DUP
      data_stack[data_sp] <= data_stack[data_sp - 1]
      data_sp <= data_sp + 1

    when DROP
      data_sp <= data_sp - 1

    when SWAP
      temp = data_stack[data_sp - 1]
      data_stack[data_sp - 1] <= data_stack[data_sp - 2]
      data_stack[data_sp - 2] <= temp

    when OVER
      data_stack[data_sp] <= data_stack[data_sp - 2]
      data_sp <= data_sp + 1

    when ROT
      a = data_stack[data_sp - 3]
      b = data_stack[data_sp - 2]
      c = data_stack[data_sp - 1]
      data_stack[data_sp - 3] <= b
      data_stack[data_sp - 2] <= c
      data_stack[data_sp - 1] <= a

    when ADD
      data_stack[data_sp - 2] <= data_stack[data_sp - 2] + data_stack[data_sp - 1]
      data_sp <= data_sp - 1

    when SUB
      data_stack[data_sp - 2] <= data_stack[data_sp - 2] - data_stack[data_sp - 1]
      data_sp <= data_sp - 1

    when MUL
      data_stack[data_sp - 2] <= data_stack[data_sp - 2] * data_stack[data_sp - 1]
      data_sp <= data_sp - 1

    when AND
      data_stack[data_sp - 2] <= data_stack[data_sp - 2] & data_stack[data_sp - 1]
      data_sp <= data_sp - 1

    when OR
      data_stack[data_sp - 2] <= data_stack[data_sp - 2] | data_stack[data_sp - 1]
      data_sp <= data_sp - 1

    when XOR
      data_stack[data_sp - 2] <= data_stack[data_sp - 2] ^ data_stack[data_sp - 1]
      data_sp <= data_sp - 1

    when NOT
      data_stack[data_sp - 1] <= ~data_stack[data_sp - 1]

    when CALL
      ret_stack[ret_sp] <= pc
      ret_sp <= ret_sp + 1
      pc <= arg

    when RET
      ret_sp <= ret_sp - 1
      pc <= ret_stack[ret_sp - 1]

    when JMP
      pc <= arg

    when JZ
      if data_stack[data_sp - 1] == 0
        pc <= arg
      end
      data_sp <= data_sp - 1
    end
  end
end
```

## Instruction Encoding

```
┌────────────────────────────────────────┐
│        8-BIT INSTRUCTION FORMAT         │
├────────────────────────────────────────┤
│                                         │
│  Stack operations (no argument):        │
│  ┌──────────────────────────────────┐  │
│  │         opcode (8 bits)          │  │
│  └──────────────────────────────────┘  │
│                                         │
│  Literal/Branch (with argument):        │
│  ┌──────────────────────────────────┐  │
│  │ opcode (8)  │  argument (8)      │  │
│  └──────────────────────────────────┘  │
│                                         │
└────────────────────────────────────────┘
```

## Complete Instruction Set

| Opcode | Mnemonic | Stack Effect | Description |
|--------|----------|--------------|-------------|
| 0x00 | LIT n | ( -- n ) | Push literal |
| 0x01 | DUP | ( a -- a a ) | Duplicate TOS |
| 0x02 | DROP | ( a -- ) | Discard TOS |
| 0x03 | SWAP | ( a b -- b a ) | Swap top two |
| 0x04 | OVER | ( a b -- a b a ) | Copy second |
| 0x05 | ROT | ( a b c -- b c a ) | Rotate three |
| 0x10 | ADD | ( a b -- a+b ) | Add |
| 0x11 | SUB | ( a b -- a-b ) | Subtract |
| 0x12 | MUL | ( a b -- a*b ) | Multiply |
| 0x13 | DIV | ( a b -- a/b ) | Divide |
| 0x14 | AND | ( a b -- a&b ) | Bitwise AND |
| 0x15 | OR | ( a b -- a\|b ) | Bitwise OR |
| 0x16 | XOR | ( a b -- a^b ) | Bitwise XOR |
| 0x17 | NOT | ( a -- ~a ) | Bitwise NOT |
| 0x20 | @ | ( addr -- val ) | Fetch memory |
| 0x21 | ! | ( val addr -- ) | Store memory |
| 0x30 | CALL | ( -- ) (R: -- ret) | Call subroutine |
| 0x31 | RET | ( -- ) (R: ret -- ) | Return |
| 0x32 | JMP | ( -- ) | Unconditional jump |
| 0x33 | JZ | ( flag -- ) | Jump if zero |
| 0xFF | HALT | ( -- ) | Stop execution |

## Example Programs

### Factorial

```forth
\ Factorial: n! = n * (n-1) * ... * 1
\ Input: n on stack
\ Output: n! on stack

: FACTORIAL   ( n -- n! )
    DUP 1 > IF
        DUP 1- FACTORIAL *
    ELSE
        DROP 1
    THEN
;
```

Machine code:
```
; FACTORIAL (address 0x10)
0x10: DUP         ; ( n -- n n )
0x11: LIT 1       ; ( n n -- n n 1 )
0x13: SUB         ; ( n n 1 -- n n-1 )
0x14: DUP         ; ( n n-1 -- n n-1 n-1 )
0x15: JZ 0x1A     ; if n-1 == 0, goto base case
0x17: CALL 0x10   ; recurse
0x19: MUL         ; ( n result -- n*result )
0x1A: RET
```

### Fibonacci

```forth
: FIB   ( n -- fib[n] )
    DUP 2 < IF
        \ Base case: fib(0)=0, fib(1)=1
    ELSE
        DUP 1- FIB
        SWAP 2- FIB
        +
    THEN
;
```

## Test Harness

```ruby
class StackCPUTestbench < SimComponent
  instance :cpu, StackCPU
  instance :memory, RAM, size: 256

  wire :addr, width: 16
  wire :data_in, width: 8
  wire :data_out, width: 8

  port :clk => [:cpu, :clk]
  port :reset => [:cpu, :reset]
  port [:cpu, :mem_addr] => :addr
  port :addr => [:memory, :addr]
  port [:memory, :data_out] => [:cpu, :mem_data_in]

  def load_program(bytes)
    bytes.each_with_index do |byte, addr|
      memory.write(addr, byte)
    end
  end

  def run_until_halt
    until cpu.halted
      clock_cycle
    end
  end
end
```

## Further Resources

- RTX2000 datasheet - Commercial Forth chip
- GreenArrays GA144 documentation
- Chuck Moore's colorForth implementation

> Return to [Chapter 5](05-stack-machines.md) for conceptual introduction.
