# Chapter 5: Stack Machines

## Overview

What's the simplest computer architecture you can build? Arguably, a **stack machine**. No general-purpose registers to manage. No complex addressing modes. Just push, pop, and operate. Languages like Forth and the Java Virtual Machine use stack architectures, and they're remarkably easy to implement in hardware.

## The Stack Model

### Registers vs. Stack

**Register machine** (like x86, ARM):
```asm
; Compute (a + b) * (c + d)
LOAD  R1, a      ; R1 = a
ADD   R1, b      ; R1 = a + b
LOAD  R2, c      ; R2 = c
ADD   R2, d      ; R2 = c + d
MUL   R1, R2     ; R1 = (a+b) * (c+d)
STORE R1, result
```

**Stack machine:**
```forth
; Compute (a + b) * (c + d)
PUSH a           ; Stack: [a]
PUSH b           ; Stack: [a, b]
ADD              ; Stack: [a+b]
PUSH c           ; Stack: [a+b, c]
PUSH d           ; Stack: [a+b, c, d]
ADD              ; Stack: [a+b, c+d]
MUL              ; Stack: [(a+b)*(c+d)]
POP  result
```

No registers needed! The stack implicitly holds intermediate values.

### Stack Operations

```
┌─────────────────────────────────────────┐
│            STACK OPERATIONS             │
├─────────────────────────────────────────┤
│                                         │
│  PUSH x:        POP:         ADD:       │
│    ┌───┐         ┌───┐        ┌───┐    │
│    │ x │ ←top    │   │        │a+b│    │
│    ├───┤         ├───┤        ├───┤    │
│    │ a │         │ b │        │ c │    │
│    ├───┤         ├───┤        ├───┤    │
│    │ b │         │ c │        │ d │    │
│    └───┘         └───┘        └───┘    │
│                                         │
│  DUP:          SWAP:        OVER:      │
│    ┌───┐         ┌───┐        ┌───┐    │
│    │ a │         │ b │        │ a │    │
│    ├───┤         ├───┤        ├───┤    │
│    │ a │         │ a │        │ b │    │
│    ├───┤         ├───┤        ├───┤    │
│    │ b │         │ c │        │ a │    │
│    └───┘         └───┘        ├───┤    │
│                               │ c │    │
│                               └───┘    │
└─────────────────────────────────────────┘
```

### Why Stacks?

1. **Simple hardware** - Just a pointer and memory
2. **No register allocation** - Compiler doesn't choose registers
3. **Compact instructions** - No operand fields needed
4. **Expression evaluation** - Naturally matches RPN notation
5. **Recursive calls** - Stack frames just work

## Forth: The Stack Language

### Forth Basics

Forth (1970) is the purest stack language:

```forth
\ Comments start with backslash

\ Define a word (function) to square a number
: SQUARE ( n -- n^2 )
    DUP * ;

\ Use it
5 SQUARE .   \ Prints 25

\ Stack effect notation: ( before -- after )
\ DUP:    ( a -- a a )
\ *:      ( a b -- a*b )
\ So SQUARE: ( n -- n n -- n*n )
```

### Postfix (Reverse Polish) Notation

Forth uses **postfix** notation—operators come after operands:

```
Infix:    (3 + 4) * (5 - 2)
Postfix:  3 4 + 5 2 - *

Execution:
  3 4 +    → 7
  5 2 -    → 3
  7 3 *    → 21
```

No parentheses needed! Order of operations is explicit.

### Forth Words (Instructions)

| Word | Stack Effect | Description |
|------|--------------|-------------|
| `DUP` | ( a -- a a ) | Duplicate top |
| `DROP` | ( a -- ) | Discard top |
| `SWAP` | ( a b -- b a ) | Swap top two |
| `OVER` | ( a b -- a b a ) | Copy second to top |
| `ROT` | ( a b c -- b c a ) | Rotate top three |
| `+` | ( a b -- a+b ) | Add |
| `-` | ( a b -- a-b ) | Subtract |
| `*` | ( a b -- a*b ) | Multiply |
| `/` | ( a b -- a/b ) | Divide |
| `@` | ( addr -- val ) | Fetch from memory |
| `!` | ( val addr -- ) | Store to memory |

## Stack Machine Architecture

### Minimal Stack CPU

```
┌─────────────────────────────────────────┐
│         STACK MACHINE CPU               │
├─────────────────────────────────────────┤
│                                         │
│   ┌──────────────────────────────────┐  │
│   │           DATA STACK             │  │
│   │  ┌───┬───┬───┬───┬───┬───┐      │  │
│   │  │TOS│NOS│   │   │   │   │      │  │
│   │  └───┴───┴───┴───┴───┴───┘      │  │
│   │            ▲                     │  │
│   │            │ SP (stack pointer)  │  │
│   └────────────┼─────────────────────┘  │
│                │                        │
│   ┌────────────┼─────────────────────┐  │
│   │   ALU      │                     │  │
│   │  ┌─────┐   │                     │  │
│   │  │ +−×÷│◀──┘                     │  │
│   │  └──┬──┘                         │  │
│   │     │ result                     │  │
│   │     ▼                            │  │
│   │   Push to stack                  │  │
│   └──────────────────────────────────┘  │
│                                         │
│   ┌──────────────────────────────────┐  │
│   │           RETURN STACK           │  │
│   │  (for call/return addresses)     │  │
│   └──────────────────────────────────┘  │
│                                         │
│   PC ──▶ [Instruction Memory]           │
│                                         │
└─────────────────────────────────────────┘
```

### Instruction Encoding

Stack instructions are tiny:
```
┌────────────────────────────────────────┐
│        8-BIT INSTRUCTION FORMAT         │
├────────────────────────────────────────┤
│                                         │
│   ┌─────────┬───────────────────────┐  │
│   │ opcode  │   immediate/unused    │  │
│   │ (4 bits)│      (4 bits)         │  │
│   └─────────┴───────────────────────┘  │
│                                         │
│   0000 = NOP     1000 = ADD            │
│   0001 = PUSH    1001 = SUB            │
│   0010 = POP     1010 = MUL            │
│   0011 = DUP     1011 = DIV            │
│   0100 = SWAP    1100 = AND            │
│   0101 = OVER    1101 = OR             │
│   0110 = CALL    1110 = XOR            │
│   0111 = RET     1111 = NOT            │
│                                         │
└────────────────────────────────────────┘
```

Compare to x86 where instructions can be 1-15 bytes!

### Two-Stack Architecture

Most stack machines have two stacks:

**Data Stack:** Holds operands and results
**Return Stack:** Holds return addresses for calls

```forth
: FACTORIAL ( n -- n! )
    DUP 1 > IF
        DUP 1- FACTORIAL *
    THEN ;

\ Return stack holds return addresses for recursive calls
```

## Java Virtual Machine

### JVM as a Stack Machine

The JVM bytecode is a stack architecture:

```java
// Java source
int result = (a + b) * (c + d);

// JVM bytecode
iload_0          // Push a
iload_1          // Push b
iadd             // a + b
iload_2          // Push c
iload_3          // Push d
iadd             // c + d
imul             // (a+b) * (c+d)
istore 4         // Store to result
```

### JVM Stack Frame

```
┌─────────────────────────────────────────┐
│           JVM STACK FRAME               │
├─────────────────────────────────────────┤
│                                         │
│  ┌─────────────────────────────────┐   │
│  │      Operand Stack              │   │
│  │  ┌───┬───┬───┬───┐              │   │
│  │  │ 5 │ 3 │   │   │              │   │
│  │  └───┴───┴───┴───┘              │   │
│  └─────────────────────────────────┘   │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │      Local Variables            │   │
│  │  ┌───┬───┬───┬───┬───┐          │   │
│  │  │ a │ b │ c │ d │res│          │   │
│  │  │[0]│[1]│[2]│[3]│[4]│          │   │
│  │  └───┴───┴───┴───┴───┘          │   │
│  └─────────────────────────────────┘   │
│                                         │
│  Return address, previous frame ptr    │
│                                         │
└─────────────────────────────────────────┘
```

## RHDL Stack Machine Implementation

### Basic Stack

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

### Stack ALU

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
  OP_ADD  = 5
  OP_SUB  = 6
  OP_MUL  = 7
  OP_AND  = 8
  OP_OR   = 9
  OP_XOR  = 10
  OP_NOT  = 11

  DEPTH = 16
  register :stack, width: 8, count: DEPTH
  register :sp, width: 4

  behavior do
    on_rising_edge(clk) do
      case op
      when OP_PUSH
        stack[sp] <= push_val
        sp <= sp + 1

      when OP_POP
        sp <= sp - 1

      when OP_DUP
        stack[sp] <= stack[sp - 1]
        sp <= sp + 1

      when OP_SWAP
        temp = stack[sp - 1]
        stack[sp - 1] <= stack[sp - 2]
        stack[sp - 2] <= temp

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
      end
    end

    tos <= (sp > 0) ? stack[sp - 1] : 0
    nos <= (sp > 1) ? stack[sp - 2] : 0
  end
end
```

### Complete Stack CPU

```ruby
class StackCPU < SimComponent
  input :clk
  input :reset
  input :mem_data_in, width: 8
  output :mem_addr, width: 16
  output :mem_data_out, width: 8
  output :mem_write

  # Registers
  register :pc, width: 16        # Program counter
  register :data_sp, width: 4    # Data stack pointer
  register :ret_sp, width: 4     # Return stack pointer

  # Stack memories
  register :data_stack, width: 8, count: 16
  register :ret_stack, width: 16, count: 16

  # Instruction set
  PUSH_LIT = 0x00   # Push literal (next byte)
  DUP      = 0x01
  DROP     = 0x02
  SWAP     = 0x03
  OVER     = 0x04
  ADD      = 0x10
  SUB      = 0x11
  MUL      = 0x12
  DIV      = 0x13
  AND      = 0x14
  OR       = 0x15
  XOR      = 0x16
  NOT      = 0x17
  FETCH    = 0x20   # Memory fetch
  STORE    = 0x21   # Memory store
  CALL     = 0x30
  RET      = 0x31
  JMP      = 0x32
  JZ       = 0x33   # Jump if zero

  behavior do
    on_rising_edge(clk) do
      if reset
        pc <= 0
        data_sp <= 0
        ret_sp <= 0
      else
        # Fetch-decode-execute
        opcode = mem_data_in
        execute_instruction(opcode)
      end
    end

    mem_addr <= pc
    mem_write <= 0  # Default: reading
  end

  def execute_instruction(opcode)
    # Implementation of each instruction...
    # (See Appendix F for full implementation)
  end
end
```

## Hardware Stack Machines

### Burroughs B5000 (1961)

First commercial stack machine:
- Hardware stack for expression evaluation
- Tagged memory (data vs. pointer)
- Influenced Algol compilers

### Forth Chips

Several chips implemented Forth directly:

**RTX2000 (1988):**
- 16-bit stack machine
- Two hardware stacks (data + return)
- 20 MIPS at 10 MHz
- Most Forth primitives in 1 cycle

```
┌─────────────────────────────────────────┐
│            RTX2000 ARCHITECTURE         │
├─────────────────────────────────────────┤
│                                         │
│   ┌─────────┐      ┌─────────┐         │
│   │  Data   │      │ Return  │         │
│   │  Stack  │      │  Stack  │         │
│   │ (256×16)│      │ (256×16)│         │
│   └────┬────┘      └────┬────┘         │
│        │                │               │
│        ▼                ▼               │
│   ┌─────────────────────────────┐      │
│   │           ALU               │      │
│   └─────────────────────────────┘      │
│                                         │
│   Single-cycle: DUP ADD (2 ops!)       │
│                                         │
└─────────────────────────────────────────┘
```

### GreenArrays GA144

Modern Forth chip (2010):
- 144 cores!
- Each core is a tiny stack machine
- 18-bit words
- Extremely low power

## Stack vs. Register Trade-offs

| Aspect | Stack Machine | Register Machine |
|--------|---------------|------------------|
| Instruction size | Small (no operands) | Large (register fields) |
| Hardware complexity | Simple | Complex |
| Code density | High | Medium |
| Performance | Lower (memory pressure) | Higher (register cache) |
| Compiler complexity | Low | High (register alloc) |
| Pipelining | Harder (stack deps) | Easier |

Modern CPUs use registers internally but often have stack-based ISAs (JVM, WebAssembly) for portability.

## Hands-On Exercises

### Exercise 1: Stack Trace

Trace the stack through this Forth program:
```forth
3 4 DUP * SWAP DUP * + .
```

What value is printed?

### Exercise 2: Implement ROT

Add the ROT operation to the StackALU:
```
ROT: ( a b c -- b c a )
```

### Exercise 3: Fibonacci in Forth

Write Forth to compute Fibonacci:
```forth
: FIB ( n -- fib[n] )
    \ Your code here
    ;

10 FIB .   \ Should print 55
```

## Key Takeaways

1. **Stacks are simple** - Just a pointer and memory
2. **No register allocation** - Temporaries live on stack
3. **Postfix is natural** - Matches stack evaluation
4. **Two stacks** - Data and return addresses
5. **Easy to implement** - Minimal hardware for a working CPU

## Further Reading

- *Starting Forth* by Leo Brodie - Best Forth introduction
- *Thinking Forth* by Leo Brodie - Forth philosophy
- *Stack Computers: The New Wave* by Philip Koopman
- JVM specification - Modern stack machine

> See [Appendix F](appendix-f-stack-machine.md) for complete RHDL stack CPU implementation.
