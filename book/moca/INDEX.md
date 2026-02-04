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

### Part IV: Beyond Classical Computing

- [10 - Stochastic Computing](10-stochastic-computing.md) - Probability as data: AND gates multiply, MUX gates add
- [11 - Reversible Computation](11-reversible-computation.md) - Fredkin gates, Toffoli gates, and the thermodynamics of computing
- [12 - Quantum Computing](12-quantum-computing.md) - Qubits, superposition, entanglement, and quantum algorithms
- [13 - Asynchronous Computing](13-asynchronous-computing.md) - Clockless circuits: self-timed logic, handshaking, and NULL convention
- [14 - Neuromorphic Computing](14-neuromorphic-computing.md) - Brain-inspired architectures: spiking neurons, STDP, and memristors

### Part V: Hardware Practice

- [15 - Hardware Description Languages](15-hdl.md) - Verilog, VHDL, and RHDL compared
- [16 - Synthesis and Implementation](16-synthesis.md) - From HDL to silicon: FPGAs, ASICs, and the synthesis flow
- [17 - Reconfigurable Computing](17-reconfigurable-computing.md) - FPGAs: LUTs, CLBs, routing, and hardware that changes itself

### Part VI: Case Studies

- [18 - The MOS 6502](18-mos6502.md) - Deep dive into the classic CPU that powered the Apple II, C64, and NES
- [19 - The VideoCore IV](19-videocore-iv.md) - The Raspberry Pi GPU: 12 QPUs, SIMD, and tile-based rendering
- [20 - The Google TPU v1](20-tpu.md) - A 256×256 systolic array for neural network inference
- [21 - The Cray-1](21-cray1.md) - Vector processing pioneer: chaining, banking, and DAXPY in silicon
- [22 - The RISC-V RV32I](22-riscv.md) - The open ISA: clean design, modular extensions, and modern RISC
- [23 - The Transputer](23-transputer.md) - CSP in hardware: message passing, links, and occam
- [24 - The Cerebras WSE](24-cerebras.md) - Wafer-scale computing: 850K cores, 2D mesh NoC, dataflow at extreme scale
- [25 - Photonic Computing](25-photonic-computing.md) - Computing with light: MZI meshes, optical matrix multiply, and interference
- [26 - Analog Computing](26-analog-computing.md) - Continuous values: op-amps, integrators, and differential equations in real-time

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
- [Appendix J - Stochastic Implementation](appendix-j-stochastic.md) - LFSRs, stochastic multipliers, and probabilistic neural networks
- [Appendix K - Reversible Gates](appendix-k-reversible.md) - Fredkin, Toffoli, and building circuits that lose no information
- [Appendix L - Quantum Circuits](appendix-l-quantum.md) - Quantum gate implementations and simulators
- [Appendix M - Asynchronous Implementation](appendix-m-asynchronous.md) - C-elements, dual-rail logic, and self-timed circuits in RHDL
- [Appendix N - Neuromorphic Implementation](appendix-n-neuromorphic.md) - LIF neurons, STDP synapses, and spiking networks in RHDL
- [Appendix O - HDL Comparison](appendix-o-hdl.md) - Verilog, VHDL, Chisel, and RHDL side-by-side
- [Appendix P - Synthesis Details](appendix-p-synthesis.md) - Gate-level synthesis, optimization, and FPGA mapping
- [Appendix Q - FPGA Implementation](appendix-q-reconfigurable.md) - LUTs, CLBs, routing, and FPGA primitives in RHDL
- [Appendix R - MOS 6502 Implementation](appendix-r-mos6502.md) - Full 6502 in RHDL with test suite
- [Appendix S - VideoCore IV Implementation](appendix-s-videocore.md) - QPU cores, VPM, and sample assembly programs
- [Appendix T - TPU Implementation](appendix-t-tpu.md) - Systolic array, weight FIFOs, and matrix multiply in RHDL
- [Appendix U - Cray-1 Implementation](appendix-u-cray1.md) - Vector registers, chaining controller, and banked memory in RHDL
- [Appendix V - RISC-V Implementation](appendix-v-riscv.md) - RV32I decoder, ALU, pipeline stages, and hazard handling
- [Appendix W - Transputer Implementation](appendix-w-transputer.md) - Links, channels, scheduler, and ALT controller in RHDL
- [Appendix X - Cerebras Implementation](appendix-x-cerebras.md) - Mesh routers, crossbars, virtual channels, and NoC in RHDL
- [Appendix Y - Photonic Simulation](appendix-y-photonic.md) - Ruby simulation of MZIs, interference, and optical neural networks
- [Appendix Z - Analog Simulation](appendix-z-analog.md) - Ruby simulation of op-amps, ODEs, and analog neural networks

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
│                           Modern CPUs ◀──── FPGA             │
│                                           (reconfigurable)   │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Beyond Classical: Stoch ─ Reverse ─ Quantum ─ Async ─ Neuro│
│                       │       │          │        │       │  │
│                       ▼       ▼          ▼        ▼       ▼  │
│                     Prob    Zero     Exponential No    Brain │
│                     math    energy   speedup    clock  learn │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Case Studies:    6502 (CISC) │ VideoCore (GPU) │ TPU (ML)  │
│                    Cray-1 (Vector) │ RISC-V │ Transputer (CSP) │
│                    Cerebras (NoC) │ Photonic │ Analog           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Themes

1. **Computation is substrate-independent** - Gears, relays, DNA, transistors—same computation
2. **Many roads to the same destination** - Turing machines, lambda calculus, cellular automata are equivalent
3. **Spatial vs sequential** - Dataflow/systolic process in space; stack/register process in time
4. **Register machines won for practical reasons** - Not because they're theoretically superior
5. **Randomness enables simplicity** - Stochastic computing: AND gate = multiplier, MUX = adder
6. **Reversible computing bridges classical and quantum** - Same gates work in both
7. **Quantum offers new possibilities** - But only for certain problem classes
8. **Thermodynamics constrains computation** - Reversible computing may be the future
9. **Neuromorphic computing learns from biology** - Spiking neurons, local learning, massive parallelism
10. **Clocks are optional** - Asynchronous circuits trade complexity for power and average-case performance
11. **Hardware can be software** - FPGAs bridge the gap between flexibility and performance

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
| 10 | Stochastic Computing | J | Stochastic Implementation |
| 11 | Reversible Computation | K | Reversible Gates |
| 12 | Quantum Computing | L | Quantum Circuits |
| 13 | Asynchronous Computing | M | Asynchronous Implementation |
| 14 | Neuromorphic Computing | N | Neuromorphic Implementation |
| 15 | Hardware Description Languages | O | HDL Comparison |
| 16 | Synthesis and Implementation | P | Synthesis Details |
| 17 | Reconfigurable Computing | Q | FPGA Implementation |
| 18 | The MOS 6502 | R | 6502 RHDL Implementation |
| 19 | The VideoCore IV | S | VideoCore IV Implementation |
| 20 | The Google TPU v1 | T | TPU Implementation |
| 21 | The Cray-1 | U | Cray-1 Implementation |
| 22 | The RISC-V RV32I | V | RISC-V Implementation |
| 23 | The Transputer | W | Transputer Implementation |
| 24 | The Cerebras WSE | X | Cerebras/NoC Implementation |
| 25 | Photonic Computing | Y | Photonic Simulation (Ruby) |
| 26 | Analog Computing | Z | Analog Simulation (Ruby) |

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
