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

- [07 - Dataflow Computation](07-dataflow-computation.md) - Data-driven execution, token machines, and deterministic pipelines
- [08 - Systolic Arrays](08-systolic-arrays.md) - Regular structures, matrix operations, and modern AI accelerators
- [09 - GPU Architecture](09-gpu-architecture.md) - SIMD/SIMT execution, streaming multiprocessors, and massively parallel computing
- [10 - Wafer-Scale Computing](10-wafer-scale.md) - Using entire wafers: 2D mesh NoC, dataflow at extreme scale
- [11 - Vector Processing](11-vector-processing.md) - SIMD with vector registers: pipelining, chaining, and memory banking

### Part IV: Non-Classical Computing

- [12 - Stochastic Computing](12-stochastic-computing.md) - Probability as data: AND gates multiply, MUX gates add
- [13 - Reversible Computation](13-reversible-computation.md) - Fredkin gates, Toffoli gates, and the thermodynamics of computing
- [14 - Quantum Computing](14-quantum-computing.md) - Qubits, superposition, entanglement, and quantum algorithms

### Part V: Alternative Substrates

- [15 - Asynchronous Computing](15-asynchronous-computing.md) - Clockless circuits: self-timed logic, handshaking, and NULL convention
- [16 - Neuromorphic Computing](16-neuromorphic-computing.md) - Brain-inspired architectures: spiking neurons, STDP, and memristors
- [17 - Photonic Computing](17-photonic-computing.md) - Computing with light: MZI meshes, optical matrix multiply, and interference
- [18 - Analog Computing](18-analog-computing.md) - Continuous values: op-amps, integrators, and differential equations in real-time

### Part VI: Reconfigurable Computing

- [19 - FPGAs](19-fpga.md) - Field-programmable gate arrays: LUTs, CLBs, routing, and fine-grained reconfiguration
- [20 - Coarse-Grained Reconfigurable Arrays](20-cgra.md) - CGRAs: word-level datapaths, spatial computing, and domain-specific acceleration

### Part VII: Case Studies

- [21 - The MOS 6502](21-mos6502.md) - (1975) The classic CPU that powered the Apple II, C64, and NES
- [22 - The Cray-1](22-cray1.md) - (1976) The supercomputer that defined vector processing
- [23 - The NVIDIA G80](23-nvidia-g80.md) - (2006) The first CUDA GPU: unified shaders and GPGPU revolution
- [24 - The RISC-V RV32I](24-riscv.md) - (2010) The open ISA: clean design, modular extensions, and modern RISC
- [25 - The Google TPU v1](25-tpu.md) - (2016) A 256x256 systolic array for neural network inference
- [26 - The Cerebras WSE](26-cerebras.md) - (2019) The largest chip ever built: 850K cores on a single wafer
- [27 - The Groq LPU](27-groq.md) - (2020) Deterministic dataflow for AI inference: time as the program counter

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
- [Appendix K - Vector Implementation](appendix-k-vector.md) - Vector registers, chaining controller, and banked memory in RHDL
- [Appendix L - Stochastic Implementation](appendix-l-stochastic.md) - LFSRs, stochastic multipliers, and probabilistic neural networks
- [Appendix M - Reversible Gates](appendix-m-reversible.md) - Fredkin, Toffoli, and building circuits that lose no information
- [Appendix N - Quantum Circuits](appendix-n-quantum.md) - Quantum gate implementations and simulators
- [Appendix O - Asynchronous Implementation](appendix-o-asynchronous.md) - C-elements, dual-rail logic, and self-timed circuits in RHDL
- [Appendix P - Neuromorphic Implementation](appendix-p-neuromorphic.md) - LIF neurons, STDP synapses, and spiking networks in RHDL
- [Appendix Q - Photonic Simulation](appendix-q-photonic.md) - Ruby simulation of MZIs, interference, and optical neural networks
- [Appendix R - Analog Simulation](appendix-r-analog.md) - Ruby simulation of op-amps, ODEs, and analog neural networks
- [Appendix S - FPGA Implementation](appendix-s-fpga.md) - LUTs, CLBs, routing, and FPGA primitives in RHDL
- [Appendix T - CGRA Implementation](appendix-t-cgra.md) - PE arrays, interconnect, and configuration in RHDL
- [Appendix U - MOS 6502 Implementation](appendix-u-mos6502.md) - Full 6502 in RHDL with test suite
- [Appendix V - Cray-1 Implementation](appendix-v-cray1.md) - Vector registers, functional units, chaining, and memory in RHDL
- [Appendix W - TPU Implementation](appendix-w-tpu.md) - Systolic array, weight FIFOs, and matrix multiply in RHDL
- [Appendix X - RISC-V Implementation](appendix-x-riscv.md) - RV32I decoder, ALU, pipeline stages, cache, TLB, and MMU
- [Appendix Y - NVIDIA G80 Implementation](appendix-y-g80.md) - Streaming multiprocessors, warp scheduler, and shared memory in RHDL

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
|   Spatial:   Dataflow - Systolic - GPU - Wafer-Scale - Vector|
|             (tokens)  (regular)  (SIMT) (mesh)      (SIMD)   |
|                  |         |       |        |          |     |
|                  +---------+-------+--------+----------+     |
|                                |                             |
|                          Modern CPUs <---- Reconfigurable    |
|                                          (FPGA, CGRA)        |
|                                                              |
+-------------------------------------------------------------+
|                                                              |
|   Non-Classical:   Stochastic -- Reversible -- Quantum       |
|                        |             |            |          |
|                        v             v            v          |
|                    Probability    Zero       Superposition   |
|                    as data       energy      & entanglement  |
|                                                              |
+-------------------------------------------------------------+
|                                                              |
|   Alternative      Async ----- Neuromorphic                  |
|   Substrates:        |             |                         |
|   (still classical)  v             v                         |
|                   Clockless    Brain-inspired                |
|                                                              |
|                   Photonic ------- Analog                    |
|                      |               |                       |
|                      v               v                       |
|                  Light/MZI     Continuous/Op-amps            |
|                                                              |
+-------------------------------------------------------------+
|                                                              |
|   Case Studies:    6502 (1975) | Cray-1 (1976) | G80 (2006)        |
|   (chronological)  RISC-V (2010) | TPU (2016) | Cerebras (2019)    |
|                    Groq (2020)                                      |
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
11. **Hardware can be software** - FPGAs and CGRAs bridge flexibility and performance
12. **Scale changes everything** - Wafer-scale integration enables new architectural possibilities
13. **Vectors unlock throughput** - Single instruction, multiple data paths
14. **Determinism enables efficiency** - Static scheduling maximizes utilization
15. **Light and continuous values are valid substrates** - Classical computation doesn't require digital electronics

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
| 11 | Vector Processing | K | Vector Implementation |
| 12 | Stochastic Computing | L | Stochastic Implementation |
| 13 | Reversible Computation | M | Reversible Gates |
| 14 | Quantum Computing | N | Quantum Circuits |
| 15 | Asynchronous Computing | O | Asynchronous Implementation |
| 16 | Neuromorphic Computing | P | Neuromorphic Implementation |
| 17 | Photonic Computing | Q | Photonic Simulation (Ruby) |
| 18 | Analog Computing | R | Analog Simulation (Ruby) |
| 19 | FPGAs | S | FPGA Implementation |
| 20 | CGRAs | T | CGRA Implementation |
| 21 | The MOS 6502 | U | 6502 RHDL Implementation |
| 22 | The Cray-1 | V | Cray-1 Implementation |
| 23 | The NVIDIA G80 | Y | G80 RHDL Implementation |
| 24 | The RISC-V RV32I | X | RISC-V Implementation |
| 25 | The Google TPU v1 | W | TPU Implementation |
| 26 | The Cerebras WSE | J | (see Wafer-Scale appendix) |
| 27 | The Groq LPU | G | (see Dataflow appendix) |

*Note: Chapters 26 and 27 share appendices with their corresponding paradigm chapters, as they are case studies of those architectures.*

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
