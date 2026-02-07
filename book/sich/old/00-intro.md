# SICH: Structure and Interpretation of Computer Hardware

## Introduction

### The Gap Between Software and Hardware

Most software engineers think in abstractions: functions, objects, threads, APIs. But underneath it all, there's hardware—billions of transistors switching on and off, propagating signals through logic gates, storing bits in flip-flops. Understanding this layer transforms how you think about performance, concurrency, and system design.

### Why This Book?

This book bridges the gap between software and hardware thinking. You'll learn to:

- Think in parallel (everything happens at once)
- Design with constraints (timing, area, power)
- Build from first principles (gates to CPUs)
- Use Ruby as your hardware description language

### Who This Book Is For

- Software engineers curious about what's "below" their code
- Developers wanting to understand CPU architecture deeply
- Anyone interested in FPGA or ASIC design
- Programmers who want to build their own CPU

### The RHDL Approach

We'll use RHDL (Ruby Hardware Description Language) throughout this book. Why Ruby?

- Familiar syntax for software engineers
- Interactive development and testing
- Simulation without expensive tools
- Export to real Verilog when ready

### What You'll Build

By the end of this book, you'll have built:

- Logic gates from first principles
- An arithmetic logic unit (ALU)
- Memory systems (RAM, ROM, registers)
- A complete 8-bit CPU
- Understanding of the MOS 6502

### How to Read This Book

Each chapter builds on the previous. The code is runnable—experiment as you go. Hardware design is learned by doing, not just reading.

---

## Notes and Ideas

- Start with the "aha moment" - showing how software ultimately becomes hardware
- Use visualizations heavily - timing diagrams, circuit diagrams
- Include "Software Analogy" sidebars mapping hardware concepts to familiar software patterns
- Each chapter should have a hands-on project
- Consider a "debugging hardware" chapter - it's very different from software debugging
