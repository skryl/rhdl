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
- [07 - Neural Computation](07-neural-computation.md) - Threshold circuits, perceptrons, universality, and function approximation

### Part II: Physical and Natural Computation

- [08 - Mechanical Computation](08-mechanical-computation.md) - Babbage, Ada Lovelace, Zuse, and relay computers
- [09 - Biological Computation](09-biological-computation.md) - DNA computing, neurons as gates, cellular automata
- [10 - Analog Computing](10-analog-computing.md) - Continuous values: op-amps, integrators, and differential equations in real-time

### Part III: Sequential Architectures

- [11 - Computing with Memory](11-computing-with-memory.md) - Precomputation and content addressing: LUTs, ROM microcode, CAM, and associative lookup
- [12 - Register Machines](12-register-machines.md) - The von Neumann architecture that dominates modern computing
- [13 - Stack Machines](13-stack-machines.md) - Forth, JVM, and the simplest computer architecture
- [14 - Asynchronous Computing](14-asynchronous-computing.md) - Clockless circuits: self-timed logic, bundled-data vs dual-rail, handshakes, and GALS
- [15 - Modern CPU Architectures](15-modern-cpu-architectures.md) - Pipelining, superscalar execution, out-of-order, and speculation

### Part IV: Parallel and Distributed Architectures

- [16 - Message Passing Systems](16-message-passing.md) - MPI, CSP, actors, and communication as the basis of parallel computation
- [17 - Distributed Shared Memory](17-distributed-shared-memory.md) - NUMA, cache coherence, directory protocols, and the illusion of shared state
- [18 - GPU and Vector Architecture](18-gpu-vector-architecture.md) - Vector ISA and chaining; SIMT warps and occupancy; memory coalescing and divergence

### Part V: Dataflow and Spatial Architectures

- [19 - Dataflow Computation](19-dataflow-computation.md) - Data-driven execution, token machines, and deterministic pipelines
- [20 - Systolic Arrays](20-systolic-arrays.md) - Regular structures, matrix operations, and modern AI accelerators
- [21 - Wafer-Scale Computing](21-wafer-scale.md) - Using entire wafers: 2D mesh NoC, dataflow at extreme scale

### Part VI: Brain-Inspired Architectures

- [22 - Deep Neural Networks](22-deep-neural-networks.md) - CNNs, RNNs, transformers: training dynamics, dataflow, and hardware mapping
- [23 - Neuromorphic Computing](23-neuromorphic-computing.md) - Spiking neurons, STDP, memristors, and event-driven computation

### Part VII: Reconfigurable Computing

- [24 - FPGAs](24-fpga.md) - Field-programmable gate arrays: LUTs, CLBs, routing, and fine-grained reconfiguration
- [25 - Coarse-Grained Reconfigurable Arrays](25-cgra.md) - CGRAs: word-level datapaths, spatial computing, and domain-specific acceleration

### Part VIII: Unconventional Computing Models

- [26 - Stochastic Computing](26-stochastic-computing.md) - Probability as data: AND gates multiply, MUX gates add
- [27 - Reversible Computation](27-reversible-computation.md) - Fredkin gates, Toffoli gates, and the thermodynamics of computing
- [28 - Photonic Computing](28-photonic-computing.md) - Computing with light: MZI meshes, optical matrix multiply, and interference
- [29 - Quantum Computing](29-quantum-computing.md) - Qubits, superposition, entanglement, and quantum algorithms

---

## Appendices

Each appendix provides complete RHDL implementations and formal details for its corresponding chapter. Chapters 01-02 (Introduction) have no appendices.

- [Appendix A - Turing Machines](appendix-a-turing-machines.md) - Formal definition, examples, and universality
- [Appendix B - Lambda Calculus](appendix-b-lambda-calculus.md) - Church encodings and RHDL implementations
- [Appendix C - Interaction Nets](appendix-c-interaction-nets.md) - Agents, rules, optimal lambda reduction in RHDL
- [Appendix D - Boolean Circuit Implementation](appendix-d-boolean-circuits.md) - Gate primitives, circuit synthesis, and complexity examples in RHDL
- [Appendix E - Neural Computation](appendix-e-neural-computation.md) - McCulloch-Pitts neurons, perceptrons, threshold circuits, and universality proofs
- [Appendix F - Ada Lovelace's Program](appendix-f-ada-lovelace.md) - The first program, before hardware existed
- [Appendix G - Cellular Automata](appendix-g-cellular-automata.md) - Rule 110, Game of Life, and emergent computation
- [Appendix H - Analog Simulation](appendix-h-analog.md) - Ruby simulation of op-amps, ODEs, and analog neural networks
- [Appendix I - Memory-Based Computation](appendix-i-memory-computation.md) - LUTs, CAM cells, ROM microcode, and memoization patterns in RHDL
- [Appendix J - Register Machine ISA](appendix-j-register-machine.md) - Complete 8-bit instruction set with RHDL CPU
- [Appendix K - Stack Machine ISA](appendix-k-stack-machine.md) - Complete Forth-like instruction set with RHDL implementation
- [Appendix L - Asynchronous Implementation](appendix-l-asynchronous.md) - C-elements, dual-rail logic, and self-timed circuits in RHDL
- [Appendix M - Modern CPU Implementation](appendix-m-modern-cpu.md) - Pipelines, superscalar, reorder buffers, and Tomasulo's algorithm in RHDL
- [Appendix N - Message Passing Implementation](appendix-n-message-passing.md) - Channels, routers, and MPI-style primitives in RHDL
- [Appendix O - DSM/NUMA Implementation](appendix-o-dsm-numa.md) - Directory protocols, cache coherence, and NUMA simulation in RHDL
- [Appendix P - GPU and Vector Implementation](appendix-p-gpu-vector.md) - Vector registers, CUDA execution model, and RHDL streaming multiprocessor
- [Appendix Q - Dataflow Architectures](appendix-q-dataflow.md) - Token machines, static vs dynamic dataflow, RHDL examples
- [Appendix R - Systolic Array Patterns](appendix-r-systolic.md) - Matrix multiply, convolution, and other array algorithms
- [Appendix S - Wafer-Scale Implementation](appendix-s-wafer-scale.md) - Mesh routers, crossbars, virtual channels, and NoC in RHDL
- [Appendix T - Deep Learning Implementation](appendix-t-deep-learning.md) - Backprop, optimizers, and inference accelerator patterns in RHDL
- [Appendix U - Neuromorphic Implementation](appendix-u-neuromorphic.md) - LIF neurons, STDP synapses, and spiking networks in RHDL
- [Appendix V - FPGA Implementation](appendix-v-fpga.md) - LUTs, CLBs, routing, and FPGA primitives in RHDL
- [Appendix W - CGRA Implementation](appendix-w-cgra.md) - PE arrays, interconnect, and configuration in RHDL
- [Appendix X - Stochastic Implementation](appendix-x-stochastic.md) - LFSRs, stochastic multipliers, and probabilistic neural networks
- [Appendix Y - Reversible Gates](appendix-y-reversible.md) - Fredkin, Toffoli, and building circuits that lose no information
- [Appendix Z - Photonic Simulation](appendix-z-photonic.md) - Ruby simulation of MZIs, interference, and optical neural networks
- [Appendix AA - Quantum Circuits](appendix-aa-quantum.md) - Quantum gate implementations and simulators

---

## The Big Picture

```
+-------------------------------------------------------------+
|                  MODELS OF COMPUTATION                       |
+-------------------------------------------------------------+
|                                                              |
|   Theoretical:  Turing <-> Lambda <-> Interaction <-> Circuits <-> Neural
|                    |          |           |            |           |    |
|                    v          v           v            v           v    |
|   All equivalent: They compute the same things (gates/rules/thresholds) |
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
| 07 | Neural Computation | E | McCulloch-Pitts, perceptrons, threshold circuits |
| 08 | Mechanical Computation | F | Ada Lovelace's Program |
| 09 | Biological Computation | G | Cellular Automata |
| 10 | Analog Computing | H | Analog Simulation (Ruby) |
| 11 | Computing with Memory | I | Memory-Based Computation |
| 12 | Register Machines | J | Register Machine ISA |
| 13 | Stack Machines | K | Stack Machine ISA |
| 14 | Asynchronous Computing | L | Asynchronous Implementation |
| 15 | Modern CPU Architectures | M | Modern CPU Implementation |
| 16 | Message Passing Systems | N | Message Passing Implementation |
| 17 | Distributed Shared Memory | O | DSM/NUMA Implementation |
| 18 | GPU and Vector Architecture | P | GPU and Vector Implementation |
| 19 | Dataflow Computation | Q | Dataflow RHDL |
| 20 | Systolic Arrays | R | Systolic Patterns |
| 21 | Wafer-Scale Computing | S | Wafer-Scale/NoC Implementation |
| 22 | Deep Neural Networks | T | Deep Learning Implementation |
| 23 | Neuromorphic Computing | U | Neuromorphic Implementation |
| 24 | FPGAs | V | FPGA Implementation |
| 25 | CGRAs | W | CGRA Implementation |
| 26 | Stochastic Computing | X | Stochastic Implementation |
| 27 | Reversible Computation | Y | Reversible Gates |
| 28 | Photonic Computing | Z | Photonic Simulation (Ruby) |
| 29 | Quantum Computing | AA | Quantum Circuits |

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
