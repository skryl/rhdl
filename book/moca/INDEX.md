# MOCA: Models Of Computational Architectures

*What is Computation? From Turing Machines to Silicon*

---

## Table of Contents

### Part 0: Introduction

- [01 - What Makes an Architecture](01-what-makes-an-architecture.md) - ISA vs microarchitecture, abstraction layers, and the design space of computation

### Part I: Theoretical Foundations

- [02 - Symbol Manipulation](02-symbol-manipulation.md) - The essence of computation: symbols, rules, and Turing machines
- [03 - Lambda Calculus](03-lambda-calculus.md) - Computation as function application
- [04 - Interaction Nets](04-interaction-nets.md) - Graph rewriting, linear logic, and optimal reduction
- [05 - Mechanical Computation](05-mechanical-computation.md) - Babbage, Ada Lovelace, Zuse, and relay computers
- [06 - Biological Computation](06-biological-computation.md) - DNA computing, neurons as gates, cellular automata

### Part II: Sequential Architectures

- [07 - Stack Machines](07-stack-machines.md) - Forth, JVM, and the simplest computer architecture
- [08 - Register Machines](08-register-machines.md) - The von Neumann architecture that dominates modern computing
- [09 - Pipelined Architectures](09-pipelined-architectures.md) - Instruction pipelines, hazards, forwarding, and branch prediction
- [10 - Superscalar Architectures](10-superscalar-architectures.md) - Multiple issue, out-of-order execution, register renaming, and speculation

### Part III: Parallel and Distributed Architectures

- [11 - Message Passing Systems](11-message-passing.md) - MPI, CSP, actors, and communication as the basis of parallel computation
- [12 - Distributed Shared Memory](12-distributed-shared-memory.md) - NUMA, cache coherence, directory protocols, and the illusion of shared state
- [13 - GPU and Vector Architecture](13-gpu-vector-architecture.md) - From Cray vectors to CUDA: SIMD, SIMT, and massively parallel computing

### Part IV: Dataflow and Spatial Architectures

- [14 - Dataflow Computation](14-dataflow-computation.md) - Data-driven execution, token machines, and deterministic pipelines
- [15 - Systolic Arrays](15-systolic-arrays.md) - Regular structures, matrix operations, and modern AI accelerators
- [16 - Wafer-Scale Computing](16-wafer-scale.md) - Using entire wafers: 2D mesh NoC, dataflow at extreme scale

### Part V: Brain-Inspired Architectures

- [17 - Neural Networks](17-neural-networks.md) - Perceptrons to transformers: layers, backpropagation, and hardware acceleration
- [18 - Neuromorphic Computing](18-neuromorphic-computing.md) - Spiking neurons, STDP, memristors, and event-driven computation
- [19 - Associative Memory](19-associative-memory.md) - Content-addressable memory, Hopfield networks, and processing-in-memory

### Part VI: Reconfigurable Computing

- [20 - FPGAs](20-fpga.md) - Field-programmable gate arrays: LUTs, CLBs, routing, and fine-grained reconfiguration
- [21 - Coarse-Grained Reconfigurable Arrays](21-cgra.md) - CGRAs: word-level datapaths, spatial computing, and domain-specific acceleration

### Part VII: Alternative Substrates

- [22 - Asynchronous Computing](22-asynchronous-computing.md) - Clockless circuits: self-timed logic, handshaking, and NULL convention
- [23 - Photonic Computing](23-photonic-computing.md) - Computing with light: MZI meshes, optical matrix multiply, and interference
- [24 - Analog Computing](24-analog-computing.md) - Continuous values: op-amps, integrators, and differential equations in real-time

### Part VIII: Non-Classical Computing

- [25 - Stochastic Computing](25-stochastic-computing.md) - Probability as data: AND gates multiply, MUX gates add
- [26 - Reversible Computation](26-reversible-computation.md) - Fredkin gates, Toffoli gates, and the thermodynamics of computing
- [27 - Quantum Computing](27-quantum-computing.md) - Qubits, superposition, entanglement, and quantum algorithms

---

## Appendices

Each appendix provides complete RHDL implementations and formal details for its corresponding chapter. Chapter 01 (Introduction) has no appendix.

- [Appendix A - Turing Machines](appendix-a-turing-machines.md) - Formal definition, examples, and universality
- [Appendix B - Lambda Calculus](appendix-b-lambda-calculus.md) - Church encodings and RHDL implementations
- [Appendix C - Interaction Nets](appendix-c-interaction-nets.md) - Agents, rules, optimal lambda reduction in RHDL
- [Appendix D - Ada Lovelace's Program](appendix-d-ada-lovelace.md) - The first program, before hardware existed
- [Appendix E - Cellular Automata](appendix-e-cellular-automata.md) - Rule 110, Game of Life, and emergent computation
- [Appendix F - Stack Machine ISA](appendix-f-stack-machine.md) - Complete Forth-like instruction set with RHDL implementation
- [Appendix G - Register Machine ISA](appendix-g-register-machine.md) - Complete 8-bit instruction set with RHDL CPU
- [Appendix H - Pipelined CPU Implementation](appendix-h-pipelined.md) - 5-stage pipeline, hazard detection, and forwarding in RHDL
- [Appendix I - Superscalar Implementation](appendix-i-superscalar.md) - Reorder buffer, reservation stations, and Tomasulo's algorithm in RHDL
- [Appendix J - Message Passing Implementation](appendix-j-message-passing.md) - Channels, routers, and MPI-style primitives in RHDL
- [Appendix K - DSM/NUMA Implementation](appendix-k-dsm-numa.md) - Directory protocols, cache coherence, and NUMA simulation in RHDL
- [Appendix L - GPU and Vector Implementation](appendix-l-gpu-vector.md) - Vector registers, CUDA execution model, and RHDL streaming multiprocessor
- [Appendix M - Dataflow Architectures](appendix-m-dataflow.md) - Token machines, static vs dynamic dataflow, RHDL examples
- [Appendix N - Systolic Array Patterns](appendix-n-systolic.md) - Matrix multiply, convolution, and other array algorithms
- [Appendix O - Wafer-Scale Implementation](appendix-o-wafer-scale.md) - Mesh routers, crossbars, virtual channels, and NoC in RHDL
- [Appendix P - Neural Network Implementation](appendix-p-neural-networks.md) - Layers, activations, backprop, and inference accelerators in RHDL
- [Appendix Q - Neuromorphic Implementation](appendix-q-neuromorphic.md) - LIF neurons, STDP synapses, and spiking networks in RHDL
- [Appendix R - Associative Memory Implementation](appendix-r-associative-memory.md) - CAM cells, Hopfield networks, and PIM architectures in RHDL
- [Appendix S - FPGA Implementation](appendix-s-fpga.md) - LUTs, CLBs, routing, and FPGA primitives in RHDL
- [Appendix T - CGRA Implementation](appendix-t-cgra.md) - PE arrays, interconnect, and configuration in RHDL
- [Appendix U - Asynchronous Implementation](appendix-u-asynchronous.md) - C-elements, dual-rail logic, and self-timed circuits in RHDL
- [Appendix V - Photonic Simulation](appendix-v-photonic.md) - Ruby simulation of MZIs, interference, and optical neural networks
- [Appendix W - Analog Simulation](appendix-w-analog.md) - Ruby simulation of op-amps, ODEs, and analog neural networks
- [Appendix X - Stochastic Implementation](appendix-x-stochastic.md) - LFSRs, stochastic multipliers, and probabilistic neural networks
- [Appendix Y - Reversible Gates](appendix-y-reversible.md) - Fredkin, Toffoli, and building circuits that lose no information
- [Appendix Z - Quantum Circuits](appendix-z-quantum.md) - Quantum gate implementations and simulators

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
|   Sequential:      Stack --- Register --- Pipelined --- Superscalar
|                   (Forth)  (von Neumann)  (stages)    (OoO, ILP) |
|                                                              |
|   Parallel:    Message Passing --- DSM/NUMA --- GPU/Vector   |
|                (MPI, actors)     (coherence)   (SIMD/SIMT)   |
|                                                              |
|   Spatial:         Dataflow ----- Systolic ----- Wafer-Scale |
|                   (tokens)      (regular)        (mesh)      |
|                                                              |
|                          Modern CPUs <---- Reconfigurable    |
|                                          (FPGA, CGRA)        |
|                                                              |
+-------------------------------------------------------------+
|                                                              |
|   Brain-Inspired:  Neural Nets -- Neuromorphic -- Associative|
|                         |              |              |      |
|                         v              v              v      |
|                    Perceptrons    Spiking       CAM, PIM,    |
|                    transformers   neurons       Hopfield     |
|                                                              |
+-------------------------------------------------------------+
|                                                              |
|   Alternative      Async ----- Photonic ----- Analog         |
|   Substrates:        |            |             |            |
|   (still classical)  v            v             v            |
|                   Clockless    Light/MZI   Continuous        |
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
16. **Memory can compute** - Content-addressable memory and associative recall blur the line between storage and processing
17. **Communication is computation** - Message passing and shared memory are dual approaches to parallel coordination
18. **Pipelining exploits temporal parallelism** - Overlapping instruction execution hides latency and increases throughput

---

## Chapter - Appendix Mapping

| Chapter | Topic | Appendix | Contents |
|---------|-------|----------|----------|
| 01 | What Makes an Architecture | — | (Introduction, no appendix) |
| 02 | Symbol Manipulation | A | Turing Machines (formal) |
| 03 | Lambda Calculus | B | Church encodings, RHDL |
| 04 | Interaction Nets | C | Agents, rules, optimal reduction |
| 05 | Mechanical Computation | D | Ada Lovelace's Program |
| 06 | Biological Computation | E | Cellular Automata |
| 07 | Stack Machines | F | Stack Machine ISA |
| 08 | Register Machines | G | Register Machine ISA |
| 09 | Pipelined Architectures | H | Pipelined CPU Implementation |
| 10 | Superscalar Architectures | I | Superscalar Implementation |
| 11 | Message Passing Systems | J | Message Passing Implementation |
| 12 | Distributed Shared Memory | K | DSM/NUMA Implementation |
| 13 | GPU and Vector Architecture | L | GPU and Vector Implementation |
| 14 | Dataflow Computation | M | Dataflow RHDL |
| 15 | Systolic Arrays | N | Systolic Patterns |
| 16 | Wafer-Scale Computing | O | Wafer-Scale/NoC Implementation |
| 17 | Neural Networks | P | Neural Network Implementation |
| 18 | Neuromorphic Computing | Q | Neuromorphic Implementation |
| 19 | Associative Memory | R | Associative Memory Implementation |
| 20 | FPGAs | S | FPGA Implementation |
| 21 | CGRAs | T | CGRA Implementation |
| 22 | Asynchronous Computing | U | Asynchronous Implementation |
| 23 | Photonic Computing | V | Photonic Simulation (Ruby) |
| 24 | Analog Computing | W | Analog Simulation (Ruby) |
| 25 | Stochastic Computing | X | Stochastic Implementation |
| 26 | Reversible Computation | Y | Reversible Gates |
| 27 | Quantum Computing | Z | Quantum Circuits |

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
