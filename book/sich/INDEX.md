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

- [11 - Memory Systems](part-3-state-and-time/ch-11-memory-systems/ch-11-chapter.md) - Registers, RAM, and ROM: the storage elements of digital systems.

  - **Registers and Register Files** - Small, fast storage built from flip-flops. Register files provide multiple read and write ports for CPU datapaths.

  - **Static RAM (SRAM)** - Larger storage using six-transistor cells. We explore the tradeoff between density and speed, and see how decoders select memory locations.

  - **Read-Only Memory (ROM)** - Fixed data encoded in hardware. ROMs implement lookup tables and store programs that never change.

### Part IV: Computing with Register Machines

- [12 - Designing the Machine](part-4-register-machines/ch-12-designing-the-machine/ch-12-chapter.md) - Registers, ALU, memory, and control: the anatomy of a programmable computer.

  - **The von Neumann Architecture** - Instructions and data share a single memory. The CPU fetches instructions, decodes them, and executes them in sequence.

  - **Registers: Fast Local Storage** - A small set of registers holds working data. Instructions operate on registers, moving results back to memory as needed.

  - **The ALU: Computation Engine** - The ALU performs arithmetic and logic operations selected by control signals. We design an ALU for our instruction set.

  - **Memory: Instructions and Data** - A unified memory holds the program and its data. The program counter addresses instructions; load/store instructions access data.

  - **Control: Orchestrating Execution** - The control unit sequences operations, generating signals that coordinate registers, ALU, and memory through each instruction.

- [13 - Building the CPU](part-4-register-machines/ch-13-building-the-cpu/ch-13-chapter.md) - Wiring up the datapath: from components to a working 8-bit processor in RHDL.

  - **The Datapath Block Diagram** - A schematic showing all major components and their interconnections. We map our architecture to a concrete structure.

  - **Connecting Registers to ALU** - Multiplexers select which registers feed the ALU inputs. We route data through the datapath based on instruction requirements.

  - **The Program Counter** - A register that holds the address of the next instruction. It increments each cycle and can be loaded for branches.

  - **Instruction Register and Decoder** - The current instruction is held in a register and decoded into control signals. We implement the decoder as combinational logic.

  - **Wiring It All Together** - The complete datapath in RHDL code. We simulate it and watch instructions execute, verifying correct operation.

- [14 - The Explicit-Control Datapath](part-4-register-machines/ch-14-explicit-control-datapath/ch-14-chapter.md) - Fetch-decode-execute: the microarchitecture that interprets the instruction set.

  - **The Fetch-Decode-Execute Cycle** - The fundamental rhythm of computation: fetch the next instruction, decode it, execute it, repeat. We implement this cycle as a state machine.

  - **Control Signals and Sequencing** - Each instruction requires a sequence of control signals asserted over multiple cycles. We design the control logic that generates these signals.

  - **Microcode: Programs for Hardware** - Complex instructions become sequences of micro-operations. We write microcode that runs on our control store.

  - **Implementing Instructions** - Each instruction in our ISA becomes a microcode routine. We implement arithmetic, logic, memory access, and branches.

  - **The Complete Machine** - The full CPU running programs. We load machine code into memory, start the clock, and watch our creation compute.

### Part V: Metalinguistic Abstraction

- [15 - The ISA as Language](part-5-metalinguistic/ch-15-isa-as-language/ch-15-chapter.md) - Machine code is a language; the CPU is its interpreter; microcode is its implementation.

  - **Machine Code as Language** - Binary patterns encode operations and operands. We design a syntax (bit fields) and semantics (what each instruction does).

  - **The CPU as Interpreter** - The fetch-decode-execute loop is an interpreter for machine code. The hardware "reads" each instruction and "executes" it.

  - **Instruction Formats and Encoding** - We choose encodings that balance code density, decoder simplicity, and extensibility. RISC vs CISC tradeoffs emerge.

  - **Addressing Modes** - Different ways to specify operand locations: immediate, register, direct, indirect. Each mode adds flexibility at the cost of complexity.

  - **The Semantic Gap** - High-level languages are far from machine code. We glimpse the layers of interpretation that bridge this gap.

- [16 - Assembly and the Stack](part-5-metalinguistic/ch-16-assembly-and-stack/ch-16-chapter.md) - Subroutines, call/return, stack frames: the software conventions that enable recursion.

  - **Assembly Language Syntax** - Mnemonics replace binary opcodes. We write assembly language and assemble it into machine code.

  - **The Stack: LIFO Memory** - A region of memory with push and pop operations. The stack pointer register tracks the current top.

  - **Subroutine Call and Return** - CALL pushes the return address; RET pops it back to the PC. We can now factor code into reusable procedures.

  - **Stack Frames and Local Variables** - Each call allocates a frame for local variables. We establish calling conventions for argument passing and register saving.

  - **Recursion in Hardware** - With a stack, recursion works naturally. We implement factorial and Fibonacci, watching the stack grow and shrink.

- [17 - A Lisp Interpreter](part-5-metalinguistic/ch-17-lisp-interpreter/ch-17-chapter.md) - Eval and apply on our CPU: building a language from cons cells and recursion.

  - **S-Expressions and Cons Cells** - Lists built from pairs: car, cdr, and cons. We represent Lisp data structures in our memory.

  - **Memory Layout for Lisp** - Atoms, pairs, and symbols laid out in memory. We design tagging schemes to distinguish data types at runtime.

  - **The Read-Eval-Print Loop** - Parse input into S-expressions, evaluate them, print results. The REPL is the user interface to our interpreter.

  - **Implementing Eval** - The evaluator dispatches on expression type: self-evaluating, variable, quote, if, lambda, application. We write eval in assembly.

  - **Implementing Apply** - Function application binds arguments to parameters and evaluates the body. We manage environments and handle primitive vs compound procedures.

- [18 - Lambda Comes Full Circle](part-5-metalinguistic/ch-18-lambda-full-circle/ch-18-chapter.md) - The revelation: muxes are Church booleans, registers are Y combinators—we were computing lambda all along.

  - **Church Booleans and Muxes** - True and False as functions that select their first or second argument. A multiplexer implements exactly this selection—it IS a Church boolean.

  - **Church Numerals and Counters** - Numbers as repeated function application. A counter's tick is successor; the count is encoded in the state—hardware implements Church numerals.

  - **The Y Combinator and Feedback** - Fixed-point combinators enable recursion without naming. Flip-flops create fixed points through feedback—they ARE Y combinators.

  - **Hardware as Lambda Calculus** - Every circuit computes a lambda term. Wires are variables, gates are applications, feedback is fixed-point. The isomorphism is complete.

  - **The Isomorphism Revealed** - We started with transistors and arrived at lambda. But lambda was there all along, in every mux and every flip-flop. Hardware and software are one.

### Part VI: Advanced Topics

- [19 - Interrupts and Exceptions](part-6-advanced/ch-19-interrupts-exceptions/ch-19-chapter.md) - Asynchronous events, traps, and the hardware/software boundary.

  - **The Metastability Problem** - External signals are asynchronous to the CPU clock. Flip-flops can enter undefined states; synchronizers reduce this risk.

  - **Interrupt Handling** - External devices signal the CPU through interrupt lines. We save state, jump to a handler, and return when done.

  - **Exceptions and Traps** - Illegal instructions, divide by zero, system calls. Internal events that transfer control to the operating system.

  - **Interrupt Vectors and Priority** - Multiple interrupt sources need arbitration. We implement a priority encoder and vector table.

  - **Adding Interrupts to Our CPU** - We extend our CPU with interrupt support, implementing a timer interrupt and UART for I/O.

- [20 - Privilege and Protection](part-6-advanced/ch-20-privilege-protection/ch-20-chapter.md) - User mode, kernel mode, and the hardware foundations of security.

  - **Why Protection Matters** - Without isolation, any program can crash the system or steal data. The OS needs hardware support to protect itself.

  - **Privilege Levels** - User mode vs kernel mode. Certain instructions (halt, I/O, MMU control) are only available in kernel mode.

  - **Mode Switching** - System calls trap from user to kernel; return instructions restore user mode. We implement the mode bit and protection checks.

  - **Protected Instructions** - I/O, interrupt control, and page table updates require privilege. We add checks to our decoder.

  - **Adding Protection to Our CPU** - We extend our CPU with a privilege bit, trap instruction, and return-from-exception.

- [21 - Virtual Memory](part-6-advanced/ch-21-virtual-memory/ch-21-chapter.md) - Address translation, page tables, and the illusion of infinite memory.

  - **Address Spaces** - Each process sees its own private memory. Virtual addresses are translated to physical addresses by hardware.

  - **Page Tables** - Memory is divided into pages; a table maps virtual pages to physical frames. We implement a simple page table walker.

  - **The TLB** - Translation is slow; the Translation Lookaside Buffer caches recent mappings. We add a TLB to our MMU.

  - **Page Faults** - When a page isn't in memory, the OS loads it from disk. We generate exceptions for missing pages.

  - **Adding an MMU to Our CPU** - We integrate address translation into our memory pipeline, connecting the TLB and page table walker.

- [22 - Memory Hierarchy and Caches](part-6-advanced/ch-22-memory-hierarchy/ch-22-chapter.md) - Hiding memory latency behind locality: from registers to DRAM.

  - **The Memory Wall** - Processors get faster, but memory doesn't keep up. We quantify the problem and see why caches are essential.

  - **Locality of Reference** - Programs tend to access the same data repeatedly (temporal) and nearby data (spatial). We exploit these patterns to predict what to cache.

  - **Cache Organization** - Direct-mapped, set-associative, fully-associative. We explore the tradeoffs between simplicity, hit rate, and hardware cost.

  - **Cache Policies** - Write-through vs write-back, replacement policies (LRU, random). We design policies that balance performance and complexity.

  - **Adding a Cache to Our CPU** - We integrate a simple cache into our CPU design, connecting it between the processor and main memory.

- [23 - Throughput and Pipelining](part-6-advanced/ch-23-throughput-and-pipelining/ch-23-chapter.md) - Overlapping instruction execution: how throughput decouples from latency.

  - **Latency vs Throughput** - Latency is the time for one instruction; throughput is instructions per second. Pipelining dramatically improves throughput.

  - **Pipeline Stages** - Fetch, decode, execute, memory, writeback. We divide instruction execution into stages that operate in parallel.

  - **Pipeline Hazards** - Data hazards, control hazards, structural hazards. When one instruction depends on another, the pipeline stalls.

  - **Forwarding and Stalling** - Bypass networks forward results directly; stalls pause the pipeline. We implement both to handle hazards.

  - **Pipelining Our CPU** - We transform our single-cycle CPU into a 5-stage pipeline, measuring the speedup and handling the hazards.

- [24 - The Complete System](part-6-advanced/ch-24-complete-system/ch-24-chapter.md) - Integration, boot sequence, and running an operating system.

  - **Putting It All Together** - Cache, pipeline, interrupts, protection, virtual memory. We integrate all advanced features into a coherent system.

  - **The Boot Sequence** - Power on, reset vector, firmware, bootloader, kernel. We trace the path from power-on to running code.

  - **Context Switching** - Saving and restoring CPU state to switch between processes. We implement the hardware support for multitasking.

  - **A Minimal Operating System** - Process table, scheduler, system calls. We write just enough OS to run multiple programs.

  - **Multiple Lisp REPLs** - The payoff: our hardware runs an OS that runs multiple Lisp interpreters, each in its own protected address space.

---

## The Journey

```
Start here:                         End here:

Transistors & switches              Operating system
    |                                   ^
    v                                   |
Logic gates (AND, OR, NOT)          Virtual memory & protection
    |                                   ^
    v                                   |
Combinational circuits              Pipelining & caches
    |                                   ^
    v                                   |
Sequential logic & state            Lambda revealed
    |                                   ^
    v                                   |
Memory                              Lisp interpreter
    |                                   ^
    v                                   |
Simple CPU  -----> Assembly -----> ISA as language
```

---

## Appendices

Each chapter has an accompanying appendix with complete RHDL implementations. Additional topics that support but aren't essential to the main narrative are also in appendices.

| Chapter | Topic | Appendix |
|---------|-------|----------|
| 01 | Thinking in Hardware | [Mental Models](part-1-gates/ch-01-thinking-in-hardware/ch-01-appendix.md) |
| 02 | Elements of Digital Logic | [Gate Primitives](part-1-gates/ch-02-elements-of-digital-logic/ch-02-appendix.md) |
| 03 | Gates and Processes | [Timing Analysis, Hazards, Performance](part-1-gates/ch-03-gates-and-processes/ch-03-appendix.md) |
| 04 | Higher-Order Hardware | [Generators](part-1-gates/ch-04-higher-order-hardware/ch-04-appendix.md) |
| 05 | Circuit Abstraction | [Interface Testing](part-2-circuits/ch-05-circuit-abstraction/ch-05-appendix.md) |
| 06 | Hierarchical Circuits | [ALU Implementation](part-2-circuits/ch-06-hierarchical-circuits/ch-06-appendix.md) |
| 07 | Multiple Representations | [Adder Variants](part-2-circuits/ch-07-multiple-representations/ch-07-appendix.md) |
| 08 | Generic Components | [Parameterized Designs](part-2-circuits/ch-08-generic-components/ch-08-appendix.md) |
| 09 | Sequential Logic | [Flip-Flop Zoo](part-3-state-and-time/ch-09-sequential-logic/ch-09-appendix.md) |
| 10 | The Timing Model | [Timing Violations and Failure Modes](part-3-state-and-time/ch-10-timing-model/ch-10-appendix.md) |
| 11 | Memory Systems | [Memory Implementation Details](part-3-state-and-time/ch-11-memory-systems/ch-11-appendix.md) |
| 12 | Designing the Machine | [CPU Block Diagram](part-4-register-machines/ch-12-designing-the-machine/ch-12-appendix.md) |
| 13 | Building the CPU | [Complete CPU](part-4-register-machines/ch-13-building-the-cpu/ch-13-appendix.md) |
| 14 | Explicit-Control | [Microcode](part-4-register-machines/ch-14-explicit-control-datapath/ch-14-appendix.md) |
| 15 | ISA as Language | [Instruction Set](part-5-metalinguistic/ch-15-isa-as-language/ch-15-appendix.md) |
| 16 | Assembly and Stack | [Calling Convention](part-5-metalinguistic/ch-16-assembly-and-stack/ch-16-appendix.md) |
| 17 | Lisp Interpreter | [Eval/Apply](part-5-metalinguistic/ch-17-lisp-interpreter/ch-17-appendix.md) |
| 18 | Lambda Full Circle | [The Isomorphism](part-5-metalinguistic/ch-18-lambda-full-circle/ch-18-appendix.md) |
| 19 | Interrupts and Exceptions | [Interrupt Controller](part-6-advanced/ch-19-interrupts-exceptions/ch-19-appendix.md) |
| 20 | Privilege and Protection | [Protection Implementation](part-6-advanced/ch-20-privilege-protection/ch-20-appendix.md) |
| 21 | Virtual Memory | [MMU Implementation](part-6-advanced/ch-21-virtual-memory/ch-21-appendix.md) |
| 22 | Memory Hierarchy and Caches | [Cache Implementation](part-6-advanced/ch-22-memory-hierarchy/ch-22-appendix.md) |
| 23 | Throughput and Pipelining | [Pipeline Implementation](part-6-advanced/ch-23-throughput-and-pipelining/ch-23-appendix.md) |
| 24 | Complete System | [OS Kernel](part-6-advanced/ch-24-complete-system/ch-24-appendix.md) |

---

## SICP Correspondence

This book is an inverted SICP, ascending from hardware to lambda, then continuing to a full system:

| SICP | SICH | Theme |
|------|------|-------|
| Ch 1: Procedures | Part I: Gates | Primitives, combination, abstraction |
| Ch 2: Data | Part II: Circuits | Compound structures, interfaces, generic ops |
| Ch 3: State | Part III: State and Time | Mutation, time, clocks |
| Ch 5: Register Machines | Part IV: Register Machines | The hardware foundation |
| Ch 4: Interpreters | Part V: Metalinguistic | Languages all the way up |
| — | Part VI: Advanced | Caches, pipelines, OS support |

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
- How operating systems depend on hardware support for protection and virtual memory

## Prerequisites

- Basic programming experience (any language)
- Familiarity with binary numbers helpful but not required
- No prior hardware experience needed
