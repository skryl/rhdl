# Hardware Design for Software Engineers

## Table of Contents

### Introduction
- [00 - Introduction](00-intro.md) - Book overview, target audience, and the RHDL approach

### Part I: Foundations of Computation
- [01 - What is Computation?](01-what-is-computation.md) - Computation as symbol manipulation, mechanical computers, Ada Lovelace's first program, why transistors just made things faster
- [02 - Thinking in Hardware](02-thinking-in-hardware.md) - The mental shift from sequential software to parallel hardware

### Part II: Digital Logic
- [03 - Digital Logic Fundamentals](03-digital-logic-fundamentals.md) - Gates, truth tables, Boolean algebra
- [04 - Combinational Logic](04-combinational-logic.md) - Multiplexers, decoders, encoders, ALU design
- [05 - Sequential Logic](05-sequential-logic.md) - Flip-flops, registers, counters, finite state machines

### Part III: Computer Systems
- [06 - Memory Systems](06-memory-systems.md) - RAM, ROM, caches, memory hierarchy
- [07 - Computer Architecture Basics](07-computer-architecture.md) - CPU fundamentals, fetch-decode-execute cycle
- [08 - Building a CPU](08-building-a-cpu.md) - Hands-on construction of an 8-bit processor

### Part IV: Real-World Hardware
- [09 - The MOS 6502](09-the-mos-6502.md) - Deep dive into the classic CPU that powered the Apple II, C64, and NES
- [10 - Hardware Description Languages](10-hardware-description-languages.md) - Verilog, VHDL, and RHDL compared
- [11 - Synthesis and Implementation](11-synthesis-and-implementation.md) - From HDL to silicon: FPGAs, ASICs, and the synthesis flow

### Appendices
- [Appendix A - Ada Lovelace's Program](appendix-a-ada-lovelace-program.md) - Complete Bernoulli number algorithm with original notation, pseudocode, and Ruby implementation
- [Appendix B - Turing Machines & Symbol Manipulation](appendix-b-turing-machines.md) - Computation as symbol manipulation, string rewriting systems, Turing machine programs with execution traces
- [Appendix C - Lambda Calculus](appendix-c-lambda-calculus.md) - Church's alternative model of computation, Church encodings, Y combinator, connection to functional programming and hardware
- [Appendix D - Cellular Automata](appendix-d-cellular-automata.md) - Elementary automata, Rule 110 universality, Conway's Game of Life, Wireworld circuits, emergence from simple rules

---

## Chapter Status

| Chapter | Status | Notes |
|---------|--------|-------|
| 00 - Intro | Draft | Overview complete |
| 01 - Computation | Draft | Ada Lovelace section added |
| 02 - Thinking in Hardware | Outline | Key concepts identified |
| 03 - Digital Logic | Outline | Key concepts identified |
| 04 - Combinational | Outline | Key concepts identified |
| 05 - Sequential | Outline | Key concepts identified |
| 06 - Memory | Outline | Key concepts identified |
| 07 - Architecture | Outline | Key concepts identified |
| 08 - Building a CPU | Outline | Key concepts identified |
| 09 - MOS 6502 | Outline | Key concepts identified |
| 10 - HDLs | Outline | Key concepts identified |
| 11 - Synthesis | Outline | Key concepts identified |
| Appendix A | Draft | Ada's complete program |
| Appendix B | Draft | Symbol manipulation, Turing machines |
| Appendix C | Draft | Lambda calculus and functional computation |
| Appendix D | Draft | Cellular automata and emergent computation |

## Key Themes

1. **Computation is substrate-independent** - The same algorithms work on gears, relays, or transistors
2. **Hardware is parallel by default** - Everything happens at once unless you add sequencing
3. **Learn by building** - Each chapter includes hands-on RHDL projects
4. **Bridge software concepts** - Leverage what you already know from programming
5. **From abstraction to silicon** - Understand the full stack from Ruby to gates

## Target Audience

Software engineers who want to understand:
- How computers actually work at the hardware level
- Digital logic design principles
- How to read and write HDL code
- The path from code to physical circuits

## Prerequisites

- Basic programming experience (any language)
- Familiarity with binary numbers helpful but not required
- No prior hardware experience needed
