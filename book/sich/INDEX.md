# SICH: Structure and Interpretation of Computer Hardware

*Building a Computer from First Principles*

## Table of Contents

### Introduction
- [00 - Introduction](00-intro.md) - Book overview, target audience, and the RHDL approach

### Part I: Switches and Gates
- [09 - Thinking in Hardware](09-thinking-in-hardware.md) - The mental shift from sequential software to parallel hardware
- [10 - Digital Logic Fundamentals](10-digital-logic-fundamentals.md) - Gates, truth tables, Boolean algebra
- [11 - Combinational Logic](11-combinational-logic.md) - Multiplexers, decoders, encoders, ALU design

### Part II: Memory and Time
- [12 - Sequential Logic](12-sequential-logic.md) - Flip-flops, registers, counters, finite state machines
- [13 - Memory Systems](13-memory-systems.md) - RAM, ROM, caches, memory hierarchy

### Part III: The Register Machine
- [14 - Computer Architecture](14-computer-architecture.md) - CPU fundamentals, fetch-decode-execute cycle
- [15 - Building a CPU](15-building-a-cpu.md) - Hands-on construction of an 8-bit processor

### Part IV: From Hardware to Lambda
- [16 - Assembly and the Stack](16-assembly-and-stack.md) - Subroutines, call/return, stack frames, the software/hardware boundary
- [17 - A Lisp Interpreter](17-lisp-interpreter.md) - S-expressions, cons cells, eval/apply—building Lisp on our CPU
- [18 - Lambda Comes Full Circle](18-lambda-full-circle.md) - The revelation: muxes are Church booleans, registers are Y combinators, we were computing lambda all along

---

## The Journey

```
Start here:                    End here:

Transistors & switches        λ calculus revealed
    ↓                             ↑
Logic gates (AND, OR, NOT)    Lisp interpreter
    ↓                             ↑
Combinational circuits        Assembly language
    ↓                             ↑
Sequential logic              CPU architecture
    ↓                             ↑
Memory                        ─────────┘
```

---

## Chapter Status

| Chapter | Status | Notes |
|---------|--------|-------|
| 00 - Intro | Draft | Overview complete |
| 09 - Thinking in Hardware | Outline | Key concepts identified |
| 10 - Digital Logic | Outline | Key concepts identified |
| 11 - Combinational | Outline | Key concepts identified |
| 12 - Sequential | Outline | Key concepts identified |
| 13 - Memory | Outline | Key concepts identified |
| 14 - Architecture | Outline | Key concepts identified |
| 15 - Building a CPU | Outline | Key concepts identified |
| 16 - Assembly/Stack | Planned | Software/hardware boundary |
| 17 - Lisp Interpreter | Planned | The interpreter |
| 18 - Lambda Full Circle | Planned | The punchline |

## Companion Book

For advanced topics on computation theory and alternative architectures, see:

**[MOCA: Models Of Computational Architectures](../moca/INDEX.md)** - Explores Turing machines, lambda calculus, dataflow, stack machines, systolic arrays, reversible computing, and the theoretical foundations underlying all computer architectures.

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
