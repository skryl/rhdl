# Chapter 7: Reversible Computation

## Overview

Every time your computer erases a bit, it generates heat. This isn't just engineering—it's physics. Landauer's principle states that erasing information has a fundamental thermodynamic cost. But what if computation never erased anything? **Reversible computation** uses gates that preserve information, theoretically allowing computation with zero energy dissipation.

## The Thermodynamics of Computation

### Landauer's Principle

In 1961, Rolf Landauer proved that erasing one bit of information requires a minimum energy:

```
E_min = kT × ln(2)

where:
  k = Boltzmann constant (1.38 × 10⁻²³ J/K)
  T = temperature (Kelvin)
  ln(2) ≈ 0.693

At room temperature (300K):
  E_min ≈ 2.9 × 10⁻²¹ joules per bit erased
```

This seems tiny, but:
- Modern CPUs erase ~10¹⁸ bits/second
- That's ~3 milliwatts just from Landauer's limit
- Real CPUs use ~1000× more (other losses)
- As we approach physical limits, this matters

### Why Erasure Costs Energy

Think of a bit as a ball in a double well:

```
┌─────────────────────────────────────────┐
│        INFORMATION AS ENTROPY           │
├─────────────────────────────────────────┤
│                                         │
│   Known bit (low entropy):              │
│   ┌─────────────────────┐               │
│   │     ●               │  Ball is here │
│   │   ╲   ╱   ╲   ╱    │  (state = 0)  │
│   │    ╲ ╱     ╲ ╱     │               │
│   │     0       1      │               │
│   └─────────────────────┘               │
│                                         │
│   Erased bit (high entropy):            │
│   ┌─────────────────────┐               │
│   │         ●           │  Could be     │
│   │   ╲   ╱   ╲   ╱    │  anywhere     │
│   │    ╲ ╱     ╲ ╱     │               │
│   │     0       1      │               │
│   └─────────────────────┘               │
│                                         │
│   Erasure increases entropy of system   │
│   → Must decrease entropy elsewhere     │
│   → Heat released to environment        │
│                                         │
└─────────────────────────────────────────┘
```

### Irreversible Gates Erase Information

Consider an AND gate:

```
A  B  │  A AND B
──────┼─────────
0  0  │    0
0  1  │    0
1  0  │    0
1  1  │    1
```

Three input combinations (00, 01, 10) all produce output 0. Given output 0, you can't determine which input it was. **Information has been erased.**

```
2 bits in (A, B) → 1 bit out (Y)
1 bit erased per AND operation!
```

## Reversible Gates

### What Makes a Gate Reversible?

A gate is **reversible** if you can determine its inputs from its outputs. This requires:
- Same number of input and output bits
- One-to-one mapping (bijection)

### The NOT Gate

NOT is already reversible:

```
A  │  NOT A
───┼───────
0  │   1
1  │   0

Given output, input is uniquely determined.
```

### The Fredkin Gate (CSWAP)

The Fredkin gate (1982) is a 3-input, 3-output reversible gate:

```
┌─────────────────────────────────────────┐
│          FREDKIN GATE (CSWAP)           │
├─────────────────────────────────────────┤
│                                         │
│   Inputs:     Outputs:                  │
│   C ─────────── C' = C                  │
│   A ────╲  ╱─── A' = C ? B : A          │
│         ╳                               │
│   B ────╱  ╲─── B' = C ? A : B          │
│                                         │
│   If C=0: A and B pass through          │
│   If C=1: A and B are swapped           │
│                                         │
│   Truth table:                          │
│   C A B │ C' A' B'                      │
│   ──────┼────────                       │
│   0 0 0 │ 0  0  0                       │
│   0 0 1 │ 0  0  1                       │
│   0 1 0 │ 0  1  0                       │
│   0 1 1 │ 0  1  1                       │
│   1 0 0 │ 1  0  0                       │
│   1 0 1 │ 1  1  0  ← swapped            │
│   1 1 0 │ 1  0  1  ← swapped            │
│   1 1 1 │ 1  1  1                       │
│                                         │
└─────────────────────────────────────────┘
```

**Key property:** Every output combination corresponds to exactly one input combination. No information is lost.

### The Toffoli Gate (CCNOT)

The Toffoli gate (1980) is another fundamental reversible gate:

```
┌─────────────────────────────────────────┐
│          TOFFOLI GATE (CCNOT)           │
├─────────────────────────────────────────┤
│                                         │
│   Inputs:     Outputs:                  │
│   A ─────●──── A' = A                   │
│          │                              │
│   B ─────●──── B' = B                   │
│          │                              │
│   C ────[⊕]─── C' = C XOR (A AND B)     │
│                                         │
│   C is flipped only if A=1 AND B=1      │
│                                         │
│   Truth table:                          │
│   A B C │ A' B' C'                      │
│   ──────┼────────                       │
│   0 0 0 │ 0  0  0                       │
│   0 0 1 │ 0  0  1                       │
│   0 1 0 │ 0  1  0                       │
│   0 1 1 │ 0  1  1                       │
│   1 0 0 │ 1  0  0                       │
│   1 0 1 │ 1  0  1                       │
│   1 1 0 │ 1  1  1  ← C flipped          │
│   1 1 1 │ 1  1  0  ← C flipped          │
│                                         │
└─────────────────────────────────────────┘
```

### Universality

Both Fredkin and Toffoli gates are **universal**—any computation can be built from them alone:

**AND from Toffoli:**
```
A ─────●──── A
       │
B ─────●──── B
       │
0 ────[⊕]─── A AND B
```

**NOT from Toffoli:**
```
1 ─────●──── 1
       │
1 ─────●──── 1
       │
A ────[⊕]─── NOT A
```

**OR from Toffoli:** Use De Morgan's law (NOT-AND-NOT)

## RHDL Implementation

Reversible gates map directly to RHDL with explicit input preservation:

### Key Components

| Component | Inputs | Outputs | Function |
|-----------|--------|---------|----------|
| **ToffoliGate** | a, b, c | a', b', c' | c' = c XOR (a AND b) |
| **FredkinGate** | c, a, b | c', a', b' | Conditional swap |
| **ReversibleAnd** | a, b | a', b', result | AND with preserved inputs |
| **ReversibleFullAdder** | a, b, cin | a', b', sum, cout | Addition with garbage |

### Gate Costs

| Circuit | Toffoli Gates | Garbage Bits |
|---------|---------------|--------------|
| NOT | 1 | 0 |
| AND | 1 | 2 (inputs preserved) |
| OR | 3 | 2 |
| Full Adder | 4 | 2 |
| N-bit Adder | 4N | 2N |

> See [Appendix H](appendix-h-reversible.md) for complete RHDL implementations of all reversible gates and circuits.

## The Garbage Problem

### Reversible Circuits Generate Garbage

To make computation reversible, we must preserve inputs:

```
Irreversible:           Reversible:
A ─┐                    A ─────────── A (garbage)
   ├─[AND]── Y          B ─────────── B (garbage)
B ─┘                    0 ────[TOFF]── A AND B
```

This "garbage" must be:
1. Kept around (uses space)
2. Or **uncomputed** later (uses time)

### Bennett's Method

Charles Bennett (1973) showed how to compute reversibly with bounded garbage:

```
┌─────────────────────────────────────────┐
│        BENNETT'S TRICK                  │
├─────────────────────────────────────────┤
│                                         │
│   1. Compute forward (generate garbage) │
│                                         │
│   input ──▶ [Forward] ──▶ output        │
│                  │                      │
│               garbage                   │
│                                         │
│   2. Copy output to fresh bits          │
│                                         │
│   3. Run computation backward           │
│      (uncomputes garbage!)              │
│                                         │
│   output ──▶ [Backward] ──▶ input       │
│                  │                      │
│               (garbage erased)          │
│                                         │
│   Result: input preserved, output copy  │
│           garbage cleaned up            │
│                                         │
└─────────────────────────────────────────┘
```

## Quantum Connection

### Quantum Gates are Reversible

Quantum mechanics requires unitary (reversible) operations:

```
┌─────────────────────────────────────────┐
│      REVERSIBLE ↔ QUANTUM               │
├─────────────────────────────────────────┤
│                                         │
│   Classical Reversible:                 │
│   Toffoli, Fredkin                      │
│            ↓                            │
│   Quantum versions:                     │
│   CCNOT (quantum Toffoli)               │
│   CSWAP (quantum Fredkin)               │
│                                         │
│   Plus quantum-only gates:              │
│   Hadamard, Phase, CNOT                 │
│                                         │
│   Reversible computing is a stepping    │
│   stone to quantum computing!           │
│                                         │
└─────────────────────────────────────────┘
```

The Toffoli and Fredkin gates work identically in quantum circuits—they're the "classical subset" of quantum gates.

## Practical Considerations

### Why Not Use Reversible Logic Today?

1. **Garbage overhead** - Extra bits and gates needed
2. **No practical advantage yet** - We're far from Landauer's limit
3. **Timing complexity** - Forward/backward computation adds latency
4. **Tool support** - Synthesis tools assume irreversible logic

### When It Might Matter

```
Year   Technology    Energy/op    Landauer limit
─────────────────────────────────────────────────
1980   10 μm CMOS    10⁻¹² J     10⁻²¹ J
2000   180 nm        10⁻¹⁴ J     10⁻²¹ J
2020   5 nm          10⁻¹⁶ J     10⁻²¹ J
20??   ???           10⁻²¹ J     ← Approaching limit!
```

As we approach 10⁻²¹ J/op, reversible computing becomes necessary, not optional.

### Adiabatic Logic

**Adiabatic circuits** are a practical middle ground:
- Slow voltage transitions
- Energy recycled rather than dissipated
- Not fully reversible, but low power

```
┌─────────────────────────────────────────┐
│       ADIABATIC CHARGING                │
├─────────────────────────────────────────┤
│                                         │
│   Normal CMOS:        Adiabatic:        │
│                                         │
│   V ┌────┐            V    ╱─────       │
│     │    │               ╱              │
│     │    │            ╱                 │
│   0 └────┴───t      0───────────t       │
│                                         │
│   Fast transition     Slow ramp         │
│   Energy = CV²        Energy ≈ 0        │
│   (dissipated)        (recoverable)     │
│                                         │
└─────────────────────────────────────────┘
```

## Hands-On Exercises

### Exercise 1: Verify Reversibility

For the Toffoli gate truth table, verify that each output combination appears exactly once.

### Exercise 2: Build OR from Toffoli

Using only Toffoli gates (and constants 0, 1), build an OR gate:
```
Hint: A OR B = NOT(NOT A AND NOT B)
```

### Exercise 3: Count Garbage

How many garbage bits does a reversible 4-bit adder produce using the naive approach (no uncomputation)?

### Exercise 4: Reversible Multiplexer

Implement a reversible 2:1 multiplexer using Fredkin gates.

## Key Takeaways

1. **Erasure costs energy** - Landauer's principle is physics, not engineering
2. **Reversible gates preserve information** - Every output maps to one input
3. **Toffoli and Fredkin are universal** - Any computation is possible
4. **Garbage is the price** - Extra bits needed for reversibility
5. **Quantum gates are reversible** - Classical reversible → quantum stepping stone

## Further Reading

- *Reversible Computing* by Frank (2017) - Comprehensive survey
- Landauer's original 1961 paper
- Bennett's 1973 paper on reversible Turing machines
- *Quantum Computation and Quantum Information* by Nielsen & Chuang

> See [Appendix H](appendix-h-reversible.md) for more reversible circuits and formal analysis.
