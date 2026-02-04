# Appendix D: Cellular Automata

Cellular automata are among the simplest systems that can perform universal computation. A grid of cells, each following identical local rules, can produce behavior complex enough to simulate any computer.

## The Basic Idea

A cellular automaton consists of:
1. **A grid of cells** (1D, 2D, or higher)
2. **A set of states** each cell can be in (often just 0 and 1)
3. **A neighborhood** definition (which nearby cells affect each cell)
4. **A rule** that determines the next state based on current neighborhood

All cells update simultaneously (synchronously), creating discrete time steps called "generations."

---

## Elementary Cellular Automata (1D)

The simplest cellular automata are one-dimensional with two states and a 3-cell neighborhood (left, center, right).

### Wolfram's Numbering System

Stephen Wolfram classified all 256 possible rules by encoding them as binary numbers:

```
Neighborhood:     111  110  101  100  011  010  001  000
                   ↓    ↓    ↓    ↓    ↓    ↓    ↓    ↓
New state:         ?    ?    ?    ?    ?    ?    ?    ?
```

The 8 output bits form a binary number 0-255. Hence "Rule 30," "Rule 110," etc.

### Rule 30: Chaos from Order

```
Neighborhood:  111  110  101  100  011  010  001  000
New state:      0    0    0    1    1    1    1    0
               ─────────────────────────────────────────
               Binary: 00011110 = 30
```

**Rule 30 evolution:**
```
Gen 0:  ................................#................................
Gen 1:  ...............................###...............................
Gen 2:  ..............................##..#..............................
Gen 3:  .............................##.####.............................
Gen 4:  ............................##..#...#............................
Gen 5:  ...........................##.####.###...........................
Gen 6:  ..........................##..#....#..#..........................
Gen 7:  .........................##.####..######.........................
Gen 8:  ........................##..#...###.....#........................
Gen 9:  .......................##.####.##..#...###.......................
Gen 10: ......................##..#....#.####.##..#......................
```

**Properties of Rule 30:**
- Produces chaotic, unpredictable patterns
- Used in Mathematica's random number generator
- Cannot be predicted without running it (no shortcut formula)
- Left edge is periodic; center and right are chaotic

### Rule 110: Universal Computation

```
Neighborhood:  111  110  101  100  011  010  001  000
New state:      0    1    1    0    1    1    1    0
               ─────────────────────────────────────────
               Binary: 01101110 = 110
```

**Rule 110 evolution:**
```
Gen 0:  .............................................................#...
Gen 1:  ............................................................##...
Gen 2:  ...........................................................###...
Gen 3:  ..........................................................##.#...
Gen 4:  .........................................................#####...
Gen 5:  ........................................................##...#...
Gen 6:  .......................................................###..##...
Gen 7:  ......................................................##.#.###...
Gen 8:  .....................................................########...
Gen 9:  ....................................................##......#...
Gen 10: ...................................................###.....##...
Gen 11: ..................................................##.#....###...
Gen 12: .................................................#####...##.#...
Gen 13: ................................................##...#..#####...
Gen 14: ...............................................###..####....#...
Gen 15: ..............................................##.#.##..#...##...
```

**Rule 110 is Turing complete!** (Proved by Matthew Cook in 2004)

This means Rule 110 can compute anything any computer can compute. The proof works by showing that Rule 110 can simulate a universal Turing machine through carefully constructed initial conditions.

### The Four Classes of Cellular Automata

Wolfram classified all elementary automata into four classes:

| Class | Behavior | Examples |
|-------|----------|----------|
| I | Uniform | Rule 0, 255 (all cells become same) |
| II | Periodic | Rule 4, 108 (stable or repeating patterns) |
| III | Chaotic | Rule 30, 45, 73 (random-looking) |
| IV | Complex | Rule 110, 54 (localized structures) |

Class IV automata exist "at the edge of chaos"—complex enough to compute, ordered enough to maintain structure.

### Ruby Implementation

```ruby
# Elementary Cellular Automaton Simulator

class ElementaryCA
  def initialize(rule_number, width = 80)
    @rule = rule_number
    @width = width
    # Convert rule number to lookup table
    @lookup = (0..7).map { |i| (rule_number >> i) & 1 }
  end

  def apply_rule(left, center, right)
    index = (left << 2) | (center << 1) | right
    @lookup[index]
  end

  def step(row)
    new_row = Array.new(@width, 0)
    @width.times do |i|
      left = row[(i - 1) % @width]
      center = row[i]
      right = row[(i + 1) % @width]
      new_row[i] = apply_rule(left, center, right)
    end
    new_row
  end

  def run(generations, initial = nil)
    # Default: single cell in center
    row = initial || Array.new(@width, 0).tap { |r| r[@width / 2] = 1 }

    generations.times do
      puts row.map { |c| c == 1 ? '#' : '.' }.join
      row = step(row)
    end
  end
end

# Run Rule 110
ca = ElementaryCA.new(110, 60)
ca.run(30)

# Run Rule 30
ca = ElementaryCA.new(30, 60)
ca.run(30)
```

---

## Conway's Game of Life (2D)

The Game of Life is a 2D cellular automaton created by John Conway in 1970. Despite having only three rules, it produces extraordinarily complex behavior.

### The Rules

Each cell has 8 neighbors (Moore neighborhood). At each step:

1. **Survival**: A live cell with 2 or 3 neighbors stays alive
2. **Birth**: A dead cell with exactly 3 neighbors becomes alive
3. **Death**: All other cells die or stay dead

```
Neighborhood (Moore):

  NW  N  NE
   ╲  │  ╱
    ╲ │ ╱
  W ──●── E     ● = center cell
    ╱ │ ╲       8 neighbors total
   ╱  │  ╲
  SW  S  SE
```

### Common Patterns

**Still Lifes** (stable patterns):
```
Block:      Beehive:      Loaf:
  ##          .##.          .##.
  ##          #..#          #..#
              .##.          .#.#
                            ..#.
```

**Oscillators** (periodic patterns):
```
Blinker (period 2):

  Phase 1:    Phase 2:
    .#.         ...
    .#.   →     ###   →  (repeats)
    .#.         ...
```

**Spaceships** (moving patterns):
```
Glider (moves diagonally):

  Gen 0:    Gen 1:    Gen 2:    Gen 3:    Gen 4:
   .#.       ...       ...       ...       ...
   ..#       #.#       ..#       #..       .#.
   ###       .##       #.#       ..##      ..#
             .#.       .##       .##       ###

   (back to original shape, shifted one cell diagonally)
```

**Glider Gun** (produces gliders indefinitely):
```
Gosper Glider Gun (period 30):

........................#...........
......................#.#...........
............##......##............##
...........#...#....##............##
##........#.....#...##..............
##........#...#.##....#.#...........
..........#.....#.......#...........
...........#...#....................
............##......................
```

### Game of Life is Turing Complete

The Game of Life can simulate any Turing machine because:

1. **Gliders** can represent data (presence = 1, absence = 0)
2. **Glider collisions** can implement logic gates
3. **Glider guns** provide clocking and data generation
4. **Carefully arranged patterns** create memory and processing

People have built:
- Logic gates (AND, OR, NOT, XOR)
- Adders and ALUs
- Memory (registers, RAM)
- Complete computers running programs
- A pattern that simulates the Game of Life itself!

### Logic Gates in Life

**AND Gate** (simplified concept):
```
Two glider streams → collision region → output only if both present
```

**NOT Gate:**
```
Continuous glider stream → collision with input glider destroys output
No input → stream continues (inverted)
```

### Ruby Implementation

```ruby
# Conway's Game of Life

class GameOfLife
  def initialize(width, height)
    @width = width
    @height = height
    @grid = Array.new(height) { Array.new(width, 0) }
  end

  def set(x, y, value = 1)
    @grid[y % @height][x % @width] = value
  end

  def get(x, y)
    @grid[y % @height][x % @width]
  end

  def count_neighbors(x, y)
    count = 0
    (-1..1).each do |dy|
      (-1..1).each do |dx|
        next if dx == 0 && dy == 0
        count += get(x + dx, y + dy)
      end
    end
    count
  end

  def step
    new_grid = Array.new(@height) { Array.new(@width, 0) }

    @height.times do |y|
      @width.times do |x|
        neighbors = count_neighbors(x, y)
        alive = get(x, y) == 1

        # Apply rules
        if alive && (neighbors == 2 || neighbors == 3)
          new_grid[y][x] = 1  # Survival
        elsif !alive && neighbors == 3
          new_grid[y][x] = 1  # Birth
        end
        # Otherwise death/stay dead (already 0)
      end
    end

    @grid = new_grid
  end

  def display
    @grid.each do |row|
      puts row.map { |c| c == 1 ? '#' : '.' }.join
    end
    puts
  end

  # Add a glider at position (x, y)
  def add_glider(x, y)
    pattern = [
      [0, 1, 0],
      [0, 0, 1],
      [1, 1, 1]
    ]
    pattern.each_with_index do |row, dy|
      row.each_with_index do |cell, dx|
        set(x + dx, y + dy, cell)
      end
    end
  end

  # Add a Gosper glider gun at position (x, y)
  def add_glider_gun(x, y)
    pattern = <<~GUN
      ........................#...........
      ......................#.#...........
      ............##......##............##
      ...........#...#....##............##
      ##........#.....#...##..............
      ##........#...#.##....#.#...........
      ..........#.....#.......#...........
      ...........#...#....................
      ............##......................
    GUN

    pattern.lines.each_with_index do |line, dy|
      line.chomp.chars.each_with_index do |char, dx|
        set(x + dx, y + dy, char == '#' ? 1 : 0)
      end
    end
  end
end

# Demo: Glider
life = GameOfLife.new(20, 10)
life.add_glider(2, 2)

10.times do
  life.display
  life.step
  sleep(0.3)
end
```

---

## Wireworld: A Circuit Simulator

Wireworld is a cellular automaton designed to simulate electronic circuits.

### States and Rules

Four states:
1. **Empty** (black) - Background
2. **Wire** (yellow) - Conductor
3. **Electron head** (blue) - Signal front
4. **Electron tail** (red) - Signal back

Rules:
```
Empty       → Empty (always)
Electron head → Electron tail (always)
Electron tail → Wire (always)
Wire        → Electron head (if 1 or 2 neighbors are heads)
              Otherwise stays Wire
```

### Signals Propagate Like Electricity

```
Time 0:  ═══●○═══════
Time 1:  ════●○══════
Time 2:  ═════●○═════
Time 3:  ═══════●○═══

● = electron head
○ = electron tail
═ = wire
```

### Logic Gates in Wireworld

**Diode (one-way signal):**
```
     ══╗
═══════╬════
     ══╝
```

**OR Gate:**
```
══════╗
      ╠═════
══════╝
```

**AND Gate:**
```
══════╗
      ║
══════╬═════
      ║
══════╝
```

**XOR Gate (more complex):**
```
        ╔═══════╗
════════╬═══════╬═════
        ╚═══════╝
```

People have built complete computers in Wireworld, including a programmable computer with ROM.

---

## Why Cellular Automata Matter

### 1. Minimal Universal Computation

Rule 110 proves that universality requires surprisingly little:
- 2 states
- 3-cell neighborhood
- 8 rules

This is near the theoretical minimum for universal computation.

### 2. Emergence

Complex global behavior emerges from simple local rules:
- No cell "knows" about gliders or glider guns
- Patterns arise from interactions
- This mirrors how transistors don't "know" about programs

### 3. Physics Connection

Cellular automata model physical phenomena:
- Fluid dynamics (lattice Boltzmann methods)
- Crystal growth
- Forest fires and epidemics
- Traffic flow

Some physicists (like Wolfram) propose the universe itself might be a cellular automaton.

### 4. Hardware Implementation

Cellular automata map naturally to hardware:
- Each cell is identical → easy to replicate
- Local connections only → simple wiring
- Synchronous updates → clock-driven

**RHDL Cellular Automaton:**

```ruby
# 1D Elementary Cellular Automaton in RHDL

class CellularAutomaton < SimComponent
  RULE = 110
  WIDTH = 64

  input :clk
  input :reset

  output :cells, width: WIDTH

  # Current state
  wire :state, width: WIDTH
  wire :next_state, width: WIDTH

  behavior do
    if reset == 1
      # Initialize with single cell
      state <= 1 << (WIDTH / 2)
    elsif rising_edge(clk)
      state <= next_state
    end

    # Compute next state for all cells in parallel
    WIDTH.times do |i|
      left = (i == 0) ? 0 : state[i - 1]
      center = state[i]
      right = (i == WIDTH - 1) ? 0 : state[i + 1]

      index = (left << 2) | (center << 1) | right
      next_state[i] <= (RULE >> index) & 1
    end

    cells <= state
  end
end
```

Each cell updates simultaneously based on its neighbors—exactly how hardware operates.

---

## Langton's Ant: Emergent Complexity

Langton's Ant is the simplest 2D automaton with Turing completeness:

**Rules:**
1. On white square: turn right, flip color, move forward
2. On black square: turn left, flip color, move forward

**Behavior:**
- First ~10,000 steps: chaotic, unpredictable pattern
- After ~10,000 steps: suddenly builds a "highway"—diagonal pattern extending infinitely

```
Chaotic phase:           Highway phase:
  ▓░▓▓░░▓░               ░▓░░▓░░▓░░▓
  ░░▓▓░▓▓▓               ▓░░▓░░▓░░▓░
  ▓▓░░█░▓░        →      ░░▓░░▓░░▓░░
  ░▓░▓░░▓▓               ░▓░░▓░░▓░░▓
  ▓░░▓▓░░▓               ▓░░▓░░▓░░▓░
```

Nobody knows *why* the ant always builds a highway. It's been proven for billions of steps but not proven in general.

---

## Connection to Hardware Design

Cellular automata illuminate fundamental truths about computation:

| Cellular Automata | Digital Hardware |
|-------------------|------------------|
| Cell | Gate or flip-flop |
| State | Signal value (0/1) |
| Neighborhood | Fan-in (input wires) |
| Rule | Logic function |
| Generation | Clock cycle |
| Grid | Chip layout |

**Key insights:**
1. **Local rules create global behavior** - Gates don't know about programs
2. **Parallelism is inherent** - All cells/gates update together
3. **Simple components suffice** - NAND gates are universal; so is Rule 110
4. **Emergence is inevitable** - Complex patterns from simple rules

When you design hardware, you're creating cellular automata rules. The behavior that emerges—your program running—is no different in principle from gliders gliding.

---

## Exercises

### Exercise 1: Implement Rule 90
Rule 90 produces the Sierpinski triangle. Implement it and verify.
```
Rule 90: neighborhood XOR (ignore center)
```

### Exercise 2: Find Still Lifes
Write code to search for Game of Life still lifes (stable patterns) of a given size.

### Exercise 3: Wireworld Adder
Design a half-adder in Wireworld (two inputs, sum and carry outputs).

### Exercise 4: Rule 110 Computation
Research how Rule 110 simulates a cyclic tag system to achieve Turing completeness.

---

## References

- Wolfram, S. (2002). *A New Kind of Science*
- Berlekamp, Conway, Guy (2001). *Winning Ways for Your Mathematical Plays* (Vol. 4)
- Cook, M. (2004). "Universality in Elementary Cellular Automata"
- Adamatzky, A. (2010). *Game of Life Cellular Automata*
- Rendell, P. (2011). "A Universal Turing Machine in Conway's Game of Life"
