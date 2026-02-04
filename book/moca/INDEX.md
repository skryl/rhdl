# MOCA: Models Of Computational Architectures

*What is Computation? From Turing Machines to Silicon*

---

## Table of Contents

### Part I: Theoretical Foundations

- [01 - Symbol Manipulation](01-symbol-manipulation.md) - The essence of computation: symbols, rules, and Turing machines
- [02 - Lambda Calculus](02-lambda-calculus.md) - Computation as function application
- [03 - Mechanical Computation](03-mechanical-computation.md) - Babbage, Ada Lovelace, Zuse, and relay computers
- [04 - Biological Computation](04-biological-computation.md) - DNA computing, neurons as gates, cellular automata

### Part II: Sequential Architectures

- [05 - Stack Machines](05-stack-machines.md) - Forth, JVM, and the simplest computer architecture
- [06 - Register Machines](06-register-machines.md) - The von Neumann architecture that dominates modern computing

### Part III: Dataflow and Spatial Architectures

- [07 - Dataflow Computation](07-dataflow-computation.md) - Data-driven execution, Groq's deterministic dataflow, token machines
- [08 - Systolic Arrays](08-systolic-arrays.md) - Regular structures, matrix operations, and modern AI accelerators
- [09 - GPU Architecture](09-gpu-architecture.md) - SIMD/SIMT execution, streaming multiprocessors, and massively parallel computing
- [10 - Wafer-Scale Computing](10-wafer-scale.md) - Cerebras WSE: 850K cores, 2D mesh NoC, dataflow at extreme scale

### Part IV: Beyond Classical Computing

- [11 - Stochastic Computing](11-stochastic-computing.md) - Probability as data: AND gates multiply, MUX gates add
- [12 - Reversible Computation](12-reversible-computation.md) - Fredkin gates, Toffoli gates, and the thermodynamics of computing
- [13 - Quantum Computing](13-quantum-computing.md) - Qubits, superposition, entanglement, and quantum algorithms
- [14 - Asynchronous Computing](14-asynchronous-computing.md) - Clockless circuits: self-timed logic, handshaking, and NULL convention
- [15 - Neuromorphic Computing](15-neuromorphic-computing.md) - Brain-inspired architectures: spiking neurons, STDP, and memristors
- [16 - Photonic Computing](16-photonic-computing.md) - Computing with light: MZI meshes, optical matrix multiply, and interference
- [17 - Analog Computing](17-analog-computing.md) - Continuous values: op-amps, integrators, and differential equations in real-time

### Part V: Hardware Practice

- [18 - Hardware Description Languages](18-hdl.md) - Verilog, VHDL, and RHDL compared
- [19 - Synthesis and Implementation](19-synthesis.md) - From HDL to silicon: FPGAs, ASICs, and the synthesis flow
- [20 - Reconfigurable Computing](20-reconfigurable-computing.md) - FPGAs: LUTs, CLBs, routing, and hardware that changes itself

### Part VI: Case Studies

- [21 - The MOS 6502](21-mos6502.md) - Deep dive into the classic CPU that powered the Apple II, C64, and NES
- [22 - The VideoCore IV](22-videocore-iv.md) - The Raspberry Pi GPU: 12 QPUs, SIMD, and tile-based rendering
- [23 - The Google TPU v1](23-tpu.md) - A 256x256 systolic array for neural network inference
- [24 - The Cray-1](24-cray1.md) - Vector processing pioneer: chaining, banking, and DAXPY in silicon
- [25 - The RISC-V RV32I](25-riscv.md) - The open ISA: clean design, modular extensions, and modern RISC
- [26 - The Transputer](26-transputer.md) - CSP in hardware: message passing, links, and occam

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
- [Appendix J - Wafer-Scale Implementation](appendix-j-wafer-scale.md) - Mesh routers, crossbars, virtual channels, and NoC in RHDL
- [Appendix K - Stochastic Implementation](appendix-k-stochastic.md) - LFSRs, stochastic multipliers, and probabilistic neural networks
- [Appendix L - Reversible Gates](appendix-l-reversible.md) - Fredkin, Toffoli, and building circuits that lose no information
- [Appendix M - Quantum Circuits](appendix-m-quantum.md) - Quantum gate implementations and simulators
- [Appendix N - Asynchronous Implementation](appendix-n-asynchronous.md) - C-elements, dual-rail logic, and self-timed circuits in RHDL
- [Appendix O - Neuromorphic Implementation](appendix-o-neuromorphic.md) - LIF neurons, STDP synapses, and spiking networks in RHDL
- [Appendix P - Photonic Simulation](appendix-p-photonic.md) - Ruby simulation of MZIs, interference, and optical neural networks
- [Appendix Q - Analog Simulation](appendix-q-analog.md) - Ruby simulation of op-amps, ODEs, and analog neural networks
- [Appendix R - HDL Comparison](appendix-r-hdl.md) - Verilog, VHDL, Chisel, and RHDL side-by-side
- [Appendix S - Synthesis Details](appendix-s-synthesis.md) - Gate-level synthesis, optimization, and FPGA mapping
- [Appendix T - FPGA Implementation](appendix-t-reconfigurable.md) - LUTs, CLBs, routing, and FPGA primitives in RHDL
- [Appendix U - MOS 6502 Implementation](appendix-u-mos6502.md) - Full 6502 in RHDL with test suite
- [Appendix V - VideoCore IV Implementation](appendix-v-videocore.md) - QPU cores, VPM, and sample assembly programs
- [Appendix W - TPU Implementation](appendix-w-tpu.md) - Systolic array, weight FIFOs, and matrix multiply in RHDL
- [Appendix X - Cray-1 Implementation](appendix-x-cray1.md) - Vector registers, chaining controller, and banked memory in RHDL
- [Appendix Y - RISC-V Implementation](appendix-y-riscv.md) - RV32I decoder, ALU, pipeline stages, cache, TLB, and MMU
- [Appendix Z - Transputer Implementation](appendix-z-transputer.md) - Links, channels, scheduler, and ALT controller in RHDL

---

## The Big Picture

```
+-------------------------------------------------------------+
|                  MODELS OF COMPUTATION                       |
+-------------------------------------------------------------+
|                                                              |
|   Theoretical:     Turing <-> Lambda <-> Cellular Automata   |
|                      |          |            |               |
|                      v          v            v               |
|   All equivalent:  They compute the same things              |
|                                                              |
+-------------------------------------------------------------+
|                                                              |
|   Sequential:      Stack ----------- Register                |
|                    (operand stack)  (von Neumann)            |
|                                                              |
|   Spatial:     Dataflow --- Systolic --- GPU --- Wafer-Scale |
|               (Groq)      (regular)   (SIMD)   (Cerebras)    |
|                    |           |         |          |        |
|                    +-----------+---------+----------+        |
|                                |                             |
|                          Modern CPUs <---- FPGA              |
|                                          (reconfigurable)    |
|                                                              |
+-------------------------------------------------------------+
|                                                              |
|   Beyond Classical: Stoch - Reverse - Quantum - Async - Neuro|
|                       |       |          |        |       |  |
|                       v       v          v        v       v  |
|                     Prob    Zero     Exponential No    Brain |
|                     math    energy   speedup    clock  learn |
|                                                              |
|                    Photonic ------------- Analog             |
|                       |                       |              |
|                       v                       v              |
|                   Light/MZI           Continuous/Op-amps     |
|                                                              |
+-------------------------------------------------------------+
|                                                              |
|   Case Studies:    6502 (CISC) | VideoCore (GPU) | TPU (ML)  |
|                    Cray-1 (Vector) | RISC-V | Transputer (CSP)|
|                                                              |
+-------------------------------------------------------------+
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
12. **Scale changes everything** - Wafer-scale integration enables new architectural possibilities

---

## Chapter - Appendix Mapping

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
| 10 | Wafer-Scale Computing | J | Wafer-Scale/NoC Implementation |
| 11 | Stochastic Computing | K | Stochastic Implementation |
| 12 | Reversible Computation | L | Reversible Gates |
| 13 | Quantum Computing | M | Quantum Circuits |
| 14 | Asynchronous Computing | N | Asynchronous Implementation |
| 15 | Neuromorphic Computing | O | Neuromorphic Implementation |
| 16 | Photonic Computing | P | Photonic Simulation (Ruby) |
| 17 | Analog Computing | Q | Analog Simulation (Ruby) |
| 18 | Hardware Description Languages | R | HDL Comparison |
| 19 | Synthesis and Implementation | S | Synthesis Details |
| 20 | Reconfigurable Computing | T | FPGA Implementation |
| 21 | The MOS 6502 | U | 6502 RHDL Implementation |
| 22 | The VideoCore IV | V | VideoCore IV Implementation |
| 23 | The Google TPU v1 | W | TPU Implementation |
| 24 | The Cray-1 | X | Cray-1 Implementation |
| 25 | The RISC-V RV32I | Y | RISC-V Implementation |
| 26 | The Transputer | Z | Transputer Implementation |

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
