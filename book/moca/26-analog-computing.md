# Chapter 26: Analog Computing

*Computation with continuous values*

---

## The Road Not Taken

Before digital computers dominated, **analog computers** solved the hardest problems of their era. They computed with continuous voltages, not discrete bits—and for certain problems, they were faster and more efficient than anything digital.

```
Digital Computing:                  Analog Computing:
┌─────────────────────────────┐    ┌─────────────────────────────┐
│                             │    │                             │
│  Values: 0 or 1             │    │  Values: -10V to +10V       │
│  Operations: AND, OR, NOT   │    │  Operations: +, -, ∫, d/dt  │
│  Precision: Exact (N bits)  │    │  Precision: ~0.01-1%        │
│  Speed: Clock-limited       │    │  Speed: Continuous!         │
│                             │    │                             │
└─────────────────────────────┘    └─────────────────────────────┘
```

---

## Why Analog?

### Physics IS Analog

The physical world computes continuously:

```
Resistor network:          Naturally solves Kirchhoff's laws
Mass-spring system:        Naturally solves F = ma
RC circuit:                Naturally integrates current
Pendulum:                  Naturally solves d²θ/dt² = -g/L·sin(θ)

The universe is an analog computer running physics simulations!
```

### Parallelism for Free

In an analog circuit, all components compute simultaneously:

```
Digital (sequential):
  Step 1: Fetch A
  Step 2: Fetch B
  Step 3: Compute A + B
  Step 4: Store result
  Total: 4 clock cycles

Analog (continuous):
  Voltages A and B exist
  Op-amp output IS the sum
  Total: propagation delay (~µs)

  AND it handles millions of "additions" (across circuit) at once!
```

### Energy Efficiency

Analog can be incredibly efficient:

```
Digital multiply-accumulate (MAC):
  ~1 pJ per operation (modern GPU)
  Requires: transistors switching, moving charge

Analog MAC:
  ~1 fJ per operation (theoretical)
  Just: current through resistor × voltage

Ratio: 1000× more efficient!
```

---

## The Operational Amplifier

The **op-amp** is the building block of analog computing:

```
                    Vcc (+15V)
                      │
                 ┌────┴────┐
                 │         │
  V- ──────────►─┤-        │
                 │    A    ├──────► Vout
  V+ ──────────►─┤+        │
                 │         │
                 └────┬────┘
                      │
                    Vee (-15V)

Ideal op-amp:
  - Infinite gain (A → ∞)
  - Infinite input impedance
  - Zero output impedance
  - V+ = V- (virtual short)

With negative feedback: Vout = f(V+, V-, components)
```

---

## Basic Analog Operations

### Inverting Amplifier (Scaling)

```
              Rf
         ┌───/\/\/───┐
         │           │
  Vin ──/\/\/──┬─────┤-
         R1   │     │   \
              │     │    >───► Vout = -(Rf/R1) × Vin
              │     │   /
              └─────┤+
                    │
                   GND

If Rf = R1: Vout = -Vin (inverter)
If Rf = 2R1: Vout = -2Vin (multiply by -2)
```

### Summing Amplifier (Addition)

```
              Rf
         ┌───/\/\/───┐
  V1 ──/\/\/──┐      │
         R1   │      │
              ├──────┤-
  V2 ──/\/\/──┤     │   \
         R2   │     │    >───► Vout = -Rf(V1/R1 + V2/R2 + V3/R3)
              │     │   /
  V3 ──/\/\/──┘     ┤+
         R3         │
                   GND

If all R equal: Vout = -(V1 + V2 + V3)
Weighted sum: Choose different resistors!
```

### Integrator (∫)

```
                C
         ┌─────┤├─────┐
         │            │
  Vin ──/\/\/──┬──────┤-
         R     │     │   \
               │     │    >───► Vout = -(1/RC)∫Vin dt
               │     │   /
               └─────┤+
                     │
                    GND

Output is the TIME INTEGRAL of input!
This is incredibly useful for solving differential equations.
```

### Differentiator (d/dt)

```
              R
         ┌───/\/\/───┐
         │           │
  Vin ───┤├────┬─────┤-
          C    │     │   \
               │     │    >───► Vout = -RC × dVin/dt
               │     │   /
               └─────┤+
                     │
                    GND

Output is the TIME DERIVATIVE of input!
(Rarely used in practice due to noise amplification)
```

### Multiplier

```
         ┌───────────┐
  X ────►│           │
         │  Analog   ├────► Vout = (X × Y) / 10V
  Y ────►│ Multiplier│
         └───────────┘

Usually implemented with:
  - Gilbert cell (transistor-based)
  - Log-antilog circuits
  - Pulse-width modulation
```

---

## Solving Differential Equations

The killer app for analog computers: **solving ODEs in real-time**.

### Example: Mass-Spring-Damper

```
Physical system:
  m·(d²x/dt²) + c·(dx/dt) + k·x = F(t)

Rearrange for highest derivative:
  d²x/dt² = (1/m)[F(t) - c·(dx/dt) - k·x]

Analog circuit:
                    ┌─────────────────────────────────────┐
                    │                                     │
  F(t) ──►(+)──────►│ ∫ ├───────►│ ∫ ├────────────────────┼───► x(t)
           ▲        │            │                       │
           │        │ d²x/dt²    │  dx/dt                │
           │        └────────────┴───────────┬───────────┘
           │                                 │
           │    ┌────────┐                   │
           └────┤ -c/m   │◄──────────────────┤ (dx/dt)
           │    └────────┘                   │
           │                                 │
           │    ┌────────┐                   │
           └────┤ -k/m   │◄──────────────────┘ (x)
                └────────┘

Set up the circuit, apply F(t), and x(t) appears at output!
Runs in REAL TIME (or faster with time scaling).
```

### Lorenz Attractor (Chaos)

```
The famous chaotic system:
  dx/dt = σ(y - x)
  dy/dt = x(ρ - z) - y
  dz/dt = xy - βz

Analog implementation:
  - 3 integrators (for x, y, z)
  - 2 multipliers (for xz, xy)
  - Several summers and scalers

Result: Continuous chaotic trajectory on oscilloscope!
```

---

## Historical Analog Computers

### Fire Control (WWII)

```
Problem: Aim anti-aircraft guns at moving planes

Inputs:
  - Target bearing (θ)
  - Target elevation (φ)
  - Target range (r)
  - Aircraft speed estimate

Output:
  - Where to aim (future position)

The analog computer solved ballistic equations
in real-time, tracking the target continuously.

Example: Mark 37 Fire Control System
  - Mechanical + electrical analog
  - Continuously computed lead angle
  - Won the war in the Pacific
```

### ENIAC's Predecessor

```
Before ENIAC (digital), there was the
Differential Analyzer (1930s, Vannevar Bush):

  ┌────────────────────────────────────────┐
  │                                        │
  │  Mechanical integrators (wheel-disk)   │
  │  Connected by shafts and gears         │
  │  Solved 6th-order differential eqs     │
  │                                        │
  │  Used for:                             │
  │    - Ballistics tables                 │
  │    - Atomic bomb calculations          │
  │    - Electrical grid analysis          │
  │                                        │
  └────────────────────────────────────────┘
```

### Electronic Analog Computers (1950s-70s)

```
┌──────────────────────────────────────────────────────────────┐
│                    EAI 680 ANALOG COMPUTER                    │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○  │  │
│  │ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○  │  │
│  │               PATCH PANEL                              │  │
│  │  (Connect op-amps, integrators, multipliers)          │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐       │
│  │ INTEGR 1 │ │ INTEGR 2 │ │ SUMMER 1 │ │ MULT 1   │  ...  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘       │
│                                                              │
│  Components: 20+ integrators, 40+ summers, 8 multipliers    │
│  Precision: 0.01% (4 decimal digits)                        │
│  Speed: 1000× real-time possible                            │
└──────────────────────────────────────────────────────────────┘

Programming = plugging patch cables!
```

---

## Modern Analog Computing

### Analog Neural Networks

```
Traditional digital NN:
  y = Σ(wi × xi) + b    ← billions of MACs

Analog NN:
                R1       R2       R3
  x1 ──────────/\/\/─┐
                     │
  x2 ──────────/\/\/─┼───────┤-
                     │       │  \
  x3 ──────────/\/\/─┘       │   >──► y
                             │  /
                        ─────┤+

  Resistor values = weights!
  Currents sum automatically (Kirchhoff)
  One op-amp = one neuron's weighted sum
```

### In-Memory Computing

```
Traditional (von Neumann):
  ┌──────────┐        ┌──────────┐
  │  Memory  │◄──────►│  Compute │
  └──────────┘        └──────────┘
       Data moves back and forth (bottleneck!)

In-Memory Analog:
  ┌────────────────────────────────────┐
  │         MEMORY ARRAY               │
  │  ┌───┬───┬───┬───┐                │
  │  │ R │ R │ R │ R │ ← Resistors    │
  │  ├───┼───┼───┼───┤   store        │
  │  │ R │ R │ R │ R │   weights      │
  │  ├───┼───┼───┼───┤                │
  │  │ R │ R │ R │ R │                │
  │  └───┴───┴───┴───┘                │
  │    ↑   ↑   ↑   ↑                  │
  │   V1  V2  V3  V4  ← Input voltages │
  │                                    │
  │   Output = Σ(Vi × Gi) per row     │
  │   Matrix-vector multiply IN MEMORY │
  └────────────────────────────────────┘

No data movement! Computation happens where data lives.
```

### Memristors

```
The "missing" circuit element (discovered 2008):

  Resistor:   V = IR         (resistance)
  Capacitor:  Q = CV         (capacitance)
  Inductor:   Φ = LI         (inductance)
  Memristor:  Φ = M(q)·q     (memristance)

Key property: Resistance depends on history of current!

           ┌─────────────┐
  ───────►│  Memristor  │───────►
           └─────────────┘

  R = f(∫I dt)  ← Remembers how much charge passed!

Applications:
  - Non-volatile analog memory
  - Synaptic weights in neuromorphic chips
  - In-memory matrix operations
```

---

## Precision and Noise

### The Fundamental Tradeoff

```
Digital:
  Precision: Exact (32 bits = 9 decimal digits)
  Noise: Doesn't matter (0 vs 1 is robust)
  Cost: Many transistors per bit

Analog:
  Precision: Limited by noise (~0.1-1%)
  Noise: Thermal, shot, 1/f all accumulate
  Cost: Simple circuits, but calibration needed

Thermal noise in resistor:
  Vn = √(4kTRB)

  At room temp, 1kΩ, 1MHz bandwidth:
  Vn ≈ 4 µV RMS

  For ±10V range: ~0.00004% noise floor
  But: offsets, drift, nonlinearity add more!
```

### Signal-to-Noise Ratio

```
Effective bits ≈ log2(SNR)

Example:
  60 dB SNR = 1000:1 voltage ratio
  Effective bits ≈ log2(1000) ≈ 10 bits

Typical analog computer: 40-60 dB → 6-10 bits
Best analog ICs: 80+ dB → 13+ bits
But: Much faster than equivalent digital!
```

---

## Hybrid Analog-Digital

The best of both worlds:

```
┌─────────────────────────────────────────────────────────────┐
│                    HYBRID SYSTEM                             │
│                                                             │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐ │
│  │ Digital │    │   ADC   │    │ Analog  │    │   DAC   │ │
│  │ Control │───►│         │───►│ Compute │───►│         │ │
│  │         │    │         │    │         │    │         │ │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘ │
│       │                                             │       │
│       └─────────────────────────────────────────────┘       │
│                     Feedback loop                           │
│                                                             │
│  Digital: Programmability, precision, control               │
│  Analog: Speed, efficiency, natural computation             │
└─────────────────────────────────────────────────────────────┘
```

### Modern Examples

| Company | Approach | Application |
|---------|----------|-------------|
| Mythic | Analog in-memory | Edge AI inference |
| Syntiant | Analog + digital NN | Voice/audio processing |
| IBM | PCM crossbar arrays | AI accelerator research |
| Intel Loihi | Mixed analog-digital | Neuromorphic computing |
| Aspinity | Analog feature extraction | Always-on sensors |

---

## When to Use Analog

### Analog Excels At

- **Differential equations**: Natural fit
- **Matrix operations**: Resistor crossbars
- **Low-power sensing**: Analog preprocessing
- **Real-time control**: No sampling delay
- **Approximate computing**: When 6 bits is enough

### Digital Excels At

- **Exact computation**: Financial, cryptography
- **Complex logic**: Conditionals, loops
- **Storage**: Bits don't drift
- **Programmability**: Software changes everything
- **Debugging**: State is observable

### The Future: Analog Renaissance?

```
1950s: Analog computers everywhere
1970s: Digital wins (Moore's Law)
2020s: Analog returns for AI!

Why now?
  - AI is mostly matrix math (analog-friendly)
  - Power efficiency matters (mobile, edge)
  - "Good enough" precision (neural nets are robust)
  - Moore's Law slowing (need new approaches)
```

---

## RHDL?

Analog circuits don't map naturally to RHDL's digital model. Instead, see [Appendix Z](appendix-z-analog.md) for Ruby simulation of analog components using continuous-time differential equations.

```ruby
# This captures the physics better than RHDL
class Integrator
  def initialize(gain: 1.0)
    @gain = gain
    @state = 0.0
  end

  def step(input, dt)
    @state += -@gain * input * dt
    @state
  end
end
```

---

## Summary

- **Continuous values**: Voltages, not bits
- **Op-amp building blocks**: Summer, integrator, multiplier
- **Differential equations**: Solved naturally and in real-time
- **Historical importance**: Won WWII, computed bomb trajectories
- **Modern revival**: Analog AI, in-memory computing, memristors
- **Tradeoffs**: Speed/efficiency vs precision/programmability
- **Hybrid future**: Analog compute + digital control

---

## Exercises

1. Design an analog circuit for y = 3x + 2
2. Build an integrator and verify ∫sin(t)dt = -cos(t)
3. Implement a 2nd-order lowpass filter
4. Simulate the Lorenz attractor
5. Compare power consumption: analog vs digital MAC

---

## Further Reading

- Ulmann, "Analog Computing" (2013)
- Cowan & Sharp, "Neural Nets and Analog Computation" (2016)
- IEEE Solid-State Circuits, "Analog AI" special issues
- "The Differential Analyzer" (Vannevar Bush, 1931)

---

*Previous: [Chapter 25 - Photonic Computing](25-photonic-computing.md)*

*Appendix: [Appendix Z - Analog Simulation](appendix-z-analog.md)*
