# Chapter 17: Photonic Computing

*Computing at the speed of light*

---

## Why Light?

What if we computed with photons instead of electrons?

```
Electrons:                          Photons:
┌──────────────────────────┐       ┌──────────────────────────┐
│ Speed: ~1% of c in wire  │       │ Speed: c (speed of light) │
│ Interference: problematic│       │ Interference: useful!     │
│ Heat: major problem      │       │ Heat: minimal            │
│ Bandwidth: GHz           │       │ Bandwidth: THz+          │
│ Energy: pJ per op        │       │ Energy: fJ per op        │
└──────────────────────────┘       └──────────────────────────┘
```

Photonic computing exploits the physical properties of light:
- **Speed**: Light travels at 3×10⁸ m/s
- **Parallelism**: Multiple wavelengths in same waveguide (WDM)
- **Interference**: Two beams combine—this *is* computation
- **Low loss**: Photons don't dissipate heat like electrons
- **Bandwidth**: Optical signals can carry THz of information

---

## The Key Insight: Interference Is Computation

When two coherent light beams combine, they interfere:

```
Constructive Interference:          Destructive Interference:
    ~~~~                               ~~~~
  +     → amplitude doubles         +  ^^^^ → amplitude cancels
    ~~~~                               vvvv
       ↓                                  ↓
    ≈≈≈≈ (bright)                     ___ (dark)

This is NOT noise—it's physics we can USE for computation!
```

The intensity after interference:
```
I = |E₁ + E₂|² = |E₁|² + |E₂|² + 2|E₁||E₂|cos(φ)

The cross-term 2|E₁||E₂|cos(φ) is a MULTIPLICATION!
```

---

## Optical Components

### Waveguide

Light's equivalent of a wire:

```
Silicon Waveguide (cross-section):
       ┌─────────────────┐
       │    SiO₂ cladding │
       │   ┌───────────┐  │
       │   │   Silicon  │  │ ← Light confined here
       │   │  220×500nm │  │   (total internal reflection)
       │   └───────────┘  │
       │    SiO₂ cladding │
       └─────────────────┘

Light propagates along the length
Mode shape determines how light travels
```

### Phase Shifter

Changes the phase of light (the "variable" in optical computing):

```
         ──────┬────────────────────
               │
    input →    │ heater (thermal)   → output
               │ or voltage (E-O)     (phase shifted)
         ──────┴────────────────────

Phase shift: φ = (2π/λ) × Δn × L

Where:
  Δn = refractive index change (from heat or voltage)
  L = interaction length
```

### Directional Coupler (Beam Splitter)

Splits light between two paths:

```
         Input A ───────┐     ┌─────── Output A'
                         ╲   ╱   (partial)
                          ╲ ╱
                           ╳   ← Evanescent coupling
                          ╱ ╲
                         ╱   ╲
         Input B ───────┘     └─────── Output B'

Coupling ratio determined by gap and length

Matrix form:
┌───┐   ┌                    ┐ ┌───┐
│A' │   │ √(1-κ)    j√κ      │ │ A │
│   │ = │                    │ │   │
│B' │   │   j√κ    √(1-κ)    │ │ B │
└───┘   └                    ┘ └───┘

Where κ = coupling ratio (0 to 1)
```

### Mach-Zehnder Interferometer (MZI)

The **fundamental building block** of photonic computing:

```
                         ┌───────────────┐
                    ┌────┤ Phase shift θ ├────┐
         ┌──────┐  │    └───────────────┘    │  ┌──────┐
 In1 ───►│      ├──┤                         ├──┤      ├──► Out1
         │  DC  │  │                         │  │  DC  │
 In2 ───►│ 50:50├──┤                         ├──┤ 50:50├──► Out2
         └──────┘  │    ┌───────────────┐    │  └──────┘
                    └────┤ Phase shift φ ├────┘
                         └───────────────┘

DC = Directional Coupler (50:50 beam splitter)
θ, φ = programmable phase shifts
```

The MZI implements a 2×2 unitary matrix:

```
       ┌             ┐
U(θ,φ) = │ e^(jφ)cos(θ)   -sin(θ) │
       │ e^(jφ)sin(θ)    cos(θ)  │
       └             ┘

By choosing θ and φ, we can implement ANY 2×2 unitary!
```

---

## Matrix-Vector Multiplication

This is the killer application for photonic computing.

### The Problem

Neural networks spend most time on:
```
y = Wx

Where:
  x = input vector (N elements)
  W = weight matrix (M × N)
  y = output vector (M elements)

Operations: M × N multiplications + M × (N-1) additions
For large N, M: billions of operations per layer
```

### Photonic Solution

Matrix-vector multiplication in a *single pass* through the chip:

```
          W = U Σ V†  (Singular Value Decomposition)

Any matrix can be decomposed into:
  V† = unitary (MZI mesh)
  Σ  = diagonal (attenuators)
  U  = unitary (MZI mesh)

Input ──►[V† mesh]──►[Σ attenuators]──►[U mesh]──► Output
   x                                                 y

Light passes through in ~100 picoseconds
Billions of "operations" happen simultaneously!
```

### MZI Mesh for Unitary Matrices

Any N×N unitary matrix can be built from N(N-1)/2 MZIs:

```
4×4 Unitary (Reck decomposition):

 In₀ ─────────●────────●────────●──── Out₀
              │        │        │
 In₁ ────●────┴───●────┴───●────┴──── Out₁
         │        │        │
 In₂ ────┴───●────┴───●────┴───────── Out₂
             │        │
 In₃ ────────┴────────┴────────────── Out₃

● = MZI (with programmable phases)

Total MZIs for N×N: N(N-1)/2
For N=64: 2016 MZIs
For N=128: 8128 MZIs
```

---

## Coherent Detection

To read the output, we need to measure the light:

```
Homodyne Detection:
                    ┌─────────────────┐
 Signal ──────────►│                 │
                    │  50:50 coupler  ├──► Photodetector 1
 Local oscillator ─►│                 │        │
 (reference)        └─────────────────┘        │
                           │                    │
                           └──► Photodetector 2─┤
                                                │
                                          ┌─────┴─────┐
                                          │ Subtract  │
                                          └─────┬─────┘
                                                │
                                          Output ∝ E_signal
```

Benefits:
- Measures electric field (amplitude AND phase)
- Shot-noise limited sensitivity
- Can recover complex-valued outputs

---

## Example: Optical Neural Network

```
                    Optical Neural Network Layer
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│   ┌─────┐     ┌───────────────┐     ┌────────┐     ┌─────┐   │
│   │     │     │               │     │        │     │     │   │
│ ─►│ DAC ├────►│   MZI Mesh    ├────►│ Detect ├────►│ ADC │─► │
│   │     │     │   (Weights)   │     │        │     │     │   │
│   └─────┘     └───────────────┘     └────────┘     └─────┘   │
│   Electrical    Optical domain      Electrical                │
│    input         (matrix mult)       output                   │
│                                                                │
│        ┌───────────────────────────────────────┐              │
│        │ Time per layer: ~100 ps (optical)     │              │
│        │ vs ~1 μs (GPU)  → 10,000× speedup    │              │
│        └───────────────────────────────────────┘              │
└────────────────────────────────────────────────────────────────┘
```

---

## Wavelength Division Multiplexing (WDM)

Multiple computations in parallel using different colors:

```
Different wavelengths, same waveguide:

    λ₁ (1530 nm) ───┐
                    ├───►  ═══════════════  ───┬──► λ₁
    λ₂ (1535 nm) ───┤      Single waveguide    ├──► λ₂
                    │      Carries ALL λs      │
    λ₃ (1540 nm) ───┤                          ├──► λ₃
                    │                          │
    λ₄ (1545 nm) ───┘                          └──► λ₄

Each wavelength is independent → parallel computation!

Dense WDM: 100+ channels in C-band (1530-1565 nm)
```

---

## Challenges

### Optical Loss

Light attenuates as it travels:

```
Silicon waveguide loss: ~2 dB/cm
MZI insertion loss: ~0.2 dB per MZI
Coupler loss: ~0.1 dB per coupler

For 64×64 matrix:
  Total MZIs: 2016
  Estimated loss: >200 dB  ← Signal vanishes!

Solutions:
  - Optical amplifiers (but noisy)
  - Lower-loss materials
  - Smaller meshes with electronic refresh
```

### Precision

Analog computation has limited precision:

```
Typical achievable: 4-6 bits effective
Why:
  - Phase shifter precision: ~0.1 radian
  - Fabrication variations
  - Temperature sensitivity
  - Shot noise at detector

Workarounds:
  - Training-aware quantization
  - Calibration loops
  - Hybrid analog-digital architectures
```

### Integration Complexity

```
Photonic chip needs:
  - Lasers (light source)
  - Modulators (electrical → optical)
  - Phase shifters (tunable)
  - Waveguides (routing)
  - Detectors (optical → electrical)
  - Electronics (control, readout)

Heterogeneous integration is HARD:
  - Silicon photonics: CMOS-compatible
  - III-V lasers: different materials
  - Control electronics: different process
```

---

## Commercial Efforts

| Company | Approach | Target |
|---------|----------|--------|
| Lightmatter | MZI mesh, silicon photonics | AI inference |
| Luminous | Holographic computing | AI training |
| Lightelligence | MZI mesh + memory | AI accelerator |
| Intel | Silicon photonics integration | Datacenter |
| Ayar Labs | Optical I/O (not compute) | Chip interconnect |

---

## Comparison with Electronic Computing

| Aspect | Electronic | Photonic |
|--------|------------|----------|
| Matrix mult speed | ~1 μs (GPU) | ~100 ps |
| Energy per MAC | ~1 pJ | ~1 fJ (theoretical) |
| Precision | 32-bit float | 4-6 bit |
| Programmability | Flexible | Matrix operations |
| Integration | Mature | Developing |
| Memory | Dense, fast | Difficult |

**Photonics excels at**: Large matrix multiplications, low-latency inference

**Photonics struggles with**: Nonlinearities, memory, high precision, general compute

---

## The Future: Photonic-Electronic Hybrid

```
┌──────────────────────────────────────────────────────────────┐
│                      Hybrid System                            │
│                                                               │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐    │
│  │   Memory    │     │   Photonic  │     │   Memory    │    │
│  │   (SRAM)    │────►│   Matrix    │────►│   (SRAM)    │    │
│  │             │     │   Engine    │     │             │    │
│  └─────────────┘     └─────────────┘     └─────────────┘    │
│        ▲                                        │            │
│        │     ┌─────────────────────────┐       │            │
│        │     │   Electronic Control    │       │            │
│        └─────┤   (Nonlinearities,      │◄──────┘            │
│              │    normalization)       │                     │
│              └─────────────────────────┘                     │
│                                                               │
│  Use photonics for what it's good at: matrix operations     │
│  Use electronics for everything else                         │
└──────────────────────────────────────────────────────────────┘
```

---

## RHDL Simulation?

Unlike quantum computing (which can be simulated classically), photonics *can* be implemented in RHDL—but it misses the point:

```ruby
# This defeats the purpose!
class MZI < SimComponent
  input :in1, :in2
  input :theta, :phi
  output :out1, :out2

  behavior do
    # Matrix multiplication... digitally
    out1 <= in1 * cos(theta) + in2 * sin(theta) * exp(j*phi)
    out2 <= -in1 * sin(theta) + in2 * cos(theta) * exp(j*phi)
  end
end
```

Instead, see [Appendix Q](appendix-q-photonic.md) for a Ruby complex-number simulation that captures the physics of optical interference.

---

## Summary

- **Light as computation**: Interference IS arithmetic
- **MZI**: The fundamental 2×2 unitary building block
- **Matrix decomposition**: Any matrix = unitary × diagonal × unitary
- **Single-pass multiplication**: ~100 ps for arbitrary matrix size
- **WDM parallelism**: Multiple wavelengths = parallel computations
- **Challenges**: Loss, precision, integration
- **Best for**: Matrix-heavy, low-precision workloads (AI inference)
- **Hybrid future**: Photonic matrix engines + electronic control

---

## Exercises

1. Calculate the transfer matrix for a 50:50 directional coupler
2. Show that cascaded MZIs can implement any 2×2 unitary
3. Estimate signal loss for a 32×32 MZI mesh
4. Design a photonic circuit for 2×2 matrix multiplication
5. Compare energy per MAC: GPU vs photonic (with realistic losses)

---

## Further Reading

- Shen et al., "Deep learning with coherent nanophotonic circuits" Nature (2017)
- Clements et al., "Optimal design for universal multiport interferometers" Optica (2016)
- Harris et al., "Linear programmable nanophotonic processors" Nature Photonics (2018)
- Miller, "Attojoule Optoelectronics for Low-Energy Information Processing" (2017)

---

*Previous: [Chapter 14 - Neuromorphic Computing](14-neuromorphic-computing.md)*

*Appendix: [Appendix Q - Photonic Simulation](appendix-q-photonic.md)*
