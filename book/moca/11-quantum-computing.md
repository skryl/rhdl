# Chapter 11: Quantum Computing

## Overview

Quantum computing exploits the strange properties of quantum mechanics—superposition, entanglement, and interference—to solve certain problems exponentially faster than classical computers. But it's not magic, and it's not a universal speedup. Understanding what quantum computers can and cannot do requires understanding the physics.

## Classical vs Quantum Bits

### Classical Bits

A classical bit is either 0 or 1:

```
Classical bit: |0⟩ or |1⟩

Like a coin: heads or tails, never both
```

### Quantum Bits (Qubits)

A qubit can be in a **superposition** of both states simultaneously:

```
Qubit: α|0⟩ + β|1⟩

where |α|² + |β|² = 1

α and β are complex numbers (amplitudes)
|α|² = probability of measuring 0
|β|² = probability of measuring 1
```

### The Bloch Sphere

A qubit's state can be visualized on a sphere:

```
┌─────────────────────────────────────────────────────────────┐
│                    BLOCH SPHERE                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│                      |0⟩ (north pole)                        │
│                        ●                                     │
│                       /|\                                    │
│                      / | \                                   │
│                     /  |  \                                  │
│         |+⟩ ●─────●───●───●───────● |-⟩                     │
│                     \  |  /                                  │
│                      \ | /                                   │
│                       \|/                                    │
│                        ●                                     │
│                      |1⟩ (south pole)                        │
│                                                              │
│   |+⟩ = (|0⟩ + |1⟩)/√2   Equal superposition                │
│   |-⟩ = (|0⟩ - |1⟩)/√2   Equal superposition, opposite phase│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Quantum Gates

### Single-Qubit Gates

**Pauli-X (NOT):**
```
X|0⟩ = |1⟩
X|1⟩ = |0⟩

Matrix: [0 1]
        [1 0]
```

**Hadamard (Superposition):**
```
H|0⟩ = (|0⟩ + |1⟩)/√2 = |+⟩
H|1⟩ = (|0⟩ - |1⟩)/√2 = |-⟩

Matrix: [1  1] / √2
        [1 -1]
```

**Phase gates:**
```
Z|0⟩ = |0⟩
Z|1⟩ = -|1⟩   (phase flip)

S|0⟩ = |0⟩
S|1⟩ = i|1⟩   (90° phase)

T|0⟩ = |0⟩
T|1⟩ = e^(iπ/4)|1⟩   (45° phase)
```

### Two-Qubit Gates

**CNOT (Controlled-NOT):**
```
Control ──●──
          │
Target  ──⊕──

CNOT|00⟩ = |00⟩
CNOT|01⟩ = |01⟩
CNOT|10⟩ = |11⟩  ← target flipped
CNOT|11⟩ = |10⟩  ← target flipped
```

**CZ (Controlled-Z):**
```
CZ|11⟩ = -|11⟩   (phase flip only when both 1)
```

### Universal Gate Sets

Any quantum computation can be built from:
- **{H, T, CNOT}** - Standard universal set
- **{Toffoli, H}** - Classical + superposition

## Entanglement

When qubits are entangled, measuring one instantly affects the other:

```
Bell state: |Φ+⟩ = (|00⟩ + |11⟩)/√2

If you measure qubit 1 and get 0 → qubit 2 is definitely 0
If you measure qubit 1 and get 1 → qubit 2 is definitely 1

This correlation is instantaneous, regardless of distance!
```

Creating entanglement:
```
|00⟩ ──[H]──●────  = (|00⟩ + |11⟩)/√2
            │
|0⟩  ───────⊕────
```

## Quantum Algorithms

### Deutsch-Jozsa

**Problem:** Is f(x) constant or balanced?
- Classical: Need 2^(n-1)+1 queries (worst case)
- Quantum: 1 query!

### Grover's Search

**Problem:** Find marked item in unsorted database
- Classical: O(N) queries
- Quantum: O(√N) queries

Quadratic speedup—significant but not exponential.

### Shor's Algorithm

**Problem:** Factor large integers
- Classical: Exponential time (RSA security relies on this!)
- Quantum: Polynomial time

This is why quantum computers threaten current cryptography.

## The Connection to Reversible Computing

**All quantum gates are reversible!**

```
┌─────────────────────────────────────────────────────────────┐
│           REVERSIBLE → QUANTUM                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Classical Gate    Reversible Version   Quantum Version    │
│   ─────────────────────────────────────────────────────────│
│   NOT               NOT                  X (Pauli-X)         │
│   AND               Toffoli              Toffoli             │
│   XOR               CNOT                 CNOT                │
│   SWAP              SWAP                 SWAP                │
│   ---               Fredkin              Fredkin             │
│                                                              │
│   Reversible gates work identically in quantum!              │
│   (They're the "classical subset" of quantum gates)          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

The Toffoli gate from Chapter 10 is a valid quantum gate.

## Quantum Error Correction

Qubits are fragile—noise destroys superposition (decoherence):

```
Challenges:
- Can't copy qubits (no-cloning theorem)
- Measurement destroys superposition
- Environment causes errors

Solution: Encode 1 logical qubit in many physical qubits
- Surface codes: ~1000 physical per logical qubit
- Error detection without measuring the data
```

## Current State (2025)

| System | Qubits | Error Rate | Notes |
|--------|--------|------------|-------|
| IBM | ~1000+ | ~0.1% | Superconducting |
| Google | ~100 | ~0.1% | Superconducting |
| IonQ | ~30 | ~0.01% | Trapped ions |
| Photonic | ~200 | Varies | Optical |

Still in "NISQ era" (Noisy Intermediate-Scale Quantum).

## What Quantum Computers Can't Do

Common misconceptions:

1. **Not parallel processing** - Measuring collapses to one answer
2. **Not exponential speedup for everything** - Only specific problems
3. **Not breaking all encryption** - Only certain schemes (RSA, not AES)
4. **Not conscious or magical** - Just different physics

## Simulating Quantum on Classical

For small systems, we can simulate quantum computers:

```
n qubits = 2^n complex amplitudes

10 qubits = 1,024 amplitudes (~16 KB)
20 qubits = 1,048,576 amplitudes (~16 MB)
30 qubits = 1,073,741,824 amplitudes (~16 GB)
40 qubits = ~16 TB
50 qubits = ~16 PB (impractical)

"Quantum supremacy" = doing what classical can't simulate
```

## Key Takeaways

1. **Qubits are probability amplitudes** - Not just "0 and 1 at once"
2. **Superposition enables interference** - Amplitudes can cancel or reinforce
3. **Entanglement creates correlations** - Spooky action at a distance
4. **Reversibility is required** - Quantum gates must be unitary
5. **Limited speedups** - Exponential only for specific problems (factoring, simulation)
6. **Errors are the enemy** - Decoherence and noise dominate current systems

> See [Appendix K](appendix-k-quantum.md) for quantum circuit implementations and simulators.
