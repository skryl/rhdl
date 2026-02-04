# Chapter 10: Stochastic Computing

*When randomness becomes computation*

---

## The Radical Idea

What if we represented numbers not as binary digits, but as *probabilities*?

```
Traditional binary:  0.75 = 0b0.11 (fixed-point)
Stochastic:          0.75 = a stream where 75% of bits are 1

Example stream:      1 1 0 1 1 1 0 1 1 1 0 1 ... (roughly 75% ones)
```

This seems wasteful—why use thousands of bits to represent one number? Because the *operations* become incredibly simple.

---

## Stochastic Number Representation

### Unipolar Encoding

Value *p* ∈ [0, 1] is represented by a bit stream where P(bit = 1) = *p*.

```
Value   Example Stream (16 bits)         Meaning
0.0     0000 0000 0000 0000              Never 1
0.25    0001 0010 0001 0100              25% ones
0.5     0101 1010 0110 1001              50% ones
0.75    1011 1110 1101 1011              75% ones
1.0     1111 1111 1111 1111              Always 1
```

### Bipolar Encoding

Value *x* ∈ [-1, 1] where P(bit = 1) = (x + 1)/2.

```
Value   P(1)    Example Stream
-1.0    0.0     0000 0000 0000 0000
-0.5    0.25    0001 0010 0001 0100
 0.0    0.5     0101 1010 0110 1001
+0.5    0.75    1011 1110 1101 1011
+1.0    1.0     1111 1111 1111 1111
```

---

## The Magic: Simple Gates Do Complex Math

### Multiplication = AND Gate

For unipolar encoding, multiplication is just an AND gate!

```
A = 0.75 (stream with 75% ones)
B = 0.50 (stream with 50% ones)

       A: 1 1 0 1 1 1 0 1 1 1 0 1 1 0 1 1
       B: 0 1 1 0 1 0 1 1 0 1 1 0 0 1 1 0
   A∧B:   0 1 0 0 1 0 0 1 0 1 0 0 0 0 1 0

P(A∧B = 1) = P(A = 1) × P(B = 1) = 0.75 × 0.50 = 0.375
```

**One AND gate replaces an entire multiplier circuit!**

### Multiplication (Bipolar) = XNOR Gate

For bipolar encoding: A × B = XNOR(A, B)

```
If A, B ∈ [-1, 1] with P(a=1) = (A+1)/2, P(b=1) = (B+1)/2

Then XNOR(a,b) has P = 1 when a=b
P(XNOR=1) = P(a=1)P(b=1) + P(a=0)P(b=0)
          = (A+1)/2 × (B+1)/2 + (1-A)/2 × (1-B)/2
          = (AB + 1)/2

Which encodes the value AB in bipolar format!
```

### Scaled Addition = MUX

Adding with a multiplexer:

```
        A ──┐
            ├──▶ MUX ──▶ (A + B) / 2
        B ──┘
             ▲
             │
        S (random 50% stream)

When S=0, output A
When S=1, output B
Average output = (A + B) / 2
```

This computes the *average*—scaled addition. For true addition, you need to scale inputs.

### Subtraction (Bipolar)

For bipolar: A - B = XOR(A, B)... almost. Actually:

```
NOT(B) in bipolar negates: if B encodes x, NOT(B) encodes -x
So: A - B = XNOR(A, NOT(B)) = XOR(A, B)
```

---

## Operations Summary

| Operation | Unipolar | Bipolar |
|-----------|----------|---------|
| Multiply | AND | XNOR |
| Scaled Add | MUX | MUX |
| Square | Wire (copy) | Wire (copy) |
| Negate | N/A | NOT |
| Absolute Value | N/A | XNOR with self |

**Squaring is free!** Copying a wire gives you P(A∧A) = P(A)² in unipolar, or A×A = A² in bipolar.

---

## Random Number Generation

Stochastic computing needs random bit streams. The quality of randomness matters!

### Linear Feedback Shift Register (LFSR)

```
┌──────────────────────────────────────────┐
│                                          │
│  ┌───┐   ┌───┐   ┌───┐   ┌───┐         │
└─▶│ D │──▶│ D │──▶│ D │──▶│ D │─────────┼──▶ out
   └───┘   └───┘   └───┘   └───┘         │
     │       │               │            │
     │       └───────XOR─────┘            │
     │                │                   │
     └────────────────┘                   │
                                          │
                      XOR─────────────────┘
```

- Cheap to implement (few gates)
- Pseudo-random, deterministic
- Long period (2^n - 1 for n-bit LFSR)

### Converting Values to Streams

To convert a value *p* to a stochastic stream:

```
Compare with random number:
  if LFSR_value < p × MAX:
    output 1
  else:
    output 0
```

This requires a comparator—the most expensive part!

---

## Correlation: The Hidden Problem

### What Goes Wrong

Stochastic operations assume *independence*. Correlated streams break the math:

```
A = stream with P(1) = 0.5
B = A  (same stream, perfectly correlated)

A ∧ B should give 0.5 × 0.5 = 0.25
But A ∧ A = A, which is still 0.5!
```

### Solutions

**1. Use different LFSRs for each input:**
```
LFSR1 ──▶ stream A
LFSR2 ──▶ stream B  (different seed/polynomial)
```

**2. Decorrelation circuits:**
Insert buffers or delays to break correlation.

**3. Careful design:**
Track which streams share history; re-randomize when needed.

---

## Accuracy vs Stream Length

Stochastic computing trades precision for simplicity:

```
Stream Length    Precision      Error
16 bits          ~4 bits        ±6.25%
256 bits         ~8 bits        ±0.4%
4096 bits        ~12 bits       ±0.025%
65536 bits       ~16 bits       ±0.0015%
```

More bits = more accuracy, but longer computation time.

### Progressive Precision

A unique property: you can *stop early* for a rough answer!

```
After 16 bits:   Answer ≈ 0.73 ± 0.06
After 64 bits:   Answer ≈ 0.748 ± 0.03
After 256 bits:  Answer ≈ 0.7512 ± 0.015
After 1024 bits: Answer ≈ 0.75003 ± 0.008
```

Useful when approximate answers are acceptable.

---

## Error Tolerance

Stochastic circuits are remarkably fault-tolerant:

```
Traditional:  Flip one bit → completely wrong answer
Stochastic:   Flip one bit → tiny change in probability

If a 1000-bit stream has 10 bit flips:
  Original: 750 ones (0.750)
  Corrupted: 740-760 ones (0.740-0.760)
  Error: ~1%
```

This makes stochastic computing attractive for:
- Radiation-hardened systems
- Low-voltage operation (more noise)
- Unreliable emerging technologies

---

## Applications

### Image Processing

Edge detection, noise reduction, filtering:

```
3×3 kernel convolution = 9 multiplications + 8 additions

Traditional: 9 multipliers + 8 adders (expensive!)
Stochastic:  9 AND gates + MUX tree (trivial!)
```

### Neural Networks

Weights and activations as stochastic streams:

```
Neuron: y = σ(Σ wᵢxᵢ)

Multiply weights × inputs: AND gates
Sum: MUX tree
Activation: stochastic tanh approximation
```

### Signal Processing

Filters, transforms, correlations—all become gate-level simple.

### Machine Learning Inference

Low-power edge AI where approximate is acceptable.

---

## Complex Operations

### Exponentiation

Using the identity: e^x = lim(1 + x/n)^n

For small x, approximate with FSM:

```
          ┌─────┐
x ────────│ FSM │────▶ e^x (approximately)
          └─────┘

States encode partial computation
Transitions based on input stream
```

### Division

Harder—requires feedback:

```
        ┌──────────────────┐
        │                  │
A ──────┤  JK Flip-Flop   ├──────▶ A/B
        │                  │
B ──────┴──────────────────┘
```

JK flip-flop with A=J, B=K approximates A/B.

### Square Root

Using feedback and comparison:

```
If output² < input, increase output
If output² > input, decrease output
```

Implemented with simple state machines.

---

## Hybrid Approaches

### Stochastic-Binary Interface

Convert at boundaries:

```
Binary → [Comparator + LFSR] → Stochastic Stream
                  ↓
          [Stochastic Circuit]
                  ↓
Stochastic → [Counter] → Binary
```

The conversion overhead must be amortized over enough computation.

### Deterministic Stochastic

Use *deterministic* bit streams that have exact statistics:

```
Instead of random: 1 0 1 1 0 1 1 0 1 0 1 1 ...
Use structured:    1 0 1 0 1 0 1 0 1 0 1 0 ... (exactly 50%)
```

Eliminates randomness errors but requires careful stream design.

---

## Comparison with Traditional Computing

| Aspect | Binary | Stochastic |
|--------|--------|------------|
| Multiply | Large circuit | 1 gate |
| Add | Adder circuit | MUX (scaled) |
| Precision | Exact | Statistical |
| Error tolerance | Low | High |
| Latency | Low | High (stream length) |
| Area | High | Very low |
| Power | Medium | Low |
| Best for | General compute | Specialized, low-power |

---

## Historical Context

- **1960s**: Introduced by John von Neumann (!) and Brian Pippenger
- **1960s-70s**: Used in early neural network simulations
- **1990s-2000s**: Mostly dormant
- **2010s-present**: Revival for ML, image processing, low-power computing

The renewed interest comes from:
- Machine learning tolerates approximation
- Edge computing needs low power
- Emerging devices are unreliable (need fault tolerance)

---

## RHDL Implementation

See [Appendix J](appendix-j-stochastic.md) for complete implementations:

```ruby
# Stochastic multiplier = AND gate!
class StochasticMultiplier < SimComponent
  input :a  # Stochastic stream encoding value A
  input :b  # Stochastic stream encoding value B
  output :product  # Stream encoding A × B

  behavior do
    product <= a & b  # That's it!
  end
end
```

---

## Summary

- **Numbers as probabilities**: Value encoded in fraction of 1s
- **Multiplication = AND**: One gate replaces a multiplier
- **Scaled addition = MUX**: Simple combining
- **Random streams required**: LFSRs generate pseudo-random bits
- **Correlation breaks math**: Streams must be independent
- **Precision vs time**: Longer streams = more accuracy
- **Fault tolerant**: Bit errors cause small probability changes
- **Best for approximation**: ML, image processing, signal processing

---

## Exercises

1. Implement a stochastic multiplier and verify it over 1000 bits
2. Build an LFSR-based random number generator
3. Create a stochastic adder using a MUX and random select
4. Measure error vs stream length experimentally
5. Implement a stochastic edge detector for images

---

## Further Reading

- Gaines, "Stochastic Computing Systems" (1969) - The classic introduction
- Alaghi & Hayes, "Survey of Stochastic Computing" (2013)
- "Stochastic Computing: Techniques and Applications" (2019)

---

*Next: [Chapter 11 - Reversible Computation](11-reversible-computation.md)*

*Appendix: [Appendix J - Stochastic Implementation](appendix-j-stochastic.md)*
