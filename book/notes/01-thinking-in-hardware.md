# Chapter 1: Thinking in Hardware

## Overview

The fundamental mental shift from sequential software execution to parallel hardware operation.

## Key Concepts

### Everything Happens at Once

In software:
```ruby
a = 1
b = 2
c = a + b  # This happens AFTER a and b are assigned
```

In hardware:
```ruby
# All of these "happen" simultaneously, continuously
wire :a, value: input_a
wire :b, value: input_b
wire :c, value: a + b  # This is always a + b, not a sequence
```

### Signals vs Variables

- Variables hold state that changes over time via assignment
- Signals are continuous connections - like water flowing through pipes
- A signal's value is determined by what it's connected to

### Time and Clocks

- Software: time is implicit (instruction after instruction)
- Hardware: time is explicit (clock edges, propagation delays)
- The clock is the heartbeat of synchronous digital systems

### State and Combinational Logic

- Combinational: output depends only on current inputs (pure functions)
- Sequential: output depends on inputs AND previous state (stateful)

## Software Analogies

| Hardware Concept | Software Analogy |
|-----------------|------------------|
| Wire/Signal | Reactive variable / Observable |
| Combinational logic | Pure function |
| Register | Variable |
| Clock edge | Event trigger |
| Module | Class/Object |
| Port | Interface/API |

## Hands-On: Your First Hardware Module

Build a simple module that:
1. Takes two inputs
2. Outputs their AND, OR, and XOR

```ruby
class FirstModule < SimComponent
  input :a
  input :b
  output :and_out
  output :or_out
  output :xor_out

  behavior do
    and_out <= a & b
    or_out <= a | b
    xor_out <= a ^ b
  end
end
```

## Discussion Questions

1. Why can't hardware have "if statements" in the same way software does?
2. What happens if you create a "loop" in combinational logic?
3. How does parallelism in hardware differ from multi-threading?

---

## Notes and Ideas

- Use the "spreadsheet" analogy - cells that auto-update based on formulas
- Show timing diagrams early - they're the "print debugging" of hardware
- Contrast: software bugs are usually logic errors, hardware bugs are often timing
- Include common mistakes software engineers make when starting hardware
