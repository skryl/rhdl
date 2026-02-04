# Chapter 1: What is Computation?

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

## Mechanical Computers

### Babbage's Engines (1830s-1840s)

Charles Babbage designed two mechanical computers:

**Difference Engine:**
- Computed polynomial functions
- Used for generating mathematical tables
- Purely mechanical: gears, levers, cams
- A working version was built in 1991—it works perfectly

**Analytical Engine:**
- A general-purpose programmable computer
- Had all the components of a modern computer:
  - "Mill" (CPU/ALU)
  - "Store" (Memory)
  - Input via punched cards
  - Output via printer/plotter
  - Conditional branching!

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

### Ada Lovelace: The First Programmer (1843)

Ada Lovelace, daughter of poet Lord Byron, worked with Babbage and wrote extensive notes on the Analytical Engine. In "Note G" of her translation of an Italian article about the engine, she included what is now recognized as the first computer program: an algorithm to compute Bernoulli numbers.

**What are Bernoulli numbers?**

Bernoulli numbers (B₀, B₁, B₂, ...) are a sequence important in number theory and analysis. They appear in formulas for sums of powers:

```
1¹ + 2¹ + 3¹ + ... + n¹ = n(n+1)/2
1² + 2² + 3² + ... + n² = n(n+1)(2n+1)/6
1³ + 2³ + 3³ + ... + n³ = [n(n+1)/2]²
```

The coefficients in the general formula involve Bernoulli numbers:
```
B₀ =  1
B₁ = -1/2   (or +1/2 in some conventions)
B₂ =  1/6
B₃ =  0
B₄ = -1/30
B₅ =  0
B₆ =  1/42
B₇ =  0
B₈ = -1/30
...
```

**Ada's Original Notation**

Ada wrote her program as a table showing operations, variables, and the state of the machine at each step. Here's a portion of her diagram for computing B₇ (which she called B₈, using 1-based indexing):

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    DIAGRAM FOR THE COMPUTATION OF BERNOULLI NUMBERS             │
├───────┬───────────────┬─────────────────────────────────────────────────────────┤
│       │               │              Variables                                  │
│ Op #  │  Operation    ├────────┬────────┬────────┬────────┬────────┬───────────┤
│       │               │  V0    │  V1    │  V2    │  V3    │  V4    │   ...     │
├───────┼───────────────┼────────┼────────┼────────┼────────┼────────┼───────────┤
│   1   │  × (multiply) │  1     │  2     │  n     │        │        │           │
│   2   │  − (subtract) │  2n    │  2n-1  │        │        │        │           │
│   3   │  ÷ (divide)   │  2n-1  │  2     │        │        │        │           │
│   4   │  × (multiply) │(2n-1)/2│  ...   │        │        │        │           │
│   5   │  − (subtract) │        │        │        │        │        │           │
│   6   │  × (multiply) │        │        │        │        │        │           │
│  ...  │     ...       │        │        │        │        │        │           │
│  25   │  + (add)      │        │        │        │        │  B₇    │  Result   │
└───────┴───────────────┴────────┴────────┴────────┴────────┴────────┴───────────┘

Working Variables (the "Store"):
V0, V1, V2  = temporary calculations
V4-V10     = previously computed Bernoulli numbers (B₁ through B₆)
V11-V13    = intermediate results
V21-V24    = constants and loop counters
```

**The Algorithm in Modern Pseudocode**

Ada's algorithm, translated to modern notation:

```
# Computing Bernoulli number B_n using the recurrence relation
# B_n = -Σ(k=0 to n-1) [C(n+1,k) * B_k] / (n+1)
# where C(n,k) is the binomial coefficient "n choose k"

function bernoulli(n):
    if n == 0: return 1
    if n == 1: return -1/2

    B = array[0..n]
    B[0] = 1
    B[1] = -1/2

    for m from 2 to n:
        if m is odd and m > 1:
            B[m] = 0
            continue

        sum = 0
        for k from 0 to m-1:
            coefficient = binomial(m+1, k)
            sum = sum + coefficient * B[k]

        B[m] = -sum / (m + 1)

    return B[n]
```

**What Made Ada's Program Revolutionary**

1. **Variables and memory**: She used V0, V1, V2... as named storage locations—like variables in programming.

2. **Loops**: Her algorithm included what she called "backing" - returning to earlier operations to repeat them. This is iteration:

```
Ada's notation:                    Modern equivalent:

"Here follows a repetition        for i = 1 to n:
 of Operations 13-23"                 ... operations 13-23 ...
```

3. **Conditional branching**: She described how the engine could take different paths based on results:

> "The engine can arrange that after the first time a certain group of operations has been gone through, the expression shall be changed [so that subsequent iterations use different values]."

4. **Nested loops**: Her Bernoulli algorithm required loops within loops:

```
for n from 2 to target:           # Outer loop: each Bernoulli number
    for k from 0 to n-1:          # Inner loop: sum the series
        accumulate term
    compute B[n]
```

**Ada's Program in RHDL-Style Ruby**

Here's how Ada's algorithm might look in a modern Ruby implementation:

```ruby
# Ada Lovelace's Bernoulli number algorithm (1843)
# Translated to Ruby - she would have understood this!

def bernoulli_numbers(count)
  b = [Rational(1, 1)]  # B₀ = 1

  (1...count).each do |n|
    # Compute B_n using the recurrence relation
    # B_n = -Σ(k=0 to n-1) [C(n+1,k) * B_k] / (n+1)

    sum = Rational(0, 1)

    (0...n).each do |k|
      # This inner loop is what Ada called "backing"
      # - returning to repeat operations with new values
      coeff = binomial(n + 1, k)
      sum += coeff * b[k]
    end

    b[n] = -sum / (n + 1)
  end

  b
end

def binomial(n, k)
  return 1 if k == 0 || k == n
  (1..k).reduce(1) { |acc, i| acc * (n - k + i) / i }
end

# Run Ada's algorithm
result = bernoulli_numbers(10)
result.each_with_index do |b, i|
  puts "B_#{i} = #{b}" unless b == 0
end

# Output:
# B_0 = 1
# B_1 = -1/2
# B_2 = 1/6
# B_4 = -1/30
# B_6 = 1/42
# B_8 = -1/30
```

**The First Bug?**

Historians have found what may be the first documented computer bug in Ada's notes. In one version of her table, there's an error where she wrote "V4/V5" instead of "V5/V4". Whether this was Ada's error, a transcription error, or Babbage's is still debated. But it shows that even the first program had bugs!

**Ada's Vision**

Most remarkably, Ada understood that the Analytical Engine was not just a calculator. She saw that it could manipulate any symbols—not just numbers:

> "The Analytical Engine might act upon other things besides number, were objects found whose mutual fundamental relations could be expressed by those of the abstract science of operations, and which should be also susceptible of adaptations to the action of the operating notation and mechanism of the engine."

She gave the example of music:

> "Supposing, for instance, that the fundamental relations of pitched sounds in the science of harmony and of musical composition were susceptible of such expression and adaptations, the engine might compose elaborate and scientific pieces of music of any degree of complexity or extent."

This insight—that computation is about symbol manipulation, not arithmetic—anticipated computer science by a century. It's exactly what we discussed at the start of this chapter: computation is abstract. Ada understood this in 1843.

**Why This Matters**

Ada's program proves that:
1. **General-purpose programming existed before electronics** - Her algorithm has variables, loops, conditionals—all the essentials
2. **The concepts haven't changed** - Her program structure maps directly to modern code
3. **Hardware is irrelevant to the algorithm** - The same algorithm works on gears or transistors
4. **Abstraction is timeless** - She was thinking in terms of operations on variables, just like we do today

When you write RHDL code, you're doing exactly what Ada did: describing computation abstractly, independent of the physical implementation.

**Key insight:** The Analytical Engine was a *real computer*, Turing-complete, designed 100 years before electronic computers. It was never built due to manufacturing limitations, not theoretical ones. But Ada proved it could be programmed.

### Zuse's Z1 (1938)

Konrad Zuse built the first working programmable computer in his parents' living room in Berlin:

- Entirely mechanical (metal plates, pins, levers)
- Binary floating-point arithmetic
- 64 words of memory (22-bit words)
- Programmable via punched film
- Clock speed: ~1 Hz (one operation per second)

The Z1 could:
- Add, subtract, multiply, divide
- Store and retrieve values
- Execute conditional logic
- Run programs

It was destroyed in WWII, but Zuse rebuilt it in the 1980s.

### Relay Computers (1940s)

Before transistors, relays were the "fast" option:

**How a relay works:**
```
        Electromagnet
            ┌───┐
  Control ──┤   ├──┐
  Input     └───┘  │
                   │ (magnetic attraction)
                   ▼
  Input A ────┐   ╱ ────── Output
              └──╱
              (switch)
```

When current flows through the control input, the electromagnet pulls the switch closed, connecting Input A to Output.

**A relay AND gate:**
```
    A ──[Relay 1]──┬──[Relay 2]── Output
                   │
    B ─────────────┘ (controls Relay 2)
```

Output is HIGH only when both A AND B are HIGH.

**Notable relay computers:**
- Harvard Mark I (1944): 765,000 components, 5 tons
- Zuse Z3 (1941): First working programmable, automatic computer
- Bell Labs relay computers for military calculations

**Speed:** ~10-100 operations per second (vs. billions today)

### The Pattern Emerges

Notice what all these machines have in common:

| Machine | Switch Element | AND Gate | OR Gate | Memory |
|---------|---------------|----------|---------|---------|
| Analytical Engine | Gear engagement | Gear train | Gear train | Number wheels |
| Z1 | Metal plates | Plate arrangement | Plate arrangement | Mechanical register |
| Relay computer | Electromagnetic relay | Series relays | Parallel relays | Relay latch |
| Electronic computer | Transistor | Series transistors | Parallel transistors | Flip-flop |

**The implementation differs. The computation is identical.**

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

### What Hasn't Changed

Compare a 1940s relay computer to a modern CPU:

**1944 Harvard Mark I:**
- AND gate: Two relays in series
- OR gate: Two relays in parallel
- Memory bit: Relay latch (two relays)
- Clock: ~3 Hz

**2024 Modern CPU:**
- AND gate: Two transistors in series
- OR gate: Two transistors in parallel
- Memory bit: 6-transistor SRAM cell
- Clock: ~5 GHz

The *structure* is the same. The *implementation* is 10 billion times faster.

## Implications for Hardware Design

### Abstraction is Power

This chapter reveals why hardware design can be learned through simulation:

1. **Computation is abstract** - The same logic works regardless of implementation
2. **Simulation is equivalent** - RHDL simulating an ALU computes the same as silicon
3. **Understanding transfers** - Learn it in Ruby, build it in Verilog, fabricate in silicon

### Why Software Engineers Have an Advantage

You already understand:
- Boolean logic (if statements)
- State machines (object state)
- Data transformation (functions)
- Abstraction layers (APIs)

Hardware is the same concepts, just:
- Everything happens at once (parallelism)
- Time is explicit (clock cycles)
- Resources are finite (gates, wires)

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

## A Brief History of "Computers"

Before electronic computers, "computer" was a job title:

```
1600s-1900s: Human computers (people doing calculations)
     │
     ▼
1800s: Mechanical calculators (Babbage, Leibniz)
     │
     ▼
1930s: Electromechanical (Zuse Z1, relay machines)
     │
     ▼
1940s: Vacuum tubes (ENIAC, Colossus)
     │
     ▼
1950s: Transistors (first transistor computers)
     │
     ▼
1960s: Integrated circuits (multiple transistors on one chip)
     │
     ▼
1970s: Microprocessors (entire CPU on one chip)
     │
     ▼
Today: Billions of transistors, same fundamental logic
```

At every stage, the computation remained the same. Only the speed changed.

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

### Exercise 3: Relay Computer Simulation

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

1. **Computation is substrate-independent** - Gears, relays, or transistors all compute the same things

2. **Transistors are just fast switches** - The logic is identical to mechanical computers

3. **Turing completeness is the threshold** - Once you can build certain basic operations, you can compute anything

4. **Speed ≠ Capability** - A mechanical computer and a supercomputer can solve the same problems; one just takes longer

5. **This is why simulation works** - RHDL simulating hardware is computation simulating computation

## Further Reading

- *The Annotated Turing* by Charles Petzold - Walk through Turing's original paper
- *Engines of Logic* by Martin Davis - History of computation from Leibniz to Turing
- *Code* by Charles Petzold - Building a computer from first principles
- *The Information* by James Gleick - The history of information theory

## Notes and Ideas

- Video recommendations for marble computers, water computers
- Interactive Turing machine simulator
- Photos of Babbage's engines (Science Museum, London)
- Zuse's rebuilt Z1 (Deutsches Technikmuseum, Berlin)
- Discuss DNA computing, quantum computing as other substrates
- The philosophical implications: Is the universe a computer?
- Connection to lambda calculus (Church's equivalent formulation)
