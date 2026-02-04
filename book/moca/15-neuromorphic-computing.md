# Chapter 12: Neuromorphic Computing

## Overview

Neuromorphic computing takes inspiration from biological neural networks to create computing systems that are fundamentally different from von Neumann architectures. Instead of separating memory and processing, neuromorphic chips integrate them at the neuron level, enabling massively parallel, event-driven, low-power computation.

## The Von Neumann Bottleneck

Traditional computers suffer from a fundamental limitation:

```
┌─────────────────────────────────────────────────────────────┐
│              THE VON NEUMANN BOTTLENECK                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌─────────────┐         Bus          ┌─────────────┐     │
│   │             │◄───────────────────►│             │     │
│   │     CPU     │   (limited bandwidth) │   Memory    │     │
│   │             │                       │             │     │
│   └─────────────┘                       └─────────────┘     │
│                                                              │
│   Problem: All data must travel through the bus             │
│   - Memory access is slow (100+ cycles)                     │
│   - Power consumed moving data, not computing               │
│   - Sequential processing limits parallelism                │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Brain's approach: Memory and compute are ONE              │
│                                                              │
│   ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐                     │
│   │ N ├─┤ N ├─┤ N ├─┤ N ├─┤ N ├─┤ N │ ← Each neuron is    │
│   └─┬─┘ └─┬─┘ └─┬─┘ └─┬─┘ └─┬─┘ └─┬─┘   both memory       │
│     │     │     │     │     │     │       and processor     │
│   ┌─┴─┐ ┌─┴─┐ ┌─┴─┐ ┌─┴─┐ ┌─┴─┐ ┌─┴─┐                     │
│   │ N ├─┤ N ├─┤ N ├─┤ N ├─┤ N ├─┤ N │                     │
│   └───┘ └───┘ └───┘ └───┘ └───┘ └───┘                     │
│                                                              │
│   No bottleneck: Local computation with local memory        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Biological Neurons

Real neurons operate very differently from digital circuits:

### The Biological Model

```
┌─────────────────────────────────────────────────────────────┐
│                 BIOLOGICAL NEURON                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│                    Dendrites (inputs)                        │
│                      ╱  │  ╲                                │
│                     ╱   │   ╲                               │
│                    ╱    │    ╲                              │
│               ┌────────────────┐                            │
│               │   Cell Body    │                            │
│               │   (Soma)       │ ← Integration              │
│               │                │   Membrane potential       │
│               └───────┬────────┘   accumulates inputs       │
│                       │                                      │
│                       │ Axon                                 │
│                       │                                      │
│                   ┌───┴───┐                                 │
│                  ╱    │    ╲                                │
│                 ╱     │     ╲ Synapses (outputs)            │
│                                                              │
│   Key properties:                                           │
│   - Analog membrane potential (not binary)                  │
│   - Spikes when threshold reached                           │
│   - Synaptic weights change (learning)                      │
│   - Timing matters (spike timing dependent plasticity)      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Spiking Neural Networks (SNNs)

Unlike artificial neural networks (ANNs), SNNs communicate with discrete spikes:

```
ANN (rate-coded):
  Input: 0.7 ──────────────────► Output: 0.85
         continuous activation

SNN (spike-coded):
  Input: ─┐ ┐  ┐   ┐ ┐ ──────► Output: ─┐   ┐  ┐ ┐
          │ │  │   │ │  spikes          │   │  │ │
          └─┴──┴───┴─┴─                 └───┴──┴─┴─

  Information encoded in:
  - Spike rate (frequency)
  - Spike timing (temporal patterns)
  - Interspike intervals
```

## The Leaky Integrate-and-Fire (LIF) Neuron

The most common neuromorphic neuron model:

```
┌─────────────────────────────────────────────────────────────┐
│           LEAKY INTEGRATE-AND-FIRE MODEL                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Membrane potential V(t):                                   │
│                                                              │
│   τ_m × dV/dt = -(V - V_rest) + R × I(t)                   │
│                                                              │
│   where:                                                     │
│   - τ_m = membrane time constant (leak)                     │
│   - V_rest = resting potential                               │
│   - R = membrane resistance                                  │
│   - I(t) = input current                                     │
│                                                              │
│   When V ≥ V_threshold:                                      │
│     1. Emit spike                                            │
│     2. Reset V = V_reset                                     │
│     3. Enter refractory period                               │
│                                                              │
│   Voltage trace:                                             │
│                                                              │
│   V_th ─ ─ ─ ─ ─ ─ ─ ─┬─ ─ ─ ─ ─ ─┬─ ─ ─ ─ ─             │
│                      /│           /│                         │
│                     / │          / │                         │
│                    /  │         /  │                         │
│   V_rest ────────/    └────────/   └────────                │
│                 ↑     ↑       ↑     ↑                        │
│               input  spike  input  spike                     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Neuromorphic Hardware

### Intel Loihi

```
┌─────────────────────────────────────────────────────────────┐
│                    INTEL LOIHI                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   128 Neuromorphic Cores                                    │
│   ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐        │
│   │Core │Core │Core │Core │Core │Core │Core │Core │  ...   │
│   │  0  │  1  │  2  │  3  │  4  │  5  │  6  │  7  │        │
│   └─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘        │
│                                                              │
│   Each core contains:                                        │
│   - 1024 neurons (compartments)                             │
│   - Learning engine                                          │
│   - Spike router                                             │
│                                                              │
│   Total: 128 × 1024 = 131,072 neurons                       │
│   Synapses: Up to 130 million                               │
│                                                              │
│   ┌─────────────────────────────────────────────────┐       │
│   │              Single Core                         │       │
│   │  ┌─────────┐  ┌─────────┐  ┌─────────┐         │       │
│   │  │ Neuron  │  │ Synapse │  │ Learning│         │       │
│   │  │ Array   │  │ Memory  │  │ Engine  │         │       │
│   │  │ (1024)  │  │ (SRAM)  │  │ (STDP)  │         │       │
│   │  └────┬────┘  └────┬────┘  └────┬────┘         │       │
│   │       └────────────┼────────────┘               │       │
│   │                    │                             │       │
│   │              Spike Router                        │       │
│   └─────────────────────────────────────────────────┘       │
│                                                              │
│   Key features:                                              │
│   - Event-driven (no global clock)                          │
│   - On-chip learning (STDP)                                 │
│   - Programmable neuron models                              │
│   - <100 mW for inference                                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### IBM TrueNorth

```
┌─────────────────────────────────────────────────────────────┐
│                    IBM TRUENORTH                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   4096 Neurosynaptic Cores                                  │
│   (64 × 64 array)                                           │
│                                                              │
│   Each core:                                                 │
│   - 256 neurons                                              │
│   - 256 × 256 synapses                                      │
│   - Fully connected within core                             │
│                                                              │
│   Total:                                                     │
│   - 1 million neurons                                        │
│   - 256 million synapses                                    │
│   - 70 mW power consumption                                 │
│                                                              │
│   ┌─────────────────────────────────────┐                   │
│   │         Neurosynaptic Core          │                   │
│   │                                      │                   │
│   │   256 inputs → [256×256] → 256 neurons                 │
│   │              synapses                │                   │
│   │                                      │                   │
│   │   Crossbar architecture:            │                   │
│   │   ───┬───┬───┬───                   │                   │
│   │      │   │   │                       │                   │
│   │   ───┼───┼───┼───                   │                   │
│   │      │   │   │     Each crossing    │                   │
│   │   ───┼───┼───┼───  is a synapse     │                   │
│   │      │   │   │                       │                   │
│   │      ▼   ▼   ▼                       │                   │
│   │     N0  N1  N2  (neurons)           │                   │
│   └─────────────────────────────────────┘                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Memristors: The Fourth Element

Memristors enable analog synaptic weights in hardware:

```
┌─────────────────────────────────────────────────────────────┐
│                    MEMRISTOR                                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   The four fundamental circuit elements:                     │
│                                                              │
│   Resistor:   V = R × I                                     │
│   Capacitor:  Q = C × V                                     │
│   Inductor:   Φ = L × I                                     │
│   Memristor:  Φ = M × Q    ← Memory + Resistor              │
│                                                              │
│   Key property: Resistance depends on history               │
│                                                              │
│   ┌─────────────────────────────────────────────────┐       │
│   │                                                  │       │
│   │   Current flow changes resistance:              │       │
│   │                                                  │       │
│   │   ──▶ More current → Lower resistance          │       │
│   │   ◀── Reverse current → Higher resistance      │       │
│   │                                                  │       │
│   │   Like a synapse strengthening/weakening!       │       │
│   │                                                  │       │
│   └─────────────────────────────────────────────────┘       │
│                                                              │
│   Crossbar array:                                            │
│                                                              │
│   V₀ ───[M]───[M]───[M]───                                  │
│   V₁ ───[M]───[M]───[M]───                                  │
│   V₂ ───[M]───[M]───[M]───                                  │
│          │     │     │                                       │
│          I₀    I₁    I₂                                     │
│                                                              │
│   Matrix-vector multiply in ONE operation!                  │
│   I = M × V (Ohm's law + Kirchhoff's current law)          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Spike Timing Dependent Plasticity (STDP)

The biological learning rule:

```
┌─────────────────────────────────────────────────────────────┐
│                        STDP                                  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   "Neurons that fire together, wire together"               │
│                                                              │
│   Δw (weight change)                                        │
│    ↑                                                         │
│    │     ╱╲                                                 │
│  + │    ╱  ╲         Pre before post:                       │
│    │   ╱    ╲        Strengthen (LTP)                       │
│    │  ╱      ╲                                              │
│  0 ├─╱────────╲──────────► Δt (timing)                     │
│    │           ╲      ╱                                     │
│  - │            ╲    ╱   Post before pre:                   │
│    │             ╲  ╱    Weaken (LTD)                       │
│    │              ╲╱                                        │
│    │                                                         │
│                                                              │
│   If pre-synaptic spike arrives BEFORE post-synaptic:       │
│     → Pre "caused" post → Strengthen connection             │
│                                                              │
│   If pre-synaptic spike arrives AFTER post-synaptic:        │
│     → Pre didn't cause post → Weaken connection             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Comparison with Other Paradigms

| Feature | Von Neumann | GPU | Neuromorphic |
|---------|-------------|-----|--------------|
| Processing | Sequential | SIMD parallel | Event-driven |
| Memory | Separate | Separate | Integrated |
| Communication | Clocked bus | Clocked bus | Asynchronous spikes |
| Power | ~100W | ~300W | ~0.1W |
| Learning | Software | Software | Hardware (STDP) |
| Best for | General compute | Matrix ops | Pattern recognition |

## Applications

Neuromorphic chips excel at:

1. **Pattern recognition** - Visual/audio classification
2. **Anomaly detection** - Always-on monitoring
3. **Robotics** - Sensorimotor control
4. **Edge AI** - Ultra-low power inference
5. **Adaptive systems** - Online learning

## Challenges

```
Current limitations:
├── Programming models - No standard framework (yet)
├── Training - Most SNNs trained by converting from ANNs
├── Precision - Analog weights have limited accuracy
├── Scale - Millions of neurons vs brain's 86 billion
└── Ecosystem - Limited tools compared to GPUs
```

## Key Takeaways

1. **Event-driven beats clock-driven** - Process only when inputs change
2. **Collocate memory and compute** - Eliminates von Neumann bottleneck
3. **Spikes encode information** - Timing matters, not just values
4. **Learning is local** - STDP enables on-chip adaptation
5. **Analog enables efficiency** - Memristors for synaptic weights
6. **Power efficiency is key** - 1000× less power than GPUs for some tasks

> See [Appendix L](appendix-l-neuromorphic.md) for RHDL implementation of LIF neurons and STDP learning.
