# Chapter 5: Sequential Logic

## Overview

Adding memory and state to circuits: flip-flops, registers, counters, and state machines.

## Key Concepts

### The Need for Memory

- Combinational logic has no memory
- To build useful systems, we need to remember things
- State: the current "situation" of the system

### Latches vs Flip-Flops

**Latch (Level-Sensitive):**
- Transparent when enable is high
- Changes propagate through immediately
- Problem: can cause race conditions

**Flip-Flop (Edge-Triggered):**
- Only captures input at clock edge
- Predictable, safe timing
- The building block of synchronous design

### The D Flip-Flop

The most common flip-flop:
- D (data) input
- Q output (and often Q')
- CLK (clock) input
- Captures D at rising edge of CLK

```ruby
class DFlipFlop < SimComponent
  input :clk
  input :d
  output :q

  behavior do
    on rising_edge(clk) do
      q <= d
    end
  end
end
```

### Other Flip-Flop Types

**T Flip-Flop (Toggle):**
- Toggles output when T=1 at clock edge
- Useful for counters

**JK Flip-Flop:**
- J=1, K=0: Set (Q=1)
- J=0, K=1: Reset (Q=0)
- J=1, K=1: Toggle
- J=0, K=0: Hold

**SR Flip-Flop:**
- Set/Reset
- S=1: Q=1
- R=1: Q=0
- S=R=1: Invalid (avoid!)

### Registers

Multiple flip-flops sharing a clock:

```ruby
class Register8 < SimComponent
  input :clk
  input :d, width: 8
  input :en  # Enable
  output :q, width: 8

  behavior do
    on rising_edge(clk) do
      if en
        q <= d
      end
    end
  end
end
```

### Counters

Registers that count:

```ruby
class Counter4 < SimComponent
  input :clk
  input :reset
  output :count, width: 4

  behavior do
    on rising_edge(clk) do
      if reset
        count <= 0
      else
        count <= count + 1
      end
    end
  end
end
```

### Shift Registers

Move bits left or right each clock:
- Serial-in, parallel-out (SIPO)
- Parallel-in, serial-out (PISO)
- Uses: serial communication, delay lines

### Finite State Machines (FSMs)

The hardware equivalent of a state machine:

```ruby
# States
IDLE = 0
RUNNING = 1
DONE = 2

class SimpleFSM < SimComponent
  input :clk
  input :start
  input :stop
  output :state, width: 2

  behavior do
    on rising_edge(clk) do
      case state
      when IDLE
        state <= RUNNING if start
      when RUNNING
        state <= DONE if stop
      when DONE
        state <= IDLE
      end
    end
  end
end
```

### Timing Diagrams

Reading and creating timing diagrams:
- Clock edges
- Setup and hold times
- Propagation delays

## Hands-On Project: Traffic Light Controller

Build an FSM for a traffic light:
- States: GREEN, YELLOW, RED
- Transitions based on timer
- Pedestrian crossing button

## Exercises

1. Build a 4-bit up/down counter
2. Design a sequence detector (detects pattern 1011)
3. Create a debouncer for a mechanical button

---

## Notes and Ideas

- Metastability: what happens when setup/hold times are violated
- Clock domains and synchronization (advanced topic teaser)
- Software analogy: flip-flop is like a variable, register is like a struct
- Show physical flip-flop circuit (cross-coupled inverters)
- Real-world: clock speeds and why they're limited
