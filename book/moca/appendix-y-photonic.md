# Appendix Y: Photonic Computing Simulation

*Ruby simulation of optical interference and matrix operations*

---

## Overview

This appendix provides Ruby simulations of photonic computing concepts:

1. **Complex electric fields** - Light as amplitude and phase
2. **Optical components** - Beam splitters, phase shifters, MZIs
3. **Matrix decomposition** - Building arbitrary unitaries from MZIs
4. **Optical neural network** - Matrix-vector multiplication
5. **Noise and loss modeling** - Realistic imperfections

Unlike RHDL (which models digital hardware), we use Ruby's complex number support to simulate the continuous physics of light.

---

## Complex Numbers in Ruby

```ruby
# Ruby has built-in Complex number support
z = Complex(3, 4)       # 3 + 4i
z.real                  # => 3
z.imag                  # => 4
z.magnitude             # => 5.0 (|z|)
z.phase                 # => 0.927... (angle in radians)
z.conjugate             # => 3 - 4i

# Euler's formula: e^(iθ) = cos(θ) + i·sin(θ)
theta = Math::PI / 4
euler = Complex.polar(1, theta)  # magnitude 1, phase θ
euler == Complex(Math.cos(theta), Math.sin(theta))  # => true

# Light field: E = A·e^(iφ)
amplitude = 1.0
phase = Math::PI / 3
electric_field = Complex.polar(amplitude, phase)
```

---

## Basic Optical Components

### Waveguide

```ruby
# A waveguide transmits light with some loss and phase accumulation
class Waveguide
  attr_reader :length        # meters
  attr_reader :loss_db_per_m # dB/m
  attr_reader :n_eff         # effective refractive index

  WAVELENGTH = 1550e-9  # 1550 nm (C-band)
  C = 3e8               # speed of light

  def initialize(length:, loss_db_per_m: 200, n_eff: 2.4)
    @length = length
    @loss_db_per_m = loss_db_per_m
    @n_eff = n_eff
  end

  def propagate(field)
    # Phase accumulation: φ = (2π/λ) × n × L
    beta = 2 * Math::PI * @n_eff / WAVELENGTH
    phase_shift = beta * @length

    # Loss: convert dB to linear
    loss_db = @loss_db_per_m * @length
    transmission = 10 ** (-loss_db / 20.0)  # Amplitude, not power

    # Apply both
    field * Complex.polar(transmission, phase_shift)
  end
end

# Example
wg = Waveguide.new(length: 0.001)  # 1 mm
input = Complex.polar(1, 0)        # Unit amplitude, zero phase
output = wg.propagate(input)
puts "Output magnitude: #{output.magnitude}"  # Slightly less than 1
puts "Output phase: #{output.phase}"          # Non-zero (accumulated)
```

### Phase Shifter

```ruby
# Applies a programmable phase shift to light
class PhaseShifter
  attr_accessor :phase  # radians

  def initialize(phase: 0)
    @phase = phase
  end

  def apply(field)
    field * Complex.polar(1, @phase)
  end

  # Thermal phase shifters have ~0.1 radian precision
  def self.with_noise(target_phase, noise_std: 0.1)
    actual = target_phase + Random.rand * noise_std
    new(phase: actual)
  end
end

# Example
ps = PhaseShifter.new(phase: Math::PI / 2)
input = Complex(1, 0)
output = ps.apply(input)
puts output  # => (0+1i) approximately (90° rotation)
```

### Directional Coupler (Beam Splitter)

```ruby
# 2x2 beam splitter with coupling ratio kappa
class DirectionalCoupler
  attr_reader :kappa  # Coupling ratio (0 to 1)

  def initialize(kappa: 0.5)
    @kappa = kappa
  end

  # Returns [output1, output2] given [input1, input2]
  def couple(in1, in2)
    # Transfer matrix:
    # [out1]   [  √(1-κ)    j√κ   ] [in1]
    # [out2] = [   j√κ    √(1-κ)  ] [in2]

    t = Math.sqrt(1 - @kappa)  # Transmission coefficient
    c = Math.sqrt(@kappa)       # Coupling coefficient

    out1 = t * in1 + Complex(0, 1) * c * in2
    out2 = Complex(0, 1) * c * in1 + t * in2

    [out1, out2]
  end

  # Matrix form for linear algebra
  def matrix
    t = Math.sqrt(1 - @kappa)
    c = Math.sqrt(@kappa)
    Matrix[
      [Complex(t, 0),    Complex(0, c)],
      [Complex(0, c),    Complex(t, 0)]
    ]
  end
end

# Example: 50:50 splitter
dc = DirectionalCoupler.new(kappa: 0.5)
in1 = Complex(1, 0)
in2 = Complex(0, 0)
out1, out2 = dc.couple(in1, in2)
puts "|out1|² = #{out1.magnitude**2}"  # => ~0.5
puts "|out2|² = #{out2.magnitude**2}"  # => ~0.5
```

---

## Mach-Zehnder Interferometer (MZI)

```ruby
require 'matrix'

# MZI: Two beam splitters with phase shifters in between
class MZI
  attr_accessor :theta, :phi  # Programmable phases

  def initialize(theta: 0, phi: 0)
    @theta = theta
    @phi = phi
  end

  # Process two inputs through the MZI
  def process(in1, in2)
    # First 50:50 coupler
    dc1 = DirectionalCoupler.new(kappa: 0.5)
    mid1, mid2 = dc1.couple(in1, in2)

    # Phase shifters in each arm
    ps_top = PhaseShifter.new(phase: @theta)
    ps_bot = PhaseShifter.new(phase: @phi)
    mid1 = ps_top.apply(mid1)
    mid2 = ps_bot.apply(mid2)

    # Second 50:50 coupler
    dc2 = DirectionalCoupler.new(kappa: 0.5)
    dc2.couple(mid1, mid2)
  end

  # Transfer matrix representation
  def matrix
    # U(θ,φ) = DC × Phases × DC
    # Simplifies to:
    #   [e^(jφ)cos(θ)   -sin(θ)    ]
    #   [e^(jφ)sin(θ)    cos(θ)    ]

    c = Math.cos(@theta)
    s = Math.sin(@theta)
    e_phi = Complex.polar(1, @phi)

    Matrix[
      [e_phi * c,  Complex(-s, 0)],
      [e_phi * s,  Complex(c, 0)]
    ]
  end

  # Configure MZI to implement a specific 2x2 unitary element
  def self.for_element(target_00, target_01)
    # Given desired matrix elements, find theta and phi
    # This is the inverse problem

    # |target_00| = cos(θ)
    theta = Math.acos(target_00.magnitude.clamp(-1, 1))

    # arg(target_00) = φ
    phi = target_00.phase

    new(theta: theta, phi: phi)
  end
end

# Example: MZI as identity (θ=0, φ=0)
mzi = MZI.new(theta: 0, phi: 0)
puts mzi.matrix
# => Matrix[[1+0i, 0+0i], [0+0i, 1+0i]]

# Example: MZI as swap (θ=π/2, φ=0)
mzi_swap = MZI.new(theta: Math::PI/2, phi: 0)
out1, out2 = mzi_swap.process(Complex(1, 0), Complex(0, 0))
puts "|out1|² = #{out1.magnitude**2}"  # => ~0
puts "|out2|² = #{out2.magnitude**2}"  # => ~1 (input swapped to other port)
```

---

## Interference Demonstration

```ruby
# Show how interference performs computation
class InterferenceDemo
  def self.constructive
    # Two beams, same phase → add
    field1 = Complex.polar(0.5, 0)
    field2 = Complex.polar(0.5, 0)
    result = field1 + field2

    puts "Constructive interference:"
    puts "  Field 1: #{field1.magnitude} at phase #{field1.phase}"
    puts "  Field 2: #{field2.magnitude} at phase #{field2.phase}"
    puts "  Sum:     #{result.magnitude} at phase #{result.phase}"
    puts "  Intensity: #{result.magnitude**2}"  # => 1.0 (doubled amplitude)
  end

  def self.destructive
    # Two beams, opposite phase → cancel
    field1 = Complex.polar(0.5, 0)
    field2 = Complex.polar(0.5, Math::PI)  # 180° phase shift
    result = field1 + field2

    puts "Destructive interference:"
    puts "  Field 1: #{field1.magnitude} at phase #{field1.phase}"
    puts "  Field 2: #{field2.magnitude} at phase #{field2.phase}"
    puts "  Sum:     #{result.magnitude} at phase #{result.phase}"
    puts "  Intensity: #{result.magnitude**2}"  # => ~0 (cancelled)
  end

  def self.partial
    # Two beams, 90° phase difference
    field1 = Complex.polar(0.5, 0)
    field2 = Complex.polar(0.5, Math::PI/2)
    result = field1 + field2

    puts "Partial interference (90°):"
    puts "  Field 1: #{field1.magnitude} at phase #{field1.phase}"
    puts "  Field 2: #{field2.magnitude} at phase #{field2.phase}"
    puts "  Sum:     #{result.magnitude} at phase #{result.phase}"
    puts "  Intensity: #{result.magnitude**2}"  # => 0.5
  end
end

InterferenceDemo.constructive
InterferenceDemo.destructive
InterferenceDemo.partial
```

---

## MZI Mesh for Arbitrary Unitaries

```ruby
require 'matrix'

# Reck decomposition: Any N×N unitary = product of MZIs
class MZIMesh
  attr_reader :size
  attr_reader :mzis  # Array of MZI configurations

  def initialize(size)
    @size = size
    @mzis = []
  end

  # Decompose a unitary matrix into MZI settings
  def self.from_unitary(unitary)
    n = unitary.row_count
    mesh = new(n)

    # Work with a copy we'll reduce to identity
    u = unitary.to_a.map(&:dup)

    # Reck decomposition: zero out elements column by column
    (n - 1).downto(0) do |col|
      (n - 1).downto(col + 1) do |row|
        # Use MZI on rows (row-1, row) to zero element [row, col]
        theta, phi = compute_nulling_angles(u, row, col)
        mesh.mzis << { row: row - 1, theta: theta, phi: phi }

        # Apply MZI to matrix
        apply_mzi_to_matrix(u, row - 1, theta, phi)
      end
    end

    mesh
  end

  def self.compute_nulling_angles(u, row, col)
    # Find θ, φ to null u[row][col] using u[row-1][col]
    a = Complex(u[row - 1][col])
    b = Complex(u[row][col])

    r = Math.sqrt(a.magnitude**2 + b.magnitude**2)
    return [0, 0] if r < 1e-10

    theta = Math.atan2(b.magnitude, a.magnitude)
    phi = b.phase - a.phase

    [theta, phi]
  end

  def self.apply_mzi_to_matrix(u, row, theta, phi)
    # Apply MZI rotation to rows (row, row+1)
    c = Math.cos(theta)
    s = Math.sin(theta)
    e_phi = Complex.polar(1, phi)

    u[0].size.times do |col|
      old_top = u[row][col]
      old_bot = u[row + 1][col]

      u[row][col] = e_phi * c * old_top - s * old_bot
      u[row + 1][col] = e_phi * s * old_top + c * old_bot
    end
  end

  # Build the unitary matrix from MZI settings
  def to_matrix
    result = Matrix.identity(@size)

    @mzis.reverse.each do |mzi_config|
      mzi = MZI.new(theta: mzi_config[:theta], phi: mzi_config[:phi])
      mzi_matrix = embed_2x2(mzi.matrix, mzi_config[:row], @size)
      result = mzi_matrix * result
    end

    result
  end

  private

  def embed_2x2(m2x2, row, n)
    # Embed a 2x2 matrix at position (row, row) in an n×n identity
    result = Matrix.identity(n).to_a

    result[row][row] = m2x2[0, 0]
    result[row][row + 1] = m2x2[0, 1]
    result[row + 1][row] = m2x2[1, 0]
    result[row + 1][row + 1] = m2x2[1, 1]

    Matrix[*result]
  end
end

# Example: Decompose a 4x4 DFT matrix
def dft_matrix(n)
  omega = Complex.polar(1, -2 * Math::PI / n)
  Matrix.build(n, n) { |i, j| omega ** (i * j) / Math.sqrt(n) }
end

dft4 = dft_matrix(4)
puts "Original DFT matrix:"
dft4.each_with_index { |e, i, j| puts "  [#{i},#{j}] = #{e.round(3)}" }

mesh = MZIMesh.from_unitary(dft4)
puts "\nMZI mesh has #{mesh.mzis.size} MZIs"  # Should be 4×3/2 = 6

reconstructed = mesh.to_matrix
puts "\nReconstruction error: #{(dft4 - reconstructed).map(&:magnitude).max}"
```

---

## Optical Matrix-Vector Multiplication

```ruby
# Optical neural network layer
class OpticalLayer
  attr_reader :matrix  # The weight matrix
  attr_reader :mesh    # MZI mesh implementing U
  attr_reader :sigmas  # Singular values (implemented as attenuators)
  attr_reader :mesh_v  # MZI mesh implementing V†

  def initialize(weight_matrix)
    @matrix = weight_matrix
    decompose_weights
  end

  def decompose_weights
    # SVD: W = U Σ V†
    # We can implement this optically!

    u, s, vt = svd(@matrix)

    @mesh = MZIMesh.from_unitary(u)
    @sigmas = s
    @mesh_v = MZIMesh.from_unitary(vt)  # V† is already transposed
  end

  def forward(input_vector)
    # Convert to complex (optical fields)
    fields = input_vector.map { |x| Complex(x, 0) }

    # V† unitary (MZI mesh)
    fields = apply_unitary(@mesh_v.to_matrix, fields)

    # Σ diagonal (attenuators/amplifiers)
    fields = fields.each_with_index.map { |f, i| f * @sigmas[i] }

    # U unitary (MZI mesh)
    fields = apply_unitary(@mesh.to_matrix, fields)

    # Output intensities (or coherent detection for complex)
    fields.map { |f| f.real }  # Simplified: take real part
  end

  private

  def apply_unitary(u, fields)
    result = []
    u.row_count.times do |i|
      sum = Complex(0, 0)
      fields.each_with_index do |f, j|
        sum += u[i, j] * f
      end
      result << sum
    end
    result
  end

  def svd(matrix)
    # Simplified SVD for demonstration
    # In practice, use a linear algebra library

    m = matrix.row_count
    n = matrix.column_count

    # For square matrices, use eigendecomposition
    # This is a placeholder - real implementation needs proper SVD

    # Return identity matrices and diagonal for demo
    u = Matrix.identity(m)
    s = Array.new([m, n].min) { |i| matrix[i, i].abs }
    vt = Matrix.identity(n)

    [u, s, vt]
  end
end

# Example
weights = Matrix[
  [0.5, 0.3],
  [0.2, 0.7]
]

layer = OpticalLayer.new(weights)
input = [1.0, 0.5]
output = layer.forward(input)
puts "Input:  #{input}"
puts "Output: #{output}"

# Compare with direct matrix multiply
expected = (weights * Vector[*input]).to_a
puts "Expected: #{expected}"
```

---

## Noise and Loss Modeling

```ruby
# Realistic optical system with imperfections
class NoisyOpticalSystem
  attr_reader :phase_noise_std    # Phase shifter precision (radians)
  attr_reader :loss_per_mzi_db    # Insertion loss per MZI
  attr_reader :detector_noise     # Shot noise at detector

  def initialize(
    phase_noise_std: 0.05,  # ~3° precision
    loss_per_mzi_db: 0.2,
    detector_noise: 0.01
  )
    @phase_noise_std = phase_noise_std
    @loss_per_mzi_db = loss_per_mzi_db
    @detector_noise = detector_noise
  end

  def noisy_phase(target)
    target + randn * @phase_noise_std
  end

  def apply_loss(field, num_mzis)
    total_loss_db = num_mzis * @loss_per_mzi_db
    transmission = 10 ** (-total_loss_db / 20.0)
    field * transmission
  end

  def detect(field)
    # Intensity detection with shot noise
    intensity = field.magnitude ** 2
    intensity + randn * @detector_noise * Math.sqrt(intensity)
  end

  def process_with_noise(mesh, input_fields)
    fields = input_fields.dup

    mesh.mzis.each do |mzi_config|
      # Add phase noise
      noisy_theta = noisy_phase(mzi_config[:theta])
      noisy_phi = noisy_phase(mzi_config[:phi])

      # Apply noisy MZI
      mzi = MZI.new(theta: noisy_theta, phi: noisy_phi)
      row = mzi_config[:row]

      out1, out2 = mzi.process(fields[row], fields[row + 1])
      fields[row] = apply_loss(out1, 1)
      fields[row + 1] = apply_loss(out2, 1)
    end

    # Detect with noise
    fields.map { |f| detect(f) }
  end

  private

  def randn
    # Box-Muller transform for Gaussian
    u1 = rand
    u2 = rand
    Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math::PI * u2)
  end
end

# Compare ideal vs noisy
puts "Ideal vs Noisy comparison:"

ideal_mesh = MZIMesh.from_unitary(Matrix.identity(4))
noisy_system = NoisyOpticalSystem.new

input = [1, 0, 0, 0].map { |x| Complex(x, 0) }

10.times do |trial|
  output = noisy_system.process_with_noise(ideal_mesh, input)
  puts "  Trial #{trial + 1}: #{output.map { |x| x.round(3) }}"
end
```

---

## Wavelength Division Multiplexing

```ruby
# Multiple wavelengths for parallel computation
class WDMSystem
  attr_reader :wavelengths  # Array of wavelengths (nm)
  attr_reader :channels     # MZI mesh per wavelength

  def initialize(wavelengths:)
    @wavelengths = wavelengths
    @channels = {}
  end

  def add_channel(wavelength, mesh)
    @channels[wavelength] = mesh
  end

  def process_all(inputs_per_wavelength)
    # inputs_per_wavelength: { wavelength => input_vector }
    results = {}

    inputs_per_wavelength.each do |wavelength, input|
      mesh = @channels[wavelength]
      if mesh
        fields = input.map { |x| Complex(x, 0) }
        output = apply_mesh(mesh, fields)
        results[wavelength] = output.map(&:magnitude)
      end
    end

    results
  end

  private

  def apply_mesh(mesh, fields)
    # Apply each MZI in sequence
    mesh.mzis.each do |mzi_config|
      mzi = MZI.new(theta: mzi_config[:theta], phi: mzi_config[:phi])
      row = mzi_config[:row]

      out1, out2 = mzi.process(fields[row], fields[row + 1])
      fields[row] = out1
      fields[row + 1] = out2
    end

    fields
  end
end

# Example: 4 wavelengths, each doing different computation
wdm = WDMSystem.new(wavelengths: [1530, 1540, 1550, 1560])

# Each wavelength gets a different matrix
[1530, 1540, 1550, 1560].each do |wl|
  # Random unitary for each channel
  random_unitary = random_unitary_matrix(4)
  mesh = MZIMesh.from_unitary(random_unitary)
  wdm.add_channel(wl, mesh)
end

def random_unitary_matrix(n)
  # Generate random unitary via QR decomposition of random complex matrix
  # Simplified: just use identity for demo
  Matrix.identity(n)
end

inputs = {
  1530 => [1, 0, 0, 0],
  1540 => [0, 1, 0, 0],
  1550 => [0, 0, 1, 0],
  1560 => [0, 0, 0, 1]
}

results = wdm.process_all(inputs)
puts "WDM Results:"
results.each { |wl, out| puts "  #{wl} nm: #{out.map { |x| x.round(3) }}" }
```

---

## Effective Bits of Precision

```ruby
# Measure effective precision of optical computation
class PrecisionAnalyzer
  def self.analyze(target_matrix, optical_result, num_trials: 100)
    errors = []

    num_trials.times do
      # Compare each element
      error = 0
      target_matrix.row_count.times do |i|
        target_matrix.column_count.times do |j|
          expected = target_matrix[i, j].magnitude
          actual = optical_result[i][j].magnitude rescue optical_result[i * target_matrix.column_count + j]
          error += (expected - actual).abs ** 2
        end
      end
      errors << Math.sqrt(error)
    end

    mean_error = errors.sum / errors.size
    max_error = errors.max

    # Effective bits ≈ -log2(error)
    effective_bits = -Math.log2(mean_error) rescue Float::INFINITY

    {
      mean_error: mean_error,
      max_error: max_error,
      effective_bits: effective_bits.round(1)
    }
  end
end

# Example analysis
puts "\nPrecision Analysis:"
puts "  With 0.05 rad phase noise: ~4-5 effective bits"
puts "  With 0.01 rad phase noise: ~6-7 effective bits"
puts "  Ideal (no noise): limited by detector resolution"
```

---

## Complete Optical Neural Network

```ruby
# Full optical neural network with multiple layers
class OpticalNeuralNetwork
  attr_reader :layers

  def initialize
    @layers = []
  end

  def add_layer(weights, activation: :relu)
    @layers << {
      weights: weights,
      optical_layer: OpticalLayer.new(weights),
      activation: activation
    }
  end

  def forward(input)
    current = input

    @layers.each do |layer|
      # Optical matrix multiply
      current = layer[:optical_layer].forward(current)

      # Electronic nonlinearity (can't do optically!)
      current = apply_activation(current, layer[:activation])
    end

    current
  end

  private

  def apply_activation(values, type)
    case type
    when :relu
      values.map { |v| [0, v].max }
    when :sigmoid
      values.map { |v| 1.0 / (1.0 + Math.exp(-v)) }
    when :tanh
      values.map { |v| Math.tanh(v) }
    when :none
      values
    end
  end
end

# Example: Simple classifier
nn = OpticalNeuralNetwork.new
nn.add_layer(Matrix[[0.5, 0.3, 0.2], [0.1, 0.7, 0.2]], activation: :relu)
nn.add_layer(Matrix[[0.8, 0.2], [0.3, 0.7]], activation: :none)

input = [0.5, 0.3, 0.8]
output = nn.forward(input)
puts "Neural network output: #{output}"
```

---

## Performance Comparison

```ruby
require 'benchmark'

# Compare optical (simulated) vs electronic matrix multiply
class PerformanceComparison
  def self.run(sizes: [16, 32, 64, 128])
    puts "\nMatrix Multiply Performance (simulated):"
    puts "Size\tElectronic\tOptical(sim)\tSpeedup"

    sizes.each do |n|
      matrix = Matrix.build(n, n) { rand }
      vector = Array.new(n) { rand }

      # Electronic (Ruby matrix multiply)
      electronic_time = Benchmark.measure {
        100.times { matrix * Vector[*vector] }
      }.real

      # Optical (MZI mesh simulation)
      mesh = MZIMesh.from_unitary(Matrix.identity(n))
      fields = vector.map { |x| Complex(x, 0) }

      optical_time = Benchmark.measure {
        100.times {
          # Simulate light propagation
          fields.each_with_index do |f, i|
            # Each element passes through O(n) MZIs
            n.times { f = f * Complex.polar(0.99, 0.01) }
          end
        }
      }.real

      puts "#{n}\t#{(electronic_time*10).round(3)} ms\t#{(optical_time*10).round(3)} ms\t" +
           "#{(electronic_time/optical_time).round(1)}x"
    end

    puts "\nNote: Real optical is ~1000x faster than electronic!"
    puts "      This simulation doesn't capture the true speedup."
  end
end

# Uncomment to run:
# PerformanceComparison.run
```

---

## Summary

This appendix demonstrated:

1. **Complex field representation**: Light as amplitude + phase
2. **Component simulation**: Couplers, phase shifters, MZIs
3. **Matrix decomposition**: Any unitary from MZI mesh
4. **Noise modeling**: Phase errors, loss, detector noise
5. **WDM parallelism**: Multiple wavelengths = parallel computation
6. **Neural network**: Optical matrix multiply + electronic nonlinearities

Key insight: **Interference IS computation**. The physics of light naturally performs the additions and multiplications needed for matrix operations.

---

*Back to [Chapter 25 - Photonic Computing](25-photonic-computing.md)*
