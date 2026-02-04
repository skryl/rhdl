# Chapter 12: Asynchronous Computing

*Computation without a global clock*

---

## The Tyranny of the Clock

Every computer you've used runs on a clock—a metronome that synchronizes all operations. But clocks create problems:

- **Power consumption**: Clock distribution uses 30-50% of chip power
- **Worst-case timing**: Everything must wait for the slowest path
- **Electromagnetic interference**: Clocks create predictable radiation patterns
- **Global synchronization**: Clock skew limits chip size and speed

What if we could compute without a clock?

---

## Self-Timed Circuits

Asynchronous circuits synchronize locally, using handshaking protocols instead of a global clock.

### The Basic Handshake

```
Sender                          Receiver
   │                               │
   │──── request ─────────────────▶│
   │                               │ (processes data)
   │◀──── acknowledge ────────────│
   │                               │
   │  (prepares next data)         │
   │                               │
```

**Four-phase handshake:**
1. Sender raises request, puts data on bus
2. Receiver processes data, raises acknowledge
3. Sender lowers request
4. Receiver lowers acknowledge

**Two-phase handshake:**
- Transitions (edges) carry information
- Faster but harder to implement

---

## Delay-Insensitive Circuits

The holy grail: circuits that work regardless of wire and gate delays.

### Muller C-Element

The fundamental building block of asynchronous circuits:

```
     a ──┐
         ├──▶ c
     b ──┘

Truth table:
a  b  c(prev) │ c(next)
0  0    x     │   0
1  1    x     │   1
0  1    c     │   c      (holds previous value)
1  0    c     │   c      (holds previous value)
```

Output changes only when both inputs agree.

### NULL Convention Logic (NCL)

Uses three-valued logic: DATA0, DATA1, and NULL.

**Dual-rail encoding:**
```
Value    Rail0  Rail1
NULL       0      0
DATA0      1      0
DATA1      0      1
Invalid    1      1    (never occurs)
```

**NCL wavefront:**
1. NULL wavefront clears all gates
2. DATA wavefront computes result
3. Completion detected when all outputs are DATA
4. Request NULL, wait for NULL completion

---

## Quasi-Delay-Insensitive (QDI)

Practical middle ground: delay-insensitive except for isochronic forks.

**Isochronic fork assumption:**
When a signal fans out, all branches arrive "at the same time."

```
        ┌──▶ A
   x ───┤
        └──▶ B

Assumption: A and B see x change simultaneously
```

This is physically reasonable for short wires on a chip.

---

## Asynchronous Pipeline

### Micropipeline (Sutherland, 1989)

```
┌─────────┐    ┌─────────┐    ┌─────────┐
│ Stage 1 │───▶│ Stage 2 │───▶│ Stage 3 │
└─────────┘    └─────────┘    └─────────┘
     │              │              │
     ▼              ▼              ▼
   ┌───┐          ┌───┐          ┌───┐
   │ C │◀────────│ C │◀────────│ C │◀── ack_in
   └───┘          └───┘          └───┘
     │              │              │
     ▼              ▼              ▼
   req_out        req            req
```

Each stage:
1. Waits for request from previous stage
2. Captures data in latch
3. Signals acknowledge to previous stage
4. Starts processing, signals request to next stage

### Bundled Data

Simpler approach: data travels with a "valid" signal.

```
       ┌─────────────────────────────┐
data ──┤     Combinational Logic     ├── result
       └─────────────────────────────┘
                                     │
                    ┌────────────────┤
valid ──[delay]────▶│ C-element     │───▶ valid_out
                    └────────────────┘
                           ▲
                           │
                        ack_in
```

The delay must be longer than the worst-case combinational delay.

---

## Why Asynchronous?

### Advantages

**Average-case performance:**
```
Synchronous:   ████████████████████  (worst case every cycle)
Asynchronous:  ████  ██████  ████    (actual time per operation)
```

**Power proportional to activity:**
- No clock means no power when idle
- Each gate switches only when computing

**Modularity:**
- Components are truly independent
- No clock domain crossing issues
- Easier IP integration

**Security:**
- No clock to analyze for side-channel attacks
- Timing variations make attacks harder

### Disadvantages

- More complex design and verification
- Larger area (extra handshaking logic)
- Fewer EDA tools available
- Testing is more difficult

---

## Real-World Asynchronous Systems

### Commercial Successes

**ARM996HS**: Asynchronous ARM processor
- Used in implanted medical devices
- Near-zero standby power

**Intel 80C51 (Handshake Solutions)**:
- Asynchronous 8051 microcontroller
- Medical and security applications

**Epson ACT11**: Asynchronous RISC processor

### Research Chips

**Caltech:**
- MiniMIPS (1998): Fully asynchronous MIPS
- Lutonium (2003): 8051-compatible, 1.8V, 200MHz equivalent

**University of Manchester:**
- Amulet series: Asynchronous ARM processors
- SpiNNaker: Million-core brain simulator (locally asynchronous)

---

## Asynchronous Meets Other Paradigms

### GALS: Globally Asynchronous, Locally Synchronous

Best of both worlds:
- Synchronous islands with local clocks
- Asynchronous communication between islands
- No global clock distribution

```
┌─────────────────┐     async     ┌─────────────────┐
│   Sync Island   │◀────────────▶│   Sync Island   │
│   (100 MHz)     │    channel    │   (150 MHz)     │
└─────────────────┘               └─────────────────┘
```

### Asynchronous Dataflow

Natural fit: dataflow is inherently asynchronous.

```
   ┌───┐        ┌───┐        ┌───┐
──▶│ + │───────▶│ × │───────▶│ + │──▶
   └───┘        └───┘        └───┘
     ▲                          ▲
     │    Tokens flow when      │
     │    data and space        │
     │    are available         │
     └──────────────────────────┘
```

### Asynchronous Neural Networks

Spiking neural networks are naturally asynchronous:
- Neurons fire when threshold is reached
- No global clock synchronizing computation
- Event-driven, low power

---

## Design Methodology

### Communicating Hardware Processes (CHP)

High-level language for asynchronous design:

```
*[ L?x; R!f(x) ]

Meaning:
*[...]         - infinite loop
L?x            - receive x from channel L
;              - sequential composition
R!f(x)         - send f(x) on channel R
```

### Petri Nets

Graphical model for asynchronous behavior:

```
     ●          ● (tokens = data ready)
     │          │
     ▼          ▼
   ┌───┐      ┌───┐
   │ T1│      │ T2│  (transitions = computations)
   └───┘      └───┘
     │          │
     ▼          ▼
     ○          ○    (places = data storage)
```

Transitions fire when all input places have tokens.

---

## Comparison: Sync vs Async

| Aspect | Synchronous | Asynchronous |
|--------|-------------|--------------|
| Timing | Clock-based | Handshake-based |
| Speed | Worst-case limited | Average-case |
| Power | Clock always runs | Activity-proportional |
| Modularity | Clock domains | True independence |
| Design | Mature tools | Specialized tools |
| Area | Smaller | 20-50% overhead |
| Testing | Straightforward | Complex |
| EMI | Predictable spikes | Spread spectrum |

---

## RHDL Approach

See [Appendix L](appendix-l-asynchronous.md) for complete implementations:

```ruby
# Muller C-element in RHDL
class CElement < SimComponent
  input :a
  input :b
  output :c

  behavior do
    if a == b
      c <= a
    end
    # else: hold previous value
  end
end
```

---

## The Future

Asynchronous computing may become more important as:
- Clock distribution becomes harder at smaller nodes
- Power efficiency becomes critical (mobile, IoT, medical)
- Security concerns grow (side-channel attacks)
- Heterogeneous integration (chiplets) increases

The principles of local synchronization and handshaking will likely blend with synchronous design in hybrid approaches.

---

## Summary

- **Clocks have costs**: power, worst-case timing, EMI, skew
- **Handshaking replaces clocking**: request/acknowledge protocols
- **C-element is fundamental**: outputs change only when inputs agree
- **QDI is practical**: delay-insensitive with isochronic fork assumption
- **GALS offers compromise**: synchronous islands, asynchronous interconnect
- **Natural fit for dataflow**: tokens flow when ready
- **Security advantage**: no clock means harder timing attacks

---

## Exercises

1. Design a 4-phase handshake controller in RHDL
2. Implement a QDI full adder using dual-rail encoding
3. Build an asynchronous FIFO with bundled data
4. Compare power consumption of sync vs async counters
5. Design a GALS wrapper for a synchronous module

---

## Further Reading

- Sparsø & Furber, *Principles of Asynchronous Circuit Design*
- Sutherland, "Micropipelines" (Turing Award lecture, 1989)
- Martin, "The Design of an Asynchronous Microprocessor"
- Nowick & Singh, "Asynchronous Design" (survey papers)

---

*Next: [Chapter 15 - Neuromorphic Computing](13-neuromorphic-computing.md)*

*Appendix: [Appendix L - Asynchronous Implementation](appendix-l-asynchronous.md)*
