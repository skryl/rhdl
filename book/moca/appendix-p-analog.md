# Appendix P: Analog Computing Simulation

*Ruby simulation of continuous-time analog circuits*

---

## Overview

This appendix provides Ruby simulations of analog computing concepts:

1. **Op-amp circuits** - Inverter, summer, integrator, differentiator
2. **ODE solvers** - Euler, Runge-Kutta for analog simulation
3. **Classic systems** - Mass-spring-damper, Lorenz attractor
4. **Analog neural network** - Resistor crossbar array
5. **Noise modeling** - Thermal noise, precision limits

Unlike digital RHDL, we simulate continuous-time physics using numerical integration.

---

## Basic Analog Components

### Voltage Source

```ruby
# Analog signal sources
class VoltageSource
  def constant(value)
    ->(_t) { value }
  end

  def sine(amplitude:, frequency:, phase: 0)
    omega = 2 * Math::PI * frequency
    ->(t) { amplitude * Math.sin(omega * t + phase) }
  end

  def step(low:, high:, switch_time:)
    ->(t) { t < switch_time ? low : high }
  end

  def ramp(slope:, start_time: 0)
    ->(t) { t < start_time ? 0 : slope * (t - start_time) }
  end

  def square(amplitude:, frequency:)
    period = 1.0 / frequency
    ->(t) { (t % period) < (period / 2) ? amplitude : -amplitude }
  end

  def pulse(amplitude:, duration:, start_time:)
    ->(t) { (t >= start_time && t < start_time + duration) ? amplitude : 0 }
  end
end

# Example usage
source = VoltageSource.new
sine_wave = source.sine(amplitude: 5.0, frequency: 1000)
puts sine_wave.call(0.00025)  # At t=0.25ms
```

---

## Op-Amp Circuits

### Ideal Op-Amp Model

```ruby
# Ideal operational amplifier
class IdealOpAmp
  attr_accessor :v_plus, :v_minus

  def initialize
    @v_plus = 0.0
    @v_minus = 0.0
  end

  # In ideal op-amp with negative feedback:
  # Virtual short: V+ ≈ V-
  # Infinite gain means output adjusts to make this true
end
```

### Inverting Amplifier

```ruby
# Vout = -(Rf/R1) × Vin
class InvertingAmplifier
  attr_reader :gain

  def initialize(r1:, rf:)
    @r1 = r1
    @rf = rf
    @gain = -@rf.to_f / @r1
  end

  def output(vin)
    @gain * vin
  end

  def transfer_function
    "Vout = #{@gain} × Vin"
  end
end

# Example: Amplifier with gain of -10
amp = InvertingAmplifier.new(r1: 1000, rf: 10000)
puts amp.output(0.5)  # => -5.0
puts amp.transfer_function
```

### Summing Amplifier

```ruby
# Vout = -Rf × (V1/R1 + V2/R2 + V3/R3 + ...)
class SummingAmplifier
  def initialize(rf:, input_resistors:)
    @rf = rf.to_f
    @input_resistors = input_resistors.map(&:to_f)
  end

  def output(*voltages)
    raise "Wrong number of inputs" if voltages.length != @input_resistors.length

    sum = 0.0
    voltages.each_with_index do |v, i|
      sum += v / @input_resistors[i]
    end

    -@rf * sum
  end

  def weights
    @input_resistors.map { |r| -@rf / r }
  end
end

# Example: Equal-weight 3-input summer
summer = SummingAmplifier.new(rf: 10000, input_resistors: [10000, 10000, 10000])
puts summer.output(1.0, 2.0, 3.0)  # => -6.0 (inverted sum)
puts "Weights: #{summer.weights}"
```

### Integrator

```ruby
# Vout = -(1/RC) × ∫Vin dt
class Integrator
  attr_reader :state  # Current output voltage

  def initialize(r:, c:, initial: 0.0)
    @r = r.to_f
    @c = c.to_f
    @tau = @r * @c  # Time constant
    @state = initial
  end

  def step(vin, dt)
    # Euler integration
    @state += -vin / @tau * dt
    @state
  end

  def reset(value = 0.0)
    @state = value
  end

  def time_constant
    @tau
  end
end

# Example: Integrate a constant voltage
int = Integrator.new(r: 10000, c: 1e-6)  # RC = 10ms
100.times do |i|
  t = i * 0.0001  # 0.1ms steps
  v = int.step(1.0, 0.0001)  # Integrate 1V
  puts "t=#{(t*1000).round(2)}ms: Vout=#{v.round(4)}V"
end
```

### Differentiator

```ruby
# Vout = -RC × dVin/dt
class Differentiator
  def initialize(r:, c:)
    @r = r.to_f
    @c = c.to_f
    @tau = @r * @c
    @prev_vin = nil
  end

  def step(vin, dt)
    if @prev_vin.nil?
      @prev_vin = vin
      return 0.0
    end

    derivative = (vin - @prev_vin) / dt
    @prev_vin = vin

    -@tau * derivative
  end

  def reset
    @prev_vin = nil
  end
end

# Example: Differentiate a ramp
diff = Differentiator.new(r: 10000, c: 1e-6)
20.times do |i|
  t = i * 0.001
  vin = t * 100  # Ramp: 100 V/s
  vout = diff.step(vin, 0.001)
  puts "t=#{(t*1000).round(1)}ms: Vin=#{vin.round(2)}V, Vout=#{vout.round(4)}V"
end
```

### Multiplier

```ruby
# Vout = (Vx × Vy) / Vref
class AnalogMultiplier
  def initialize(vref: 10.0)
    @vref = vref.to_f
  end

  def output(vx, vy)
    (vx * vy) / @vref
  end
end

mult = AnalogMultiplier.new(vref: 10.0)
puts mult.output(3.0, 4.0)  # => 1.2 (3×4/10)
```

---

## Numerical Integration Methods

### Euler Method (Simple but inaccurate)

```ruby
class EulerSolver
  def initialize(&derivative)
    @derivative = derivative
  end

  def step(state, t, dt)
    dstate = @derivative.call(state, t)

    if state.is_a?(Array)
      state.zip(dstate).map { |s, ds| s + ds * dt }
    else
      state + dstate * dt
    end
  end

  def solve(initial, t_start, t_end, dt)
    t = t_start
    state = initial
    trajectory = [[t, state.dup]]

    while t < t_end
      state = step(state, t, dt)
      t += dt
      trajectory << [t, state.dup]
    end

    trajectory
  end
end
```

### Runge-Kutta 4th Order (More accurate)

```ruby
class RK4Solver
  def initialize(&derivative)
    @derivative = derivative
  end

  def step(state, t, dt)
    if state.is_a?(Array)
      step_vector(state, t, dt)
    else
      step_scalar(state, t, dt)
    end
  end

  private

  def step_scalar(y, t, dt)
    k1 = @derivative.call(y, t)
    k2 = @derivative.call(y + k1 * dt / 2, t + dt / 2)
    k3 = @derivative.call(y + k2 * dt / 2, t + dt / 2)
    k4 = @derivative.call(y + k3 * dt, t + dt)

    y + (k1 + 2 * k2 + 2 * k3 + k4) * dt / 6
  end

  def step_vector(y, t, dt)
    k1 = @derivative.call(y, t)
    k2 = @derivative.call(vadd(y, vscale(k1, dt / 2)), t + dt / 2)
    k3 = @derivative.call(vadd(y, vscale(k2, dt / 2)), t + dt / 2)
    k4 = @derivative.call(vadd(y, vscale(k3, dt)), t + dt)

    # y + (k1 + 2*k2 + 2*k3 + k4) * dt/6
    vadd(y, vscale(vadd(vadd(k1, vscale(k2, 2)), vadd(vscale(k3, 2), k4)), dt / 6))
  end

  def vadd(a, b)
    a.zip(b).map { |x, y| x + y }
  end

  def vscale(v, s)
    v.map { |x| x * s }
  end
end
```

---

## Classic Analog Computer Problems

### RC Circuit (First Order)

```ruby
# dV/dt = -(1/RC) × V + Vin/RC
class RCCircuit
  def initialize(r:, c:, vin: 0.0)
    @r = r
    @c = c
    @tau = r * c
    @vin = vin  # Input voltage (can be changed)
    @v = 0.0    # Capacitor voltage
  end

  attr_accessor :vin, :v

  def derivative
    -@v / @tau + @vin / @tau
  end

  def step(dt)
    @v += derivative * dt
  end

  def simulate(duration:, dt:, vin_func: nil)
    results = []
    t = 0.0

    while t <= duration
      @vin = vin_func ? vin_func.call(t) : @vin
      results << { t: t, vin: @vin, v: @v }
      step(dt)
      t += dt
    end

    results
  end
end

# Example: Step response
rc = RCCircuit.new(r: 1000, c: 1e-6)  # τ = 1ms
step_input = ->(t) { t >= 0 ? 5.0 : 0.0 }
results = rc.simulate(duration: 0.005, dt: 0.00001, vin_func: step_input)

puts "RC Circuit Step Response:"
results.each_slice(50) do |batch|
  r = batch.first
  puts "t=#{(r[:t]*1000).round(2)}ms: Vout=#{r[:v].round(4)}V"
end
```

### Mass-Spring-Damper (Second Order)

```ruby
# m·x'' + c·x' + k·x = F(t)
# State: [x, v] where v = dx/dt
class MassSpringDamper
  def initialize(mass:, damping:, spring:)
    @m = mass
    @c = damping
    @k = spring
  end

  def derivative(state, t, force: 0)
    x, v = state
    # dx/dt = v
    # dv/dt = (F - c·v - k·x) / m
    [v, (force - @c * v - @k * x) / @m]
  end

  def simulate(x0:, v0:, duration:, dt:, force_func: ->(_t) { 0 })
    solver = RK4Solver.new do |state, t|
      derivative(state, t, force: force_func.call(t))
    end

    t = 0.0
    state = [x0, v0]
    results = [{ t: t, x: x0, v: v0 }]

    while t < duration
      state = solver.step(state, t, dt)
      t += dt
      results << { t: t, x: state[0], v: state[1] }
    end

    results
  end

  def natural_frequency
    Math.sqrt(@k / @m)
  end

  def damping_ratio
    @c / (2 * Math.sqrt(@k * @m))
  end
end

# Example: Underdamped oscillation
msd = MassSpringDamper.new(mass: 1.0, damping: 0.5, spring: 10.0)
puts "Natural frequency: #{msd.natural_frequency.round(2)} rad/s"
puts "Damping ratio: #{msd.damping_ratio.round(3)}"

results = msd.simulate(x0: 1.0, v0: 0.0, duration: 5.0, dt: 0.01)

puts "\nMass-Spring-Damper Response:"
results.each_slice(50) do |batch|
  r = batch.first
  puts "t=#{r[:t].round(2)}s: x=#{r[:x].round(4)}, v=#{r[:v].round(4)}"
end
```

### Lorenz Attractor (Chaos)

```ruby
# dx/dt = σ(y - x)
# dy/dt = x(ρ - z) - y
# dz/dt = xy - βz
class LorenzSystem
  def initialize(sigma: 10.0, rho: 28.0, beta: 8.0 / 3.0)
    @sigma = sigma
    @rho = rho
    @beta = beta
  end

  def derivative(state, _t)
    x, y, z = state
    [
      @sigma * (y - x),
      x * (@rho - z) - y,
      x * y - @beta * z
    ]
  end

  def simulate(x0:, y0:, z0:, duration:, dt:)
    solver = RK4Solver.new { |state, t| derivative(state, t) }

    t = 0.0
    state = [x0, y0, z0]
    results = [{ t: t, x: x0, y: y0, z: z0 }]

    while t < duration
      state = solver.step(state, t, dt)
      t += dt
      results << { t: t, x: state[0], y: state[1], z: state[2] }
    end

    results
  end
end

# Example: Lorenz attractor
lorenz = LorenzSystem.new
results = lorenz.simulate(x0: 1.0, y0: 1.0, z0: 1.0, duration: 50.0, dt: 0.01)

puts "Lorenz Attractor (sample points):"
results.each_slice(500) do |batch|
  r = batch.first
  puts "t=#{r[:t].round(1)}: (#{r[:x].round(2)}, #{r[:y].round(2)}, #{r[:z].round(2)})"
end
```

### Van der Pol Oscillator

```ruby
# x'' - μ(1 - x²)x' + x = 0
class VanDerPolOscillator
  def initialize(mu: 1.0)
    @mu = mu
  end

  def derivative(state, _t)
    x, v = state
    [
      v,
      @mu * (1 - x * x) * v - x
    ]
  end

  def simulate(x0:, v0:, duration:, dt:)
    solver = RK4Solver.new { |state, t| derivative(state, t) }

    t = 0.0
    state = [x0, v0]
    results = [{ t: t, x: x0, v: v0 }]

    while t < duration
      state = solver.step(state, t, dt)
      t += dt
      results << { t: t, x: state[0], v: state[1] }
    end

    results
  end
end

vdp = VanDerPolOscillator.new(mu: 2.0)
results = vdp.simulate(x0: 0.1, v0: 0.0, duration: 30.0, dt: 0.01)

puts "\nVan der Pol Oscillator:"
results.each_slice(300) do |batch|
  r = batch.first
  puts "t=#{r[:t].round(1)}: x=#{r[:x].round(4)}"
end
```

---

## Analog Neural Network

### Resistor Crossbar Array

```ruby
# Analog matrix-vector multiplication using resistor array
class ResistorCrossbar
  attr_reader :rows, :cols

  def initialize(rows:, cols:)
    @rows = rows
    @cols = cols
    # Conductances (1/R) - easier to work with for currents
    @conductances = Array.new(rows) { Array.new(cols) { 0.0 } }
  end

  # Set weight at position (converts to conductance)
  def set_weight(row, col, weight, g_max: 1e-3)
    # Map weight [0, 1] to conductance [0, g_max]
    @conductances[row][col] = weight.clamp(0, 1) * g_max
  end

  # Load a weight matrix
  def load_weights(matrix, g_max: 1e-3)
    matrix.each_with_index do |row, i|
      row.each_with_index do |w, j|
        set_weight(i, j, w, g_max: g_max)
      end
    end
  end

  # Compute output currents given input voltages
  # I_out[row] = Σ_col G[row][col] × V_in[col]
  def compute(input_voltages)
    raise "Input size mismatch" if input_voltages.length != @cols

    @rows.times.map do |row|
      current = 0.0
      @cols.times do |col|
        current += @conductances[row][col] * input_voltages[col]
      end
      current
    end
  end

  # Convert currents to voltages through transimpedance amp
  def compute_voltages(input_voltages, r_tia: 1000)
    currents = compute(input_voltages)
    currents.map { |i| -i * r_tia }  # Inverting TIA
  end
end

# Example: 3x4 weight matrix
crossbar = ResistorCrossbar.new(rows: 3, cols: 4)

weights = [
  [0.5, 0.3, 0.1, 0.2],
  [0.1, 0.8, 0.2, 0.1],
  [0.3, 0.2, 0.6, 0.4]
]
crossbar.load_weights(weights)

input = [1.0, 0.5, 0.8, 0.3]  # Input voltages
output = crossbar.compute_voltages(input)

puts "Resistor Crossbar Matrix-Vector Multiply:"
puts "Input: #{input}"
puts "Output: #{output.map { |v| v.round(6) }}"

# Verify against digital computation
digital = weights.map do |row|
  -row.zip(input).map { |w, v| w * v * 1e-3 * 1000 }.sum
end
puts "Digital verification: #{digital.map { |v| v.round(6) }}"
```

### Analog Neuron

```ruby
# Single analog neuron with activation
class AnalogNeuron
  def initialize(num_inputs:, activation: :relu)
    @weights = Array.new(num_inputs) { 0.0 }
    @bias = 0.0
    @activation = activation
  end

  attr_accessor :weights, :bias

  def forward(inputs)
    # Weighted sum (analog: resistor network)
    sum = inputs.zip(@weights).map { |x, w| x * w }.sum + @bias

    # Activation (analog: diode/transistor circuit)
    apply_activation(sum)
  end

  private

  def apply_activation(x)
    case @activation
    when :relu
      x > 0 ? x : 0
    when :sigmoid
      1.0 / (1.0 + Math.exp(-x))
    when :tanh
      Math.tanh(x)
    when :linear
      x
    end
  end
end

# Example
neuron = AnalogNeuron.new(num_inputs: 3, activation: :relu)
neuron.weights = [0.5, -0.3, 0.8]
neuron.bias = -0.1

inputs = [1.0, 0.5, 0.7]
output = neuron.forward(inputs)
puts "Neuron output: #{output.round(4)}"
```

### Simple Analog Neural Network

```ruby
class AnalogNeuralNetwork
  def initialize(layer_sizes)
    @layers = []
    (layer_sizes.length - 1).times do |i|
      @layers << {
        crossbar: ResistorCrossbar.new(
          rows: layer_sizes[i + 1],
          cols: layer_sizes[i]
        ),
        biases: Array.new(layer_sizes[i + 1]) { 0.0 }
      }
    end
  end

  def set_weights(layer_idx, weights)
    @layers[layer_idx][:crossbar].load_weights(weights)
  end

  def set_biases(layer_idx, biases)
    @layers[layer_idx][:biases] = biases
  end

  def forward(input)
    current = input

    @layers.each do |layer|
      # Matrix multiply (analog crossbar)
      currents = layer[:crossbar].compute_voltages(current)

      # Add bias and apply activation
      current = currents.zip(layer[:biases]).map do |v, b|
        relu(v + b)
      end
    end

    current
  end

  private

  def relu(x)
    x > 0 ? x : 0
  end
end

# Example: Simple 2-layer network
nn = AnalogNeuralNetwork.new([4, 3, 2])

nn.set_weights(0, [
  [0.5, 0.3, 0.1, 0.2],
  [0.1, 0.8, 0.2, 0.1],
  [0.3, 0.2, 0.6, 0.4]
])
nn.set_biases(0, [0.1, -0.1, 0.05])

nn.set_weights(1, [
  [0.4, 0.5, 0.3],
  [0.2, 0.3, 0.7]
])
nn.set_biases(1, [0.0, 0.0])

input = [1.0, 0.5, 0.8, 0.3]
output = nn.forward(input)
puts "Neural network output: #{output.map { |v| v.round(6) }}"
```

---

## Noise Modeling

### Thermal Noise

```ruby
# Johnson-Nyquist noise in resistors
class ThermalNoise
  BOLTZMANN = 1.38e-23  # J/K

  def initialize(temperature: 300)  # Kelvin
    @temp = temperature
  end

  # RMS noise voltage for resistor with bandwidth
  def rms_voltage(resistance:, bandwidth:)
    Math.sqrt(4 * BOLTZMANN * @temp * resistance * bandwidth)
  end

  # Generate noise sample
  def sample(resistance:, bandwidth:)
    rms = rms_voltage(resistance: resistance, bandwidth: bandwidth)
    gaussian_random * rms
  end

  private

  def gaussian_random
    # Box-Muller transform
    u1 = rand
    u2 = rand
    Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math::PI * u2)
  end
end

noise = ThermalNoise.new(temperature: 300)
rms = noise.rms_voltage(resistance: 10_000, bandwidth: 1_000_000)
puts "Thermal noise RMS (10kΩ, 1MHz): #{(rms * 1e6).round(2)} µV"

# Generate samples
puts "Noise samples:"
10.times do
  sample = noise.sample(resistance: 10_000, bandwidth: 1_000_000)
  puts "  #{(sample * 1e6).round(2)} µV"
end
```

### Noisy Op-Amp

```ruby
class NoisyOpAmp
  def initialize(
    gain_bandwidth: 1e6,    # Hz
    input_noise: 10e-9,     # V/√Hz
    offset_voltage: 1e-3    # V
  )
    @gbw = gain_bandwidth
    @en = input_noise
    @vos = offset_voltage
  end

  def amplify(vin, gain:, bandwidth:)
    # Add input-referred noise
    noise_rms = @en * Math.sqrt(bandwidth)
    noise = gaussian_random * noise_rms

    # Add offset
    effective_input = vin + @vos + noise

    # Apply gain (with GBW limit)
    effective_gain = [gain, @gbw / bandwidth].min
    effective_input * effective_gain
  end

  private

  def gaussian_random
    u1 = rand
    u2 = rand
    Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math::PI * u2)
  end
end

op_amp = NoisyOpAmp.new
puts "\nNoisy amplifier outputs (10× gain, 10kHz BW):"
10.times do
  output = op_amp.amplify(0.1, gain: 10, bandwidth: 10_000)
  puts "  #{output.round(6)} V (ideal: 1.0 V)"
end
```

### Effective Bits Calculation

```ruby
class PrecisionAnalyzer
  def effective_bits(signal_range:, noise_rms:)
    snr = signal_range / (noise_rms * 6)  # 6σ for 99.7% coverage
    Math.log2(snr)
  end

  def snr_db(signal_power:, noise_power:)
    10 * Math.log10(signal_power / noise_power)
  end
end

analyzer = PrecisionAnalyzer.new

# Example: ±10V range, 1mV RMS noise
bits = analyzer.effective_bits(signal_range: 20.0, noise_rms: 0.001)
puts "Effective bits (±10V, 1mV noise): #{bits.round(1)}"

# Example: 60 dB SNR
bits_60db = 60.0 / 6.02
puts "Effective bits at 60 dB SNR: #{bits_60db.round(1)}"
```

---

## Complete Analog Computer Simulation

```ruby
# Simulates a full analog computer solving a 2nd order ODE
class AnalogComputer
  def initialize
    @integrators = {}
    @summers = {}
    @gains = {}
    @connections = []
  end

  def add_integrator(name, initial: 0.0)
    @integrators[name] = Integrator.new(r: 10_000, c: 1e-6, initial: initial)
  end

  def add_summer(name, input_resistors:, rf:)
    @summers[name] = SummingAmplifier.new(rf: rf, input_resistors: input_resistors)
  end

  def add_gain(name, value)
    @gains[name] = value
  end

  def connect(from, to)
    @connections << [from, to]
  end

  # Solve: a·x'' + b·x' + c·x = f(t)
  # Setup: Two integrators, feedback summers
  def solve_second_order(a:, b:, c:, f_func:, x0:, v0:, duration:, dt:)
    # State
    x = x0
    v = v0  # dx/dt

    results = []
    t = 0.0

    while t <= duration
      f = f_func.call(t)

      # Compute x'' = (f - b·x' - c·x) / a
      x_ddot = (f - b * v - c * x) / a

      # Integrate (Euler for simplicity)
      v += x_ddot * dt
      x += v * dt

      results << { t: t, x: x, v: v, x_ddot: x_ddot }
      t += dt
    end

    results
  end
end

# Example: Damped oscillator
# x'' + 0.5·x' + 4·x = 0
computer = AnalogComputer.new
results = computer.solve_second_order(
  a: 1.0, b: 0.5, c: 4.0,
  f_func: ->(_t) { 0 },
  x0: 1.0, v0: 0.0,
  duration: 10.0, dt: 0.01
)

puts "\nAnalog Computer: Damped Oscillator"
results.each_slice(100) do |batch|
  r = batch.first
  puts "t=#{r[:t].round(1)}: x=#{r[:x].round(4)}"
end
```

---

## Comparison: Analog vs Digital

```ruby
class PerformanceComparison
  def self.run
    puts "=" * 60
    puts "Analog vs Digital Comparison"
    puts "=" * 60

    # Matrix multiply performance
    n = 64

    # "Digital" (Ruby native)
    require 'benchmark'

    matrix = Array.new(n) { Array.new(n) { rand } }
    vector = Array.new(n) { rand }

    digital_time = Benchmark.measure {
      1000.times do
        result = matrix.map do |row|
          row.zip(vector).map { |a, b| a * b }.sum
        end
      end
    }.real

    # "Analog" simulation (crossbar)
    crossbar = ResistorCrossbar.new(rows: n, cols: n)
    matrix.each_with_index do |row, i|
      row.each_with_index do |w, j|
        crossbar.set_weight(i, j, w)
      end
    end

    analog_time = Benchmark.measure {
      1000.times do
        crossbar.compute(vector)
      end
    }.real

    puts "\n#{n}×#{n} Matrix-Vector Multiply (1000 iterations):"
    puts "  Digital (Ruby): #{(digital_time * 1000).round(2)} ms"
    puts "  Analog (sim):   #{(analog_time * 1000).round(2)} ms"
    puts "\n  Note: Real analog would be ~1000× faster than digital!"

    puts "\nPrecision comparison:"
    puts "  Digital: 64-bit float = ~15 decimal digits"
    puts "  Analog:  ~0.1% = ~3 decimal digits (typical)"
    puts "           ~0.01% = ~4 decimal digits (precision analog)"

    puts "\nEnergy comparison (theoretical):"
    puts "  Digital MAC: ~1 pJ"
    puts "  Analog MAC:  ~1 fJ (1000× more efficient)"
  end
end

PerformanceComparison.run
```

---

## Summary

This appendix demonstrated:

1. **Op-amp circuits**: Inverter, summer, integrator, differentiator
2. **ODE solvers**: Euler and RK4 for continuous-time simulation
3. **Classic problems**: RC circuit, mass-spring-damper, Lorenz attractor
4. **Analog neural networks**: Resistor crossbar matrix multiplication
5. **Noise modeling**: Thermal noise, effective bits

Key insight: **Analog computers solve differential equations naturally** because the physics of capacitors and op-amps IS integration.

---

*Back to [Chapter 16 - Analog Computing](16-analog-computing.md)*
