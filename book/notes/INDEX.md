# Hardware Design for Software Engineers

*The Reverse SICP: From Gates to Lambda*

## Table of Contents

### Introduction
- [00 - Introduction](00-intro.md) - Book overview, target audience, and the RHDL approach

### Part 0: What is Computation?
- [01 - What is Computation?](01-what-is-computation.md) - Computation as symbol manipulation, mechanical computers, Ada Lovelace's first program, biological computing, why transistors just made things faster

### Part I: Switches and Gates
- [02 - Thinking in Hardware](02-thinking-in-hardware.md) - The mental shift from sequential software to parallel hardware
- [03 - Digital Logic Fundamentals](03-digital-logic-fundamentals.md) - Gates, truth tables, Boolean algebra
- [04 - Combinational Logic](04-combinational-logic.md) - Multiplexers, decoders, encoders, ALU design

### Part II: Memory and Time
- [05 - Sequential Logic](05-sequential-logic.md) - Flip-flops, registers, counters, finite state machines
- [06 - Memory Systems](06-memory-systems.md) - RAM, ROM, caches, memory hierarchy

### Part III: The Register Machine
- [07 - Computer Architecture](07-computer-architecture.md) - CPU fundamentals, fetch-decode-execute cycle
- [08 - Building a CPU](08-building-a-cpu.md) - Hands-on construction of an 8-bit processor
- [09 - The MOS 6502](09-the-mos-6502.md) - Deep dive into the classic CPU that powered the Apple II, C64, and NES

### Part IV: From Hardware to Lambda
- [10 - Assembly and the Stack](10-assembly-and-stack.md) - Subroutines, call/return, stack frames, the software/hardware boundary
- [11 - A Lisp Interpreter](11-lisp-interpreter.md) - S-expressions, cons cells, eval/apply—building Lisp on our CPU
- [12 - Lambda Comes Full Circle](12-lambda-full-circle.md) - The revelation: muxes are Church booleans, registers are Y combinators, we were computing lambda all along

### Appendices

#### Theory
- [Appendix A - Ada Lovelace's Program](appendix-a-ada-lovelace-program.md) - The first program, before hardware existed
- [Appendix B - Turing Machines](appendix-b-turing-machines.md) - Computation as symbol manipulation
- [Appendix C - Lambda Calculus](appendix-c-lambda-calculus.md) - Computation as function application
- [Appendix D - Cellular Automata](appendix-d-cellular-automata.md) - Computation from simple local rules

#### Practice
- [Appendix E - Hardware Description Languages](appendix-e-hdl.md) - Verilog, VHDL, and RHDL compared
- [Appendix F - Synthesis and Implementation](appendix-f-synthesis.md) - From HDL to silicon: FPGAs, ASICs, and the synthesis flow

---

## The Journey

```
SICP (top-down):              This book (bottom-up):

λ calculus                    12: Lambda revealed
    ↓                             ↑
Lisp                          11: Lisp interpreter
    ↓                             ↑
procedures & state            10: Assembly and stack
    ↓                             ↑
interpreters                  07-09: CPU (the register machine)
    ↓                             ↑
register machines             05-06: Memory and time
                                  ↑
                              02-04: Gates and combinational logic
                                  ↑
                              01: What is computation?

        Both meet at the register machine / interpreter boundary
        Both reveal: it's the same computation at every level
```

---

## Chapter Status

| Chapter | Status | Notes |
|---------|--------|-------|
| 00 - Intro | Draft | Overview complete |
| 01 - Computation | Draft | Biological computation, cellular automata added |
| 02 - Thinking in Hardware | Outline | Key concepts identified |
| 03 - Digital Logic | Outline | Key concepts identified |
| 04 - Combinational | Outline | Key concepts identified |
| 05 - Sequential | Outline | Key concepts identified |
| 06 - Memory | Outline | Key concepts identified |
| 07 - Architecture | Outline | Key concepts identified |
| 08 - Building a CPU | Outline | Key concepts identified |
| 09 - MOS 6502 | Outline | Key concepts identified |
| 10 - Assembly/Stack | Planned | New chapter |
| 11 - Lisp Interpreter | Planned | New chapter |
| 12 - Lambda Full Circle | Planned | New chapter - the punchline |
| Appendix A | Draft | Ada's complete program |
| Appendix B | Draft | Symbol manipulation, Turing machines |
| Appendix C | Draft | Lambda calculus (with RHDL examples) |
| Appendix D | Draft | Cellular automata and emergent computation |
| Appendix E | Outline | Moved from Ch 10 |
| Appendix F | Outline | Moved from Ch 11 |

## Key Themes

1. **Computation is substrate-independent** - Gears, relays, DNA, transistors—same computation
2. **Hardware is parallel by default** - Everything happens at once unless you add sequencing
3. **Simple rules yield complex behavior** - NAND gates, cellular automata, neurons
4. **The abstraction ladder is climbable both ways** - SICP goes down; we go up
5. **Lambda is always there** - Muxes, registers, ALUs—it was lambda calculus all along

## Target Audience

Software engineers who want to understand:
- How computers actually work at the hardware level
- The connection between hardware and the languages that run on it
- Why SICP's register machine looks the way it does
- That lambda calculus isn't just theory—it's what the hardware computes

## Prerequisites

- Basic programming experience (any language)
- Familiarity with binary numbers helpful but not required
- No prior hardware experience needed
- Having read SICP is *not* required (but you'll appreciate the symmetry if you have)
