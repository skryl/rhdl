# Chapter 3: Biological Computation

## Overview

Life itself computes. From DNA replication to neural networks, biological systems process information using the same fundamental principles as silicon chips—just with different substrates. This chapter explores how nature performs computation, revealing deep connections between biology and digital logic.

## DNA: The Original Digital Storage

### The Genetic Code

DNA stores information in a 4-symbol alphabet: A, T, G, C (adenine, thymine, guanine, cytosine):

```
DNA:    ...ATCGATCGATCG...
         │ │ │ │ │ │ │
         base pairs

Encoding: Each base pair = 2 bits of information
          (log₂(4) = 2)

Human genome: ~3 billion base pairs
            = ~6 billion bits
            = ~750 megabytes

All in a nucleus 6 micrometers across!
```

Compare storage density:
| Medium | Bits per mm³ |
|--------|-------------|
| Hard drive | 10⁹ |
| Flash memory | 10¹⁰ |
| DNA | 10¹⁹ |

DNA is a billion times denser than flash memory.

### DNA as a Computing Substrate

In 1994, Leonard Adleman demonstrated that DNA molecules could solve computational problems.

**The Problem:** Hamiltonian Path (visit all cities exactly once)

```
Graph:
    A ──── B
    │ ╲    │
    │  ╲   │
    │   ╲  │
    D ──── C

Find path visiting A, B, C, D exactly once.
```

**DNA Solution:**

1. **Encode cities as DNA sequences:**
```
City A: ACTTGCAG
City B: TCGTACGA
City C: GGCTATGT
City D: AGTCGACT
```

2. **Encode edges as complements:**
```
Edge A→B: complement of (end of A + start of B)
        = complement of GCAGTCGT
        = CGTCAGCA

This fragment bridges A and B sequences
```

3. **Mix all sequences in a test tube**

4. **Let chemistry happen:**
   - DNA strands self-assemble
   - Billions of possible paths form simultaneously
   - Massive parallelism!

5. **Filter for correct answer:**
   - PCR amplification of correct-length strands
   - Gel electrophoresis to separate by length
   - Affinity separation for strands containing all cities

**Result:** Test tube contains DNA encoding the Hamiltonian path.

### DNA Computing Trade-offs

| Property | DNA Computer | Silicon Computer |
|----------|-------------|-----------------|
| Parallelism | ~10¹⁸ operations at once | ~10⁹ (GPU) |
| Speed per operation | Hours | Nanoseconds |
| Energy per operation | ~10⁻¹⁹ J | ~10⁻¹² J |
| Programming | Difficult | Easy |
| Error rate | High | Very low |

DNA computing excels at problems with massive search spaces where parallelism helps.

## Neurons as Logic Gates

### The Biological Neuron

```
         BIOLOGICAL NEURON

         Dendrites (inputs)
              │ │ │
              ▼ ▼ ▼
         ┌─────────┐
         │  Cell   │
         │  Body   │──────────▶ Axon (output)
         │ (soma)  │
         └─────────┘

    Inputs:  Chemical signals at synapses
    Process: Sum weighted inputs
    Output:  Fire (spike) if sum > threshold
```

**Mathematical model:**
```
output = 1  if  Σ(wᵢ × inputᵢ) + bias > threshold
         0  otherwise
```

This is a **threshold logic unit**—it computes a weighted sum and compares to a threshold.

### Neurons Implement Logic Gates

**AND Gate** (high threshold, equal weights):
```
    w=0.6      w=0.6
    ───────┐  ┌───────
           │  │
           ▼  ▼
         ┌─────┐
         │ Σ>1 │──────▶ Output
         └─────┘
         threshold=1

    Inputs    Sum     Output
    0, 0      0       0
    0, 1      0.6     0
    1, 0      0.6     0
    1, 1      1.2     1  ✓ (only case > 1)
```

**OR Gate** (low threshold):
```
    w=0.6      w=0.6
    ───────┐  ┌───────
           │  │
           ▼  ▼
         ┌──────┐
         │ Σ>0.5│──────▶ Output
         └──────┘
         threshold=0.5

    Inputs    Sum     Output
    0, 0      0       0
    0, 1      0.6     1  ✓
    1, 0      0.6     1  ✓
    1, 1      1.2     1  ✓
```

**NOT Gate** (inhibitory input):
```
    w=-1
    ───────────┐
               │
               ▼
         ┌──────┐
    1 ───│ Σ>0  │──────▶ Output
   bias  └──────┘

    Input    Sum      Output
    0        1        1
    1        0        0
```

### The Scale of Neural Computation

| Property | Human Brain |
|----------|-------------|
| Neurons | ~86 billion |
| Synapses | ~150 trillion |
| Connections per neuron | ~7,000 average |
| Power consumption | ~20 watts |
| Operations per second | ~10¹⁶ (estimated) |

For comparison, a modern GPU uses ~300W for ~10¹⁴ ops/sec.

The brain is remarkably efficient—it does ~10¹⁵ ops/watt, while silicon achieves ~10¹¹ ops/watt.

## Cellular Automata

Perhaps the most striking example of computation from simple rules is **cellular automata**: grids of cells following identical local rules that produce astonishing complexity.

### Elementary Cellular Automata (1D)

Stephen Wolfram classified all 256 possible rules for 1D cellular automata with 2 states and 3-cell neighborhoods.

**Rule 110:**
```
Current pattern:  111  110  101  100  011  010  001  000
New center cell:   0    1    1    0    1    1    1    0
                   ─────────────────────────────────────
                   Binary: 01101110 = 110 (hence "Rule 110")
```

**Evolution of Rule 110:**
```
Gen 0:  ..........................................#.
Gen 1:  .........................................##.
Gen 2:  ........................................###.
Gen 3:  .......................................##.#.
Gen 4:  ......................................#####.
Gen 5:  .....................................##...#.
Gen 6:  ....................................###..##.
Gen 7:  ...................................##.#.###.
...
        (complex triangular patterns emerge)
```

**Rule 110 is Turing complete!** Matthew Cook proved in 2004 that any computation can be encoded in Rule 110's initial conditions.

### Conway's Game of Life (2D)

John Conway's Game of Life (1970) uses three simple rules on a 2D grid:

```
Rules:
1. A live cell with 2-3 live neighbors survives
2. A dead cell with exactly 3 live neighbors becomes alive
3. All other cells die or stay dead
```

**Common patterns:**

**Still lifes (stable):**
```
Block:     Beehive:      Loaf:
 ##         .##.         .##.
 ##        #..#         #..#
            .##.        .#.#
                         .#.
```

**Oscillators (periodic):**
```
Blinker (period 2):
 .#.          ...
 .#.    →     ###
 .#.          ...
```

**Spaceships (moving):**
```
Glider (moves diagonally):
 .#.     ..#     ...     #..     .#.
 ..#  →  #.#  →  .##  →  ..#  →  ..#
 ###     .##     .##     .##     ###
```

**Glider Gun (emits gliders):**
```
                              #
                            # #
                  ##      ##            ##
                 #   #    ##            ##
      ##        #     #   ##
      ##        #   # ##    # #
                #     #       #
                 #   #
                  ##
```

### Life is Universal

People have built **working computers** inside the Game of Life:
- Logic gates from glider collisions
- Memory from stable patterns
- Clocks from oscillators
- Complete CPUs running programs

It's the ultimate proof: three rules about counting neighbors can compute anything.

> See [Appendix D](appendix-d-cellular-automata.md) for detailed patterns, Wireworld, and RHDL implementations.

## Biological Computing Examples in RHDL

### Neural AND Gate

```ruby
class NeuralAnd < SimComponent
  input :a
  input :b
  output :y

  WEIGHT = 0.6
  THRESHOLD = 1.0

  behavior do
    sum = (a.to_i * WEIGHT) + (b.to_i * WEIGHT)
    y <= (sum > THRESHOLD) ? 1 : 0
  end
end
```

### Cellular Automaton (Rule 110)

```ruby
class Rule110Cell < SimComponent
  input :left
  input :center
  input :right
  input :clk
  output :state

  # Rule 110: 01101110 in binary
  RULE = 0b01101110

  behavior do
    on_rising_edge(clk) do
      # 3-bit neighborhood index
      index = (left << 2) | (center << 1) | right
      # Look up new state in rule
      state <= (RULE >> index) & 1
    end
  end
end
```

### Simple Neuron Model

```ruby
class Neuron < SimComponent
  input :inputs, width: 8    # 8 input signals
  input :weights, width: 32  # 8 x 4-bit weights
  input :threshold, width: 8
  output :fire

  behavior do
    weighted_sum = 0
    8.times do |i|
      input_bit = (inputs >> i) & 1
      weight = (weights >> (i * 4)) & 0xF
      weighted_sum += input_bit * weight
    end
    fire <= (weighted_sum > threshold) ? 1 : 0
  end
end
```

## Why Biology Matters for Hardware Design

### Lessons from Nature

1. **Massive parallelism is natural**
   - Brain: 86 billion neurons computing simultaneously
   - DNA: 10¹⁸ molecules reacting at once
   - Silicon is catching up (GPUs, TPUs)

2. **Simple rules create complex behavior**
   - Neurons: weighted sum + threshold
   - Cells: count neighbors
   - Gates: AND, OR, NOT

3. **Efficiency comes from architecture**
   - Brain: 20 watts for human intelligence
   - Near-memory computing
   - Sparse, event-driven activation

4. **Self-organization works**
   - DNA self-assembles
   - Neural networks learn their weights
   - Future: grown rather than manufactured?

### Neuromorphic Hardware

Modern chips are borrowing from biology:

| Approach | Example | Inspiration |
|----------|---------|-------------|
| Neural accelerators | Google TPU | Matrix multiply |
| Spiking neural nets | Intel Loihi | Neuron timing |
| In-memory compute | Analog AI | Brain efficiency |
| Memristors | HP Labs | Synapse plasticity |

## The Continuum of Computation

```
          SLOW ◄─────────────────────────────────────► FAST

DNA computing     Neurons        Relays      Transistors
(hours)          (milliseconds)  (10ms)      (nanoseconds)

          DIFFERENT SUBSTRATES, SAME COMPUTATION
```

When you design hardware in RHDL, you're working at the level of abstraction that spans all these substrates. The logic is the same whether implemented with proteins or silicon.

## Hands-On Exercises

### Exercise 1: Neural XOR

A single neuron cannot compute XOR (it's not linearly separable). Design a network of threshold neurons that does:

```
    A ────┬────[N1]────┐
          │            ├────[N3]──── Output
    B ────┼────[N2]────┘
          │
          └────[N1 and N2 also receive B and A]
```

Hint: N1 computes (A AND NOT B), N2 computes (B AND NOT A), N3 computes OR.

### Exercise 2: Game of Life in RHDL

Implement a 3x3 Game of Life grid:
```ruby
class LifeCell < SimComponent
  input :n, :ne, :e, :se, :s, :sw, :w, :nw  # 8 neighbors
  input :clk
  output :alive

  # Count neighbors and apply rules
  # ...
end
```

### Exercise 3: DNA Algorithm

Write pseudocode for a DNA computing solution to:
- Find two numbers in a list that sum to a target value
- Hint: Encode each number, generate all pairs, filter for target sum

## Key Takeaways

1. **DNA computes through chemistry** - Massive parallelism, slow per operation
2. **Neurons are threshold logic** - Weighted sums computing AND, OR, NOT
3. **Cellular automata prove universality** - Rule 110 and Life are Turing complete
4. **Biology is efficient** - 20W brain vs 300W GPU, similar capability
5. **The abstraction holds** - RHDL describes logic that works on any substrate

## Further Reading

- *A New Kind of Science* by Stephen Wolfram - Cellular automata exploration
- *Molecular Computation of Solutions to Combinatorial Problems* - Adleman's original paper
- *The Game of Life* (Conway) - Still active research community
- Neuromorphic computing papers from Intel, IBM, BrainChip
