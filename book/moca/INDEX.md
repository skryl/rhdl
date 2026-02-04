# MOCA: Models Of Computational Architectures

*What is Computation? From Turing Machines to Silicon*

---

## Table of Contents

### Part 0: Introduction

- [01 - What Makes an Architecture](01-what-makes-an-architecture.md) - ISA vs microarchitecture, abstraction layers, and the design space of computation
- [02 - Metrics and Limits](02-metrics-and-limits.md) - Roofline, Amdahl/Gustafson, work/span; data movement and energy as the common currency

### Part I: Theoretical Foundations

- [03 - Symbol Manipulation](03-symbol-manipulation.md) - The essence of computation: symbols, rules, and Turing machines
- [04 - Lambda Calculus](04-lambda-calculus.md) - Computation as function application
- [05 - Interaction Nets](05-interaction-nets.md) - Graph rewriting, linear logic, and optimal reduction

### Part II: Physical and Natural Computation

- [06 - Mechanical Computation](06-mechanical-computation.md) - Babbage, Ada Lovelace, Zuse, and relay computers
- [07 - Biological Computation](07-biological-computation.md) - DNA computing, neurons as gates, cellular automata
- [08 - Analog Computing](08-analog-computing.md) - Continuous values: op-amps, integrators, and differential equations in real-time

### Part III: Sequential Architectures

- [09 - Computing with Memory](09-computing-with-memory.md) - Precomputation and content addressing: LUTs, ROM microcode, CAM, and associative lookup
- [10 - Register Machines](10-register-machines.md) - The von Neumann architecture that dominates modern computing
- [11 - Stack Machines](11-stack-machines.md) - Forth, JVM, and the simplest computer architecture
- [12 - Asynchronous Computing](12-asynchronous-computing.md) - Clockless circuits: self-timed logic, bundled-data vs dual-rail, handshakes, and GALS
- [13 - Modern CPU Architectures](13-modern-cpu-architectures.md) - Pipelining, superscalar execution, out-of-order, and speculation

### Part IV: Parallel and Distributed Architectures

- [14 - Message Passing Systems](14-message-passing.md) - MPI, CSP, actors, and communication as the basis of parallel computation
- [15 - Distributed Shared Memory](15-distributed-shared-memory.md) - NUMA, cache coherence, directory protocols, and the illusion of shared state
- [16 - GPU and Vector Architecture](16-gpu-vector-architecture.md) - Vector ISA and chaining; SIMT warps and occupancy; memory coalescing and divergence

### Part V: Dataflow and Spatial Architectures

- [17 - Dataflow Computation](17-dataflow-computation.md) - Data-driven execution, token machines, and deterministic pipelines
- [18 - Systolic Arrays](18-systolic-arrays.md) - Regular structures, matrix operations, and modern AI accelerators
- [19 - Wafer-Scale Computing](19-wafer-scale.md) - Using entire wafers: 2D mesh NoC, dataflow at extreme scale

### Part VI: Brain-Inspired Architectures

- [20 - Neural Networks](20-neural-networks.md) - Perceptrons to transformers: layers, backpropagation, and hardware acceleration
- [21 - Neuromorphic Computing](21-neuromorphic-computing.md) - Spiking neurons, STDP, memristors, and event-driven computation

### Part VII: Reconfigurable Computing

- [22 - FPGAs](22-fpga.md) - Field-programmable gate arrays: LUTs, CLBs, routing, and fine-grained reconfiguration
- [23 - Coarse-Grained Reconfigurable Arrays](23-cgra.md) - CGRAs: word-level datapaths, spatial computing, and domain-specific acceleration

### Part VIII: Unconventional Computing Models

- [24 - Stochastic Computing](24-stochastic-computing.md) - Probability as data: AND gates multiply, MUX gates add
- [25 - Reversible Computation](25-reversible-computation.md) - Fredkin gates, Toffoli gates, and the thermodynamics of computing
- [26 - Photonic Computing](26-photonic-computing.md) - Computing with light: MZI meshes, optical matrix multiply, and interference
- [27 - Quantum Computing](27-quantum-computing.md) - Qubits, superposition, entanglement, and quantum algorithms

---

## Appendices

Each appendix provides complete RHDL implementations and formal details for its corresponding chapter. Chapters 01-02 (Introduction) have no appendices.

- [Appendix A - Turing Machines](appendix-a-turing-machines.md) - Formal definition, examples, and universality
- [Appendix B - Lambda Calculus](appendix-b-lambda-calculus.md) - Church encodings and RHDL implementations
- [Appendix C - Interaction Nets](appendix-c-interaction-nets.md) - Agents, rules, optimal lambda reduction in RHDL
- [Appendix D - Ada Lovelace's Program](appendix-d-ada-lovelace.md) - The first program, before hardware existed
- [Appendix E - Cellular Automata](appendix-e-cellular-automata.md) - Rule 110, Game of Life, and emergent computation
- [Appendix F - Analog Simulation](appendix-f-analog.md) - Ruby simulation of op-amps, ODEs, and analog neural networks
- [Appendix G - Memory-Based Computation](appendix-g-memory-computation.md) - LUTs, CAM cells, ROM microcode, and memoization patterns in RHDL
- [Appendix H - Register Machine ISA](appendix-h-register-machine.md) - Complete 8-bit instruction set with RHDL CPU
- [Appendix I - Stack Machine ISA](appendix-i-stack-machine.md) - Complete Forth-like instruction set with RHDL implementation
- [Appendix J - Asynchronous Implementation](appendix-j-asynchronous.md) - C-elements, dual-rail logic, and self-timed circuits in RHDL
- [Appendix K - Modern CPU Implementation](appendix-k-modern-cpu.md) - Pipelines, superscalar, reorder buffers, and Tomasulo's algorithm in RHDL
- [Appendix L - Message Passing Implementation](appendix-l-message-passing.md) - Channels, routers, and MPI-style primitives in RHDL
- [Appendix M - DSM/NUMA Implementation](appendix-m-dsm-numa.md) - Directory protocols, cache coherence, and NUMA simulation in RHDL
- [Appendix N - GPU and Vector Implementation](appendix-n-gpu-vector.md) - Vector registers, CUDA execution model, and RHDL streaming multiprocessor
- [Appendix O - Dataflow Architectures](appendix-o-dataflow.md) - Token machines, static vs dynamic dataflow, RHDL examples
- [Appendix P - Systolic Array Patterns](appendix-p-systolic.md) - Matrix multiply, convolution, and other array algorithms
- [Appendix Q - Wafer-Scale Implementation](appendix-q-wafer-scale.md) - Mesh routers, crossbars, virtual channels, and NoC in RHDL
- [Appendix R - Neural Network Implementation](appendix-r-neural-networks.md) - Layers, activations, backprop, and inference accelerators in RHDL
- [Appendix S - Neuromorphic Implementation](appendix-s-neuromorphic.md) - LIF neurons, STDP synapses, and spiking networks in RHDL
- [Appendix T - FPGA Implementation](appendix-t-fpga.md) - LUTs, CLBs, routing, and FPGA primitives in RHDL
- [Appendix U - CGRA Implementation](appendix-u-cgra.md) - PE arrays, interconnect, and configuration in RHDL
- [Appendix V - Stochastic Implementation](appendix-v-stochastic.md) - LFSRs, stochastic multipliers, and probabilistic neural networks
- [Appendix W - Reversible Gates](appendix-w-reversible.md) - Fredkin, Toffoli, and building circuits that lose no information
- [Appendix X - Photonic Simulation](appendix-x-photonic.md) - Ruby simulation of MZIs, interference, and optical neural networks
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
|   Physical:       Mechanical ----- Biological ----- Analog   |
|                  (gears/relays)   (DNA/neurons)   (op-amps)  |
|                                                              |
+-------------------------------------------------------------+
|                                                              |
|   Sequential: Memory -- Register -- Stack -- Async -- Modern CPUs|
|               (LUTs)  (von Neumann) (Forth) (clockless) (OoO)    |
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
|   Unconventional: Stochastic -- Reversible -- Photonic -- Quantum
|                       |             |            |          | |
|                      v             v            v          v |
|                  Probability    Zero        Light/MZI  Superposition
|                  as data       energy                  entanglement
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
| 02 | Metrics and Limits | — | (Introduction, no appendix) |
| 03 | Symbol Manipulation | A | Turing Machines (formal) |
| 04 | Lambda Calculus | B | Church encodings, RHDL |
| 05 | Interaction Nets | C | Agents, rules, optimal reduction |
| 06 | Mechanical Computation | D | Ada Lovelace's Program |
| 07 | Biological Computation | E | Cellular Automata |
| 08 | Analog Computing | F | Analog Simulation (Ruby) |
| 09 | Computing with Memory | G | Memory-Based Computation |
| 10 | Register Machines | H | Register Machine ISA |
| 11 | Stack Machines | I | Stack Machine ISA |
| 12 | Asynchronous Computing | J | Asynchronous Implementation |
| 13 | Modern CPU Architectures | K | Modern CPU Implementation |
| 14 | Message Passing Systems | L | Message Passing Implementation |
| 15 | Distributed Shared Memory | M | DSM/NUMA Implementation |
| 16 | GPU and Vector Architecture | N | GPU and Vector Implementation |
| 17 | Dataflow Computation | O | Dataflow RHDL |
| 18 | Systolic Arrays | P | Systolic Patterns |
| 19 | Wafer-Scale Computing | Q | Wafer-Scale/NoC Implementation |
| 20 | Neural Networks | R | Neural Network Implementation |
| 21 | Neuromorphic Computing | S | Neuromorphic Implementation |
| 22 | FPGAs | T | FPGA Implementation |
| 23 | CGRAs | U | CGRA Implementation |
| 24 | Stochastic Computing | V | Stochastic Implementation |
| 25 | Reversible Computation | W | Reversible Gates |
| 26 | Photonic Computing | X | Photonic Simulation (Ruby) |
| 27 | Quantum Computing | Y | Quantum Circuits |

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
