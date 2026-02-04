# Chapter 8: Register Machines

## Overview

We've explored many models of computation: Turing machines, dataflow, stacks, systolic arrays, reversible gates. Now we arrive at the architecture that dominates modern computing: the **register machine**, also known as the **von Neumann architecture**. This is what we'll build in the rest of this book.

## The von Neumann Architecture

### Origins

In 1945, John von Neumann wrote the "First Draft of a Report on the EDVAC," describing a stored-program computer. Though others contributed (Eckert, Mauchly, Turing), his name stuck.

### The Key Insight: Stored Programs

Before von Neumann, computers were programmed by rewiring:

```
┌─────────────────────────────────────────┐
│      BEFORE: HARDWARE PROGRAMMING       │
├─────────────────────────────────────────┤
│                                         │
│   To change program:                    │
│   - Unplug cables                       │
│   - Replug in new pattern               │
│   - Takes hours/days                    │
│                                         │
│   ENIAC: 18,000 vacuum tubes            │
│          Weeks to reprogram             │
│                                         │
└─────────────────────────────────────────┘
```

The stored-program concept:

```
┌─────────────────────────────────────────┐
│      AFTER: STORED PROGRAMS             │
├─────────────────────────────────────────┤
│                                         │
│   Instructions stored in memory         │
│   Same memory holds data                │
│   Change program = change memory        │
│                                         │
│   Program IS data                       │
│   ← This is profound                    │
│                                         │
└─────────────────────────────────────────┘
```

### Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│           VON NEUMANN ARCHITECTURE                   │
├─────────────────────────────────────────────────────┤
│                                                      │
│                    ┌─────────────────┐              │
│                    │     MEMORY      │              │
│                    │ ┌─────────────┐ │              │
│                    │ │ Instructions│ │              │
│                    │ ├─────────────┤ │              │
│                    │ │    Data     │ │              │
│                    │ └─────────────┘ │              │
│                    └────────┬────────┘              │
│                             │                        │
│                        Bus  │  (address, data)       │
│                             │                        │
│     ┌───────────────────────┼───────────────────┐   │
│     │                       ▼                   │   │
│     │              ┌─────────────┐              │   │
│     │              │  CONTROL    │              │   │
│     │              │    UNIT     │              │   │
│     │              └──────┬──────┘              │   │
│     │                     │                     │   │
│     │              ┌──────▼──────┐              │   │
│     │              │    ALU      │              │   │
│     │              │ ┌───┬───┐   │              │   │
│     │              │ │ + │ - │...│              │   │
│     │              │ └───┴───┘   │              │   │
│     │              └──────┬──────┘              │   │
│     │                     │                     │   │
│     │              ┌──────▼──────┐              │   │
│     │              │  REGISTERS  │              │   │
│     │              │ R0 R1 R2... │              │   │
│     │              └─────────────┘              │   │
│     │                                           │   │
│     │              CPU                          │   │
│     └───────────────────────────────────────────┘   │
│                                                      │
└─────────────────────────────────────────────────────┘
```

## Registers: Fast Storage

### Why Registers?

Memory is slow. Registers are fast:

```
┌─────────────────────────────────────────┐
│        MEMORY HIERARCHY                 │
├─────────────────────────────────────────┤
│                                         │
│   Registers:  ~0.5 ns    (in CPU)       │
│   L1 Cache:   ~1 ns      (on CPU die)   │
│   L2 Cache:   ~4 ns      (on CPU die)   │
│   L3 Cache:   ~10 ns     (shared)       │
│   RAM:        ~100 ns    (off chip)     │
│   SSD:        ~100,000 ns               │
│   HDD:        ~10,000,000 ns            │
│                                         │
│   Registers are 200× faster than RAM!   │
│                                         │
└─────────────────────────────────────────┘
```

Registers hold the data currently being computed on.

### Register Operations

```
┌─────────────────────────────────────────┐
│        REGISTER OPERATIONS              │
├─────────────────────────────────────────┤
│                                         │
│   LOAD  R1, [addr]    # Memory → Reg    │
│   STORE R1, [addr]    # Reg → Memory    │
│   MOV   R1, R2        # Reg → Reg       │
│   ADD   R1, R2, R3    # R1 = R2 + R3    │
│   SUB   R1, R2, R3    # R1 = R2 - R3    │
│   AND   R1, R2, R3    # R1 = R2 & R3    │
│   ...                                   │
│                                         │
│   ALU operates on register contents     │
│   Results go back to registers          │
│                                         │
└─────────────────────────────────────────┘
```

### Register File

```
┌─────────────────────────────────────────┐
│        REGISTER FILE                    │
├─────────────────────────────────────────┤
│                                         │
│   read_addr1 ──┐     ┌── read_data1     │
│                │     │                  │
│   read_addr2 ──┼──▶──┼── read_data2     │
│                │     │                  │
│   write_addr ──┤     │                  │
│   write_data ──┤     │                  │
│   write_en ────┘     │                  │
│                      │                  │
│   ┌────┬────┬────┬────┐                 │
│   │ R0 │ R1 │ R2 │ R3 │...              │
│   └────┴────┴────┴────┘                 │
│                                         │
│   2 read ports (for ALU operands)       │
│   1 write port (for results)            │
│                                         │
└─────────────────────────────────────────┘
```

## The Fetch-Decode-Execute Cycle

Every instruction follows the same pattern:

```
┌─────────────────────────────────────────┐
│      FETCH-DECODE-EXECUTE               │
├─────────────────────────────────────────┤
│                                         │
│   ┌─────────┐                           │
│   │  FETCH  │ ← Get instruction at PC   │
│   └────┬────┘                           │
│        │                                │
│        ▼                                │
│   ┌─────────┐                           │
│   │ DECODE  │ ← What operation?         │
│   └────┬────┘   Which registers?        │
│        │                                │
│        ▼                                │
│   ┌─────────┐                           │
│   │ EXECUTE │ ← Do the ALU operation    │
│   └────┬────┘                           │
│        │                                │
│        ▼                                │
│   ┌──────────┐                          │
│   │WRITEBACK │ ← Store result           │
│   └────┬─────┘                          │
│        │                                │
│        ▼                                │
│   PC = PC + 1 (or branch target)        │
│        │                                │
│        └──────────▶ (repeat)            │
│                                         │
└─────────────────────────────────────────┘
```

## Instruction Set Architecture (ISA)

### RISC vs CISC

**CISC** (Complex Instruction Set Computing):
- Many instructions, varying length
- Instructions can access memory directly
- Example: x86

```asm
; x86 CISC
ADD [eax+ebx*4+10], ecx   ; Memory op in one instruction
```

**RISC** (Reduced Instruction Set Computing):
- Few instructions, fixed length
- Only LOAD/STORE access memory
- Example: ARM, RISC-V

```asm
; RISC-V
LW   t0, 10(a0)      ; Load from memory
ADD  t0, t0, a2      ; Add
SW   t0, 10(a0)      ; Store to memory
```

### A Simple ISA

For our 8-bit CPU, we'll use:

```
┌─────────────────────────────────────────┐
│      SIMPLE 8-BIT ISA                   │
├─────────────────────────────────────────┤
│                                         │
│   Format: [opcode:4][reg:2][reg:2]      │
│           or                            │
│           [opcode:4][immediate:4]       │
│                                         │
│   Opcode  Mnemonic    Operation         │
│   ──────────────────────────────────────│
│   0000    NOP         No operation      │
│   0001    LDI r, imm  r = imm           │
│   0010    LD  r, [a]  r = mem[a]        │
│   0011    ST  [a], r  mem[a] = r        │
│   0100    MOV r1, r2  r1 = r2           │
│   0101    ADD r1, r2  r1 = r1 + r2      │
│   0110    SUB r1, r2  r1 = r1 - r2      │
│   0111    AND r1, r2  r1 = r1 & r2      │
│   1000    OR  r1, r2  r1 = r1 | r2      │
│   1001    XOR r1, r2  r1 = r1 ^ r2      │
│   1010    NOT r       r = ~r            │
│   1011    SHL r       r = r << 1        │
│   1100    SHR r       r = r >> 1        │
│   1101    JMP addr    PC = addr         │
│   1110    JZ  addr    if Z: PC = addr   │
│   1111    HALT        Stop              │
│                                         │
└─────────────────────────────────────────┘
```

## Register Machine in RHDL

### Register File

```ruby
class RegisterFile < SimComponent
  input :clk
  input :read_addr1, width: 2   # 4 registers
  input :read_addr2, width: 2
  input :write_addr, width: 2
  input :write_data, width: 8
  input :write_en
  output :read_data1, width: 8
  output :read_data2, width: 8

  register :regs, width: 8, count: 4

  behavior do
    # Reads are combinational
    read_data1 <= regs[read_addr1]
    read_data2 <= regs[read_addr2]

    # Writes are clocked
    on_rising_edge(clk) do
      if write_en
        regs[write_addr] <= write_data
      end
    end
  end
end
```

### Simple CPU Core

```ruby
class SimpleCPU < SimComponent
  input :clk
  input :reset
  input :mem_data_in, width: 8
  output :mem_addr, width: 8
  output :mem_data_out, width: 8
  output :mem_write
  output :halted

  # Internal state
  register :pc, width: 8
  register :ir, width: 8          # Instruction register
  register :state, width: 2       # FSM state

  # Register file
  register :regs, width: 8, count: 4

  # ALU result
  wire :alu_result, width: 8
  wire :zero_flag

  # State constants
  FETCH   = 0
  DECODE  = 1
  EXECUTE = 2
  HALT    = 3

  behavior do
    on_rising_edge(clk) do
      if reset
        pc <= 0
        state <= FETCH
      else
        case state
        when FETCH
          ir <= mem_data_in
          state <= DECODE

        when DECODE
          # Decode happens combinationally
          state <= EXECUTE

        when EXECUTE
          execute_instruction
          if opcode != 0xF  # Not HALT
            pc <= next_pc
            state <= FETCH
          else
            state <= HALT
          end

        when HALT
          # Stay halted
        end
      end
    end

    # Memory interface
    mem_addr <= pc
    mem_write <= 0
    halted <= (state == HALT)
  end

  def opcode
    ir >> 4
  end

  def reg1
    (ir >> 2) & 0x3
  end

  def reg2
    ir & 0x3
  end

  def execute_instruction
    case opcode
    when 0x1  # LDI
      regs[reg1] <= reg2  # Immediate is low 2 bits
    when 0x5  # ADD
      regs[reg1] <= regs[reg1] + regs[reg2]
    when 0x6  # SUB
      regs[reg1] <= regs[reg1] - regs[reg2]
    # ... other instructions
    end
  end

  def next_pc
    case opcode
    when 0xD  # JMP
      ir & 0xF  # Target address
    when 0xE  # JZ
      zero_flag ? (ir & 0xF) : (pc + 1)
    else
      pc + 1
    end
  end
end
```

### ALU

```ruby
class ALU < SimComponent
  input :a, width: 8
  input :b, width: 8
  input :op, width: 4
  output :result, width: 8
  output :zero
  output :carry
  output :negative

  ALU_ADD = 0
  ALU_SUB = 1
  ALU_AND = 2
  ALU_OR  = 3
  ALU_XOR = 4
  ALU_NOT = 5
  ALU_SHL = 6
  ALU_SHR = 7

  behavior do
    full_result = case op
    when ALU_ADD then a + b
    when ALU_SUB then a - b
    when ALU_AND then a & b
    when ALU_OR  then a | b
    when ALU_XOR then a ^ b
    when ALU_NOT then ~a
    when ALU_SHL then a << 1
    when ALU_SHR then a >> 1
    else 0
    end

    result <= full_result & 0xFF
    zero <= (result == 0) ? 1 : 0
    carry <= (full_result > 0xFF) ? 1 : 0
    negative <= result[7]
  end
end
```

## The von Neumann Bottleneck

### The Problem

Programs and data share one memory bus:

```
┌─────────────────────────────────────────┐
│      VON NEUMANN BOTTLENECK             │
├─────────────────────────────────────────┤
│                                         │
│   CPU can either:                       │
│   - Fetch instruction, OR               │
│   - Read/write data                     │
│                                         │
│   NOT both at once!                     │
│                                         │
│        CPU ◄────────────► Memory        │
│              single bus                 │
│                                         │
│   Modern CPUs use caches to hide this   │
│                                         │
└─────────────────────────────────────────┘
```

### Harvard Architecture

Separate instruction and data memories:

```
┌─────────────────────────────────────────┐
│      HARVARD ARCHITECTURE               │
├─────────────────────────────────────────┤
│                                         │
│   Instruction ◄─── CPU ───► Data        │
│     Memory                  Memory      │
│                                         │
│   Parallel fetch + data access!         │
│                                         │
│   Used in: DSPs, some microcontrollers  │
│                                         │
└─────────────────────────────────────────┘
```

Most modern CPUs are **Modified Harvard**: separate caches but unified main memory.

## Comparing to Other Models

| Feature | Register Machine | Stack Machine | Dataflow |
|---------|------------------|---------------|----------|
| State location | Registers | Stack | Tokens |
| Control | Program counter | Program counter | Data-driven |
| Parallelism | Limited | Very limited | Automatic |
| Code density | Medium | High | N/A |
| Hardware complexity | Medium | Low | High |

### Why Register Machines Won

1. **Good performance** - Registers are fast
2. **Efficient compilers** - Register allocation is well-understood
3. **Pipelining** - Easy to overlap execution stages
4. **Caching** - Sequential access patterns work well
5. **Momentum** - Decades of software and tools

## SICP's Register Machine

In *Structure and Interpretation of Computer Programs*, Abelson and Sussman build a register machine to execute Lisp:

```scheme
;; SICP's register machine simulator
(define factorial-machine
  (make-machine
   '(n val continue)           ; Registers
   (list (list '= =) (list '- -) (list '* *))  ; Operations
   '(controller
       (assign continue (label fact-done))
     fact-loop
       (test (op =) (reg n) (const 1))
       (branch (label base-case))
       (save continue)
       (save n)
       (assign n (op -) (reg n) (const 1))
       (assign continue (label after-fact))
       (goto (label fact-loop))
     after-fact
       (restore n)
       (restore continue)
       (assign val (op *) (reg n) (reg val))
       (goto (reg continue))
     base-case
       (assign val (const 1))
       (goto (reg continue))
     fact-done)))
```

This is exactly what we'll build: a machine that can run programs, including Lisp interpreters!

## Hands-On Exercises

### Exercise 1: Trace Execution

Trace this program through the CPU:
```
LDI R0, 5      ; R0 = 5
LDI R1, 3      ; R1 = 3
ADD R0, R1     ; R0 = R0 + R1
HALT
```

What are the register values after each instruction?

### Exercise 2: Write a Program

Write assembly for: `result = (a + b) * 2`

Assume `a` is in R0, `b` is in R1, and you can use R2, R3.

### Exercise 3: Implement Multiply

Our ISA has no multiply instruction. Write a subroutine using ADD and loops to multiply R0 by R1, result in R2.

### Exercise 4: Add a Multiply Instruction

Modify the RHDL CPU to add a MUL instruction. What changes are needed in the ALU and control unit?

## What's Next

We've surveyed many models of computation. Now we focus on building a register machine from the ground up:

```
Part I:   Switches and Gates    ← Build logic from transistors
Part II:  Memory and Time       ← Add state and sequential logic
Part III: The Register Machine  ← Construct a complete CPU
Part IV:  From Hardware to Lambda ← Run Lisp on our hardware
```

The journey from NAND gates to a Lisp interpreter begins in the next chapter.

## Key Takeaways

1. **Stored program** - Instructions are data in memory
2. **Registers are fast** - Hold currently-computed values
3. **Fetch-decode-execute** - The CPU's heartbeat
4. **Von Neumann bottleneck** - Shared bus limits throughput
5. **This is what we'll build** - Parts I-IV implement this architecture

## Further Reading

- *Computer Organization and Design* by Patterson & Hennessy
- *Structure and Interpretation of Computer Programs* - Chapter 5
- Von Neumann's "First Draft of a Report on the EDVAC" (1945)
- *Computer Architecture: A Quantitative Approach* by Hennessy & Patterson

> See [Appendix I](appendix-i-register-machine.md) for extended ISA and complete RHDL CPU.
