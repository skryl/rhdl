# Appendix H: Reversible Gates

*Companion appendix to [Chapter 7: Reversible Computation](07-reversible-computation.md)*

## Overview

This appendix provides complete RHDL implementations of reversible logic gates, derived circuits, and formal analysis of reversible computation.

## Fundamental Reversible Gates

### Toffoli Gate (CCNOT)

The most common reversible gate, universal for classical computation:

```ruby
class ToffoliGate < SimComponent
  input :a
  input :b
  input :c
  output :a_out
  output :b_out
  output :c_out

  behavior do
    a_out <= a
    b_out <= b
    c_out <= c ^ (a & b)  # XOR with AND of controls
  end
end
```

### Fredkin Gate (CSWAP)

Controlled swap—conditionally exchanges two bits:

```ruby
class FredkinGate < SimComponent
  input :c       # Control
  input :a
  input :b
  output :c_out
  output :a_out
  output :b_out

  behavior do
    c_out <= c

    if c == 1
      # Swap a and b
      a_out <= b
      b_out <= a
    else
      # Pass through
      a_out <= a
      b_out <= b
    end
  end
end
```

### CNOT (Controlled NOT)

A simpler 2-input reversible gate:

```ruby
class CNOTGate < SimComponent
  input :control
  input :target
  output :control_out
  output :target_out

  behavior do
    control_out <= control
    target_out <= target ^ control
  end
end
```

## Standard Gates from Reversible Primitives

### Reversible NOT

```ruby
class ReversibleNot < SimComponent
  input :a
  output :result

  # NOT is inherently reversible (1-to-1 mapping)
  behavior do
    result <= ~a
  end
end
```

### Reversible AND (using Toffoli)

```ruby
class ReversibleAnd < SimComponent
  input :a
  input :b
  output :a_out      # Preserved
  output :b_out      # Preserved
  output :result     # a AND b

  instance :toffoli, ToffoliGate

  # Wire constant 0 as third input
  wire :zero

  behavior do
    zero <= 0
  end

  port :a => [:toffoli, :a]
  port :b => [:toffoli, :b]
  port :zero => [:toffoli, :c]
  port [:toffoli, :a_out] => :a_out
  port [:toffoli, :b_out] => :b_out
  port [:toffoli, :c_out] => :result
end
```

### Reversible OR (using Toffoli)

OR = NOT(NOT A AND NOT B), requires 3 Toffoli gates:

```ruby
class ReversibleOr < SimComponent
  input :a
  input :b
  output :a_out
  output :b_out
  output :result

  instance :not_a, ToffoliGate
  instance :not_b, ToffoliGate
  instance :nand, ToffoliGate
  instance :not_result, ToffoliGate

  wire :one, :zero
  wire :na, :nb, :na_and_nb

  behavior do
    one <= 1
    zero <= 0
  end

  # NOT A: Toffoli(1, 1, a) = a XOR 1 = NOT a
  port :one => [:not_a, :a]
  port :one => [:not_a, :b]
  port :a => [:not_a, :c]
  port [:not_a, :c_out] => :na

  # NOT B
  port :one => [:not_b, :a]
  port :one => [:not_b, :b]
  port :b => [:not_b, :c]
  port [:not_b, :c_out] => :nb

  # NOT A AND NOT B
  port :na => [:nand, :a]
  port :nb => [:nand, :b]
  port :zero => [:nand, :c]
  port [:nand, :c_out] => :na_and_nb

  # NOT (NOT A AND NOT B) = A OR B
  port :one => [:not_result, :a]
  port :one => [:not_result, :b]
  port :na_and_nb => [:not_result, :c]
  port [:not_result, :c_out] => :result

  # Preserve inputs
  port :a => :a_out
  port :b => :b_out
end
```

### Reversible XOR

XOR is naturally reversible using CNOT:

```ruby
class ReversibleXor < SimComponent
  input :a
  input :b
  output :a_out
  output :result  # a XOR b

  instance :cnot, CNOTGate

  port :a => [:cnot, :control]
  port :b => [:cnot, :target]
  port [:cnot, :control_out] => :a_out
  port [:cnot, :target_out] => :result
end
```

## Reversible Arithmetic

### Reversible Half Adder

```ruby
class ReversibleHalfAdder < SimComponent
  input :a
  input :b
  output :a_out    # Preserved (garbage)
  output :sum      # a XOR b
  output :carry    # a AND b

  instance :xor_gate, CNOTGate
  instance :and_gate, ToffoliGate

  wire :zero

  behavior do
    zero <= 0
  end

  # Sum = a XOR b
  port :a => [:xor_gate, :control]
  port :b => [:xor_gate, :target]
  port [:xor_gate, :target_out] => :sum

  # Carry = a AND b
  port :a => [:and_gate, :a]
  port :b => [:and_gate, :b]
  port :zero => [:and_gate, :c]
  port [:and_gate, :c_out] => :carry

  port :a => :a_out
end
```

### Reversible Full Adder

```ruby
class ReversibleFullAdder < SimComponent
  input :a
  input :b
  input :cin
  output :a_out       # Preserved (garbage)
  output :b_out       # Preserved (garbage)
  output :sum
  output :cout

  # Uses 4 Toffoli gates
  instance :t1, ToffoliGate
  instance :t2, ToffoliGate
  instance :t3, ToffoliGate
  instance :t4, ToffoliGate

  wire :zero1, :zero2
  wire :w1, :w2, :w3

  behavior do
    zero1 <= 0
    zero2 <= 0
  end

  # T1: Compute a XOR b (using cin as target with 0)
  port :a => [:t1, :a]
  port :b => [:t1, :b]
  port :zero1 => [:t1, :c]
  port [:t1, :c_out] => :w1  # a XOR b

  # T2: Compute (a XOR b) XOR cin = sum
  port :w1 => [:t2, :a]
  port :cin => [:t2, :b]
  port :zero2 => [:t2, :c]
  port [:t2, :c_out] => :sum

  # T3: Compute (a XOR b) AND cin
  port :w1 => [:t3, :a]
  port :cin => [:t3, :b]
  port :zero1 => [:t3, :c]
  port [:t3, :c_out] => :w2

  # T4: Compute a AND b, XOR with previous
  port :a => [:t4, :a]
  port :b => [:t4, :b]
  port :w2 => [:t4, :c]
  port [:t4, :c_out] => :cout

  # Garbage outputs
  port :a => :a_out
  port :b => :b_out
end
```

### Reversible Swap

Three CNOTs implement SWAP without any garbage:

```ruby
class ReversibleSwap < SimComponent
  input :a
  input :b
  output :a_out  # Will contain original b
  output :b_out  # Will contain original a

  # Three CNOTs implement SWAP reversibly
  wire :w1, :w2

  behavior do
    # CNOT 1: a XOR b
    w1 = a ^ b
    # CNOT 2: b XOR (a XOR b) = a
    w2 = b ^ w1  # w2 = a
    # CNOT 3: (a XOR b) XOR a = b
    a_out <= w1 ^ w2
    b_out <= w2
  end
end
```

### Reversible Comparator

```ruby
class ReversibleComparator < SimComponent
  input :a, width: 8
  input :b, width: 8
  output :a_out, width: 8    # Preserved
  output :b_out, width: 8    # Preserved
  output :a_gt_b             # Result: a > b
  output :a_eq_b             # Result: a == b

  behavior do
    # Preserve inputs
    a_out <= a
    b_out <= b

    # Comparison requires auxiliary bits for full reversibility
    # This simplified version demonstrates the interface
    a_gt_b <= (a > b) ? 1 : 0
    a_eq_b <= (a == b) ? 1 : 0
  end
end
```

## Reversible Multiplexer

Using a Fredkin gate:

```ruby
class ReversibleMux2to1 < SimComponent
  input :sel
  input :a
  input :b
  output :sel_out
  output :result
  output :garbage

  instance :fredkin, FredkinGate

  port :sel => [:fredkin, :c]
  port :a => [:fredkin, :a]
  port :b => [:fredkin, :b]

  # Output selection: when sel=0, a passes; when sel=1, b passes
  port [:fredkin, :c_out] => :sel_out
  port [:fredkin, :a_out] => :result
  port [:fredkin, :b_out] => :garbage
end
```

## Bennett's Uncomputation

Template for computing without permanent garbage:

```ruby
class BennettCompute < SimComponent
  input :x, width: 8
  output :x_out, width: 8    # Input preserved
  output :result, width: 8   # Computed result

  # Phase 1: Forward computation (generates garbage)
  # Phase 2: Copy result to output
  # Phase 3: Reverse computation (cleans garbage)

  behavior do
    # Forward: compute f(x)
    temp = x * 2 + 1  # Example function

    # Copy result (reversible with CNOT chain)
    result <= temp

    # Backward: uncompute (in real implementation)
    # This would reverse all operations to clean garbage

    # Input is preserved
    x_out <= x
  end
end
```

## Gate Count Analysis

### Complexity of Reversible Circuits

| Operation | Irreversible Gates | Toffoli Gates | Garbage Bits |
|-----------|-------------------|---------------|--------------|
| NOT | 1 | 1 | 0 |
| AND | 1 | 1 | 2 |
| OR | 1 | 3 | 2 |
| XOR | 1 | 1 (CNOT) | 1 |
| Half Adder | 2 | 2 | 1 |
| Full Adder | 5 | 4 | 2 |
| N-bit Adder | 5N | 4N | 2N |
| Multiplier (N×N) | O(N²) | O(N²) | O(N²) |

### With Bennett's Uncomputation

| Operation | Toffoli Gates | Space (garbage) |
|-----------|---------------|-----------------|
| N-bit Adder | 12N | O(1) |
| Any function | 3× forward | O(log depth) |

## Energy Analysis

### Landauer Limit Calculations

```
At room temperature (T = 300K):

E_landauer = kT × ln(2)
           = (1.38 × 10⁻²³ J/K) × (300K) × 0.693
           = 2.87 × 10⁻²¹ J/bit

For a 1 GHz processor erasing 10⁹ bits/second:
P_landauer = 2.87 × 10⁻²¹ × 10⁹
           = 2.87 × 10⁻¹² W = 2.87 pW

Current CPUs: ~10⁻¹⁶ J/op (10,000× above limit)
```

### Approaching the Limit

```
Year    Process    Energy/op    Ratio to Landauer
──────────────────────────────────────────────────
1990    1 μm       10⁻¹² J     10⁹
2000    180 nm     10⁻¹⁴ J     10⁷
2010    45 nm      10⁻¹⁵ J     10⁶
2020    5 nm       10⁻¹⁶ J     10⁵
2030?   1 nm?      10⁻¹⁸ J?    10³
20??    ???        10⁻²¹ J     1 (limit!)
```

## Quantum Gate Correspondence

| Classical Reversible | Quantum Gate | Matrix |
|---------------------|--------------|--------|
| NOT | X (Pauli-X) | [[0,1],[1,0]] |
| CNOT | CNOT | 4×4 |
| Toffoli | CCNOT | 8×8 |
| Fredkin | CSWAP | 8×8 |

The classical reversible gates work identically on quantum states—they're the "classical subset" of quantum computation.

## Further Resources

- Landauer, "Irreversibility and Heat Generation" (1961)
- Bennett, "Logical Reversibility of Computation" (1973)
- Fredkin & Toffoli, "Conservative Logic" (1982)
- Frank, "Reversible Computing" (2017)

> Return to [Chapter 7](07-reversible-computation.md) for conceptual introduction.
