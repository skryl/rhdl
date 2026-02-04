# MOCA: Models Of Computational Architectures

*What is Computation? From Turing Machines to Silicon*

---

## Table of Contents

### Part I: Theoretical Foundations

- [01 - Symbol Manipulation](01-symbol-manipulation.md) - The essence of computation: symbols, rules, and Turing machines
- [02 - Lambda Calculus](02-lambda-calculus.md) - Computation as function application
- [03 - Mechanical Computation](03-mechanical-computation.md) - Babbage, Ada Lovelace, Zuse, and relay computers
- [04 - Biological Computation](04-biological-computation.md) - DNA computing, neurons as gates, cellular automata

### Part II: Alternative Architectures

- [05 - Dataflow Computation](05-dataflow-computation.md) - Data-driven execution, token machines, why HDL is naturally dataflow
- [06 - Stack Machines](06-stack-machines.md) - Forth, JVM, and the simplest computer architecture
- [07 - Systolic Arrays](07-systolic-arrays.md) - Regular structures, matrix operations, and modern AI accelerators
- [08 - Reversible Computation](08-reversible-computation.md) - Fredkin gates, Toffoli gates, and the thermodynamics of computing

### Part III: The Register Machine

- [09 - Register Machines](09-register-machines.md) - The von Neumann architecture that dominates modern computing
- [10 - The MOS 6502](10-mos6502.md) - Deep dive into the classic CPU that powered the Apple II, C64, and NES

### Part IV: Hardware Practice

- [11 - Hardware Description Languages](11-hdl.md) - Verilog, VHDL, and RHDL compared
- [12 - Synthesis and Implementation](12-synthesis.md) - From HDL to silicon: FPGAs, ASICs, and the synthesis flow

---

## Appendices

Each appendix provides complete RHDL implementations and formal details for its corresponding chapter.

- [Appendix A - Turing Machines](appendix-a-turing-machines.md) - Formal definition, examples, and universality
- [Appendix B - Lambda Calculus](appendix-b-lambda-calculus.md) - Church encodings and RHDL implementations
- [Appendix C - Ada Lovelace's Program](appendix-c-ada-lovelace.md) - The first program, before hardware existed
- [Appendix D - Cellular Automata](appendix-d-cellular-automata.md) - Rule 110, Game of Life, and emergent computation
- [Appendix E - Dataflow Architectures](appendix-e-dataflow.md) - Token machines, static vs dynamic dataflow, RHDL examples
- [Appendix F - Stack Machine ISA](appendix-f-stack-machine.md) - Complete Forth-like instruction set with RHDL implementation
- [Appendix G - Systolic Array Patterns](appendix-g-systolic.md) - Matrix multiply, convolution, and other array algorithms
- [Appendix H - Reversible Gates](appendix-h-reversible.md) - Fredkin, Toffoli, and building circuits that lose no information
- [Appendix I - Register Machine ISA](appendix-i-register-machine.md) - Complete 8-bit instruction set with RHDL CPU
- [Appendix J - MOS 6502 Implementation](appendix-j-mos6502.md) - Full 6502 in RHDL with test suite
- [Appendix K - HDL Comparison](appendix-k-hdl.md) - Verilog, VHDL, Chisel, and RHDL side-by-side
- [Appendix L - Synthesis Details](appendix-l-synthesis.md) - Gate-level synthesis, optimization, and FPGA mapping

---

## The Big Picture

```
┌─────────────────────────────────────────────────────────────┐
│                  MODELS OF COMPUTATION                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Theoretical:     Turing ←→ Lambda ←→ Cellular Automata    │
│                      │          │            │               │
│                      ▼          ▼            ▼               │
│   All equivalent:  They compute the same things              │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Architectural:   Dataflow   Stack   Systolic  Reversible  │
│                       │         │        │          │        │
│                       └────┬────┴────┬───┴────┬─────┘        │
│                            ▼         ▼        ▼              │
│                       Register Machine (von Neumann)         │
│                            │                                 │
│                            ▼                                 │
│   Dominant:          Modern CPUs (MOS 6502, x86, ARM)        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Themes

1. **Computation is substrate-independent** - Gears, relays, DNA, transistors—same computation
2. **Many roads to the same destination** - Turing machines, lambda calculus, cellular automata are equivalent
3. **Architecture is a choice** - Dataflow, stack, systolic, reversible are all valid
4. **Register machines won for practical reasons** - Not because they're theoretically superior
5. **Understanding alternatives illuminates the mainstream** - Why does x86 look the way it does?
6. **Thermodynamics constrains computation** - Reversible computing may be the future

---

## Chapter ↔ Appendix Mapping

| Chapter | Topic | Appendix | Contents |
|---------|-------|----------|----------|
| 01 | Symbol Manipulation | A | Turing Machines (formal) |
| 02 | Lambda Calculus | B | Church encodings, RHDL |
| 03 | Mechanical Computation | C | Ada Lovelace's Program |
| 04 | Biological Computation | D | Cellular Automata |
| 05 | Dataflow Computation | E | Dataflow RHDL |
| 06 | Stack Machines | F | Stack Machine ISA |
| 07 | Systolic Arrays | G | Systolic Patterns |
| 08 | Reversible Computation | H | Reversible Gates |
| 09 | Register Machines | I | Register Machine ISA |
| 10 | The MOS 6502 | J | 6502 RHDL Implementation |
| 11 | Hardware Description Languages | K | HDL Comparison |
| 12 | Synthesis and Implementation | L | Synthesis Details |

---

## Companion Book

This book provides the theoretical foundation for:

**[SICH: Structure and Interpretation of Computer Hardware](../sich/INDEX.md)** - A hands-on guide to building a computer from gates to a working Lisp interpreter.

---

## Target Audience

Readers who want to understand:
- What computation fundamentally *is*
- Why there are many equivalent models (Turing, lambda, cellular automata)
- How different architectures trade off different concerns
- The theoretical limits of computation (halting problem, thermodynamics)
- Complete working implementations of alternative architectures

## Prerequisites

- Basic programming experience
- Interest in theoretical computer science
- For RHDL implementations: familiarity with Ruby syntax helpful
- Having read SICH is helpful but not required
