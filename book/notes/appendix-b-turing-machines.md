# Appendix B: Turing Machine Programs

This appendix contains example Turing machine programs with complete state tables and execution traces. These programs demonstrate that simple rules operating on symbols can perform any computation.

## Turing Machine Basics

A Turing machine consists of:
- An infinite tape divided into cells
- Each cell contains a symbol (we'll use `0`, `1`, and `_` for blank)
- A read/write head positioned over one cell
- A state register (current state of the machine)
- A transition table (the "program")

Each transition rule has the form:
```
(Current State, Read Symbol) → (Write Symbol, Move Direction, New State)
```

The machine halts when it reaches a state with no applicable rule.

---

## Program 1: Binary Increment

**Purpose:** Add 1 to a binary number

**Example:** `1011` (11 in decimal) → `1100` (12 in decimal)

### State Table

| State | Read | Write | Move | Next State | Comment |
|-------|------|-------|------|------------|---------|
| START | 0 | 0 | R | START | Scan right to find end |
| START | 1 | 1 | R | START | Scan right to find end |
| START | _ | _ | L | ADD | Found end, go back |
| ADD | 0 | 1 | L | DONE | 0→1, no carry, done |
| ADD | 1 | 0 | L | ADD | 1→0, carry continues |
| ADD | _ | 1 | L | DONE | Overflow: add new 1 |
| DONE | * | * | - | HALT | Stop |

### Execution Trace

```
Initial tape: _ 1 0 1 1 _
              ^
              START

Step 1: (START, 1) → (1, R, START)
        _ 1 0 1 1 _
            ^
            START

Step 2: (START, 0) → (0, R, START)
        _ 1 0 1 1 _
              ^
              START

Step 3: (START, 1) → (1, R, START)
        _ 1 0 1 1 _
                ^
                START

Step 4: (START, 1) → (1, R, START)
        _ 1 0 1 1 _
                  ^
                  START

Step 5: (START, _) → (_, L, ADD)
        _ 1 0 1 1 _
                ^
                ADD

Step 6: (ADD, 1) → (0, L, ADD)
        _ 1 0 1 0 _
              ^
              ADD

Step 7: (ADD, 1) → (0, L, ADD)
        _ 1 0 0 0 _
            ^
            ADD

Step 8: (ADD, 0) → (1, L, DONE)
        _ 1 1 0 0 _
          ^
          DONE

Step 9: HALT

Final tape: _ 1 1 0 0 _
Result: 1100 (12 in decimal) ✓
```

### Ruby Simulator

```ruby
class TuringMachine
  def initialize(tape, initial_state, transitions)
    @tape = tape.dup
    @head = 0
    @state = initial_state
    @transitions = transitions
  end

  def step
    symbol = @tape[@head] || '_'
    key = [@state, symbol]

    return false unless @transitions.key?(key)

    write, move, next_state = @transitions[key]

    @tape[@head] = write
    @head += (move == :R ? 1 : -1)
    @state = next_state

    # Extend tape if needed
    @tape.unshift('_') and @head += 1 if @head < 0
    @tape.push('_') if @head >= @tape.length

    true
  end

  def run(max_steps = 1000)
    steps = 0
    while step && steps < max_steps
      steps += 1
    end
    @tape.join.gsub(/^_+|_+$/, '')  # Trim blanks
  end
end

# Binary increment program
transitions = {
  ['START', '0'] => ['0', :R, 'START'],
  ['START', '1'] => ['1', :R, 'START'],
  ['START', '_'] => ['_', :L, 'ADD'],
  ['ADD', '0']   => ['1', :L, 'DONE'],
  ['ADD', '1']   => ['0', :L, 'ADD'],
  ['ADD', '_']   => ['1', :L, 'DONE'],
}

tm = TuringMachine.new(['_', '1', '0', '1', '1', '_'], 'START', transitions)
puts tm.run  # => "1100"
```

---

## Program 2: Binary Addition

**Purpose:** Add two binary numbers separated by `+`

**Example:** `101+11` (5+3) → `1000` (8)

### State Table

| State | Read | Write | Move | Next State | Comment |
|-------|------|-------|------|------------|---------|
| START | * | * | R | FIND_PLUS | Go to the plus sign |
| FIND_PLUS | + | + | R | FIND_END | Found plus, find end |
| FIND_PLUS | 0,1 | 0,1 | R | FIND_PLUS | Keep scanning |
| FIND_END | 0,1 | 0,1 | R | FIND_END | Find rightmost digit |
| FIND_END | _ | _ | L | BORROW_B | Start from end of B |
| BORROW_B | 0 | _ | L | FIND_A_0 | Mark 0, carry 0 to A |
| BORROW_B | 1 | _ | L | FIND_A_1 | Mark 1, carry 1 to A |
| BORROW_B | + | _ | L | CLEANUP | B exhausted, cleanup |
| FIND_A_0 | ... | ... | ... | ... | (adds 0 to A) |
| FIND_A_1 | ... | ... | ... | ... | (adds 1 to A) |
| ... | ... | ... | ... | ... | (full table omitted for brevity) |

This machine is more complex—it repeatedly:
1. Takes the rightmost digit of B
2. Adds it to A (with carry propagation)
3. Erases that digit of B
4. Repeats until B is empty

---

## Program 3: Unary to Binary Conversion

**Purpose:** Convert unary (tally marks) to binary

**Example:** `11111` (5 tally marks) → `101` (5 in binary)

### State Table

| State | Read | Write | Move | Next State | Comment |
|-------|------|-------|------|------------|---------|
| CHECK | 1 | _ | R | COUNT | Found a 1, start counting |
| CHECK | _ | _ | L | OUTPUT | No more 1s, output result |
| COUNT | 1 | 1 | R | COUNT | Count the 1s |
| COUNT | _ | _ | L | HALVE | End of number |
| HALVE | 1 | _ | L | HALVE_2 | Remove one 1 |
| HALVE | _ | _ | L | RECORD_0 | Odd: record 0 |
| HALVE_2 | 1 | _ | L | HALVE | Remove another 1 |
| HALVE_2 | _ | _ | L | RECORD_1 | Even pair: record 1 |
| ... | ... | ... | ... | ... | (continues) |

The algorithm repeatedly halves the count, recording whether each division had a remainder (which becomes a binary digit).

---

## Program 4: Busy Beaver (3-State)

**Purpose:** Write as many 1s as possible before halting

The 3-state Busy Beaver writes **6 ones** in **14 steps**. It holds the record for the most 1s written by any 3-state machine that eventually halts.

### State Table

| State | Read | Write | Move | Next State |
|-------|------|-------|------|------------|
| A | 0 | 1 | R | B |
| A | 1 | 1 | L | C |
| B | 0 | 1 | L | A |
| B | 1 | 1 | R | B |
| C | 0 | 1 | L | B |
| C | 1 | 1 | - | HALT |

### Execution Trace

```
Step 0:  ... _ _ _ [_] _ _ _ ...   State: A
Step 1:  ... _ _ _ 1 [_] _ _ ...   State: B
Step 2:  ... _ _ [_] 1 1 _ _ ...   State: A
Step 3:  ... _ _ 1 [1] 1 _ _ ...   State: B
Step 4:  ... _ _ 1 1 [1] _ _ ...   State: B
Step 5:  ... _ _ 1 1 1 [_] _ ...   State: B
Step 6:  ... _ _ 1 1 [1] 1 _ ...   State: A
Step 7:  ... _ _ 1 [1] 1 1 _ ...   State: C
Step 8:  ... _ _ [1] 1 1 1 _ ...   State: B
Step 9:  ... _ _ 1 [1] 1 1 _ ...   State: B
Step 10: ... _ _ 1 1 [1] 1 _ ...   State: B
Step 11: ... _ _ 1 1 1 [1] _ ...   State: B
Step 12: ... _ _ 1 1 1 1 [_] ...   State: B
Step 13: ... _ _ 1 1 1 [1] 1 ...   State: A
Step 14: ... _ _ 1 1 [1] 1 1 ...   State: C

Final: 6 ones on tape, HALT
```

### The Busy Beaver Function

The Busy Beaver function BB(n) = maximum 1s writable by an n-state machine

| States | BB(n) | Steps to halt |
|--------|-------|---------------|
| 1 | 1 | 1 |
| 2 | 4 | 6 |
| 3 | 6 | 14 |
| 4 | 13 | 107 |
| 5 | ≥4098 | ≥47,176,870 |
| 6 | >10↑↑15 | incomprehensibly large |

BB(n) grows faster than any computable function. It's **uncomputable**—no algorithm can calculate it for all n.

---

## Program 5: Universal Turing Machine (Sketch)

A Universal Turing Machine (UTM) can simulate any other Turing machine. It takes as input:
1. A description of a Turing machine T
2. An input tape for T

And simulates T running on that input.

### Tape Format

```
[Machine Description] # [Simulated Tape]

Machine description encodes:
- States as numbers: q0, q1, q2, ...
- Transitions as tuples: (qi, a, b, D, qj)
  meaning: in state qi, reading a, write b, move D, go to qj
```

### How It Works

The UTM:
1. Reads current state from a "state register" section of tape
2. Reads symbol under simulated head
3. Looks up transition in machine description
4. Writes new symbol to simulated tape
5. Moves simulated head (by shifting markers)
6. Updates state register
7. Repeats

This is exactly what a CPU does:
- Fetch instruction (look up transition)
- Decode (parse the tuple)
- Execute (write, move, change state)

**The UTM proves that a single, fixed machine can compute anything any Turing machine can compute—it's the theoretical foundation for general-purpose computers.**

---

## RHDL Turing Machine Simulator

Here's a hardware implementation of a simple Turing machine in RHDL:

```ruby
# A 4-state Turing machine implemented in hardware
# Demonstrates that sequential logic can implement any computation

class TuringMachineHardware < SimComponent
  input :clk
  input :reset
  input :start

  output :halted
  output :head_pos, width: 8
  output :current_state, width: 2

  # Tape memory (256 cells)
  TAPE_SIZE = 256

  # Internal state
  wire :state, width: 2
  wire :head, width: 8
  wire :tape_read, width: 1
  wire :tape_write, width: 1
  wire :write_enable, width: 1

  # Transition table ROM
  # Index: {state[1:0], tape_read} = 3 bits
  # Output: {write_val, move_dir, next_state[1:0], halt} = 5 bits
  #
  # This encodes the binary increment program:
  # State 0 (START): scan right
  # State 1 (ADD): add with carry
  # State 2 (DONE): halt

  TRANSITIONS = [
    # state=0 (START)
    0b0_1_00_0,  # read 0: write 0, move R, stay START
    0b1_1_00_0,  # read 1: write 1, move R, stay START

    # state=1 (ADD)
    0b1_0_10_0,  # read 0: write 1, move L, go DONE
    0b0_0_01_0,  # read 1: write 0, move L, stay ADD

    # state=2 (DONE)
    0b0_0_10_1,  # halt
    0b0_0_10_1,  # halt

    # state=3 (unused)
    0b0_0_11_1,
    0b0_0_11_1,
  ]

  # Tape memory (would be RAM in real implementation)
  instance :tape_mem, Memory, width: 1, depth: TAPE_SIZE

  behavior do
    if reset == 1
      state <= 0
      head <= TAPE_SIZE / 2  # Start in middle
      halted <= 0
    elsif rising_edge(clk) && start == 1 && halted == 0
      # Read current tape cell
      tape_read <= tape_mem.read(head)

      # Look up transition
      trans_idx = (state << 1) | tape_read
      transition = TRANSITIONS[trans_idx]

      # Decode transition
      write_val  = (transition >> 4) & 1
      move_right = (transition >> 3) & 1
      next_state = (transition >> 1) & 3
      halt       = transition & 1

      # Execute transition
      tape_mem.write(head, write_val)

      if move_right == 1
        head <= head + 1
      else
        head <= head - 1
      end

      state <= next_state
      halted <= halt

      # Outputs
      head_pos <= head
      current_state <= state
    end
  end
end
```

This hardware implementation shows that a Turing machine maps directly to:
- **State register** → flip-flops
- **Tape** → RAM
- **Transition table** → ROM (or combinational logic)
- **Control** → state machine

The same architecture scales to any Turing machine, proving that digital hardware can compute anything computable.

---

## Key Insights

1. **Simplicity yields universality** - A handful of states and simple rules can compute anything

2. **The tape is just memory** - Sequential access with read/write is sufficient for all computation

3. **Programs are data** - The Universal Turing Machine treats machine descriptions as input

4. **Hardware implements the same model** - CPUs are just very fast, parallel Turing machines with random-access memory

5. **Uncomputability exists** - Some problems (like the Busy Beaver function) cannot be solved by any algorithm

## References

- Turing, A.M. (1936). "On Computable Numbers, with an Application to the Entscheidungsproblem"
- Minsky, M. (1967). *Computation: Finite and Infinite Machines*
- Sipser, M. (2012). *Introduction to the Theory of Computation*
