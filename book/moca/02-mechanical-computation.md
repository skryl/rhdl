# Chapter 2: Mechanical Computation

## Overview

A century before transistors, engineers built working computers from gears, levers, and electromagnetic relays. These machines prove that computation is truly substrate-independent—the same algorithms run on brass cogs and silicon chips.

This chapter traces the history from Babbage's visionary designs through Zuse's garage workshop to the relay behemoths of World War II.

## Babbage's Engines (1830s-1840s)

Charles Babbage designed two mechanical computers that anticipated every major component of modern machines.

### The Difference Engine

The simpler of Babbage's designs, the Difference Engine computed polynomial functions using the method of finite differences:

```
Computing x² using differences:

 x    x²   1st diff   2nd diff
 1     1
              3
 2     4              2
              5
 3     9              2
              7
 4    16              2
              9
 5    25
```

The second differences are constant! This means we can compute the next value by adding:
- Add 2nd diff to 1st diff → new 1st diff
- Add new 1st diff to previous result → next x²

**Mechanical implementation:**
- Number wheels (like odometer digits)
- Carry mechanisms between wheels
- Crank operation adds the differences

**A working version was built in 1991** at the Science Museum, London—it works perfectly, proving Babbage's design was sound.

### The Analytical Engine

The Analytical Engine (1837) was far more ambitious—a general-purpose programmable computer:

```
┌─────────────────────────────────────────────────┐
│           ANALYTICAL ENGINE (1837)               │
├─────────────────────────────────────────────────┤
│                                                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐  │
│  │  INPUT   │───▶│   MILL   │───▶│  OUTPUT  │  │
│  │ (Cards)  │    │  (ALU)   │    │(Printer) │  │
│  └──────────┘    └────┬─────┘    └──────────┘  │
│                       │                         │
│                       ▼                         │
│                 ┌──────────┐                    │
│                 │  STORE   │                    │
│                 │(Memory)  │                    │
│                 │1000 x 50 │                    │
│                 │  digits  │                    │
│                 └──────────┘                    │
│                                                  │
└─────────────────────────────────────────────────┘
```

**Components mapped to modern equivalents:**
| Analytical Engine | Modern Computer |
|-------------------|-----------------|
| Mill | CPU / ALU |
| Store | RAM |
| Operation cards | Program (instructions) |
| Variable cards | Data input |
| Number cards | Constants |
| Barrel | Microcode ROM |
| Printer/plotter | Output device |

**Key capabilities:**
- **Arithmetic**: Add, subtract, multiply, divide
- **Memory**: 1000 numbers of 50 decimal digits each
- **Programming**: Punched cards (borrowed from Jacquard looms)
- **Conditional branching**: The machine could skip cards based on results
- **Loops**: Cards could be re-read

The Analytical Engine was **Turing-complete**—it could compute anything a modern computer can compute. It was never built due to manufacturing limitations, not theoretical ones.

## Ada Lovelace: The First Programmer (1843)

Ada Lovelace, daughter of poet Lord Byron, collaborated with Babbage and wrote extensive notes on the Analytical Engine. In "Note G," she described an algorithm to compute Bernoulli numbers—the first published computer program.

### Her Program's Structure

```
Variables: V0, V1, V2, V3, ... (memory locations)
Operations: +, -, ×, ÷
Control: Loops ("backing"), conditionals

Pseudocode of her algorithm:
  V1 = 1
  V2 = 2
  V3 = n (which Bernoulli number to compute)

  LOOP:
    V4 = V2 - V1        # Counter logic
    V5 = V4 / V2
    V6 = V5 × V13       # Accumulate terms
    ...
    IF counter > 0: BACK TO LOOP
```

### Key Insights

Ada understood that the Analytical Engine was not just a calculator:

> "The Analytical Engine might act upon other things besides number, were objects found whose mutual fundamental relations could be expressed by those of the abstract science of operations..."

She predicted the engine could compose music—a century before anyone would hear computer-generated sound.

> See [Appendix A](appendix-a-ada-lovelace-program.md) for Ada's complete program, including her original diagram notation and executable Ruby implementation.

## Zuse's Z1 (1938)

Konrad Zuse built the first working programmable computer in his parents' living room in Berlin.

### Z1 Specifications

```
┌─────────────────────────────────────────┐
│              ZUSE Z1 (1938)              │
├─────────────────────────────────────────┤
│                                          │
│  Memory:      64 words × 22 bits        │
│  Arithmetic:  Binary floating-point     │
│  Input:       Punched 35mm film         │
│  Clock:       ~1 Hz (1 op/second)       │
│  Technology:  Metal plates, pins        │
│                                          │
│  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐    │
│  │Plate│  │Plate│  │Plate│  │Plate│    │
│  │Stack│  │Stack│  │Stack│  │Stack│    │
│  └──┬──┘  └──┬──┘  └──┬──┘  └──┬──┘    │
│     └────────┴────────┴────────┘        │
│              Mechanical Bus             │
│                                          │
└─────────────────────────────────────────┘
```

**Capabilities:**
- Add, subtract, multiply, divide
- Store and retrieve values
- Execute conditional logic
- Run programs from punched film

**Mechanical switching:**
```
    ZUSE'S BINARY SWITCH

    Input  ────┐
               │   ┌─────────┐
               └───│ Sliding │───── Output
                   │  Plate  │
    Control ───────│─────────│
                   └─────────┘

    Control LOW:  Plate blocks connection
    Control HIGH: Plate slides, connects input to output
```

The Z1 was destroyed in WWII but rebuilt by Zuse in the 1980s.

### Z3: First Working Programmable Computer (1941)

Zuse's Z3 used relays instead of mechanical plates:
- 2,600 relays
- 22-bit floating point
- 5-10 Hz clock speed
- Proven Turing-complete (in 1998)

## Relay Computers

Before transistors, electromagnetic relays were the "fast" switching element.

### How a Relay Works

```
         ELECTROMAGNETIC RELAY

              Electromagnet
                  ┌───┐
    Control ──────┤   ├──────┐
    Input         └───┘      │ (magnetic pull)
                             ▼
    Input A ────────┐   ╱ ────── Output
                    └──╱
                  (armature)

When Control is energized:
  - Electromagnet creates magnetic field
  - Armature is pulled down
  - Contact closes
  - Input A connects to Output

When Control is off:
  - Spring returns armature
  - Contact opens
  - No connection
```

### Relay Logic Gates

**AND Gate (Series relays):**
```
    +V ────[Relay A]────[Relay B]──── Output

    A and B must both be energized for output
```

**OR Gate (Parallel relays):**
```
         ┌────[Relay A]────┐
    +V ──┤                 ├──── Output
         └────[Relay B]────┘

    Either A or B energized gives output
```

**NOT Gate (Normally-closed relay):**
```
    +V ────┬────[Relay A]────┐
           │        NC       │
           └─────────────────┴──── Output

    When A is off: output is connected to +V
    When A is on: armature breaks connection
```

**Memory Cell (SR Latch from relays):**
```
         ┌──────[R1]──────┐
    SET ─┤                ├── Q
         │    ┌───────┐   │
         └────┤       ├───┘
              │  R2   │
    RESET ────┤       ├────── Q̄
              └───────┘
```

### Notable Relay Computers

**Harvard Mark I (1944):**
- 765,000 components
- 5 tons weight
- 3 operations per second
- Used for ballistics calculations

```
┌────────────────────────────────────────────────┐
│         HARVARD MARK I (IBM ASCC)               │
├────────────────────────────────────────────────┤
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │  72 accumulators × 23 decimal digits    │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐     │
│  │Relay│ │Relay│ │Relay│ │Relay│ │Relay│ ... │
│  │ Bay │ │ Bay │ │ Bay │ │ Bay │ │ Bay │     │
│  └─────┘ └─────┘ └─────┘ └─────┘ └─────┘     │
│                                                 │
│  Length: 51 feet    Height: 8 feet             │
│  Clock:  ~3 Hz      Power: 5 HP motor          │
│                                                 │
└────────────────────────────────────────────────┘
```

**Bell Labs Model V (1946):**
- Built for military fire control
- Two independent processors
- Could solve differential equations

## The Pattern Emerges

Every mechanical computer shared the same logical structure:

| Machine | Switch Element | AND Gate | OR Gate | Memory |
|---------|---------------|----------|---------|---------|
| Analytical Engine | Gear engagement | Gear train | Gear train | Number wheels |
| Z1 | Metal plates | Plate arrangement | Plate arrangement | Mechanical register |
| Relay computer | Electromagnetic relay | Series relays | Parallel relays | Relay latch |
| Electronic computer | Transistor | Series transistors | Parallel transistors | Flip-flop |

**The implementation differs. The computation is identical.**

## RHDL: The Same Logic

The gates we design in RHDL work identically to relay logic:

```ruby
# RHDL AND gate
class And < SimComponent
  input :a
  input :b
  output :y

  behavior do
    y <= a & b
  end
end

# Relay equivalent (pseudo-structural):
# y is HIGH only when both a AND b are energized
```

If we could synthesize RHDL to relay circuits instead of silicon, the logic would work perfectly—just 10 million times slower.

## A Brief Timeline

```
1837  Babbage designs Analytical Engine
1843  Ada Lovelace writes first program
1936  Turing defines computation formally
1938  Zuse builds Z1 (mechanical)
1941  Zuse builds Z3 (relay-based, Turing-complete)
1944  Harvard Mark I operational
1946  ENIAC (vacuum tubes) - 5,000 ops/sec
1947  Transistor invented
1958  First integrated circuit
1971  Intel 4004 (2,300 transistors)
2024  Modern CPUs (50+ billion transistors)
```

The logic stayed the same. The switches got smaller and faster.

## Hands-On Exercises

### Exercise 1: Relay Counter

Design a 2-bit counter using relay logic:
- Two memory cells (each is an SR latch)
- Increment logic
- Clock input

### Exercise 2: Babbage's Method

Compute x³ for x = 1 to 10 using the method of differences:
1. Calculate the first few values by hand
2. Find the constant third difference
3. Generate the sequence using only addition

### Exercise 3: Speed Comparison

A relay switches in ~10ms. A transistor switches in ~1ns.

If we built a relay-based CPU that could run at 10 Hz:
- How long to sort 1000 numbers with bubble sort? (O(n²))
- How long for the same algorithm on a 1 GHz CPU?

## Key Takeaways

1. **Babbage anticipated everything** - CPU, RAM, I/O, conditionals, loops
2. **Ada was the first programmer** - Her program would run on modern computers
3. **Zuse proved it works** - First working programmable computer in a living room
4. **Relays compute correctly** - Just slowly
5. **Abstraction is the key** - RHDL describes the logic; implementation is separate

## Further Reading

- *The Difference Engine* by Doron Swade - Building Babbage's machine
- *Konrad Zuse: The Computer - My Life* - Zuse's autobiography
- *The Computer from Pascal to von Neumann* by Herman Goldstine
- Ada Lovelace's original notes (available online)
