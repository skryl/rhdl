# MOCA: Models Of Computational Architectures

*What is Computation? From Turing Machines to Silicon*

---

## Table of Contents

### Part 0: Introduction

- [01 - What Makes an Architecture](01-what-makes-an-architecture.md) - ISA vs microarchitecture, abstraction layers, and the design space of computation
- [02 - Metrics and Limits](02-metrics-and-limits.md) - Roofline, Amdahl/Gustafson, work/span; data movement and energy as the common currency

### Part I: Theoretical Computation

- [03 - Symbol Manipulation](03-symbol-manipulation.md) - The essence of computation: symbols, rules, and Turing machines
- [04 - Lambda Calculus](04-lambda-calculus.md) - Computation as function application
- [05 - Interaction Nets](05-interaction-nets.md) - Graph rewriting, linear logic, and optimal reduction
- [06 - Boolean Circuits](06-boolean-circuits.md) - Gates, depth, size, and circuit complexity classes

### Part II: Physical and Natural Computation

- [07 - Mechanical Computation](07-mechanical-computation.md) - Babbage, Ada Lovelace, Zuse, and relay computers
- [08 - Biological Computation](08-biological-computation.md) - DNA computing, neurons as gates, cellular automata
- [09 - Analog Computing](09-analog-computing.md) - Continuous values: op-amps, integrators, and differential equations in real-time

### Part III: Sequential Architectures

- [10 - Computing with Memory](10-computing-with-memory.md) - Precomputation and content addressing: LUTs, ROM microcode, CAM, and associative lookup
- [11 - Register Machines](11-register-machines.md) - The von Neumann architecture that dominates modern computing
- [12 - Stack Machines](12-stack-machines.md) - Forth, JVM, and the simplest computer architecture
- [13 - Asynchronous Computing](13-asynchronous-computing.md) - Clockless circuits: self-timed logic, bundled-data vs dual-rail, handshakes, and GALS
- [14 - Modern CPU Architectures](14-modern-cpu-architectures.md) - Pipelining, superscalar execution, out-of-order, and speculation

### Part IV: Parallel and Distributed Architectures

- [15 - Message Passing Systems](15-message-passing.md) - MPI, CSP, actors, and communication as the basis of parallel computation
- [16 - Distributed Shared Memory](16-distributed-shared-memory.md) - NUMA, cache coherence, directory protocols, and the illusion of shared state
- [17 - GPU and Vector Architecture](17-gpu-vector-architecture.md) - Vector ISA and chaining; SIMT warps and occupancy; memory coalescing and divergence

### Part V: Dataflow and Spatial Architectures

- [18 - Dataflow Computation](18-dataflow-computation.md) - Data-driven execution, token machines, and deterministic pipelines
- [19 - Systolic Arrays](19-systolic-arrays.md) - Regular structures, matrix operations, and modern AI accelerators
- [20 - Wafer-Scale Computing](20-wafer-scale.md) - Using entire wafers: 2D mesh NoC, dataflow at extreme scale

### Part VI: Brain-Inspired Architectures

- [21 - Neural Networks](21-neural-networks.md) - Perceptrons to transformers: layers, backpropagation, and hardware acceleration
- [22 - Neuromorphic Computing](22-neuromorphic-computing.md) - Spiking neurons, STDP, memristors, and event-driven computation

### Part VII: Reconfigurable Computing

- [23 - FPGAs](23-fpga.md) - Field-programmable gate arrays: LUTs, CLBs, routing, and fine-grained reconfiguration
- [24 - Coarse-Grained Reconfigurable Arrays](24-cgra.md) - CGRAs: word-level datapaths, spatial computing, and domain-specific acceleration

### Part VIII: Unconventional Computing Models

- [25 - Stochastic Computing](25-stochastic-computing.md) - Probability as data: AND gates multiply, MUX gates add
- [26 - Reversible Computation](26-reversible-computation.md) - Fredkin gates, Toffoli gates, and the thermodynamics of computing
- [27 - Photonic Computing](27-photonic-computing.md) - Computing with light: MZI meshes, optical matrix multiply, and interference
- [28 - Quantum Computing](28-quantum-computing.md) - Qubits, superposition, entanglement, and quantum algorithms

---

## Appendices

Each appendix provides complete RHDL implementations and formal details for its corresponding chapter. Chapters 01-02 (Introduction) have no appendices.

- [Appendix A - Turing Machines](appendix-a-turing-machines.md) - Formal definition, examples, and universality
- [Appendix B - Lambda Calculus](appendix-b-lambda-calculus.md) - Church encodings and RHDL implementations
- [Appendix C - Interaction Nets](appendix-c-interaction-nets.md) - Agents, rules, optimal lambda reduction in RHDL
- [Appendix D - Boolean Circuit Implementation](appendix-d-boolean-circuits.md) - Gate primitives, circuit synthesis, and complexity examples in RHDL
- [Appendix E - Ada Lovelace's Program](appendix-e-ada-lovelace.md) - The first program, before hardware existed
- [Appendix F - Cellular Automata](appendix-f-cellular-automata.md) - Rule 110, Game of Life, and emergent computation
- [Appendix G - Analog Simulation](appendix-g-analog.md) - Ruby simulation of op-amps, ODEs, and analog neural networks
- [Appendix H - Memory-Based Computation](appendix-h-memory-computation.md) - LUTs, CAM cells, ROM microcode, and memoization patterns in RHDL
- [Appendix I - Register Machine ISA](appendix-i-register-machine.md) - Complete 8-bit instruction set with RHDL CPU
- [Appendix J - Stack Machine ISA](appendix-j-stack-machine.md) - Complete Forth-like instruction set with RHDL implementation
- [Appendix K - Asynchronous Implementation](appendix-k-asynchronous.md) - C-elements, dual-rail logic, and self-timed circuits in RHDL
- [Appendix L - Modern CPU Implementation](appendix-l-modern-cpu.md) - Pipelines, superscalar, reorder buffers, and Tomasulo's algorithm in RHDL
- [Appendix M - Message Passing Implementation](appendix-m-message-passing.md) - Channels, routers, and MPI-style primitives in RHDL
- [Appendix N - DSM/NUMA Implementation](appendix-n-dsm-numa.md) - Directory protocols, cache coherence, and NUMA simulation in RHDL
- [Appendix O - GPU and Vector Implementation](appendix-o-gpu-vector.md) - Vector registers, CUDA execution model, and RHDL streaming multiprocessor
- [Appendix P - Dataflow Architectures](appendix-p-dataflow.md) - Token machines, static vs dynamic dataflow, RHDL examples
- [Appendix Q - Systolic Array Patterns](appendix-q-systolic.md) - Matrix multiply, convolution, and other array algorithms
- [Appendix R - Wafer-Scale Implementation](appendix-r-wafer-scale.md) - Mesh routers, crossbars, virtual channels, and NoC in RHDL
- [Appendix S - Neural Network Implementation](appendix-s-neural-networks.md) - Layers, activations, backprop, and inference accelerators in RHDL
- [Appendix T - Neuromorphic Implementation](appendix-t-neuromorphic.md) - LIF neurons, STDP synapses, and spiking networks in RHDL
- [Appendix U - FPGA Implementation](appendix-u-fpga.md) - LUTs, CLBs, routing, and FPGA primitives in RHDL
- [Appendix V - CGRA Implementation](appendix-v-cgra.md) - PE arrays, interconnect, and configuration in RHDL
- [Appendix W - Stochastic Implementation](appendix-w-stochastic.md) - LFSRs, stochastic multipliers, and probabilistic neural networks
- [Appendix X - Reversible Gates](appendix-x-reversible.md) - Fredkin, Toffoli, and building circuits that lose no information
- [Appendix Y - Photonic Simulation](appendix-y-photonic.md) - Ruby simulation of MZIs, interference, and optical neural networks
- [Appendix Z - Quantum Circuits](appendix-z-quantum.md) - Quantum gate implementations and simulators

---

## The Big Picture

```
+-------------------------------------------------------------+
|                  MODELS OF COMPUTATION                       |
+-------------------------------------------------------------+
|                                                              |
|   Theoretical:  Turing <-> Lambda <-> Interaction <-> Circuits
|                    |          |           |            |     |
|                    v          v           v            v     |
|   All equivalent: They compute the same things (gates/rules) |
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
| 06 | Boolean Circuits | D | Boolean Circuit Implementation |
| 07 | Mechanical Computation | E | Ada Lovelace's Program |
| 08 | Biological Computation | F | Cellular Automata |
| 09 | Analog Computing | G | Analog Simulation (Ruby) |
| 10 | Computing with Memory | H | Memory-Based Computation |
| 11 | Register Machines | I | Register Machine ISA |
| 12 | Stack Machines | J | Stack Machine ISA |
| 13 | Asynchronous Computing | K | Asynchronous Implementation |
| 14 | Modern CPU Architectures | L | Modern CPU Implementation |
| 15 | Message Passing Systems | M | Message Passing Implementation |
| 16 | Distributed Shared Memory | N | DSM/NUMA Implementation |
| 17 | GPU and Vector Architecture | O | GPU and Vector Implementation |
| 18 | Dataflow Computation | P | Dataflow RHDL |
| 19 | Systolic Arrays | Q | Systolic Patterns |
| 20 | Wafer-Scale Computing | R | Wafer-Scale/NoC Implementation |
| 21 | Neural Networks | S | Neural Network Implementation |
| 22 | Neuromorphic Computing | T | Neuromorphic Implementation |
| 23 | FPGAs | U | FPGA Implementation |
| 24 | CGRAs | V | CGRA Implementation |
| 25 | Stochastic Computing | W | Stochastic Implementation |
| 26 | Reversible Computation | X | Reversible Gates |
| 27 | Photonic Computing | Y | Photonic Simulation (Ruby) |
| 28 | Quantum Computing | Z | Quantum Circuits |

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
