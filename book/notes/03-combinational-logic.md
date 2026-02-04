# Chapter 3: Combinational Logic

## Overview

Building useful circuits from gates: multiplexers, decoders, encoders, and arithmetic circuits.

## Key Concepts

### What is Combinational Logic?

- Output depends ONLY on current inputs
- No memory, no state
- Like a pure function: same inputs always give same outputs
- Contrast with sequential logic (next chapter)

### Multiplexers (MUX)

The "if statement" of hardware:

```
if (sel == 0) out = a
else out = b
```

Becomes:

```ruby
class Mux2 < SimComponent
  input :a
  input :b
  input :sel
  output :out

  behavior do
    out <= sel.mux(a, b)
  end
end
```

- 2:1 MUX: 2 data inputs, 1 select, 1 output
- 4:1 MUX: 4 data inputs, 2 selects, 1 output
- N:1 MUX: N data inputs, log2(N) selects

### Demultiplexers (DEMUX)

The reverse of MUX - route one input to one of many outputs:

```
sel == 0 ? out0 = in : out0 = 0
sel == 1 ? out1 = in : out1 = 0
```

### Decoders

Convert binary to one-hot:
- 2-to-4 decoder: 2 inputs, 4 outputs (only one active)
- Used for: memory addressing, instruction decoding

```
input: 00 -> output: 0001
input: 01 -> output: 0010
input: 10 -> output: 0100
input: 11 -> output: 1000
```

### Encoders

Opposite of decoder - convert one-hot to binary:
- Priority encoder: handles multiple active inputs

### Binary Addition

Half Adder:
- Adds two 1-bit numbers
- Outputs: sum and carry
- sum = A XOR B
- carry = A AND B

Full Adder:
- Adds two 1-bit numbers plus carry-in
- Foundation for multi-bit addition

Ripple Carry Adder:
- Chain of full adders
- Simple but slow (carry must propagate)

### Comparators

- Equal: A == B (XNOR all bits, AND results)
- Less than: More complex, compare bit by bit from MSB
- Greater than: Similar approach

## Hands-On Project: 4-bit ALU

Build an ALU that supports:
- ADD
- SUB (using two's complement)
- AND
- OR
- XOR

```ruby
class SimpleALU < SimComponent
  input :a, width: 4
  input :b, width: 4
  input :op, width: 3
  output :result, width: 4
  output :zero
  output :carry

  # Operation codes:
  # 000 = ADD
  # 001 = SUB
  # 010 = AND
  # 011 = OR
  # 100 = XOR
end
```

## Exercises

1. Build an 8:1 MUX using 2:1 MUXes
2. Design a 4-bit comparator
3. Implement subtraction using addition and two's complement

---

## Notes and Ideas

- Show how MUX can implement ANY boolean function (as a lookup table)
- Carry-lookahead adder as optimization teaser
- Real-world: how FPGAs use LUTs (lookup tables) internally
- Diagram: data flow through ALU for each operation
- Software analogy: MUX is switch/case, decoder is array indexing
