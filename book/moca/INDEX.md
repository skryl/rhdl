# MOCA: Models Of Computational Architectures

*What is Computation? From Turing Machines to Silicon*

---

## Table of Contents

### Part I: Theoretical Foundations

- [01 - Symbol Manipulation](01-symbol-manipulation.md) - The essence of computation: symbols, rules, and Turing machines
- [02 - Lambda Calculus](02-lambda-calculus.md) - Computation as function application
- [03 - Interaction Nets](03-interaction-nets.md) - Graph rewriting, linear logic, and optimal reduction
- [04 - Mechanical Computation](04-mechanical-computation.md) - Babbage, Ada Lovelace, Zuse, and relay computers
- [05 - Biological Computation](05-biological-computation.md) - DNA computing, neurons as gates, cellular automata

### Part II: Sequential Architectures

- [06 - Stack Machines](06-stack-machines.md) - Forth, JVM, and the simplest computer architecture
- [07 - Register Machines](07-register-machines.md) - The von Neumann architecture that dominates modern computing

### Part III: Dataflow and Spatial Architectures

- [08 - Dataflow Computation](08-dataflow-computation.md) - Data-driven execution, token machines, and deterministic pipelines
- [09 - Systolic Arrays](09-systolic-arrays.md) - Regular structures, matrix operations, and modern AI accelerators
- [10 - GPU Architecture](10-gpu-architecture.md) - SIMD/SIMT execution, streaming multiprocessors, and massively parallel computing
- [11 - Wafer-Scale Computing](11-wafer-scale.md) - Using entire wafers: 2D mesh NoC, dataflow at extreme scale
- [12 - Vector Processing](12-vector-processing.md) - SIMD with vector registers: pipelining, chaining, and memory banking

### Part IV: Non-Classical Computing

- [13 - Stochastic Computing](13-stochastic-computing.md) - Probability as data: AND gates multiply, MUX gates add
- [14 - Reversible Computation](14-reversible-computation.md) - Fredkin gates, Toffoli gates, and the thermodynamics of computing
- [15 - Quantum Computing](15-quantum-computing.md) - Qubits, superposition, entanglement, and quantum algorithms

### Part V: Alternative Substrates

- [16 - Asynchronous Computing](16-asynchronous-computing.md) - Clockless circuits: self-timed logic, handshaking, and NULL convention
- [17 - Neuromorphic Computing](17-neuromorphic-computing.md) - Brain-inspired architectures: spiking neurons, STDP, and memristors
- [18 - Photonic Computing](18-photonic-computing.md) - Computing with light: MZI meshes, optical matrix multiply, and interference
- [19 - Analog Computing](19-analog-computing.md) - Continuous values: op-amps, integrators, and differential equations in real-time

### Part VI: Reconfigurable Computing

- [20 - FPGAs](20-fpga.md) - Field-programmable gate arrays: LUTs, CLBs, routing, and fine-grained reconfiguration
- [21 - Coarse-Grained Reconfigurable Arrays](21-cgra.md) - CGRAs: word-level datapaths, spatial computing, and domain-specific acceleration

---

## Appendices

Each appendix provides complete RHDL implementations and formal details for its corresponding chapter.

- [Appendix A - Turing Machines](appendix-a-turing-machines.md) - Formal definition, examples, and universality
- [Appendix B - Lambda Calculus](appendix-b-lambda-calculus.md) - Church encodings and RHDL implementations
- [Appendix C - Interaction Nets](appendix-c-interaction-nets.md) - Agents, rules, optimal lambda reduction in RHDL
- [Appendix D - Ada Lovelace's Program](appendix-d-ada-lovelace.md) - The first program, before hardware existed
- [Appendix E - Cellular Automata](appendix-e-cellular-automata.md) - Rule 110, Game of Life, and emergent computation
- [Appendix F - Stack Machine ISA](appendix-f-stack-machine.md) - Complete Forth-like instruction set with RHDL implementation
- [Appendix G - Register Machine ISA](appendix-g-register-machine.md) - Complete 8-bit instruction set with RHDL CPU
- [Appendix H - Dataflow Architectures](appendix-h-dataflow.md) - Token machines, static vs dynamic dataflow, RHDL examples
- [Appendix I - Systolic Array Patterns](appendix-i-systolic.md) - Matrix multiply, convolution, and other array algorithms
- [Appendix J - GPU Implementation](appendix-j-gpu.md) - CUDA-like execution model and RHDL streaming multiprocessor
- [Appendix K - Wafer-Scale Implementation](appendix-k-wafer-scale.md) - Mesh routers, crossbars, virtual channels, and NoC in RHDL
- [Appendix L - Vector Implementation](appendix-l-vector.md) - Vector registers, chaining controller, and banked memory in RHDL
- [Appendix M - Stochastic Implementation](appendix-m-stochastic.md) - LFSRs, stochastic multipliers, and probabilistic neural networks
- [Appendix N - Reversible Gates](appendix-n-reversible.md) - Fredkin, Toffoli, and building circuits that lose no information
- [Appendix O - Quantum Circuits](appendix-o-quantum.md) - Quantum gate implementations and simulators
- [Appendix P - Asynchronous Implementation](appendix-p-asynchronous.md) - C-elements, dual-rail logic, and self-timed circuits in RHDL
- [Appendix Q - Neuromorphic Implementation](appendix-q-neuromorphic.md) - LIF neurons, STDP synapses, and spiking networks in RHDL
- [Appendix R - Photonic Simulation](appendix-r-photonic.md) - Ruby simulation of MZIs, interference, and optical neural networks
- [Appendix S - Analog Simulation](appendix-s-analog.md) - Ruby simulation of op-amps, ODEs, and analog neural networks
- [Appendix T - FPGA Implementation](appendix-t-fpga.md) - LUTs, CLBs, routing, and FPGA primitives in RHDL
- [Appendix U - CGRA Implementation](appendix-u-cgra.md) - PE arrays, interconnect, and configuration in RHDL

---

## The Big Picture

```
+-------------------------------------------------------------+
|                  MODELS OF COMPUTATION                       |
+-------------------------------------------------------------+
|                                                              |
|   Theoretical:     Turing <-> Lambda <-> Interaction Nets    |
|                      |          |            |               |
|                      v          v            v               |
|   All equivalent:  They compute the same things              |
|                    (+ Cellular Automata)                     |
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
| 03 | Interaction Nets | C | Agents, rules, optimal reduction |
| 04 | Mechanical Computation | D | Ada Lovelace's Program |
| 05 | Biological Computation | E | Cellular Automata |
| 06 | Stack Machines | F | Stack Machine ISA |
| 07 | Register Machines | G | Register Machine ISA |
| 08 | Dataflow Computation | H | Dataflow RHDL |
| 09 | Systolic Arrays | I | Systolic Patterns |
| 10 | GPU Architecture | J | GPU Implementation |
| 11 | Wafer-Scale Computing | K | Wafer-Scale/NoC Implementation |
| 12 | Vector Processing | L | Vector Implementation |
| 13 | Stochastic Computing | M | Stochastic Implementation |
| 14 | Reversible Computation | N | Reversible Gates |
| 15 | Quantum Computing | O | Quantum Circuits |
| 16 | Asynchronous Computing | P | Asynchronous Implementation |
| 17 | Neuromorphic Computing | Q | Neuromorphic Implementation |
| 18 | Photonic Computing | R | Photonic Simulation (Ruby) |
| 19 | Analog Computing | S | Analog Simulation (Ruby) |
| 20 | FPGAs | T | FPGA Implementation |
| 21 | CGRAs | U | CGRA Implementation |

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
