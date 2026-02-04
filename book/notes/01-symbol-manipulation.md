# Chapter 1: Symbol Manipulation

## Overview

Before we dive into transistors and logic gates, we need to understand something profound: computation is not about electronics. It's about the manipulation of symbols according to rules. This insight frees us to see that computers can be built from anything—gears, water, marbles, or even crabs.

The transistor didn't invent computation. It just made it fast.

## The Essence of Computation

### Computation is Symbol Manipulation

At its core, computation is:
1. A set of symbols (like 0 and 1)
2. Rules for transforming those symbols
3. A mechanism to apply those rules

That's it. Nothing about electricity. Nothing about silicon.

**A simple example:**

```
Rule: If you see "AB", replace it with "BA"

Input:  AABB
Step 1: ABAB  (replaced first AB)
Step 2: BAAB  (replaced first AB)
Step 3: BABA  (replaced remaining AB)
Output: BABA
```

This is computation. We transformed symbols according to rules. The mechanism could be:
- A human with pencil and paper
- Gears and levers
- Water flowing through pipes
- Electrons through transistors

### The Turing Machine

In 1936, Alan Turing formalized computation with an elegantly simple machine:

```
┌─────────────────────────────────────────┐
│  ...  │  0  │  1  │  1  │  0  │  ...   │  ← Infinite tape
└─────────────────────────────────────────┘
                    ▲
                    │
              ┌─────┴─────┐
              │   HEAD    │  ← Read/write head
              │  State: A │
              └───────────┘
```

**Components:**
- An infinite tape divided into cells
- Each cell holds a symbol (0 or 1)
- A head that can read, write, and move left/right
- A state register
- A table of rules

**Rules look like:**
```
(Current State, Symbol Read) → (Write Symbol, Move Direction, New State)

Example rules:
(A, 0) → (1, Right, A)   # In state A, seeing 0: write 1, move right, stay in A
(A, 1) → (0, Left, B)    # In state A, seeing 1: write 0, move left, go to B
(B, 0) → (1, Right, HALT) # In state B, seeing 0: write 1, move right, stop
```

**The profound insight:** This simple machine can compute *anything* that any computer can compute. Your smartphone, a supercomputer, RHDL running on your laptop—all are equivalent in computational power to this tape-and-head machine.

### Church-Turing Thesis

> "Any function that can be computed by any mechanical process can be computed by a Turing machine."

This isn't a theorem (it can't be proven), but no one has ever found a counterexample. It suggests that computation is a fundamental concept, independent of implementation.

## Universal Computation

### What Makes Something a Computer?

A system is computationally universal (Turing-complete) if it can:
1. Store arbitrary amounts of data
2. Read and write that data
3. Make decisions based on data
4. Loop or repeat operations

Surprisingly, many simple systems meet these criteria:
- Rule 110 cellular automata (just 8 rules!)
- Conway's Game of Life
- Lambda calculus
- Even some card games (Magic: The Gathering)

### The Halting Problem

Turing also proved something can't be computed: determining whether an arbitrary program will halt or run forever.

```
HALT_CHECKER(program, input):
    if program(input) eventually halts:
        return "halts"
    else:
        return "loops forever"
```

This function cannot exist. The proof is elegant:
1. Suppose HALT_CHECKER exists
2. Create PARADOX(x) = if HALT_CHECKER(x, x) says "halts", loop forever; else halt
3. What does HALT_CHECKER(PARADOX, PARADOX) return?
4. Either answer leads to contradiction

This isn't a limitation of our technology—it's a fundamental limit of computation itself.

## Logic Gates from Anything

### The Universal Building Blocks

Any computing system needs to implement just a few logical operations:

**NOT (Inverter):**
```
Input    Output
  0   →    1
  1   →    0
```

**AND:**
```
A  B    Output
0  0  →   0
0  1  →   0
1  0  →   0
1  1  →   1
```

**OR:**
```
A  B    Output
0  0  →   0
0  1  →   1
1  0  →   1
1  1  →   1
```

With just NAND (or just NOR), you can build everything. Let's see how different media implement these:

### Water Logic Gates

```
         WATER AND GATE

    A (water)    B (water)
         │            │
         ▼            ▼
    ┌────┴────────────┴────┐
    │                      │
    │    Both streams      │
    │    must flow to      │
    │    fill chamber      │
    │                      │
    └──────────┬───────────┘
               │
               ▼
         Output (water)
         (only flows if both A and B flow)
```

Water computers have been built! They're slow (water doesn't flow fast), but they compute correctly.

### Marble Logic Gates

```
         MARBLE AND GATE

    A (marble)    B (marble)
         │            │
         ▼            ▼
    ┌────┴────┐  ┌────┴────┐
    │ Lever 1 │  │ Lever 2 │
    └────┬────┘  └────┬────┘
         │            │
         └─────┬──────┘
               │
         ┌─────▼─────┐
         │  Trap     │
         │  (opens   │
         │  only if  │
         │  both     │
         │  levers   │
         │  pushed)  │
         └─────┬─────┘
               │
               ▼
         Output marble
```

YouTube has many examples of marble computers implementing full adders!

### Domino Logic Gates

```
         DOMINO OR GATE

    A dominoes────┐
                  │
                  ├────▶ Output dominoes
                  │
    B dominoes────┘

    (Either path can trigger the output)
```

A domino AND gate requires a specially balanced domino that only falls when hit from both sides simultaneously.

### Crab Logic Gates

In 2012, researchers built logic gates using soldier crabs:

- Crabs walk in predictable swarm patterns
- Two swarms colliding merge into one (AND behavior)
- Channels direct the swarms
- Output depends on which swarms arrived

It's slow. It's impractical. But it computes.

### The Point

**If you can implement a switch—something that can be ON or OFF based on an input—you can compute.**

The medium doesn't matter:
- Gears meshing or not meshing
- Water flowing or not flowing
- Marbles present or absent
- Electrons flowing or not flowing
- Crabs present or absent

## The Transistor: Just a Faster Switch

### What a Transistor Actually Does

A transistor is a switch controlled by electricity:

```
         MOSFET TRANSISTOR

              Drain
                │
                │
         ───────┴───────
        │               │
  Gate ─┤               │
        │               │
         ───────┬───────
                │
                │
             Source

When Gate voltage is HIGH: current flows from Drain to Source
When Gate voltage is LOW: no current flows
```

That's it. It's a switch. Like a relay, but:
- No moving parts
- Switches in nanoseconds (not milliseconds)
- Uses microwatts (not watts)
- Can be made nanometers small

### From Relays to Transistors

| Property | Relay | Vacuum Tube | Transistor |
|----------|-------|-------------|------------|
| Switching speed | ~10ms | ~1μs | ~1ns |
| Size | ~1 inch | ~1 inch | ~10nm |
| Power | ~1W | ~1W | ~1μW |
| Reliability | Mechanical wear | Burns out | Very high |
| Cost (1950) | $1 | $5 | N/A |
| Cost (today) | $0.50 | $10 | $0.00000001 |

**The transistor didn't change what we could compute. It changed how fast and small we could compute.**

### Moore's Law: Scaling the Switch

Gordon Moore observed that transistor density doubles roughly every 2 years:

```
Year    Transistors per chip
1971    2,300 (Intel 4004)
1980    30,000
1990    1,000,000
2000    42,000,000
2010    2,000,000,000
2020    50,000,000,000
```

But each transistor is still just a switch. We just have billions of them now.

## Implications for This Book

### Why RHDL Works

This chapter reveals why hardware design can be learned through simulation:

1. **Computation is abstract** - The same logic works regardless of implementation
2. **Simulation is equivalent** - RHDL simulating an ALU computes the same as silicon
3. **Understanding transfers** - Learn it in Ruby, build it in Verilog, fabricate in silicon

### The RHDL Philosophy

RHDL embraces this universality:

```ruby
# This RHDL code...
class MyAnd < SimComponent
  input :a
  input :b
  output :y

  behavior do
    y <= a & b
  end
end

# ...describes the same computation whether:
# - Simulated in Ruby
# - Synthesized to Verilog
# - Fabricated in silicon
# - Built from relays
# - Implemented with water pipes
```

The description is the computation. The implementation is just engineering.

## Hands-On: Thinking in Switches

### Exercise 1: Paper Turing Machine

Implement a simple Turing machine on paper:
- Draw a tape (grid of squares)
- Track state with a marker
- Execute rules by hand

Program to try: Binary increment
```
States: SCAN, CARRY, DONE
Initial state: SCAN (head at rightmost digit)

Rules:
(SCAN, 0) → (0, Left, SCAN)   # Skip zeros going left
(SCAN, 1) → (1, Left, SCAN)   # Skip ones going left
(SCAN, _) → (_, Right, CARRY) # Hit blank, start carry
(CARRY, 0) → (1, Left, DONE)  # Found 0, make it 1, done
(CARRY, 1) → (0, Right, CARRY)# Found 1, make it 0, keep carrying
(CARRY, _) → (1, Left, DONE)  # Overflow, add new 1

Input:  _ 1 0 1 1 _
Output: _ 1 1 0 0 _  (1011 + 1 = 1100 in binary, i.e., 11 + 1 = 12)
```

### Exercise 2: Design a Mechanical AND Gate

Sketch a mechanism using:
- Levers
- Springs
- Pivots

That implements: Output moves only when both Input A AND Input B move.

### Exercise 3: Computation Speed

```ruby
# In RHDL, imagine each gate takes 10ms (like a relay)
# How long would it take to add two 8-bit numbers?

# An 8-bit ripple carry adder has:
# - 8 full adders in series
# - Each full adder: ~5 gate delays for carry propagation
# - Total: ~40 gate delays

# With relays: 40 × 10ms = 400ms per addition
# That's 2.5 additions per second!

# With transistors at 1ns: 40 × 1ns = 40ns per addition
# That's 25,000,000 additions per second!
```

## Key Takeaways

1. **Computation is symbol manipulation** - Rules transforming symbols, nothing more
2. **Turing machines define the limit** - What's computable is independent of hardware
3. **Any switch can compute** - Water, marbles, gears, electrons—all equivalent
4. **The halting problem is unsolvable** - Some things genuinely can't be computed
5. **Transistors are just fast switches** - The logic is identical to mechanical computers

## Further Reading

- *The Annotated Turing* by Charles Petzold - Walk through Turing's original paper
- *Engines of Logic* by Martin Davis - History of computation from Leibniz to Turing
- *Code* by Charles Petzold - Building a computer from first principles
- Turing's original 1936 paper: "On Computable Numbers"

> See [Appendix B](appendix-b-turing-machines.md) for a formal treatment of Turing machines with additional examples.
