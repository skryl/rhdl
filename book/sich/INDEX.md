# SICH: Structure and Interpretation of Computer Hardware

*Building a Computer from First Principles*

---

## Table of Contents

### Part I: Building Abstractions with Gates

- [01 - Thinking in Hardware](part-1-gates/ch-01-thinking-in-hardware/chapter.md) - The mental shift from sequential programs to parallel circuits where everything happens at once.
- [02 - Elements of Digital Logic](part-1-gates/ch-02-elements-of-digital-logic/chapter.md) - Gates as primitives, truth tables as contracts, and Boolean algebra as the language of combination.
- [03 - Gates and the Processes They Generate](part-1-gates/ch-03-gates-and-processes/chapter.md) - Propagation delay, critical paths, and how signals race through combinational networks.
- [04 - Higher-Order Hardware](part-1-gates/ch-04-higher-order-hardware/chapter.md) - Parameterized components, generate statements, and hardware that builds hardware.

### Part II: Building Abstractions with Circuits

- [05 - Circuit Abstraction](part-2-circuits/ch-05-circuit-abstraction/chapter.md) - Hiding complexity behind interfaces: what a component promises vs. how it delivers.
- [06 - Hierarchical Circuits](part-2-circuits/ch-06-hierarchical-circuits/chapter.md) - Building ALUs from adders, CPUs from ALUs—composition as the key to managing complexity.
- [07 - Multiple Representations](part-2-circuits/ch-07-multiple-representations/chapter.md) - Ripple-carry vs. carry-lookahead: same interface, different trade-offs, interchangeable implementations.
- [08 - Generic Components](part-2-circuits/ch-08-generic-components/chapter.md) - Width as a parameter, buses as typed connections, and designs that scale.

### Part III: State and Time

- [09 - Sequential Logic and Local State](part-3-state-and-time/ch-09-sequential-logic/chapter.md) - Flip-flops as memory elements: how feedback creates state and why clocks tame it.
- [10 - The Timing Model](part-3-state-and-time/ch-10-timing-model/chapter.md) - Setup, hold, and the contract between combinational logic and sequential elements.
- [11 - Memory Systems](part-3-state-and-time/ch-11-memory-systems/chapter.md) - RAM, ROM, caches, and the hierarchy that hides latency behind locality.
- [12 - Concurrency and Metastability](part-3-state-and-time/ch-12-concurrency-metastability/chapter.md) - Clock domain crossing, synchronizers, and the fundamental unsolvability of asynchronous consensus.
- [13 - Pipelining and Streams](part-3-state-and-time/ch-13-pipelining-streams/chapter.md) - Overlapping operations in time: how throughput decouples from latency.

### Part IV: Computing with Register Machines

- [14 - Designing the Machine](part-4-register-machines/ch-14-designing-the-machine/chapter.md) - Registers, ALU, memory, and control: the anatomy of a programmable computer.
- [15 - Building the CPU](part-4-register-machines/ch-15-building-the-cpu/chapter.md) - Wiring up the datapath: from components to a working 8-bit processor in RHDL.
- [16 - The Explicit-Control Datapath](part-4-register-machines/ch-16-explicit-control-datapath/chapter.md) - Fetch-decode-execute: the microarchitecture that interprets the instruction set.

### Part V: Metalinguistic Abstraction

- [17 - The ISA as Language](part-5-metalinguistic/ch-17-isa-as-language/chapter.md) - Machine code is a language; the CPU is its interpreter; microcode is its implementation.
- [18 - Assembly and the Stack](part-5-metalinguistic/ch-18-assembly-and-stack/chapter.md) - Subroutines, call/return, stack frames: the software conventions that enable recursion.
- [19 - A Lisp Interpreter](part-5-metalinguistic/ch-19-lisp-interpreter/chapter.md) - Eval and apply on our CPU: building a language from cons cells and recursion.
- [20 - Lambda Comes Full Circle](part-5-metalinguistic/ch-20-lambda-full-circle/chapter.md) - The revelation: muxes are Church booleans, registers are Y combinators—we were computing lambda all along.

---

## The Journey

```
Start here:                         End here:

Transistors & switches              Lambda calculus revealed
    |                                   ^
    v                                   |
Logic gates (AND, OR, NOT)          Lisp interpreter
    |                                   ^
    v                                   |
Combinational circuits              Assembly language
    |                                   ^
    v                                   |
Sequential logic & state            The ISA as language
    |                                   ^
    v                                   |
Memory systems                      CPU architecture
    |                                   |
    +-----------------------------------+
```

---

## Appendices

Each chapter has an accompanying appendix with complete RHDL implementations.

| Chapter | Topic | Appendix |
|---------|-------|----------|
| 01 | Thinking in Hardware | [Mental Models](part-1-gates/ch-01-thinking-in-hardware/appendix.md) |
| 02 | Elements of Digital Logic | [Gate Primitives](part-1-gates/ch-02-elements-of-digital-logic/appendix.md) |
| 03 | Gates and Processes | [Timing Analysis](part-1-gates/ch-03-gates-and-processes/appendix.md) |
| 04 | Higher-Order Hardware | [Generators](part-1-gates/ch-04-higher-order-hardware/appendix.md) |
| 05 | Circuit Abstraction | [Interface Contracts](part-2-circuits/ch-05-circuit-abstraction/appendix.md) |
| 06 | Hierarchical Circuits | [ALU Implementation](part-2-circuits/ch-06-hierarchical-circuits/appendix.md) |
| 07 | Multiple Representations | [Adder Variants](part-2-circuits/ch-07-multiple-representations/appendix.md) |
| 08 | Generic Components | [Parameterized Designs](part-2-circuits/ch-08-generic-components/appendix.md) |
| 09 | Sequential Logic | [Flip-Flop Zoo](part-3-state-and-time/ch-09-sequential-logic/appendix.md) |
| 10 | The Timing Model | [Timing Constraints](part-3-state-and-time/ch-10-timing-model/appendix.md) |
| 11 | Memory Systems | [Memory Hierarchy](part-3-state-and-time/ch-11-memory-systems/appendix.md) |
| 12 | Concurrency | [Synchronizers](part-3-state-and-time/ch-12-concurrency-metastability/appendix.md) |
| 13 | Pipelining | [Pipeline Stages](part-3-state-and-time/ch-13-pipelining-streams/appendix.md) |
| 14 | Designing the Machine | [CPU Block Diagram](part-4-register-machines/ch-14-designing-the-machine/appendix.md) |
| 15 | Building the CPU | [Complete CPU](part-4-register-machines/ch-15-building-the-cpu/appendix.md) |
| 16 | Explicit-Control | [Microcode](part-4-register-machines/ch-16-explicit-control-datapath/appendix.md) |
| 17 | ISA as Language | [Instruction Set](part-5-metalinguistic/ch-17-isa-as-language/appendix.md) |
| 18 | Assembly and Stack | [Calling Convention](part-5-metalinguistic/ch-18-assembly-and-stack/appendix.md) |
| 19 | Lisp Interpreter | [Eval/Apply](part-5-metalinguistic/ch-19-lisp-interpreter/appendix.md) |
| 20 | Lambda Full Circle | [The Isomorphism](part-5-metalinguistic/ch-20-lambda-full-circle/appendix.md) |

---

## SICP Correspondence

This book is an inverted SICP, ascending from hardware to lambda:

| SICP | SICH | Theme |
|------|------|-------|
| Ch 1: Procedures | Part I: Gates | Primitives, combination, abstraction |
| Ch 2: Data | Part II: Circuits | Compound structures, interfaces, generic ops |
| Ch 3: State | Part III: State and Time | Mutation, time, concurrency |
| Ch 5: Register Machines | Part IV: Register Machines | The hardware foundation |
| Ch 4: Interpreters | Part V: Metalinguistic | Languages all the way up |

---

## Companion Book

For theoretical foundations and alternative architectures, see:

**[MOCA: Models Of Computational Architectures](../moca/INDEX.md)** - Turing machines, lambda calculus, dataflow, systolic arrays, quantum computing, and the mathematical foundations of computation.

---

## Target Audience

Software engineers who want to understand:
- How computers actually work at the hardware level
- The connection between hardware and the languages that run on it
- Why CPUs are designed the way they are
- That lambda calculus isn't just theory—it's what the hardware computes

## Prerequisites

- Basic programming experience (any language)
- Familiarity with binary numbers helpful but not required
- No prior hardware experience needed
