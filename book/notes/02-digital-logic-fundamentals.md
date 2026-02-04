# Chapter 2: Digital Logic Fundamentals

## Overview

The building blocks of all digital systems: logic gates, truth tables, and Boolean algebra.

## Key Concepts

### Binary and Bits

- Why binary? (noise immunity, simplicity)
- Bits as the atom of digital information
- High/Low, 1/0, True/False - all the same thing

### The Basic Gates

#### NOT (Inverter)
- Single input, single output
- Output is opposite of input
- Symbol: triangle with bubble

#### AND Gate
- Output is 1 only if ALL inputs are 1
- Like `&&` in programming
- "Both must be true"

#### OR Gate
- Output is 1 if ANY input is 1
- Like `||` in programming
- "At least one must be true"

#### XOR (Exclusive OR)
- Output is 1 if inputs are DIFFERENT
- "One or the other, but not both"
- Useful for: addition, parity, comparison

#### NAND and NOR
- "Universal gates" - can build anything from just NANDs
- NAND = NOT(AND), NOR = NOT(OR)
- Why they matter: easier to manufacture

### Truth Tables

| A | B | AND | OR | XOR | NAND |
|---|---|-----|-----|-----|------|
| 0 | 0 |  0  |  0  |  0  |  1   |
| 0 | 1 |  0  |  1  |  1  |  1   |
| 1 | 0 |  0  |  1  |  1  |  1   |
| 1 | 1 |  1  |  1  |  0  |  0   |

### Boolean Algebra

- AND as multiplication: A * B
- OR as addition: A + B
- NOT as complement: A'
- De Morgan's Laws: (A*B)' = A' + B'
- Simplification techniques

### Gate Delays and Propagation

- Gates aren't instant - signals take time to propagate
- Critical path: longest chain of gates
- Why this matters for clock speed

## Hands-On Project: Building Complex Gates

Build these using only NAND gates:
1. NOT
2. AND
3. OR
4. XOR

```ruby
class NandOnly < SimComponent
  # Challenge: Build XOR using only NAND gates
  input :a
  input :b
  output :xor_out

  # Hint: XOR = (A NAND (A NAND B)) NAND (B NAND (A NAND B))
end
```

## Exercises

1. Create truth tables for 3-input AND, OR, XOR
2. Prove De Morgan's laws using truth tables
3. Simplify: (A AND B) OR (A AND NOT B)

---

## Notes and Ideas

- Physical analogy: gates as water valves or light switches
- Show actual transistor-level implementation (briefly) for intuition
- Interactive truth table builder exercise
- History: Claude Shannon's insight connecting Boolean algebra to circuits
- Visual: gate symbols (both US and international standards)
