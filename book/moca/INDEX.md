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

### Part IV: Brain-Inspired Architectures

- [13 - Neural Networks](13-neural-networks.md) - Perceptrons to transformers: layers, backpropagation, and hardware acceleration
- [14 - Neuromorphic Computing](14-neuromorphic-computing.md) - Spiking neurons, STDP, memristors, and event-driven computation

### Part V: Alternative Substrates

- [15 - Asynchronous Computing](15-asynchronous-computing.md) - Clockless circuits: self-timed logic, handshaking, and NULL convention
- [16 - Photonic Computing](16-photonic-computing.md) - Computing with light: MZI meshes, optical matrix multiply, and interference
- [17 - Analog Computing](17-analog-computing.md) - Continuous values: op-amps, integrators, and differential equations in real-time

### Part VI: Reconfigurable Computing

- [18 - FPGAs](18-fpga.md) - Field-programmable gate arrays: LUTs, CLBs, routing, and fine-grained reconfiguration
- [19 - Coarse-Grained Reconfigurable Arrays](19-cgra.md) - CGRAs: word-level datapaths, spatial computing, and domain-specific acceleration

### Part VII: Non-Classical Computing

- [20 - Stochastic Computing](20-stochastic-computing.md) - Probability as data: AND gates multiply, MUX gates add
- [21 - Reversible Computation](21-reversible-computation.md) - Fredkin gates, Toffoli gates, and the thermodynamics of computing
- [22 - Quantum Computing](22-quantum-computing.md) - Qubits, superposition, entanglement, and quantum algorithms

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
- [Appendix M - Neural Network Implementation](appendix-m-neural-networks.md) - Layers, activations, backprop, and inference accelerators in RHDL
- [Appendix N - Neuromorphic Implementation](appendix-n-neuromorphic.md) - LIF neurons, STDP synapses, and spiking networks in RHDL
- [Appendix O - Asynchronous Implementation](appendix-o-asynchronous.md) - C-elements, dual-rail logic, and self-timed circuits in RHDL
- [Appendix P - Photonic Simulation](appendix-p-photonic.md) - Ruby simulation of MZIs, interference, and optical neural networks
- [Appendix Q - Analog Simulation](appendix-q-analog.md) - Ruby simulation of op-amps, ODEs, and analog neural networks
- [Appendix R - FPGA Implementation](appendix-r-fpga.md) - LUTs, CLBs, routing, and FPGA primitives in RHDL
- [Appendix S - CGRA Implementation](appendix-s-cgra.md) - PE arrays, interconnect, and configuration in RHDL
- [Appendix T - Stochastic Implementation](appendix-t-stochastic.md) - LFSRs, stochastic multipliers, and probabilistic neural networks
- [Appendix U - Reversible Gates](appendix-u-reversible.md) - Fredkin, Toffoli, and building circuits that lose no information
- [Appendix V - Quantum Circuits](appendix-v-quantum.md) - Quantum gate implementations and simulators

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
|   Brain-Inspired:  Neural Networks --- Neuromorphic          |
|                         |                   |                |
|                         v                   v                |
|                    Perceptrons        Spiking neurons        |
|                    to transformers    STDP, memristors       |
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
| 13 | Neural Networks | M | Neural Network Implementation |
| 14 | Neuromorphic Computing | N | Neuromorphic Implementation |
| 15 | Asynchronous Computing | O | Asynchronous Implementation |
| 16 | Photonic Computing | P | Photonic Simulation (Ruby) |
| 17 | Analog Computing | Q | Analog Simulation (Ruby) |
| 18 | FPGAs | R | FPGA Implementation |
| 19 | CGRAs | S | CGRA Implementation |
| 20 | Stochastic Computing | T | Stochastic Implementation |
| 21 | Reversible Computation | U | Reversible Gates |
| 22 | Quantum Computing | V | Quantum Circuits |

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
