# SICH: Structure and Interpretation of Computer Hardware

*Building a Computer from First Principles*

---

## Table of Contents

### Part I: Building Abstractions with Gates

- [01 - Thinking in Hardware](part-1-gates/ch-01-thinking-in-hardware/ch-01-chapter.md) - The mental shift from sequential programs to parallel circuits where everything happens at once.
  - 1.1 Software vs Hardware Thinking
  - 1.2 Everything Happens at Once
  - 1.3 Wires as Values, Gates as Functions
  - 1.4 Your First Circuit in RHDL

- [02 - Elements of Digital Logic](part-1-gates/ch-02-elements-of-digital-logic/ch-02-chapter.md) - Gates as primitives, truth tables as contracts, and Boolean algebra as the language of combination.
  - 2.1 Voltage Levels and Binary
  - 2.2 The Primitive Gates: AND, OR, NOT
  - 2.3 Truth Tables as Specifications
  - 2.4 Boolean Algebra and Simplification
  - 2.5 Universal Gates: NAND and NOR

- [03 - Gates and the Processes They Generate](part-1-gates/ch-03-gates-and-processes/ch-03-chapter.md) - Propagation delay, critical paths, and how signals race through combinational networks.
  - 3.1 Propagation Delay
  - 3.2 Gate Networks and Signal Flow
  - 3.3 Critical Paths and Timing
  - 3.4 Hazards and Glitches
  - 3.5 Analyzing Circuit Performance

- [04 - Higher-Order Hardware](part-1-gates/ch-04-higher-order-hardware/ch-04-chapter.md) - Parameterized components, generate statements, and hardware that builds hardware.
  - 4.1 Components as First-Class Objects
  - 4.2 Parameterized Bit Widths
  - 4.3 Generate Loops and Replication
  - 4.4 Conditional Hardware Generation
  - 4.5 Hardware Generators in RHDL

### Part II: Building Abstractions with Circuits

- [05 - Circuit Abstraction](part-2-circuits/ch-05-circuit-abstraction/ch-05-chapter.md) - Hiding complexity behind interfaces: what a component promises vs. how it delivers.
  - 5.1 The Interface Contract
  - 5.2 Black Boxes and Encapsulation
  - 5.3 Input/Output Specifications
  - 5.4 Timing Contracts
  - 5.5 Testing Against Interfaces

- [06 - Hierarchical Circuits](part-2-circuits/ch-06-hierarchical-circuits/ch-06-chapter.md) - Building ALUs from adders, CPUs from ALUs—composition as the key to managing complexity.
  - 6.1 Half Adders and Full Adders
  - 6.2 Ripple-Carry Addition
  - 6.3 Building an ALU
  - 6.4 Hierarchical Composition
  - 6.5 Managing Complexity Through Layers

- [07 - Multiple Representations](part-2-circuits/ch-07-multiple-representations/ch-07-chapter.md) - Ripple-carry vs. carry-lookahead: same interface, different trade-offs, interchangeable implementations.
  - 7.1 The Adder Interface
  - 7.2 Ripple-Carry: Simple but Slow
  - 7.3 Carry-Lookahead: Fast but Complex
  - 7.4 Carry-Select and Hybrid Approaches
  - 7.5 Choosing Implementations

- [08 - Generic Components](part-2-circuits/ch-08-generic-components/ch-08-chapter.md) - Width as a parameter, buses as typed connections, and designs that scale.
  - 8.1 Width as a Type Parameter
  - 8.2 Buses and Multi-Bit Signals
  - 8.3 Slicing and Concatenation
  - 8.4 Type-Safe Connections
  - 8.5 Scaling to Any Width

### Part III: State and Time

- [09 - Sequential Logic and Local State](part-3-state-and-time/ch-09-sequential-logic/ch-09-chapter.md) - Flip-flops as memory elements: how feedback creates state and why clocks tame it.
  - 9.1 The Problem of State
  - 9.2 Feedback and Instability
  - 9.3 The SR Latch
  - 9.4 Edge-Triggered Flip-Flops
  - 9.5 The Clock as Synchronizer

- [10 - The Timing Model](part-3-state-and-time/ch-10-timing-model/ch-10-chapter.md) - Setup, hold, and the contract between combinational logic and sequential elements.
  - 10.1 Setup and Hold Times
  - 10.2 Clock-to-Q Delay
  - 10.3 The Timing Contract
  - 10.4 Maximum Clock Frequency
  - 10.5 Timing Violations and Failure

- [11 - Memory Systems](part-3-state-and-time/ch-11-memory-systems/ch-11-chapter.md) - RAM, ROM, caches, and the hierarchy that hides latency behind locality.
  - 11.1 Registers and Register Files
  - 11.2 Static RAM (SRAM)
  - 11.3 Read-Only Memory (ROM)
  - 11.4 The Memory Hierarchy
  - 11.5 Caches and Locality

- [12 - Concurrency and Metastability](part-3-state-and-time/ch-12-concurrency-metastability/ch-12-chapter.md) - Clock domain crossing, synchronizers, and the fundamental unsolvability of asynchronous consensus.
  - 12.1 Multiple Clock Domains
  - 12.2 The Metastability Problem
  - 12.3 Synchronizer Circuits
  - 12.4 FIFO Queues for Crossing Domains
  - 12.5 The Impossibility of Perfect Synchronization

- [13 - Pipelining and Streams](part-3-state-and-time/ch-13-pipelining-streams/ch-13-chapter.md) - Overlapping operations in time: how throughput decouples from latency.
  - 13.1 Latency vs Throughput
  - 13.2 Pipeline Stages
  - 13.3 Pipeline Registers
  - 13.4 Hazards and Stalls
  - 13.5 Streaming Data Through Pipelines

### Part IV: Computing with Register Machines

- [14 - Designing the Machine](part-4-register-machines/ch-14-designing-the-machine/ch-14-chapter.md) - Registers, ALU, memory, and control: the anatomy of a programmable computer.
  - 14.1 The von Neumann Architecture
  - 14.2 Registers: Fast Local Storage
  - 14.3 The ALU: Computation Engine
  - 14.4 Memory: Instructions and Data
  - 14.5 Control: Orchestrating Execution

- [15 - Building the CPU](part-4-register-machines/ch-15-building-the-cpu/ch-15-chapter.md) - Wiring up the datapath: from components to a working 8-bit processor in RHDL.
  - 15.1 The Datapath Block Diagram
  - 15.2 Connecting Registers to ALU
  - 15.3 The Program Counter
  - 15.4 Instruction Register and Decoder
  - 15.5 Wiring It All Together

- [16 - The Explicit-Control Datapath](part-4-register-machines/ch-16-explicit-control-datapath/ch-16-chapter.md) - Fetch-decode-execute: the microarchitecture that interprets the instruction set.
  - 16.1 The Fetch-Decode-Execute Cycle
  - 16.2 Control Signals and Sequencing
  - 16.3 Microcode: Programs for Hardware
  - 16.4 Implementing Instructions
  - 16.5 The Complete Machine

### Part V: Metalinguistic Abstraction

- [17 - The ISA as Language](part-5-metalinguistic/ch-17-isa-as-language/ch-17-chapter.md) - Machine code is a language; the CPU is its interpreter; microcode is its implementation.
  - 17.1 Machine Code as Language
  - 17.2 The CPU as Interpreter
  - 17.3 Instruction Formats and Encoding
  - 17.4 Addressing Modes
  - 17.5 The Semantic Gap

- [18 - Assembly and the Stack](part-5-metalinguistic/ch-18-assembly-and-stack/ch-18-chapter.md) - Subroutines, call/return, stack frames: the software conventions that enable recursion.
  - 18.1 Assembly Language Syntax
  - 18.2 The Stack: LIFO Memory
  - 18.3 Subroutine Call and Return
  - 18.4 Stack Frames and Local Variables
  - 18.5 Recursion in Hardware

- [19 - A Lisp Interpreter](part-5-metalinguistic/ch-19-lisp-interpreter/ch-19-chapter.md) - Eval and apply on our CPU: building a language from cons cells and recursion.
  - 19.1 S-Expressions and Cons Cells
  - 19.2 Memory Layout for Lisp
  - 19.3 The Read-Eval-Print Loop
  - 19.4 Implementing Eval
  - 19.5 Implementing Apply

- [20 - Lambda Comes Full Circle](part-5-metalinguistic/ch-20-lambda-full-circle/ch-20-chapter.md) - The revelation: muxes are Church booleans, registers are Y combinators—we were computing lambda all along.
  - 20.1 Church Booleans and Muxes
  - 20.2 Church Numerals and Counters
  - 20.3 The Y Combinator and Feedback
  - 20.4 Hardware as Lambda Calculus
  - 20.5 The Isomorphism Revealed

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
| 01 | Thinking in Hardware | [Mental Models](part-1-gates/ch-01-thinking-in-hardware/ch-01-appendix.md) |
| 02 | Elements of Digital Logic | [Gate Primitives](part-1-gates/ch-02-elements-of-digital-logic/ch-02-appendix.md) |
| 03 | Gates and Processes | [Timing Analysis](part-1-gates/ch-03-gates-and-processes/ch-03-appendix.md) |
| 04 | Higher-Order Hardware | [Generators](part-1-gates/ch-04-higher-order-hardware/ch-04-appendix.md) |
| 05 | Circuit Abstraction | [Interface Contracts](part-2-circuits/ch-05-circuit-abstraction/ch-05-appendix.md) |
| 06 | Hierarchical Circuits | [ALU Implementation](part-2-circuits/ch-06-hierarchical-circuits/ch-06-appendix.md) |
| 07 | Multiple Representations | [Adder Variants](part-2-circuits/ch-07-multiple-representations/ch-07-appendix.md) |
| 08 | Generic Components | [Parameterized Designs](part-2-circuits/ch-08-generic-components/ch-08-appendix.md) |
| 09 | Sequential Logic | [Flip-Flop Zoo](part-3-state-and-time/ch-09-sequential-logic/ch-09-appendix.md) |
| 10 | The Timing Model | [Timing Constraints](part-3-state-and-time/ch-10-timing-model/ch-10-appendix.md) |
| 11 | Memory Systems | [Memory Hierarchy](part-3-state-and-time/ch-11-memory-systems/ch-11-appendix.md) |
| 12 | Concurrency | [Synchronizers](part-3-state-and-time/ch-12-concurrency-metastability/ch-12-appendix.md) |
| 13 | Pipelining | [Pipeline Stages](part-3-state-and-time/ch-13-pipelining-streams/ch-13-appendix.md) |
| 14 | Designing the Machine | [CPU Block Diagram](part-4-register-machines/ch-14-designing-the-machine/ch-14-appendix.md) |
| 15 | Building the CPU | [Complete CPU](part-4-register-machines/ch-15-building-the-cpu/ch-15-appendix.md) |
| 16 | Explicit-Control | [Microcode](part-4-register-machines/ch-16-explicit-control-datapath/ch-16-appendix.md) |
| 17 | ISA as Language | [Instruction Set](part-5-metalinguistic/ch-17-isa-as-language/ch-17-appendix.md) |
| 18 | Assembly and Stack | [Calling Convention](part-5-metalinguistic/ch-18-assembly-and-stack/ch-18-appendix.md) |
| 19 | Lisp Interpreter | [Eval/Apply](part-5-metalinguistic/ch-19-lisp-interpreter/ch-19-appendix.md) |
| 20 | Lambda Full Circle | [The Isomorphism](part-5-metalinguistic/ch-20-lambda-full-circle/ch-20-appendix.md) |

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
