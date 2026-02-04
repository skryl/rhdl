# MOCA: Models Of Computational Architectures

*What is Computation? From Turing Machines to Silicon*

---

## Table of Contents

### Part I: Theoretical Foundations

- [01 - Symbol Manipulation](01-symbol-manipulation.md) - The essence of computation: symbols, rules, and Turing machines
- [02 - Lambda Calculus](02-lambda-calculus.md) - Computation as function application
- [03 - Mechanical Computation](03-mechanical-computation.md) - Babbage, Ada Lovelace, Zuse, and relay computers
- [04 - Biological Computation](04-biological-computation.md) - DNA computing, neurons as gates, cellular automata

### Part II: Stack and Register Machines

- [05 - Stack Machines](05-stack-machines.md) - Forth, JVM, and the simplest computer architecture
- [06 - Register Machines](06-register-machines.md) - The von Neumann architecture that dominates modern computing

### Part III: Dataflow and Spatial Architectures

- [07 - Dataflow Computation](07-dataflow-computation.md) - Data-driven execution, token machines, why HDL is naturally dataflow
- [08 - Systolic Arrays](08-systolic-arrays.md) - Regular structures, matrix operations, and modern AI accelerators
- [09 - GPU Architecture](09-gpu-architecture.md) - SIMD/SIMT execution, streaming multiprocessors, and massively parallel computing

### Part IV: Quantum and Reversible Computing

- [10 - Reversible Computation](10-reversible-computation.md) - Fredkin gates, Toffoli gates, and the thermodynamics of computing
- [11 - Quantum Computing](11-quantum-computing.md) - Qubits, superposition, entanglement, and quantum algorithms

### Part V: Hardware Practice

- [12 - Hardware Description Languages](12-hdl.md) - Verilog, VHDL, and RHDL compared
- [13 - Synthesis and Implementation](13-synthesis.md) - From HDL to silicon: FPGAs, ASICs, and the synthesis flow

### Part VI: Case Studies

- [14 - The MOS 6502](14-mos6502.md) - Deep dive into the classic CPU that powered the Apple II, C64, and NES
- [15 - The VideoCore IV](15-videocore-iv.md) - The Raspberry Pi GPU: 12 QPUs, SIMD, and tile-based rendering

---

## Appendices

Each appendix provides complete RHDL implementations and formal details for its corresponding chapter.

- [Appendix A - Turing Machines](appendix-a-turing-machines.md) - Formal definition, examples, and universality
- [Appendix B - Lambda Calculus](appendix-b-lambda-calculus.md) - Church encodings and RHDL implementations
- [Appendix C - Ada Lovelace's Program](appendix-c-ada-lovelace.md) - The first program, before hardware existed
- [Appendix D - Cellular Automata](appendix-d-cellular-automata.md) - Rule 110, Game of Life, and emergent computation
- [Appendix E - Stack Machine ISA](appendix-e-stack-machine.md) - Complete Forth-like instruction set with RHDL implementation
- [Appendix F - Register Machine ISA](appendix-f-register-machine.md) - Complete 8-bit instruction set with RHDL CPU
- [Appendix G - Dataflow Architectures](appendix-g-dataflow.md) - Token machines, static vs dynamic dataflow, RHDL examples
- [Appendix H - Systolic Array Patterns](appendix-h-systolic.md) - Matrix multiply, convolution, and other array algorithms
- [Appendix I - GPU Implementation](appendix-i-gpu.md) - CUDA-like execution model and RHDL streaming multiprocessor
- [Appendix J - Reversible Gates](appendix-j-reversible.md) - Fredkin, Toffoli, and building circuits that lose no information
- [Appendix K - Quantum Circuits](appendix-k-quantum.md) - Quantum gate implementations and simulators
- [Appendix L - HDL Comparison](appendix-l-hdl.md) - Verilog, VHDL, Chisel, and RHDL side-by-side
- [Appendix M - Synthesis Details](appendix-m-synthesis.md) - Gate-level synthesis, optimization, and FPGA mapping
- [Appendix N - MOS 6502 Implementation](appendix-n-mos6502.md) - Full 6502 in RHDL with test suite
- [Appendix O - VideoCore IV Implementation](appendix-o-videocore.md) - QPU cores, VPM, and sample assembly programs

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
│   Sequential:      Stack ─────────── Register               │
│                    (operand stack)  (von Neumann)           │
│                                                              │
│   Spatial:         Dataflow ─── Systolic ─── GPU            │
│                    (data-driven)  (regular)   (SIMD/SIMT)   │
│                         │               │                    │
│                         └───────┬───────┘                    │
│                                 ▼                            │
│                           Modern CPUs                        │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Beyond Classical: Reversible ──→ Quantum                   │
│                         │              │                     │
│                         ▼              ▼                     │
│                    Zero energy    Exponential speedup        │
│                    (theoretical)  (for some problems)        │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Case Studies:    MOS 6502 (CPU), VideoCore IV (GPU)        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Themes

1. **Computation is substrate-independent** - Gears, relays, DNA, transistors—same computation
2. **Many roads to the same destination** - Turing machines, lambda calculus, cellular automata are equivalent
3. **Spatial vs sequential** - Dataflow/systolic process in space; stack/register process in time
4. **Register machines won for practical reasons** - Not because they're theoretically superior
5. **Reversible computing bridges classical and quantum** - Same gates work in both
6. **Quantum offers new possibilities** - But only for certain problem classes
7. **Thermodynamics constrains computation** - Reversible computing may be the future

---

## Chapter ↔ Appendix Mapping

| Chapter | Topic | Appendix | Contents |
|---------|-------|----------|----------|
| 01 | Symbol Manipulation | A | Turing Machines (formal) |
| 02 | Lambda Calculus | B | Church encodings, RHDL |
| 03 | Mechanical Computation | C | Ada Lovelace's Program |
| 04 | Biological Computation | D | Cellular Automata |
| 05 | Stack Machines | E | Stack Machine ISA |
| 06 | Register Machines | F | Register Machine ISA |
| 07 | Dataflow Computation | G | Dataflow RHDL |
| 08 | Systolic Arrays | H | Systolic Patterns |
| 09 | GPU Architecture | I | GPU Implementation |
| 10 | Reversible Computation | J | Reversible Gates |
| 11 | Quantum Computing | K | Quantum Circuits |
| 12 | Hardware Description Languages | L | HDL Comparison |
| 13 | Synthesis and Implementation | M | Synthesis Details |
| 14 | The MOS 6502 | N | 6502 RHDL Implementation |
| 15 | The VideoCore IV | O | VideoCore IV Implementation |

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
- The connection between reversible and quantum computing
- The theoretical limits of computation (halting problem, thermodynamics)
- Complete working implementations of alternative architectures

## Prerequisites

- Basic programming experience
- Interest in theoretical computer science
- For RHDL implementations: familiarity with Ruby syntax helpful
- Having read SICH is helpful but not required
