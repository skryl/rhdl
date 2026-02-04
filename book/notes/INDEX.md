# SICH: Structure and Interpretation of Computer Hardware

*The Reverse SICP: From Gates to Lambda*

## Table of Contents

### Introduction
- [00 - Introduction](00-intro.md) - Book overview, target audience, and the RHDL approach

### Part 0: What is Computation?
- [01 - Symbol Manipulation](01-symbol-manipulation.md) - The essence of computation: symbols, rules, and Turing machines
- [02 - Mechanical Computation](02-mechanical-computation.md) - Babbage, Ada Lovelace, Zuse, and relay computers
- [03 - Biological Computation](03-biological-computation.md) - DNA computing, neurons as gates, cellular automata
- [04 - Dataflow Computation](04-dataflow-computation.md) - Data-driven execution, token machines, why HDL is naturally dataflow
- [05 - Stack Machines](05-stack-machines.md) - Forth, JVM, and the simplest computer architecture
- [06 - Systolic Arrays](06-systolic-arrays.md) - Regular structures, matrix operations, and modern AI accelerators
- [07 - Reversible Computation](07-reversible-computation.md) - Fredkin gates, Toffoli gates, and the thermodynamics of computing
- [08 - Register Machines](08-register-machines.md) - The von Neumann architecture we'll build in this book

### Part I: Switches and Gates
- [09 - Thinking in Hardware](09-thinking-in-hardware.md) - The mental shift from sequential software to parallel hardware
- [10 - Digital Logic Fundamentals](10-digital-logic-fundamentals.md) - Gates, truth tables, Boolean algebra
- [11 - Combinational Logic](11-combinational-logic.md) - Multiplexers, decoders, encoders, ALU design

### Part II: Memory and Time
- [12 - Sequential Logic](12-sequential-logic.md) - Flip-flops, registers, counters, finite state machines
- [13 - Memory Systems](13-memory-systems.md) - RAM, ROM, caches, memory hierarchy

### Part III: The Register Machine
- [14 - Computer Architecture](14-computer-architecture.md) - CPU fundamentals, fetch-decode-execute cycle
- [15 - Building a CPU](15-building-a-cpu.md) - Hands-on construction of an 8-bit processor

### Part IV: From Hardware to Lambda
- [16 - Assembly and the Stack](16-assembly-and-stack.md) - Subroutines, call/return, stack frames, the software/hardware boundary
- [17 - A Lisp Interpreter](17-lisp-interpreter.md) - S-expressions, cons cells, eval/apply—building Lisp on our CPU
- [18 - Lambda Comes Full Circle](18-lambda-full-circle.md) - The revelation: muxes are Church booleans, registers are Y combinators, we were computing lambda all along

### Appendices

#### Theory
- [Appendix A - Ada Lovelace's Program](appendix-a-ada-lovelace-program.md) - The first program, before hardware existed
- [Appendix B - Turing Machines](appendix-b-turing-machines.md) - Formal definition, examples, and universality
- [Appendix C - Lambda Calculus](appendix-c-lambda-calculus.md) - Computation as function application
- [Appendix D - Cellular Automata](appendix-d-cellular-automata.md) - Computation from simple local rules
- [Appendix E - Dataflow Architectures](appendix-e-dataflow.md) - Token machines, static vs dynamic dataflow, RHDL examples
- [Appendix F - Stack Machine ISA](appendix-f-stack-machine.md) - Complete Forth-like instruction set with RHDL implementation
- [Appendix G - Systolic Array Patterns](appendix-g-systolic.md) - Matrix multiply, convolution, and other array algorithms
- [Appendix H - Reversible Gates](appendix-h-reversible.md) - Fredkin, Toffoli, and building circuits that lose no information
- [Appendix I - Register Machine ISA](appendix-i-register-machine.md) - Complete 8-bit instruction set with RHDL CPU

#### Practice
- [Appendix J - Hardware Description Languages](appendix-j-hdl.md) - Verilog, VHDL, and RHDL compared
- [Appendix K - Synthesis and Implementation](appendix-k-synthesis.md) - From HDL to silicon: FPGAs, ASICs, and the synthesis flow

#### Case Studies
- [Appendix L - The MOS 6502](appendix-l-mos6502.md) - Deep dive into the classic CPU that powered the Apple II, C64, and NES

---

## The Journey

```
SICP (top-down):              This book (bottom-up):

λ calculus                    18: Lambda revealed
    ↓                             ↑
Lisp                          17: Lisp interpreter
    ↓                             ↑
procedures & state            16: Assembly and stack
    ↓                             ↑
interpreters                  14-15: CPU (the register machine)
    ↓                             ↑
register machines             12-13: Memory and time
                                  ↑
                              09-11: Gates and combinational logic
                                  ↑
                              01-08: What is computation?

        Both meet at the register machine / interpreter boundary
        Both reveal: it's the same computation at every level
```

---

## Chapter Status

| Chapter | Status | Notes |
|---------|--------|-------|
| 00 - Intro | Draft | Overview complete |
| 01 - Symbol Manipulation | Draft | Turing machines, universality |
| 02 - Mechanical Computation | Draft | Babbage, Ada, Zuse |
| 03 - Biological Computation | Draft | DNA, neurons, cellular automata |
| 04 - Dataflow Computation | Draft | Token machines, RHDL as dataflow |
| 05 - Stack Machines | Draft | Forth, JVM, RHDL stack CPU |
| 06 - Systolic Arrays | Draft | Matrix multiply, TPU |
| 07 - Reversible Computation | Draft | Toffoli, Fredkin, thermodynamics |
| 08 - Register Machines | Draft | Von Neumann architecture |
| 09 - Thinking in Hardware | Outline | Key concepts identified |
| 10 - Digital Logic | Outline | Key concepts identified |
| 11 - Combinational | Outline | Key concepts identified |
| 12 - Sequential | Outline | Key concepts identified |
| 13 - Memory | Outline | Key concepts identified |
| 14 - Architecture | Outline | Key concepts identified |
| 15 - Building a CPU | Outline | Key concepts identified |
| 16 - Assembly/Stack | Planned | New chapter |
| 17 - Lisp Interpreter | Planned | New chapter |
| 18 - Lambda Full Circle | Planned | New chapter - the punchline |
| Appendix A | Draft | Ada's complete program |
| Appendix B | Draft | Turing machines formal treatment |
| Appendix C | Draft | Lambda calculus (with RHDL examples) |
| Appendix D | Draft | Cellular automata and emergent computation |
| Appendix E | Planned | Dataflow architectures |
| Appendix F | Planned | Stack machine ISA |
| Appendix G | Planned | Systolic array patterns |
| Appendix H | Planned | Reversible gates |
| Appendix I | Planned | Register machine ISA |
| Appendix J | Outline | HDL comparison |
| Appendix K | Outline | Synthesis and implementation |
| Appendix L | Outline | MOS 6502 deep dive |

## Key Themes

1. **Computation is substrate-independent** - Gears, relays, DNA, transistors—same computation
2. **Hardware is parallel by default** - Everything happens at once unless you add sequencing
3. **Simple rules yield complex behavior** - NAND gates, cellular automata, neurons
4. **The abstraction ladder is climbable both ways** - SICP goes down; we go up
5. **Lambda is always there** - Muxes, registers, ALUs—it was lambda calculus all along
6. **Many roads to computation** - Dataflow, stack machines, systolic arrays, reversible gates—all equivalent
7. **Register machines are just one choice** - Dominant, but not the only way

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
