# Chapter 7: Computer Architecture Basics

## Overview

How CPUs work: the fetch-decode-execute cycle, datapath, and control unit.

## Key Concepts

### What is a CPU?

A CPU is a state machine that:
1. Fetches instructions from memory
2. Decodes what they mean
3. Executes them
4. Repeats

### The Stored Program Concept

Von Neumann's insight:
- Instructions are just data
- Store program in memory
- CPU reads and executes sequentially

### CPU Components

**Program Counter (PC):**
- Holds address of next instruction
- Usually increments by instruction size
- Jumps/branches change it

**Instruction Register (IR):**
- Holds current instruction being executed

**Registers:**
- Fast storage inside CPU
- Accumulator (A), Index (X, Y), etc.

**ALU:**
- Performs arithmetic and logic operations

**Control Unit:**
- Decodes instructions
- Generates control signals
- Orchestrates everything

### The Datapath

The "plumbing" of the CPU:

```
        +--------+
        |   PC   |
        +--------+
            |
            v
        +--------+
        | Memory |
        +--------+
            |
            v
        +--------+
        |   IR   |
        +--------+
            |
            v
        +--------+     +--------+
        |Decoder | --> |Control |
        +--------+     +--------+
                           |
            +--------------+
            |
            v
        +--------+     +--------+
        |  Reg   | <-> |  ALU   |
        |  File  |     +--------+
        +--------+
```

### Fetch-Decode-Execute Cycle

**Fetch:**
```
IR <= Memory[PC]
PC <= PC + 1
```

**Decode:**
- Extract opcode
- Extract operands
- Determine operation

**Execute:**
- Perform operation
- Write result
- Update flags

### Instruction Types

**Data Movement:**
- LOAD: Memory -> Register
- STORE: Register -> Memory
- MOVE: Register -> Register

**Arithmetic/Logic:**
- ADD, SUB, AND, OR, XOR
- Compare (like SUB but don't store)

**Control Flow:**
- JUMP: Unconditional branch
- BRANCH: Conditional (if zero, if negative, etc.)
- CALL/RETURN: Subroutines

### Addressing Modes

How operands are specified:

**Immediate:** Value in instruction
```
LDA #$42   ; Load literal 0x42
```

**Absolute:** Address in instruction
```
LDA $1234  ; Load from address 0x1234
```

**Register:** Value in register
```
TAX        ; Transfer A to X
```

**Indexed:** Base + offset
```
LDA $1000,X ; Load from 0x1000 + X
```

**Indirect:** Address points to address
```
LDA ($20)   ; Load from address stored at 0x20
```

### Control Signals

The control unit generates signals:
- `reg_write`: Enable register write
- `mem_read`: Enable memory read
- `alu_op`: Select ALU operation
- `pc_src`: Select next PC source

## Hands-On Project: Simple 8-bit CPU

Design a minimal CPU:
- 8-bit data bus
- 4 instructions: LOAD, STORE, ADD, JUMP
- 16-byte memory
- 1 register (accumulator)

## Exercises

1. Trace execution of a simple program through your CPU
2. Add a conditional branch instruction
3. Implement indirect addressing

---

## Notes and Ideas

- Show both single-cycle and multi-cycle implementations
- Diagram: the control signals for each instruction
- Software parallel: CPU is like an interpreter for machine code
- History: Von Neumann vs Harvard architecture
- Pipeline teaser: what if we overlap fetch-decode-execute?
