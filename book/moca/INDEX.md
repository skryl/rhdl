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

### Part II: Physical and Natural Computation

- [05 - Mechanical Computation](05-mechanical-computation.md) - Babbage, Ada Lovelace, Zuse, and relay computers
- [06 - Biological Computation](06-biological-computation.md) - DNA computing, neurons as gates, cellular automata
- [07 - Analog Computing](07-analog-computing.md) - Continuous values: op-amps, integrators, and differential equations in real-time
- [08 - Computing with Memory](08-computing-with-memory.md) - LUTs, truth tables, ROM microcode, CAM, memoization, and the compute-vs-store tradeoff

### Part III: Sequential Architectures

- [09 - Stack Machines](09-stack-machines.md) - Forth, JVM, and the simplest computer architecture
- [10 - Register Machines](10-register-machines.md) - The von Neumann architecture that dominates modern computing
- [11 - Modern CPU Architectures](11-modern-cpu-architectures.md) - Pipelining, superscalar execution, out-of-order, and speculation

### Part IV: Parallel and Distributed Architectures

- [12 - Message Passing Systems](12-message-passing.md) - MPI, CSP, actors, and communication as the basis of parallel computation
- [13 - Distributed Shared Memory](13-distributed-shared-memory.md) - NUMA, cache coherence, directory protocols, and the illusion of shared state
- [14 - GPU and Vector Architecture](14-gpu-vector-architecture.md) - From Cray vectors to CUDA: SIMD, SIMT, and massively parallel computing

### Part V: Dataflow and Spatial Architectures

- [15 - Dataflow Computation](15-dataflow-computation.md) - Data-driven execution, token machines, and deterministic pipelines
- [16 - Systolic Arrays](16-systolic-arrays.md) - Regular structures, matrix operations, and modern AI accelerators
- [17 - Wafer-Scale Computing](17-wafer-scale.md) - Using entire wafers: 2D mesh NoC, dataflow at extreme scale

### Part VI: Brain-Inspired Architectures

- [18 - Neural Networks](18-neural-networks.md) - Perceptrons to transformers: layers, backpropagation, and hardware acceleration
- [19 - Neuromorphic Computing](19-neuromorphic-computing.md) - Spiking neurons, STDP, memristors, and event-driven computation

### Part VII: Reconfigurable Computing

- [20 - FPGAs](20-fpga.md) - Field-programmable gate arrays: LUTs, CLBs, routing, and fine-grained reconfiguration
- [21 - Coarse-Grained Reconfigurable Arrays](21-cgra.md) - CGRAs: word-level datapaths, spatial computing, and domain-specific acceleration

### Part VIII: Alternative Substrates

- [22 - Asynchronous Computing](22-asynchronous-computing.md) - Clockless circuits: self-timed logic, handshaking, and NULL convention
- [23 - Photonic Computing](23-photonic-computing.md) - Computing with light: MZI meshes, optical matrix multiply, and interference

### Part IX: Non-Classical Computing

- [24 - Stochastic Computing](24-stochastic-computing.md) - Probability as data: AND gates multiply, MUX gates add
- [25 - Reversible Computation](25-reversible-computation.md) - Fredkin gates, Toffoli gates, and the thermodynamics of computing
- [26 - Quantum Computing](26-quantum-computing.md) - Qubits, superposition, entanglement, and quantum algorithms

---

## Appendices

Each appendix provides complete RHDL implementations and formal details for its corresponding chapter. Chapter 01 (Introduction) has no appendix.

- [Appendix A - Turing Machines](appendix-a-turing-machines.md) - Formal definition, examples, and universality
- [Appendix B - Lambda Calculus](appendix-b-lambda-calculus.md) - Church encodings and RHDL implementations
- [Appendix C - Interaction Nets](appendix-c-interaction-nets.md) - Agents, rules, optimal lambda reduction in RHDL
- [Appendix D - Ada Lovelace's Program](appendix-d-ada-lovelace.md) - The first program, before hardware existed
- [Appendix E - Cellular Automata](appendix-e-cellular-automata.md) - Rule 110, Game of Life, and emergent computation
- [Appendix F - Analog Simulation](appendix-f-analog.md) - Ruby simulation of op-amps, ODEs, and analog neural networks
- [Appendix G - Memory-Based Computation](appendix-g-memory-computation.md) - LUTs, CAM cells, ROM microcode, and memoization patterns in RHDL
- [Appendix H - Stack Machine ISA](appendix-h-stack-machine.md) - Complete Forth-like instruction set with RHDL implementation
- [Appendix I - Register Machine ISA](appendix-i-register-machine.md) - Complete 8-bit instruction set with RHDL CPU
- [Appendix J - Modern CPU Implementation](appendix-j-modern-cpu.md) - Pipelines, superscalar, reorder buffers, and Tomasulo's algorithm in RHDL
- [Appendix K - Message Passing Implementation](appendix-k-message-passing.md) - Channels, routers, and MPI-style primitives in RHDL
- [Appendix L - DSM/NUMA Implementation](appendix-l-dsm-numa.md) - Directory protocols, cache coherence, and NUMA simulation in RHDL
- [Appendix M - GPU and Vector Implementation](appendix-m-gpu-vector.md) - Vector registers, CUDA execution model, and RHDL streaming multiprocessor
- [Appendix N - Dataflow Architectures](appendix-n-dataflow.md) - Token machines, static vs dynamic dataflow, RHDL examples
- [Appendix O - Systolic Array Patterns](appendix-o-systolic.md) - Matrix multiply, convolution, and other array algorithms
- [Appendix P - Wafer-Scale Implementation](appendix-p-wafer-scale.md) - Mesh routers, crossbars, virtual channels, and NoC in RHDL
- [Appendix Q - Neural Network Implementation](appendix-q-neural-networks.md) - Layers, activations, backprop, and inference accelerators in RHDL
- [Appendix R - Neuromorphic Implementation](appendix-r-neuromorphic.md) - LIF neurons, STDP synapses, and spiking networks in RHDL
- [Appendix S - FPGA Implementation](appendix-s-fpga.md) - LUTs, CLBs, routing, and FPGA primitives in RHDL
- [Appendix T - CGRA Implementation](appendix-t-cgra.md) - PE arrays, interconnect, and configuration in RHDL
- [Appendix U - Asynchronous Implementation](appendix-u-asynchronous.md) - C-elements, dual-rail logic, and self-timed circuits in RHDL
- [Appendix V - Photonic Simulation](appendix-v-photonic.md) - Ruby simulation of MZIs, interference, and optical neural networks
- [Appendix W - Stochastic Implementation](appendix-w-stochastic.md) - LFSRs, stochastic multipliers, and probabilistic neural networks
- [Appendix X - Reversible Gates](appendix-x-reversible.md) - Fredkin, Toffoli, and building circuits that lose no information
- [Appendix Y - Quantum Circuits](appendix-y-quantum.md) - Quantum gate implementations and simulators

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
|                                                              |
|   Physical:    Mechanical --- Biological --- Analog --- Memory
|               (gears/relays) (DNA/neurons) (op-amps) (LUTs/CAM)|
|                                                              |
+-------------------------------------------------------------+
|                                                              |
|   Sequential:      Stack ------- Register ------- Modern CPUs |
|                   (Forth)     (von Neumann)    (pipeline/OoO) |
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
|   Brain-Inspired:     Neural Nets ------- Neuromorphic       |
|                            |                   |             |
|                            v                   v             |
|                       Perceptrons          Spiking           |
|                       transformers         neurons           |
|                                                              |
+-------------------------------------------------------------+
|                                                              |
|   Alternative      Asynchronous ----- Photonic               |
|   Substrates:           |               |                    |
|   (still classical)     v               v                    |
|                      Clockless       Light/MZI               |
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
| 07 | Analog Computing | F | Analog Simulation (Ruby) |
| 08 | Computing with Memory | G | Memory-Based Computation |
| 09 | Stack Machines | H | Stack Machine ISA |
| 10 | Register Machines | I | Register Machine ISA |
| 11 | Modern CPU Architectures | J | Modern CPU Implementation |
| 12 | Message Passing Systems | K | Message Passing Implementation |
| 13 | Distributed Shared Memory | L | DSM/NUMA Implementation |
| 14 | GPU and Vector Architecture | M | GPU and Vector Implementation |
| 15 | Dataflow Computation | N | Dataflow RHDL |
| 16 | Systolic Arrays | O | Systolic Patterns |
| 17 | Wafer-Scale Computing | P | Wafer-Scale/NoC Implementation |
| 18 | Neural Networks | Q | Neural Network Implementation |
| 19 | Neuromorphic Computing | R | Neuromorphic Implementation |
| 20 | FPGAs | S | FPGA Implementation |
| 21 | CGRAs | T | CGRA Implementation |
| 22 | Asynchronous Computing | U | Asynchronous Implementation |
| 23 | Photonic Computing | V | Photonic Simulation (Ruby) |
| 24 | Stochastic Computing | W | Stochastic Implementation |
| 25 | Reversible Computation | X | Reversible Gates |
| 26 | Quantum Computing | Y | Quantum Circuits |

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
