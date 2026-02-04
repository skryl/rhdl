# Appendix H: Reversible Gates

*Companion appendix to [Chapter 7: Reversible Computation](07-reversible-computation.md)*

## Overview

This appendix provides formal treatment of reversible logic, complete gate implementations, and analysis of reversible circuit synthesis.

## Contents

- Formal definition of reversibility
- Complete Toffoli and Fredkin gate implementations
- Building standard gates from reversible primitives
- Garbage management and Bennett's method
- Reversible arithmetic circuits
- Energy analysis and Landauer's principle

## Gate Library

### Fundamental Gates

```ruby
# Toffoli (CCNOT)
class ToffoliGate < SimComponent
  input :a, :b, :c
  output :a_out, :b_out, :c_out

  behavior do
    a_out <= a
    b_out <= b
    c_out <= c ^ (a & b)
  end
end
```

### Derived Circuits

- Reversible AND, OR, XOR, NOT
- Reversible half adder
- Reversible full adder
- Reversible multiplier
- Reversible comparator

## Notes

*Content to be expanded with formal proofs and optimized implementations.*

> Return to [Chapter 7](07-reversible-computation.md) for conceptual introduction.
