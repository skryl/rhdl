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

### Part III: Parallel and Distributed Architectures

- [08 - Message Passing Systems](08-message-passing.md) - MPI, CSP, actors, and communication as the basis of parallel computation
- [09 - Distributed Shared Memory](09-distributed-shared-memory.md) - NUMA, cache coherence, directory protocols, and the illusion of shared state
- [10 - GPU Architecture](10-gpu-architecture.md) - SIMD/SIMT execution, streaming multiprocessors, and massively parallel computing
- [11 - Vector Processing](11-vector-processing.md) - SIMD with vector registers: pipelining, chaining, and memory banking

### Part IV: Dataflow and Spatial Architectures

- [12 - Dataflow Computation](12-dataflow-computation.md) - Data-driven execution, token machines, and deterministic pipelines
- [13 - Systolic Arrays](13-systolic-arrays.md) - Regular structures, matrix operations, and modern AI accelerators
- [14 - Wafer-Scale Computing](14-wafer-scale.md) - Using entire wafers: 2D mesh NoC, dataflow at extreme scale

### Part V: Brain-Inspired Architectures

- [15 - Neural Networks](15-neural-networks.md) - Perceptrons to transformers: layers, backpropagation, and hardware acceleration
- [16 - Neuromorphic Computing](16-neuromorphic-computing.md) - Spiking neurons, STDP, memristors, and event-driven computation
- [17 - Associative Memory](17-associative-memory.md) - Content-addressable memory, Hopfield networks, and processing-in-memory

### Part VI: Reconfigurable Computing

- [18 - FPGAs](18-fpga.md) - Field-programmable gate arrays: LUTs, CLBs, routing, and fine-grained reconfiguration
- [19 - Coarse-Grained Reconfigurable Arrays](19-cgra.md) - CGRAs: word-level datapaths, spatial computing, and domain-specific acceleration

### Part VII: Alternative Substrates

- [20 - Asynchronous Computing](20-asynchronous-computing.md) - Clockless circuits: self-timed logic, handshaking, and NULL convention
- [21 - Photonic Computing](21-photonic-computing.md) - Computing with light: MZI meshes, optical matrix multiply, and interference
- [22 - Analog Computing](22-analog-computing.md) - Continuous values: op-amps, integrators, and differential equations in real-time

### Part VIII: Non-Classical Computing

- [23 - Stochastic Computing](23-stochastic-computing.md) - Probability as data: AND gates multiply, MUX gates add
- [24 - Reversible Computation](24-reversible-computation.md) - Fredkin gates, Toffoli gates, and the thermodynamics of computing
- [25 - Quantum Computing](25-quantum-computing.md) - Qubits, superposition, entanglement, and quantum algorithms

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
- [Appendix H - Message Passing Implementation](appendix-h-message-passing.md) - Channels, routers, and MPI-style primitives in RHDL
- [Appendix I - DSM/NUMA Implementation](appendix-i-dsm-numa.md) - Directory protocols, cache coherence, and NUMA simulation in RHDL
- [Appendix J - GPU Implementation](appendix-j-gpu.md) - CUDA-like execution model and RHDL streaming multiprocessor
- [Appendix K - Vector Implementation](appendix-k-vector.md) - Vector registers, chaining controller, and banked memory in RHDL
- [Appendix L - Dataflow Architectures](appendix-l-dataflow.md) - Token machines, static vs dynamic dataflow, RHDL examples
- [Appendix M - Systolic Array Patterns](appendix-m-systolic.md) - Matrix multiply, convolution, and other array algorithms
- [Appendix N - Wafer-Scale Implementation](appendix-n-wafer-scale.md) - Mesh routers, crossbars, virtual channels, and NoC in RHDL
- [Appendix O - Neural Network Implementation](appendix-o-neural-networks.md) - Layers, activations, backprop, and inference accelerators in RHDL
- [Appendix P - Neuromorphic Implementation](appendix-p-neuromorphic.md) - LIF neurons, STDP synapses, and spiking networks in RHDL
- [Appendix Q - Associative Memory Implementation](appendix-q-associative-memory.md) - CAM cells, Hopfield networks, and PIM architectures in RHDL
- [Appendix R - FPGA Implementation](appendix-r-fpga.md) - LUTs, CLBs, routing, and FPGA primitives in RHDL
- [Appendix S - CGRA Implementation](appendix-s-cgra.md) - PE arrays, interconnect, and configuration in RHDL
- [Appendix T - Asynchronous Implementation](appendix-t-asynchronous.md) - C-elements, dual-rail logic, and self-timed circuits in RHDL
- [Appendix U - Photonic Simulation](appendix-u-photonic.md) - Ruby simulation of MZIs, interference, and optical neural networks
- [Appendix V - Analog Simulation](appendix-v-analog.md) - Ruby simulation of op-amps, ODEs, and analog neural networks
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
|                    (+ Cellular Automata)                     |
|                                                              |
+-------------------------------------------------------------+
|                                                              |
|   Sequential:      Stack ----------- Register                |
|                    (operand stack)  (von Neumann)            |
|                                                              |
|   Parallel:    Message Passing --- DSM/NUMA --- GPU - Vector |
|                (MPI, actors)     (coherence)  (SIMT) (SIMD)  |
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
| 08 | Message Passing Systems | H | Message Passing Implementation |
| 09 | Distributed Shared Memory | I | DSM/NUMA Implementation |
| 10 | GPU Architecture | J | GPU Implementation |
| 11 | Vector Processing | K | Vector Implementation |
| 12 | Dataflow Computation | L | Dataflow RHDL |
| 13 | Systolic Arrays | M | Systolic Patterns |
| 14 | Wafer-Scale Computing | N | Wafer-Scale/NoC Implementation |
| 15 | Neural Networks | O | Neural Network Implementation |
| 16 | Neuromorphic Computing | P | Neuromorphic Implementation |
| 17 | Associative Memory | Q | Associative Memory Implementation |
| 18 | FPGAs | R | FPGA Implementation |
| 19 | CGRAs | S | CGRA Implementation |
| 20 | Asynchronous Computing | T | Asynchronous Implementation |
| 21 | Photonic Computing | U | Photonic Simulation (Ruby) |
| 22 | Analog Computing | V | Analog Simulation (Ruby) |
| 23 | Stochastic Computing | W | Stochastic Implementation |
| 24 | Reversible Computation | X | Reversible Gates |
| 25 | Quantum Computing | Y | Quantum Circuits |

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
