# Chapter 26: Case Study - Transputer

*Hardware-native message passing*

---

## Historical Context

In 1983, Inmos introduced the Transputer—a revolutionary microprocessor that embedded Tony Hoare's **Communicating Sequential Processes (CSP)** directly into silicon. While other processors treated parallelism as an afterthought, the Transputer was designed from the ground up for concurrent, message-passing computation.

The name "Transputer" combines "transistor" and "computer," reflecting the vision of processors as building blocks that could be connected like transistors to build larger systems.

```
Traditional Multiprocessor:
┌─────┐    ┌───────────┐    ┌─────┐
│ CPU │◄──►│ Shared    │◄──►│ CPU │   Contention!
└─────┘    │  Memory   │    └─────┘   Bottleneck!
           │           │
┌─────┐    │           │    ┌─────┐
│ CPU │◄──►│           │◄──►│ CPU │
└─────┘    └───────────┘    └─────┘

Transputer Network:
┌─────┐    ┌─────┐    ┌─────┐    ┌─────┐
│ T   │◄──►│ T   │◄──►│ T   │◄──►│ T   │
└──┬──┘    └──┬──┘    └──┬──┘    └──┬──┘
   │          │          │          │
   ▼          ▼          ▼          ▼
┌─────┐    ┌─────┐    ┌─────┐    ┌─────┐
│ T   │◄──►│ T   │◄──►│ T   │◄──►│ T   │
└─────┘    └─────┘    └─────┘    └─────┘

Point-to-point links, no shared bus!
```

---

## The CSP Model

**Communicating Sequential Processes** (Hoare, 1978) provides the theoretical foundation:

### Core Principles

1. **Sequential Processes**: Independent units of computation
2. **Channels**: Typed, synchronous communication links
3. **Synchronization**: Communication implies synchronization
4. **No Shared State**: Processes communicate only through channels

```
Process A                    Process B
─────────                    ─────────
compute x                    waiting...
    │                            │
    ├───── channel ! x ─────────►├
    │      (send)        (receive)
    ▼                            ▼
waiting...                   use x
    │                            │
    ├◄──── channel ? y ──────────┤
    │      (receive)       (send)
    ▼                            ▼
use y                        compute y

Both processes BLOCK until rendezvous
```

### CSP Primitives

| Primitive | Notation | Meaning |
|-----------|----------|---------|
| Output | `c ! v` | Send value v on channel c |
| Input | `c ? x` | Receive into variable x from c |
| Alternative | `ALT` | Wait for first ready channel |
| Parallel | `PAR` | Run processes in parallel |
| Sequential | `SEQ` | Run processes sequentially |

---

## Transputer Architecture

### T414/T800 Block Diagram

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                      T800 TRANSPUTER                     │
                    │  ┌─────────────────────────────────────────────────┐    │
                    │  │                   CPU CORE                       │    │
                    │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐         │    │
   Link 0 ◄────────►│  │  │ A Reg   │  │ B Reg   │  │ C Reg   │ Eval    │    │
   (20 Mbit/s)      │  │  └────┬────┘  └────┬────┘  └────┬────┘ Stack   │    │
                    │  │       │            │            │              │    │
   Link 1 ◄────────►│  │       └────────────┴────────────┘              │    │
                    │  │                     │                          │    │
                    │  │              ┌──────┴──────┐                   │    │
   Link 2 ◄────────►│  │              │     ALU     │ ◄── 32-bit       │    │
                    │  │              └──────┬──────┘                   │    │
                    │  │                     │                          │    │
   Link 3 ◄────────►│  │  ┌─────────┐  ┌────┴────┐  ┌─────────────┐   │    │
                    │  │  │ Wptr    │  │ Iptr    │  │ Oreg (oper) │   │    │
                    │  │  │(Workspace)│ │(Instr)  │  │             │   │    │
                    │  │  └─────────┘  └─────────┘  └─────────────┘   │    │
                    │  └─────────────────────────────────────────────────┘    │
                    │                         │                               │
                    │  ┌──────────────────────┴──────────────────────┐       │
                    │  │               PROCESS SCHEDULER              │       │
                    │  │  ┌───────────┐  ┌────────────┐              │       │
                    │  │  │ FptrReg0  │  │ BptrReg0   │ High Priority│       │
                    │  │  └───────────┘  └────────────┘              │       │
                    │  │  ┌───────────┐  ┌────────────┐              │       │
                    │  │  │ FptrReg1  │  │ BptrReg1   │ Low Priority │       │
                    │  │  └───────────┘  └────────────┘              │       │
                    │  └─────────────────────────────────────────────┘       │
                    │                         │                               │
                    │  ┌──────────────────────┴──────────────────────┐       │
                    │  │              4KB ON-CHIP SRAM                │       │
                    │  └─────────────────────────────────────────────┘       │
                    │                         │                               │
     External ◄────►│  ┌──────────────────────┴──────────────────────┐       │
     Memory         │  │            MEMORY INTERFACE                  │       │
                    │  │           (32-bit, 25 MHz)                   │       │
                    │  └─────────────────────────────────────────────┘       │
                    │                                                         │
                    │  ┌─────────────────────────────────────────────┐       │
                    │  │         64-BIT FPU (T800 only)              │       │
                    │  └─────────────────────────────────────────────┘       │
                    └─────────────────────────────────────────────────────────┘
```

### Key Components

**Evaluation Stack** (3 registers: A, B, C)
- All arithmetic operates on this stack
- A = top, B = next, C = bottom
- Stack-based reduces instruction encoding

**Workspace Pointer (Wptr)**
- Points to current process's workspace in memory
- Process context stored at fixed offsets from Wptr
- Context switch = change Wptr

**Instruction Pointer (Iptr)**
- Points to next instruction
- Used for process scheduling

**Hardware Scheduler**
- Two priority queues (high and low)
- Maintains linked lists of ready processes
- Preemption on high-priority events
- Zero-overhead context switching for link I/O

---

## Hardware Links

The revolutionary feature: **four bidirectional serial links** built into silicon.

### Link Architecture

```
Transputer A                                    Transputer B
┌────────────────┐                              ┌────────────────┐
│                │                              │                │
│   ┌────────┐   │    LinkOut ──────────────►   │   ┌────────┐   │
│   │ Link   │   │    (serial, 20 Mbit/s)       │   │ Link   │   │
│   │ Engine │   │                              │   │ Engine │   │
│   │   0    │   │    ◄────────────── LinkIn    │   │   0    │   │
│   └────────┘   │                              │   └────────┘   │
│                │                              │                │
└────────────────┘                              └────────────────┘

Physical connection: just 2 wires per direction!
```

### Link Protocol

```
Packet Format:
┌──────────┬──────────────────────────────────┐
│ Data (8) │        Acknowledge (1)            │
└──────────┴──────────────────────────────────┘

1. Sender transmits 8-bit data packet
2. Sender waits for acknowledge
3. Receiver sends acknowledge when ready
4. Flow control is automatic!

Timing:
     Sender                 Receiver
        │                       │
    ───►├─── data byte ────────►├───
        │                       │ process
    ◄───├◄── acknowledge ───────├◄──
        │                       │
```

### Link Integration with Scheduler

```
Process sends on channel (link):
┌──────────────────────────────────────────────────────┐
│ 1. Process executes OUT instruction                   │
│ 2. Hardware initiates link transfer                  │
│ 3. Process is DESCHEDULED (removed from run queue)   │
│ 4. Link engine handles byte-by-byte transfer         │
│ 5. When transfer complete, process RESCHEDULED       │
│ 6. Zero CPU cycles wasted waiting!                   │
└──────────────────────────────────────────────────────┘
```

---

## Instruction Set

The Transputer uses a **compact, prefix-based encoding**:

### Instruction Format

```
Each instruction is 1 byte:
┌────────────┬────────────┐
│ Function   │ Operand    │
│ (4 bits)   │ (4 bits)   │
└────────────┴────────────┘

Direct functions (0-12): Immediate operand
Prefix instructions (13-15): Extend operand
```

### Prefix Mechanism

```
To encode larger operands:

PFIX (prefix):     Oreg := (Oreg | operand) << 4
NFIX (neg prefix): Oreg := (~(Oreg | operand)) << 4
OPR (operate):     Execute secondary using Oreg as selector

Example: Load constant 0x1234
  PFIX 0x1     ; Oreg = 0x10
  PFIX 0x2     ; Oreg = 0x120
  PFIX 0x3     ; Oreg = 0x1230
  LDC  0x4     ; A = Oreg | 0x4 = 0x1234
```

### Core Instructions

| Function | Mnemonic | Operation |
|----------|----------|-----------|
| 0 | J | Jump (Iptr + Oreg) |
| 1 | LDLP | Load local pointer |
| 2 | PFIX | Prefix |
| 3 | LDNL | Load non-local |
| 4 | LDC | Load constant |
| 5 | LDNLP | Load non-local pointer |
| 6 | NFIX | Negative prefix |
| 7 | LDL | Load local |
| 8 | ADC | Add constant |
| 9 | CALL | Call subroutine |
| 10 | CJ | Conditional jump |
| 11 | AJW | Adjust workspace |
| 12 | EQC | Equals constant |
| 13 | STL | Store local |
| 14 | STNL | Store non-local |
| 15 | OPR | Operate (secondary) |

### Secondary Instructions (via OPR)

```
Arithmetic:    ADD, SUB, MUL, DIV, REM, NEG
Logic:         AND, OR, XOR, NOT
Shifts:        SHL, SHR
Comparison:    GT, DIFF
Stack:         REV (reverse A,B), DUP
Process:       STARTP, ENDP, RUNP, STOPP
Channel:       IN, OUT, OUTWORD, OUTBYTE
Timer:         LDTIMER
ALT:           ALT, ALTWT, ALTEND, ENBC, ENBT, DISC, DIST
```

---

## Process Model

### Process Workspace

Each process has a **workspace** in memory:

```
           Low addresses
                │
    Wptr-4  ───►├─────────────────┤
                │ Iptr (saved)    │ ◄── Saved when descheduled
    Wptr-3  ───►├─────────────────┤
                │ Link pointer    │ ◄── For scheduling queues
    Wptr-2  ───►├─────────────────┤
                │ State/Priority  │
    Wptr-1  ───►├─────────────────┤
                │ Local var 0     │
    Wptr    ───►├─────────────────┤ ◄── Current Wptr points here
                │ Local var 1     │
    Wptr+1  ───►├─────────────────┤
                │ Local var 2     │
    Wptr+2  ───►├─────────────────┤
                │ ...             │
                │
           High addresses
```

### Hardware Scheduling

```
Run Queues (linked lists in memory):

High Priority Queue:
┌──────────────┐                          ┌──────────────┐
│ FptrReg0     │──────────────────────────│ BptrReg0     │
└──────┬───────┘                          └───────▲──────┘
       │                                          │
       ▼                                          │
  ┌─────────┐    ┌─────────┐    ┌─────────┐      │
  │ Process │───►│ Process │───►│ Process │──────┘
  │    A    │    │    B    │    │    C    │
  └─────────┘    └─────────┘    └─────────┘

Low Priority Queue:
┌──────────────┐                          ┌──────────────┐
│ FptrReg1     │──────────────────────────│ BptrReg1     │
└──────┬───────┘                          └───────▲──────┘
       │                                          │
       ▼                                          │
  ┌─────────┐    ┌─────────┐                     │
  │ Process │───►│ Process │─────────────────────┘
  │    X    │    │    Y    │
  └─────────┘    └─────────┘

Context switch: Just update Wptr and Iptr!
```

### Process Instructions

```
STARTP - Start new process
  A: workspace address of new process
  B: initial Iptr for new process
  Effect: Add process to back of current priority queue

ENDP - End process
  Effect: Remove from queue, join with parent if applicable

RUNP - Run process
  A: workspace address
  Effect: Schedule process (add to queue)

STOPP - Stop process
  Effect: Deschedule until explicitly run
```

---

## Channel Communication

### Internal Channels

For processes on the same Transputer:

```
Memory-based channel:
┌───────────────────────────────────────┐
│ Channel Word                          │
│ ┌─────────────────────────────────┐   │
│ │ Waiting process Wptr or data    │   │
│ └─────────────────────────────────┘   │
└───────────────────────────────────────┘

State machine:
  Empty:    Channel word = MinInt (most negative)
  Waiting:  Channel word = Wptr of waiting process
  Ready:    Data transfer occurs immediately
```

### Communication Protocol

```
Process A: OUT (send)              Process B: IN (receive)
─────────────────────              ─────────────────────

Case 1: Receiver waiting
  ┌──────────────────────┐
  │ 1. Check channel     │         (already waiting)
  │ 2. Find B's Wptr     │
  │ 3. Copy data to B    │────────►(receives data)
  │ 4. Reschedule B      │
  │ 5. Continue A        │
  └──────────────────────┘

Case 2: Sender first
  ┌──────────────────────┐
  │ 1. Check channel     │
  │ 2. Empty - store Wptr│
  │ 3. Deschedule A      │         ┌──────────────────────┐
  │    (wait...)         │         │ 1. Check channel     │
  │                      │◄────────│ 2. Find A's Wptr     │
  │ 4. B copies data     │         │ 3. Copy data from A  │
  │ 5. A rescheduled     │         │ 4. Reschedule A      │
  └──────────────────────┘         │ 5. Continue B        │
                                   └──────────────────────┘
```

### External Channels (Links)

For processes on different Transputers:

```
Process A (Transputer 1)           Process B (Transputer 2)
─────────────────────────          ─────────────────────────

OUT on link:                       IN on link:
1. Process deschedules             1. Process deschedules
2. Link engine takes over          2. Link engine takes over
3. Bytes sent serially ──────────► 3. Bytes received
4. Acknowledge returned ◄────────── 4. Acknowledge sent
5. Process rescheduled             5. Process rescheduled
```

---

## ALT Construct

The **alternation** construct waits for the first ready channel:

### ALT Execution

```
Occam:
  ALT
    chan1 ? x
      ... process x
    chan2 ? y
      ... process y
    timer ? AFTER timeout
      ... handle timeout

Assembly sequence:
  ALT       ; Start alternative
  ENBC ch1  ; Enable channel 1
  ENBC ch2  ; Enable channel 2
  ENBT tim  ; Enable timer
  ALTWT     ; Wait for first ready
  ...       ; Determine which fired
  DISC ch1  ; Disable channel 1
  DISC ch2  ; Disable channel 2
  DIST tim  ; Disable timer
  ALTEND    ; End alternative
```

### Hardware Support

```
During ALT:
  - Process registers as "waiting" on multiple channels
  - Hardware tracks which channels become ready
  - First ready channel wakes the process
  - No polling required!

State in process workspace:
  ALTstate: ENABLING, WAITING, READY
  ALTcount: Number of enabled channels
```

---

## Transputer Variants

| Model | Year | Word | MIPS | FPU | On-chip RAM | Links |
|-------|------|------|------|-----|-------------|-------|
| T212 | 1985 | 16-bit | 10 | No | 2KB | 4 |
| T414 | 1985 | 32-bit | 10 | No | 2KB | 4 |
| T425 | 1989 | 32-bit | 15 | No | 4KB | 4 |
| T800 | 1987 | 32-bit | 10 | Yes | 4KB | 4 |
| T805 | 1989 | 32-bit | 30 | Yes | 4KB | 4 |
| T9000 | 1994 | 32-bit | 200 | Yes | 16KB | 4 |

---

## Network Topologies

Transputers can form various network structures:

### Pipeline

```
┌─────┐   ┌─────┐   ┌─────┐   ┌─────┐
│ T0  │──►│ T1  │──►│ T2  │──►│ T3  │
└─────┘   └─────┘   └─────┘   └─────┘
```

### Ring

```
        ┌─────┐
    ┌──►│ T0  │───┐
    │   └─────┘   │
    │             ▼
┌─────┐       ┌─────┐
│ T3  │       │ T1  │
└─────┘       └─────┘
    ▲             │
    │   ┌─────┐   │
    └───│ T2  │◄──┘
        └─────┘
```

### 2D Mesh

```
┌─────┐───┌─────┐───┌─────┐───┌─────┐
│ T00 │   │ T01 │   │ T02 │   │ T03 │
└──┬──┘   └──┬──┘   └──┬──┘   └──┬──┘
   │         │         │         │
┌──┴──┐   ┌──┴──┐   ┌──┴──┐   ┌──┴──┐
│ T10 │───│ T11 │───│ T12 │───│ T13 │
└──┬──┘   └──┬──┘   └──┬──┘   └──┬──┘
   │         │         │         │
┌──┴──┐   ┌──┴──┐   ┌──┴──┐   ┌──┴──┐
│ T20 │───│ T21 │───│ T22 │───│ T23 │
└─────┘   └─────┘   └─────┘   └─────┘
```

### Hypercube

```
    3D Hypercube (8 nodes):

         T4──────────T5
        /│          /│
       / │         / │
      T0──────────T1 │
      │  │        │  │
      │  T6───────│─T7
      │ /         │ /
      │/          │/
      T2──────────T3

    Each node connected to 3 neighbors
    (one link per dimension)
```

---

## Programming Example

### Producer-Consumer in Occam

```occam
-- Channel declaration
CHAN OF INT items:

-- Producer process
PROC producer(CHAN OF INT out)
  INT x:
  SEQ
    x := 0
    WHILE TRUE
      SEQ
        out ! x      -- Send x on channel
        x := x + 1
:

-- Consumer process
PROC consumer(CHAN OF INT in)
  INT item:
  WHILE TRUE
    SEQ
      in ? item      -- Receive from channel
      ... process item
:

-- Main: run in parallel
PAR
  producer(items)
  consumer(items)
```

### Pipeline Example

```occam
-- Stage in a pipeline
PROC pipeline.stage(CHAN OF INT in, out, INT my.op)
  INT x:
  WHILE TRUE
    SEQ
      in ? x         -- Receive input
      x := x + my.op -- Process
      out ! x        -- Forward result
:

-- Build pipeline
CHAN OF INT c0, c1, c2, c3:
PAR
  source(c0)
  pipeline.stage(c0, c1, 1)
  pipeline.stage(c1, c2, 2)
  pipeline.stage(c2, c3, 3)
  sink(c3)
```

---

## Performance Characteristics

### Context Switch Time

```
Traditional processor:
  Save 32+ registers
  Update page tables
  Flush caches
  Total: 1000s of cycles

Transputer:
  Save: Wptr already in memory, Iptr to workspace
  Update: New Wptr to register
  Total: 1-2 cycles!
```

### Communication Latency

```
Internal channel (same Transputer):
  Empty channel: ~10 cycles (store Wptr, deschedule)
  Ready channel: ~5 cycles (immediate transfer)

External link (different Transputers):
  Byte transfer: ~40 cycles at 20 Mbit/s
  Link setup: 0 (dedicated hardware)
  CPU overhead: 0 (link engine handles it)
```

### Throughput

```
Single T800 @ 20 MHz:
  Integer: ~10 MIPS
  Floating point: ~1.5 MFLOPS
  Links: 4 × 20 Mbit/s = 80 Mbit/s total

Scaling:
  N Transputers → nearly N× throughput
  (Limited by communication patterns)
```

---

## Legacy and Influence

### Direct Descendants

- **XMOS XS1**: Modern CSP-based multicore
- **Go language**: Goroutines and channels (Rob Pike worked on both)
- **Rust channels**: Similar synchronization model
- **Erlang**: Actor model (similar principles)

### Concepts That Spread

| Transputer Feature | Modern Equivalent |
|-------------------|-------------------|
| Hardware channels | Network-on-Chip |
| Link protocol | PCIe, SerDes |
| Process scheduler | Hardware threads |
| CSP model | Go, Rust, Erlang |
| No shared memory | Message passing |

### Why It Faded

1. **Single-threaded performance plateau**: Couldn't keep up with superscalar
2. **Memory bandwidth**: Links couldn't scale with memory needs
3. **Software ecosystem**: Occam never caught on
4. **x86 dominance**: PC market chose different path

---

## RHDL Implementation

See [Appendix Z](appendix-z-transputer.md) for complete implementations:

```ruby
# Transputer link engine
class LinkEngine < SimComponent
  input :clk
  input :send_data, width: 8
  input :send_valid
  output :send_ready
  input :recv_ready
  output :recv_data, width: 8
  output :recv_valid

  # External link signals
  output :link_out
  input :link_in

  behavior do
    # Serialize bytes, handle protocol
  end
end
```

---

## Summary

- **CSP in silicon**: Hardware designed for message passing
- **Four serial links**: Point-to-point communication, 20 Mbit/s each
- **Hardware scheduler**: Two priority queues, 1-cycle context switch
- **Compact instructions**: Prefix-based encoding, stack-oriented
- **Workspace model**: Process state at fixed offsets from pointer
- **ALT construct**: Hardware-supported multi-channel wait
- **Network scalable**: Pipeline, mesh, hypercube topologies
- **Occam language**: CSP syntax compiled to Transputer code
- **Lasting influence**: Go, Rust, XMOS, modern NoC

---

## Exercises

1. Implement a simple channel in RHDL with ready/valid handshaking
2. Build a hardware process scheduler with two priority queues
3. Design a 4-node Transputer network in ring topology
4. Implement the ALT state machine
5. Compare Transputer message passing to shared-memory synchronization

---

## Further Reading

- Hoare, C.A.R., "Communicating Sequential Processes" (1978)
- Inmos, "Transputer Reference Manual" (1988)
- May, David, "The XMOS XS1 Architecture" (2009)
- Roscoe, A.W., "The Theory and Practice of Concurrency" (1997)

---

*Previous: [Chapter 22 - RISC-V RV32I](24-riscv.md)*

*Appendix: [Appendix Z - Transputer Implementation](appendix-z-transputer.md)*
