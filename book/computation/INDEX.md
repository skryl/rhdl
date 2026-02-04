# Models of Computation

*What is Computation? From Turing Machines to Silicon*

## Table of Contents

### Part I: Foundations of Computation

#### The Nature of Computation
- [01 - Symbol Manipulation](01-symbol-manipulation.md) - The essence of computation: symbols, rules, and Turing machines
- [02 - Mechanical Computation](02-mechanical-computation.md) - Babbage, Ada Lovelace, Zuse, and relay computers
- [03 - Biological Computation](03-biological-computation.md) - DNA computing, neurons as gates, cellular automata

#### Alternative Architectures
- [04 - Dataflow Computation](04-dataflow-computation.md) - Data-driven execution, token machines, why HDL is naturally dataflow
- [05 - Stack Machines](05-stack-machines.md) - Forth, JVM, and the simplest computer architecture
- [06 - Systolic Arrays](06-systolic-arrays.md) - Regular structures, matrix operations, and modern AI accelerators
- [07 - Reversible Computation](07-reversible-computation.md) - Fredkin gates, Toffoli gates, and the thermodynamics of computing
- [08 - Register Machines](08-register-machines.md) - The von Neumann architecture that dominates modern computing

### Part II: Theoretical Foundations

#### Computation Theory
- [Appendix A - Ada Lovelace's Program](appendix-a-ada-lovelace-program.md) - The first program, before hardware existed
- [Appendix B - Turing Machines](appendix-b-turing-machines.md) - Formal definition, examples, and universality
- [Appendix C - Lambda Calculus](appendix-c-lambda-calculus.md) - Computation as function application
- [Appendix D - Cellular Automata](appendix-d-cellular-automata.md) - Computation from simple local rules

### Part III: Architecture Deep Dives

#### Complete RHDL Implementations
- [Appendix E - Dataflow Architectures](appendix-e-dataflow.md) - Token machines, static vs dynamic dataflow, RHDL examples
- [Appendix F - Stack Machine ISA](appendix-f-stack-machine.md) - Complete Forth-like instruction set with RHDL implementation
- [Appendix G - Systolic Array Patterns](appendix-g-systolic.md) - Matrix multiply, convolution, and other array algorithms
- [Appendix H - Reversible Gates](appendix-h-reversible.md) - Fredkin, Toffoli, and building circuits that lose no information
- [Appendix I - Register Machine ISA](appendix-i-register-machine.md) - Complete 8-bit instruction set with RHDL CPU

### Part IV: Practice

#### Hardware Implementation
- [Appendix J - Hardware Description Languages](appendix-j-hdl.md) - Verilog, VHDL, and RHDL compared
- [Appendix K - Synthesis and Implementation](appendix-k-synthesis.md) - From HDL to silicon: FPGAs, ASICs, and the synthesis flow

#### Case Studies
- [Appendix L - The MOS 6502](appendix-l-mos6502.md) - Deep dive into the classic CPU that powered the Apple II, C64, and NES

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
│   Dominant:          Modern CPUs                             │
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

## Chapter Status

| Chapter | Status | Notes |
|---------|--------|-------|
| 01 - Symbol Manipulation | Draft | Turing machines, universality |
| 02 - Mechanical Computation | Draft | Babbage, Ada, Zuse |
| 03 - Biological Computation | Draft | DNA, neurons, cellular automata |
| 04 - Dataflow Computation | Draft | Token machines, RHDL as dataflow |
| 05 - Stack Machines | Draft | Forth, JVM, RHDL stack CPU |
| 06 - Systolic Arrays | Draft | Matrix multiply, TPU |
| 07 - Reversible Computation | Draft | Toffoli, Fredkin, thermodynamics |
| 08 - Register Machines | Draft | Von Neumann architecture |
| Appendix A | Draft | Ada's complete program |
| Appendix B | Draft | Turing machines formal treatment |
| Appendix C | Draft | Lambda calculus (with RHDL examples) |
| Appendix D | Draft | Cellular automata and emergent computation |
| Appendix E | Complete | Dataflow RHDL implementations |
| Appendix F | Complete | Stack machine RHDL implementations |
| Appendix G | Complete | Systolic array RHDL implementations |
| Appendix H | Complete | Reversible gate RHDL implementations |
| Appendix I | Complete | Register machine RHDL implementations |
| Appendix J | Outline | HDL comparison |
| Appendix K | Outline | Synthesis and implementation |
| Appendix L | Outline | MOS 6502 deep dive |

## Companion Book

This book provides the theoretical foundation for:

**[SICH: Structure and Interpretation of Computer Hardware](../notes/INDEX.md)** - A hands-on guide to building a computer from gates to a working Lisp interpreter.

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
