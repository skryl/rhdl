# SICH: Structure and Interpretation of Computer Hardware

*Building a Computer from First Principles*

---

## Table of Contents

### Part I: Building Abstractions with Gates

- [01 - Thinking in Hardware](part-1-gates/ch-01-thinking-in-hardware/ch-01-chapter.md) - The mental shift from sequential programs to parallel circuits where everything happens at once.

  - **Software vs Hardware Thinking** - In software, statements execute one after another. In hardware, all wires carry their values simultaneously. We explore why this difference matters and how to rewire your intuition.

  - **Everything Happens at Once** - A circuit has no "first" or "next"—every gate computes continuously. We examine the implications of massive parallelism and why hardware designers think spatially rather than temporally.

  - **Wires as Values, Gates as Functions** - Wires don't "store" values; they *are* values. Gates are pure functions from inputs to outputs. This functional perspective makes hardware surprisingly elegant.

  - **Your First Circuit in RHDL** - We build a simple circuit in Ruby, seeing how RHDL captures hardware structure. The simulation runs and we observe signals propagating through gates.

- [02 - Elements of Digital Logic](part-1-gates/ch-02-elements-of-digital-logic/ch-02-chapter.md) - Gates as primitives, truth tables as contracts, and Boolean algebra as the language of combination.

  - **Voltage Levels and Binary** - Analog voltages become digital symbols through thresholds. We see how noise margins provide reliability and why binary dominates over multi-valued logic.

  - **The Primitive Gates: AND, OR, NOT** - The three fundamental operations and their physical implementations. Each gate is a tiny decision-maker, and together they can compute anything.

  - **Truth Tables as Specifications** - A truth table completely specifies a gate's behavior for all possible inputs. We learn to read, write, and think in truth tables as the language of combinational logic.

  - **Boolean Algebra and Simplification** - DeMorgan's laws, distributivity, and the algebra that lets us transform circuits while preserving function. Simpler circuits mean fewer gates, less power, and higher speed.

  - **Universal Gates: NAND and NOR** - A single gate type can build any logic function. We prove universality and see why real chips often use only NAND or only NOR gates.

- [03 - Gates and the Processes They Generate](part-1-gates/ch-03-gates-and-processes/ch-03-chapter.md) - Propagation delay, critical paths, and how signals race through combinational networks.

  - **Propagation Delay** - Gates don't switch instantly—each has a delay from input change to output change. We measure delays in nanoseconds and see how they accumulate through chains of gates.

  - **Gate Networks and Signal Flow** - Signals ripple through networks like waves. We trace signal paths and visualize how information flows from inputs to outputs through the gate fabric.

  - **Critical Paths and Timing** - The longest path determines how fast the circuit can run. We identify critical paths and understand why they limit performance.

  - **Hazards and Glitches** - When multiple paths have different delays, outputs can glitch momentarily. We classify hazards and learn when they matter and when they don't.

  - **Analyzing Circuit Performance** - Putting it together: gate counts, delay analysis, and the area-time tradeoff. We develop intuition for what makes a circuit "good."

- [04 - Higher-Order Hardware](part-1-gates/ch-04-higher-order-hardware/ch-04-chapter.md) - Parameterized components, generate statements, and hardware that builds hardware.

  - **Components as First-Class Objects** - In RHDL, components are Ruby classes. We can pass them as parameters, store them in collections, and generate them programmatically.

  - **Parameterized Bit Widths** - An 8-bit adder and a 32-bit adder share the same structure. We parameterize by width, creating components that scale to any size.

  - **Generate Loops and Replication** - Hardware "for loops" don't iterate—they unroll into parallel copies. We generate arrays of gates and regular structures from concise descriptions.

  - **Conditional Hardware Generation** - Different parameters can produce structurally different circuits. We use Ruby's full power to make compile-time decisions about hardware structure.

  - **Hardware Generators in RHDL** - Meta-programming for circuits: functions that return component classes. We build a library of generators and see how abstraction scales.

### Part II: Building Abstractions with Circuits

- [05 - Circuit Abstraction](part-2-circuits/ch-05-circuit-abstraction/ch-05-chapter.md) - Hiding complexity behind interfaces: what a component promises vs. how it delivers.

  - **The Interface Contract** - An interface specifies inputs, outputs, and behavior—but not implementation. We separate "what" from "how" and gain the freedom to change one without affecting the other.

  - **Black Boxes and Encapsulation** - Once an interface is defined, the implementation becomes a black box. Users depend only on the contract, not the internals.

  - **Input/Output Specifications** - Precise specifications of valid inputs and guaranteed outputs. We write specifications that are complete enough to verify correctness.

  - **Timing Contracts** - Beyond functional correctness: how long does an operation take? We specify timing as part of the interface and verify implementations meet the contract.

  - **Testing Against Interfaces** - Test cases derived from interfaces, not implementations. We build test harnesses that work for any conforming implementation.

- [06 - Hierarchical Circuits](part-2-circuits/ch-06-hierarchical-circuits/ch-06-chapter.md) - Building ALUs from adders, CPUs from ALUs—composition as the key to managing complexity.

  - **Half Adders and Full Adders** - The simplest arithmetic circuits: adding two bits, then adding three. We build our first hierarchical component.

  - **Ripple-Carry Addition** - Chaining full adders to add multi-bit numbers. The carry ripples from bit to bit, and we see our first performance bottleneck.

  - **Building an ALU** - Combining adders, logic units, and multiplexers into an Arithmetic Logic Unit. The ALU becomes the computational heart of our eventual CPU.

  - **Hierarchical Composition** - Components containing components containing components. We manage complexity through hierarchy, each level hiding the details of the level below.

  - **Managing Complexity Through Layers** - Design patterns for hardware: how to partition functionality, where to draw abstraction boundaries, and when to expose details.

- [07 - Multiple Representations](part-2-circuits/ch-07-multiple-representations/ch-07-chapter.md) - Ripple-carry vs. carry-lookahead: same interface, different trade-offs, interchangeable implementations.

  - **The Adder Interface** - All adders take two numbers and produce a sum. We define the interface precisely, independent of any implementation.

  - **Ripple-Carry: Simple but Slow** - The straightforward implementation: chain full adders. Simple to understand, easy to build, but the carry chain limits speed.

  - **Carry-Lookahead: Fast but Complex** - Compute all carries in parallel using clever Boolean expressions. Much faster, but requires more gates and more complex wiring.

  - **Carry-Select and Hybrid Approaches** - Speculate on the carry, compute both possibilities, then select. We explore the design space between simple and fast.

  - **Choosing Implementations** - Given constraints on area, speed, and power, which implementation wins? We develop frameworks for making these engineering decisions.

- [08 - Generic Components](part-2-circuits/ch-08-generic-components/ch-08-chapter.md) - Width as a parameter, buses as typed connections, and designs that scale.

  - **Width as a Type Parameter** - A register is a register whether it holds 8 bits or 64. We abstract over width, writing components that work for any size.

  - **Buses and Multi-Bit Signals** - Groups of related wires treated as a single entity. Buses have widths, and operations apply to all bits in parallel.

  - **Slicing and Concatenation** - Extracting subsets of bits and joining bit vectors together. We manipulate buses with the same ease as individual wires.

  - **Type-Safe Connections** - Connecting an 8-bit output to a 16-bit input is an error. We use Ruby's type system to catch width mismatches at elaboration time.

  - **Scaling to Any Width** - From 4-bit microcontrollers to 256-bit SIMD units, the same component descriptions scale. We build a library that works at any width.

### Part III: State and Time

- [09 - Sequential Logic and Local State](part-3-state-and-time/ch-09-sequential-logic/ch-09-chapter.md) - Flip-flops as memory elements: how feedback creates state and why clocks tame it.

  - **The Problem of State** - Combinational circuits have no memory—outputs depend only on current inputs. To compute anything interesting, we need circuits that remember.

  - **Feedback and Instability** - Connecting an output back to an input creates state, but also creates problems. Unconstrained feedback leads to oscillation, races, and chaos.

  - **The SR Latch** - Our first stable memory element: two cross-coupled gates that hold a bit. We analyze its behavior and discover the forbidden state.

  - **Edge-Triggered Flip-Flops** - The D flip-flop captures its input only at clock edges. We gain predictable timing and escape the chaos of level-sensitive latches.

  - **The Clock as Synchronizer** - A global heartbeat that coordinates all state changes. The clock divides time into discrete steps, making hardware behavior tractable.

- [10 - The Timing Model](part-3-state-and-time/ch-10-timing-model/ch-10-chapter.md) - Setup, hold, and the contract between combinational logic and sequential elements.

  - **Setup and Hold Times** - Data must be stable before the clock edge (setup) and remain stable after (hold). We quantify these requirements in nanoseconds.

  - **Clock-to-Q Delay** - After the clock edge, the flip-flop's output changes. This delay is the starting point for the next cycle's computation.

  - **The Timing Contract** - Combinational logic between flip-flops must settle within one clock period. We formalize this as an inequality relating delays to clock period.

  - **Maximum Clock Frequency** - The critical path determines how fast we can clock the circuit. We calculate fmax and understand what limits performance.

  - **Timing Violations and Failure** - When setup or hold times are violated, flip-flops enter metastable states. We examine failure modes and their probabilistic consequences.

- [11 - Memory Systems](part-3-state-and-time/ch-11-memory-systems/ch-11-chapter.md) - RAM, ROM, caches, and the hierarchy that hides latency behind locality.

  - **Registers and Register Files** - Small, fast storage built from flip-flops. Register files provide multiple read and write ports for CPU datapaths.

  - **Static RAM (SRAM)** - Larger storage using six-transistor cells. We explore the tradeoff between density and speed, and see how decoders select memory locations.

  - **Read-Only Memory (ROM)** - Fixed data encoded in hardware. ROMs implement lookup tables and store programs that never change.

  - **The Memory Hierarchy** - Registers, caches, main memory, disk—each level larger and slower. We exploit locality to make memory appear both fast and large.

  - **Caches and Locality** - Small, fast memories that hold recently-used data. We examine cache organization and how hits and misses affect performance.

- [12 - Concurrency and Metastability](part-3-state-and-time/ch-12-concurrency-metastability/ch-12-chapter.md) - Clock domain crossing, synchronizers, and the fundamental unsolvability of asynchronous consensus.

  - **Multiple Clock Domains** - Real systems have multiple clocks running at different frequencies. We must safely transfer data between domains.

  - **The Metastability Problem** - When asynchronous signals meet synchronous logic, flip-flops can enter states that are neither 0 nor 1. We examine this fundamental physical phenomenon.

  - **Synchronizer Circuits** - Two or more flip-flops in series reduce metastability probability exponentially. We design synchronizers and calculate failure rates.

  - **FIFO Queues for Crossing Domains** - Asynchronous FIFOs buffer data between clock domains. We implement gray-code counters and dual-port memories for safe crossing.

  - **The Impossibility of Perfect Synchronization** - No finite circuit can guarantee zero metastability probability. We accept probabilistic correctness and design for acceptable failure rates.

- [13 - Pipelining and Streams](part-3-state-and-time/ch-13-pipelining-streams/ch-13-chapter.md) - Overlapping operations in time: how throughput decouples from latency.

  - **Latency vs Throughput** - Latency is the time for one operation; throughput is operations per second. Pipelining dramatically improves throughput while latency stays constant.

  - **Pipeline Stages** - We insert registers to divide a long computation into stages. Each stage works on a different data item, achieving parallelism in time.

  - **Pipeline Registers** - The flip-flops between stages hold intermediate results. We balance stage delays to maximize clock frequency.

  - **Hazards and Stalls** - When one stage needs a result from a later stage, we have a hazard. We detect hazards and stall the pipeline or forward results.

  - **Streaming Data Through Pipelines** - Continuous streams of data flow through pipelined circuits. We achieve near-100% utilization with proper feeding of the pipeline.

### Part IV: Computing with Register Machines

- [14 - Designing the Machine](part-4-register-machines/ch-14-designing-the-machine/ch-14-chapter.md) - Registers, ALU, memory, and control: the anatomy of a programmable computer.

  - **The von Neumann Architecture** - Instructions and data share a single memory. The CPU fetches instructions, decodes them, and executes them in sequence.

  - **Registers: Fast Local Storage** - A small set of registers holds working data. Instructions operate on registers, moving results back to memory as needed.

  - **The ALU: Computation Engine** - The ALU performs arithmetic and logic operations selected by control signals. We design an ALU for our instruction set.

  - **Memory: Instructions and Data** - A unified memory holds the program and its data. The program counter addresses instructions; load/store instructions access data.

  - **Control: Orchestrating Execution** - The control unit sequences operations, generating signals that coordinate registers, ALU, and memory through each instruction.

- [15 - Building the CPU](part-4-register-machines/ch-15-building-the-cpu/ch-15-chapter.md) - Wiring up the datapath: from components to a working 8-bit processor in RHDL.

  - **The Datapath Block Diagram** - A schematic showing all major components and their interconnections. We map our architecture to a concrete structure.

  - **Connecting Registers to ALU** - Multiplexers select which registers feed the ALU inputs. We route data through the datapath based on instruction requirements.

  - **The Program Counter** - A register that holds the address of the next instruction. It increments each cycle and can be loaded for branches.

  - **Instruction Register and Decoder** - The current instruction is held in a register and decoded into control signals. We implement the decoder as combinational logic.

  - **Wiring It All Together** - The complete datapath in RHDL code. We simulate it and watch instructions execute, verifying correct operation.

- [16 - The Explicit-Control Datapath](part-4-register-machines/ch-16-explicit-control-datapath/ch-16-chapter.md) - Fetch-decode-execute: the microarchitecture that interprets the instruction set.

  - **The Fetch-Decode-Execute Cycle** - The fundamental rhythm of computation: fetch the next instruction, decode it, execute it, repeat. We implement this cycle as a state machine.

  - **Control Signals and Sequencing** - Each instruction requires a sequence of control signals asserted over multiple cycles. We design the control logic that generates these signals.

  - **Microcode: Programs for Hardware** - Complex instructions become sequences of micro-operations. We write microcode that runs on our control store.

  - **Implementing Instructions** - Each instruction in our ISA becomes a microcode routine. We implement arithmetic, logic, memory access, and branches.

  - **The Complete Machine** - The full CPU running programs. We load machine code into memory, start the clock, and watch our creation compute.

### Part V: Metalinguistic Abstraction

- [17 - The ISA as Language](part-5-metalinguistic/ch-17-isa-as-language/ch-17-chapter.md) - Machine code is a language; the CPU is its interpreter; microcode is its implementation.

  - **Machine Code as Language** - Binary patterns encode operations and operands. We design a syntax (bit fields) and semantics (what each instruction does).

  - **The CPU as Interpreter** - The fetch-decode-execute loop is an interpreter for machine code. The hardware "reads" each instruction and "executes" it.

  - **Instruction Formats and Encoding** - We choose encodings that balance code density, decoder simplicity, and extensibility. RISC vs CISC tradeoffs emerge.

  - **Addressing Modes** - Different ways to specify operand locations: immediate, register, direct, indirect. Each mode adds flexibility at the cost of complexity.

  - **The Semantic Gap** - High-level languages are far from machine code. We glimpse the layers of interpretation that bridge this gap.

- [18 - Assembly and the Stack](part-5-metalinguistic/ch-18-assembly-and-stack/ch-18-chapter.md) - Subroutines, call/return, stack frames: the software conventions that enable recursion.

  - **Assembly Language Syntax** - Mnemonics replace binary opcodes. We write assembly language and assemble it into machine code.

  - **The Stack: LIFO Memory** - A region of memory with push and pop operations. The stack pointer register tracks the current top.

  - **Subroutine Call and Return** - CALL pushes the return address; RET pops it back to the PC. We can now factor code into reusable procedures.

  - **Stack Frames and Local Variables** - Each call allocates a frame for local variables. We establish calling conventions for argument passing and register saving.

  - **Recursion in Hardware** - With a stack, recursion works naturally. We implement factorial and Fibonacci, watching the stack grow and shrink.

- [19 - A Lisp Interpreter](part-5-metalinguistic/ch-19-lisp-interpreter/ch-19-chapter.md) - Eval and apply on our CPU: building a language from cons cells and recursion.

  - **S-Expressions and Cons Cells** - Lists built from pairs: car, cdr, and cons. We represent Lisp data structures in our memory.

  - **Memory Layout for Lisp** - Atoms, pairs, and symbols laid out in memory. We design tagging schemes to distinguish data types at runtime.

  - **The Read-Eval-Print Loop** - Parse input into S-expressions, evaluate them, print results. The REPL is the user interface to our interpreter.

  - **Implementing Eval** - The evaluator dispatches on expression type: self-evaluating, variable, quote, if, lambda, application. We write eval in assembly.

  - **Implementing Apply** - Function application binds arguments to parameters and evaluates the body. We manage environments and handle primitive vs compound procedures.

- [20 - Lambda Comes Full Circle](part-5-metalinguistic/ch-20-lambda-full-circle/ch-20-chapter.md) - The revelation: muxes are Church booleans, registers are Y combinators—we were computing lambda all along.

  - **Church Booleans and Muxes** - True and False as functions that select their first or second argument. A multiplexer implements exactly this selection—it IS a Church boolean.

  - **Church Numerals and Counters** - Numbers as repeated function application. A counter's tick is successor; the count is encoded in the state—hardware implements Church numerals.

  - **The Y Combinator and Feedback** - Fixed-point combinators enable recursion without naming. Flip-flops create fixed points through feedback—they ARE Y combinators.

  - **Hardware as Lambda Calculus** - Every circuit computes a lambda term. Wires are variables, gates are applications, feedback is fixed-point. The isomorphism is complete.

  - **The Isomorphism Revealed** - We started with transistors and arrived at lambda. But lambda was there all along, in every mux and every flip-flop. Hardware and software are one.

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
