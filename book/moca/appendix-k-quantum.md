# Appendix K: Quantum Circuits

*Companion appendix to [Chapter 11: Quantum Computing](11-quantum-computing.md)*

## Overview

This appendix provides quantum circuit implementations, from basic gates to complete algorithms, with classical simulation code.

## Quantum Gate Matrices

### Single-Qubit Gates

```ruby
# Identity
I = Matrix[[1, 0],
           [0, 1]]

# Pauli-X (NOT)
X = Matrix[[0, 1],
           [1, 0]]

# Pauli-Y
Y = Matrix[[0, -1i],
           [1i, 0]]

# Pauli-Z
Z = Matrix[[1, 0],
           [0, -1]]

# Hadamard
H = Matrix[[1, 1],
           [1, -1]] / Math.sqrt(2)

# Phase (S)
S = Matrix[[1, 0],
           [0, 1i]]

# T gate (π/8)
T = Matrix[[1, 0],
           [0, Math::E ** (1i * Math::PI / 4)]]

# Rotation gates
def Rx(theta)
  c = Math.cos(theta / 2)
  s = Math.sin(theta / 2)
  Matrix[[c, -1i * s],
         [-1i * s, c]]
end

def Ry(theta)
  c = Math.cos(theta / 2)
  s = Math.sin(theta / 2)
  Matrix[[c, -s],
         [s, c]]
end

def Rz(theta)
  Matrix[[Math::E ** (-1i * theta / 2), 0],
         [0, Math::E ** (1i * theta / 2)]]
end
```

### Two-Qubit Gates

```ruby
# CNOT (Controlled-NOT)
CNOT = Matrix[[1, 0, 0, 0],
              [0, 1, 0, 0],
              [0, 0, 0, 1],
              [0, 0, 1, 0]]

# CZ (Controlled-Z)
CZ = Matrix[[1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [0, 0, 0, -1]]

# SWAP
SWAP = Matrix[[1, 0, 0, 0],
              [0, 0, 1, 0],
              [0, 1, 0, 0],
              [0, 0, 0, 1]]

# iSWAP
ISWAP = Matrix[[1, 0, 0, 0],
               [0, 0, 1i, 0],
               [0, 1i, 0, 0],
               [0, 0, 0, 1]]
```

### Three-Qubit Gates

```ruby
# Toffoli (CCNOT)
TOFFOLI = Matrix.identity(8)
TOFFOLI[6, 6] = 0
TOFFOLI[6, 7] = 1
TOFFOLI[7, 6] = 1
TOFFOLI[7, 7] = 0

# Fredkin (CSWAP)
FREDKIN = Matrix.identity(8)
FREDKIN[5, 5] = 0
FREDKIN[5, 6] = 1
FREDKIN[6, 5] = 1
FREDKIN[6, 6] = 0
```

## Quantum State Simulator

```ruby
class QuantumState
  attr_reader :amplitudes, :num_qubits

  def initialize(num_qubits)
    @num_qubits = num_qubits
    @amplitudes = Array.new(2 ** num_qubits, Complex(0, 0))
    @amplitudes[0] = Complex(1, 0)  # Start in |00...0⟩
  end

  def apply_gate(gate, *qubits)
    if qubits.length == 1
      apply_single_qubit_gate(gate, qubits[0])
    elsif qubits.length == 2
      apply_two_qubit_gate(gate, qubits[0], qubits[1])
    else
      raise "Gates on #{qubits.length} qubits not implemented"
    end
  end

  def apply_single_qubit_gate(gate, qubit)
    new_amplitudes = Array.new(2 ** @num_qubits, Complex(0, 0))

    (2 ** @num_qubits).times do |i|
      bit = (i >> qubit) & 1
      i0 = i & ~(1 << qubit)  # Index with qubit = 0
      i1 = i | (1 << qubit)   # Index with qubit = 1

      if bit == 0
        new_amplitudes[i] += gate[0, 0] * @amplitudes[i0] + gate[0, 1] * @amplitudes[i1]
      else
        new_amplitudes[i] += gate[1, 0] * @amplitudes[i0] + gate[1, 1] * @amplitudes[i1]
      end
    end

    @amplitudes = new_amplitudes
  end

  def measure
    # Calculate probabilities
    probs = @amplitudes.map { |a| (a * a.conj).real }

    # Random selection based on probabilities
    r = rand
    cumulative = 0
    probs.each_with_index do |p, i|
      cumulative += p
      if r < cumulative
        # Collapse state
        @amplitudes = Array.new(2 ** @num_qubits, Complex(0, 0))
        @amplitudes[i] = Complex(1, 0)
        return i
      end
    end

    probs.length - 1
  end

  def measure_qubit(qubit)
    prob_0 = 0
    (2 ** @num_qubits).times do |i|
      if ((i >> qubit) & 1) == 0
        prob_0 += (@amplitudes[i] * @amplitudes[i].conj).real
      end
    end

    result = rand < prob_0 ? 0 : 1

    # Collapse and renormalize
    norm = 0
    (2 ** @num_qubits).times do |i|
      if ((i >> qubit) & 1) != result
        @amplitudes[i] = Complex(0, 0)
      else
        norm += (@amplitudes[i] * @amplitudes[i].conj).real
      end
    end

    norm = Math.sqrt(norm)
    @amplitudes.map! { |a| a / norm }

    result
  end

  def probabilities
    @amplitudes.map { |a| (a * a.conj).real }
  end

  def to_s
    result = []
    @amplitudes.each_with_index do |amp, i|
      if amp.abs > 1e-10
        bits = i.to_s(2).rjust(@num_qubits, '0')
        result << "#{amp.round(4)}|#{bits}⟩"
      end
    end
    result.join(" + ")
  end
end
```

## Bell State Creation

```ruby
def create_bell_state
  q = QuantumState.new(2)

  # Apply Hadamard to qubit 0
  q.apply_gate(H, 0)

  # Apply CNOT with qubit 0 as control, qubit 1 as target
  q.apply_gate(CNOT, 0, 1)

  q  # Returns |Φ+⟩ = (|00⟩ + |11⟩)/√2
end

# Test
bell = create_bell_state
puts bell.to_s
# Output: (0.707+0i)|00⟩ + (0.707+0i)|11⟩
```

## Quantum Teleportation

```ruby
def quantum_teleportation(state_to_teleport)
  # 3 qubits: q0 = state to teleport, q1 and q2 = entangled pair
  q = QuantumState.new(3)

  # Prepare state to teleport on q0
  # (for simulation, we'll just use |1⟩)
  q.apply_gate(X, 0) if state_to_teleport == 1

  # Create Bell pair between q1 and q2
  q.apply_gate(H, 1)
  q.apply_gate(CNOT, 1, 2)

  # Bell measurement on q0 and q1
  q.apply_gate(CNOT, 0, 1)
  q.apply_gate(H, 0)

  m0 = q.measure_qubit(0)
  m1 = q.measure_qubit(1)

  # Classical correction on q2
  q.apply_gate(X, 2) if m1 == 1
  q.apply_gate(Z, 2) if m0 == 1

  # q2 now has the original state
  { measurements: [m0, m1], final_state: q }
end
```

## Deutsch-Jozsa Algorithm

```ruby
def deutsch_jozsa(oracle, n)
  # n input qubits + 1 output qubit
  q = QuantumState.new(n + 1)

  # Initialize output qubit to |1⟩
  q.apply_gate(X, n)

  # Apply Hadamard to all qubits
  (n + 1).times { |i| q.apply_gate(H, i) }

  # Apply oracle
  oracle.call(q)

  # Apply Hadamard to input qubits
  n.times { |i| q.apply_gate(H, i) }

  # Measure input qubits
  result = n.times.map { |i| q.measure_qubit(i) }

  # If all zeros, function is constant; otherwise balanced
  result.all?(&:zero?) ? :constant : :balanced
end

# Example: Constant oracle (f(x) = 0)
constant_oracle = ->(q) { }  # Do nothing

# Example: Balanced oracle (f(x) = x for single qubit)
balanced_oracle = ->(q) { q.apply_gate(CNOT, 0, 1) }
```

## Grover's Search

```ruby
def grover_search(n, marked_item)
  iterations = (Math::PI / 4 * Math.sqrt(2 ** n)).floor

  q = QuantumState.new(n)

  # Initialize superposition
  n.times { |i| q.apply_gate(H, i) }

  iterations.times do
    # Oracle: flip phase of marked item
    grover_oracle(q, n, marked_item)

    # Diffusion operator
    grover_diffusion(q, n)
  end

  q.measure
end

def grover_oracle(q, n, marked)
  # Flip phase of |marked⟩
  # Implementation depends on marked item
  # For simplicity, directly manipulate amplitudes
  q.amplitudes[marked] *= -1
end

def grover_diffusion(q, n)
  # H⊗n
  n.times { |i| q.apply_gate(H, i) }

  # 2|0⟩⟨0| - I (flip all except |0⟩)
  q.amplitudes.each_with_index do |_, i|
    q.amplitudes[i] *= -1 if i != 0
  end

  # H⊗n
  n.times { |i| q.apply_gate(H, i) }
end
```

## Quantum Fourier Transform

```ruby
def qft(q, n)
  n.times do |j|
    q.apply_gate(H, j)

    (j + 1...n).each do |k|
      # Controlled rotation
      theta = Math::PI / (2 ** (k - j))
      controlled_phase(q, k, j, theta)
    end
  end

  # Swap qubits to reverse order
  (n / 2).times do |i|
    swap_qubits(q, i, n - 1 - i)
  end
end

def controlled_phase(q, control, target, theta)
  # Apply phase rotation to target when control is |1⟩
  (2 ** q.num_qubits).times do |i|
    if ((i >> control) & 1) == 1 && ((i >> target) & 1) == 1
      q.amplitudes[i] *= Math::E ** (1i * theta)
    end
  end
end
```

## Complexity Comparison

| Problem | Classical | Quantum | Speedup |
|---------|-----------|---------|---------|
| Unstructured search | O(N) | O(√N) | Quadratic |
| Factoring | O(exp(n^(1/3))) | O(n³) | Exponential |
| Database query | O(N) | O(√N) | Quadratic |
| Simulation of quantum systems | O(2^n) | O(n) | Exponential |

## Physical Implementations

### Superconducting Qubits

```
Pros:
- Fast gates (~10-100 ns)
- Scalable fabrication
- Good connectivity

Cons:
- Requires dilution refrigerator (~10 mK)
- Short coherence times (~100 μs)
- Error rates ~0.1-1%
```

### Trapped Ions

```
Pros:
- Long coherence times (~minutes)
- High-fidelity gates (~99.9%)
- All-to-all connectivity

Cons:
- Slower gates (~10-100 μs)
- Scaling challenges
- Complex apparatus
```

### Photonic

```
Pros:
- Room temperature
- Natural for communication
- Low decoherence

Cons:
- Probabilistic gates
- Difficult to store qubits
- Loss in optical elements
```

## Further Resources

- Nielsen & Chuang, *Quantum Computation and Quantum Information*
- IBM Qiskit documentation and tutorials
- Quirk quantum circuit simulator (online)

> Return to [Chapter 11](11-quantum-computing.md) for conceptual introduction.
