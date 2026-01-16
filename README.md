# RHDL (Ruby Hardware Description Language)

RHDL is a Domain Specific Language (DSL) that allows you to design hardware using Ruby's flexible syntax and export to VHDL. It provides a comfortable environment for Ruby developers to create hardware designs with all the power of Ruby's metaprogramming capabilities.

## Features

- **Behavioral CPU**: A complete 8-bit CPU implementation for educational purposes
- **HDL Simulation Framework**: Gate-level simulation with support for combinational and sequential logic
- **Signal Probing & Debugging**: Waveform capture, breakpoints, watchpoints, and VCD export
- **Terminal GUI**: Interactive terminal-based simulator interface
- **Component Library**: Gates, flip-flops, registers, ALU, memory, and more
- **VHDL Export**: Generate synthesizable VHDL from Ruby definitions

## Project Structure

```
rhdl/
├── lib/rhdl/           # Core library
│   ├── dsl.rb          # VHDL DSL for component definitions
│   ├── components/     # Structural component definitions
│   └── hdl/            # HDL simulation framework
│       ├── simulation.rb    # Core simulation engine
│       ├── gates.rb         # Logic gate primitives
│       ├── sequential.rb    # Flip-flops, registers, counters
│       ├── arithmetic.rb    # Adders, ALU, comparators
│       ├── combinational.rb # Multiplexers, decoders
│       ├── memory.rb        # RAM, ROM, register files
│       ├── debug.rb         # Signal probing & debugging
│       ├── tui.rb           # Terminal GUI
│       └── cpu/             # HDL CPU implementation
├── cpu/                # Behavioral CPU implementation
├── examples/           # Demo scripts
├── spec/               # Test suite
└── docs/               # Documentation
```

## Documentation

Detailed documentation is available in the `docs/` directory:

- **[HDL Overview](docs/hdl_overview.md)** - Introduction to the HDL framework architecture
- **[Simulation Engine](docs/simulation_engine.md)** - Core simulation infrastructure and concepts
- **[Components Reference](docs/components.md)** - Complete reference for all HDL components
- **[CPU Datapath](docs/cpu_datapath.md)** - CPU architecture and instruction set details
- **[Debugging Guide](docs/debugging.md)** - Signal probing, breakpoints, and terminal GUI

## Quick Start

### Using the HDL Simulation Framework

```ruby
require 'rhdl'

# Create an ALU
alu = RHDL::HDL::ALU.new("my_alu", width: 8)
alu.set_input(:a, 10)
alu.set_input(:b, 5)
alu.set_input(:op, RHDL::HDL::ALU::OP_ADD)
alu.propagate

puts alu.get_output(:result)  # => 15
```

### Using the HDL CPU

```ruby
require 'rhdl'

# Create CPU with memory adapter
memory = MemorySimulator::Memory.new
cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)

# Load a program: LDI 42, HLT
cpu.memory.load([0xA0, 0x2A, 0xF0], 0)

# Run until halted
until cpu.halted
  cpu.step
end

puts cpu.acc  # => 42
```

### Using the Debug Simulator

```ruby
require 'rhdl'

# Create a debug simulator with probing and breakpoints
sim = RHDL::HDL::DebugSimulator.new
clock = RHDL::HDL::Clock.new("clk")
counter = RHDL::HDL::Counter.new("cnt", width: 8)

sim.add_clock(clock)
sim.add_component(counter)
RHDL::HDL::SimComponent.connect(clock, counter.inputs[:clk])

# Add a signal probe for waveform capture
sim.probe(counter, :q)

# Add a watchpoint to break when counter reaches 100
sim.watch(counter.outputs[:q], type: :equals, value: 100) do |s|
  puts "Counter reached 100!"
end

# Run simulation
sim.run(200)

# Export waveform to VCD file (viewable in GTKWave)
File.write("waveform.vcd", sim.waveform.to_vcd)
```

### Using the Terminal GUI

```ruby
require 'rhdl'

# Create simulator and components
sim = RHDL::HDL::DebugSimulator.new
# ... add components ...

# Launch the interactive TUI
tui = RHDL::HDL::SimulatorTUI.new(sim)
tui.add_component(my_component)
tui.run
```

Or run the demo:
```bash
ruby examples/simulator_tui_demo.rb
```

**TUI Key Bindings:**
- `Space` - Step one cycle
- `r` - Run simulation
- `s` - Stop/pause
- `w` - Add watchpoint
- `b` - Add breakpoint
- `:` - Enter command mode
- `h` - Show help
- `q` - Quit

## Behavioral CPU

RHDL includes a simple 8-bit CPU architecture designed for educational purposes. The CPU features:

- 8-bit data bus and 16-bit address space (64KB addressable memory)
- Single accumulator (ACC) register
- Simple ALU supporting basic operations (ADD, SUB, AND, OR, XOR, NOT, MUL, DIV, CMP)
- Zero flag for conditional operations
- 8-bit stack pointer (SP) with stack operations
- 16-bit program counter (PC) supporting long jumps
- Control unit for instruction decoding and execution
- Variable-length instruction encoding (1-byte, 2-byte, and 3-byte instructions)
- Nibble-encoded instructions for compact code
- Direct and indirect addressing modes

### Instruction Set

The CPU implements the following instructions with variable-length encoding:

#### Nibble-Encoded Instructions (1 byte for operands ≤ 0x0F, 2 bytes otherwise)

| Instruction | Description | Encoding | Format |
|-------------|-------------|----------|---------|
| NOP | No operation | 0x00 | 1 byte |
| LDA addr | Load accumulator from memory | 0x1n / 0x10 0xnn | Nibble / Direct |
| STA addr | Store accumulator to memory | 0x2n / 0x21 0xnn | Nibble / Direct |
| ADD addr | Add memory to accumulator | 0x3n / 0x30 0xnn | Nibble / Direct |
| SUB addr | Subtract memory from accumulator | 0x4n / 0x40 0xnn | Nibble / Direct |
| AND addr | Logical AND memory with accumulator | 0x5n / 0x50 0xnn | Nibble / Direct |
| OR addr | Logical OR memory with accumulator | 0x6n / 0x60 0xnn | Nibble / Direct |
| XOR addr | Logical XOR memory with accumulator | 0x7n / 0x70 0xnn | Nibble / Direct |
| JZ addr | Jump if zero flag is set (8-bit) | 0x8n / 0x80 0xnn | Nibble / Direct |
| JNZ addr | Jump if zero flag is clear (8-bit) | 0x9n / 0x90 0xnn | Nibble / Direct |
| JMP addr | Unconditional jump (8-bit) | 0xBn / 0xB0 0xnn | Nibble / Direct |
| CALL addr | Call subroutine | 0xCn / 0xC0 0xnn | Nibble / Direct |
| RET | Return from subroutine | 0xD0 | 1 byte |
| DIV addr | Divide accumulator by memory | 0xEn / 0xE0 0xnn | Nibble / Direct |

#### Multi-Byte Instructions

| Instruction | Description | Encoding | Format |
|-------------|-------------|----------|---------|
| LDI value | Load immediate value into accumulator | 0xA0 0xnn | 2 bytes |
| MUL addr | Multiply accumulator by memory | 0xF1 0xnn | 2 bytes |
| CMP addr | Compare accumulator with memory | 0xF3 0xnn | 2 bytes |
| HLT | Halt the CPU | 0xF0 | 1 byte |
| NOT | Logical NOT of accumulator | 0xF2 | 1 byte |

#### Long Jump Instructions (16-bit addressing)

| Instruction | Description | Encoding | Format |
|-------------|-------------|----------|---------|
| JZ_LONG addr | Jump if zero (16-bit address) | 0xF8 0xHH 0xLL | 3 bytes |
| JMP_LONG addr | Unconditional jump (16-bit address) | 0xF9 0xHH 0xLL | 3 bytes |
| JNZ_LONG addr | Jump if not zero (16-bit address) | 0xFA 0xHH 0xLL | 3 bytes |

#### Indirect Addressing

| Instruction | Description | Encoding | Format |
|-------------|-------------|----------|---------|
| STA [hi,lo] | Store via indirect addressing | 0x20 0xHH 0xLL | 3 bytes |

*Note: For nibble-encoded instructions, when the operand is 0x00-0x0F, it's encoded in the low nibble of the opcode byte. For operands > 0x0F, a second byte is used.*

### Memory Organization

The CPU supports a 16-bit address space (64KB addressable memory, 0x0000-0xFFFF):

- **0x0000-0x00FF**: Low memory (typically used for variables and data)
- **0x0100-0x07FF**: General purpose memory
- **0x0800-0x0FFF**: Display memory (28×80 character display at 0x0800)
- **0x1000+**: Extended memory for programs and data

The stack pointer (SP) is 8-bit and starts at 0xFF, growing downward. For large programs, use position-independent code by loading at higher addresses to avoid conflicts with data in low memory.

**Best Practices:**
- Load large programs at 0x0100 or higher to avoid overwriting low memory variables
- Use the assembler's `base_address` parameter for position-independent code
- Reserve 0x0800-0x0FFF for display memory if using graphics
- Keep critical variables in low memory (0x00-0xFF) for faster access

### Programming the CPU

RHDL includes an assembler that allows you to write assembly code and assemble it into machine code:

```ruby
# Basic program at address 0x0
program = Assembler.build do |p|
  p.label :start
  p.instr :LDI, 0x10      # Load immediate value 0x10 into accumulator
  p.instr :STA, 0x30      # Store accumulator to memory address 0x30
  p.instr :JMP, :start    # Jump back to start
end

# Position-independent program loaded at custom address
program = Assembler.build(0x300) do |p|
  p.label :start
  p.instr :LDI, 0x05
  p.instr :ADD, 0x01
  p.instr :JMP_LONG, :start  # Labels automatically resolve to base_address + offset
end
```

#### Advanced Assembler Features

**Indirect Addressing:**
```ruby
# Store accumulator to address stored in memory locations 0x09 (high) and 0x08 (low)
p.instr :STA, [0x09, 0x08]
```

**Long Jumps (16-bit addresses):**
```ruby
p.instr :JMP_LONG, :distant_label  # Jump to any address in 64KB space
p.instr :JZ_LONG, :target          # Conditional jump with 16-bit address
```

**Position-Independent Code:**
```ruby
# Build program with base address for proper label resolution
program = Assembler.build(0x100) do |p|
  p.label :loop
  p.instr :LDA, 0x00
  p.instr :ADD, 0x01
  p.instr :JMP_LONG, :loop  # Resolves to 0x100 + offset
end

# Load at the specified address
load_program(program, 0x100)
@cpu.instance_variable_set(:@pc, 0x100)
```

### Running Custom Assembly Programs

You can run your custom assembly programs on the CPU using the following approach:

```ruby
require 'rhdl'
require 'support/assembler'

# Create the memory and CPU instances
memory = MemorySimulator::Memory.new
cpu = RHDL::Components::CPU::CPU.new(memory)
cpu.reset

# Define and assemble your program
program = Assembler.build do |p|
  p.label :main
  p.instr :LDI, 0x42        # Load immediate value 0x42 into accumulator
  p.instr :STA, 0x20        # Store it at memory location 0x20
  
  p.instr :LDI, 0x05        # Initialize counter
  p.label :loop
  p.instr :SUB, 0x01        # Decrement counter
  p.instr :JZ, :done        # If counter is zero, jump to done
  p.instr :LDA, 0x20        # Load value from memory
  p.instr :ADD, 0x01        # Increment it
  p.instr :STA, 0x20        # Store it back
  p.instr :JMP, :loop       # Repeat
  
  p.label :done
  p.instr :HLT              # Halt the CPU
end

# Load the program into memory at address 0
memory.load_program(program)

# Run the program until halted
while !cpu.halted
  cpu.step
end

# Check the result at memory location 0x20
puts "Final value: #{memory.read(0x20).to_s(16)}"  # Should print "47"
```

You can also debug your program by examining the CPU state after each instruction:

```ruby
# Step through your program one instruction at a time
cpu.step
puts "PC: 0x#{cpu.pc.to_s(16)}, ACC: 0x#{cpu.acc.to_s(16)}, Zero Flag: #{cpu.zero_flag}"

# Or examine memory at specific locations
puts "Memory at 0x20: 0x#{memory.read(0x20).to_s(16)}"
```

For more complex programs with subroutines and indirect addressing:

```ruby
# Example: Write characters to display using indirect addressing
program = Assembler.build(0x100) do |p|
  # Setup: Store display address (0x0800) in memory locations 0x09 (high), 0x08 (low)
  p.instr :LDI, 0x08        # High byte of 0x0800
  p.instr :STA, 0x09
  p.instr :LDI, 0x00        # Low byte
  p.instr :STA, 0x08

  # Write 'H' to display
  p.label :main
  p.instr :LDI, 'H'.ord
  p.instr :STA, [0x09, 0x08]  # Store via indirect addressing

  # Increment address and write 'i'
  p.instr :LDA, 0x08
  p.instr :ADD, 0x01
  p.instr :STA, 0x08
  p.instr :LDI, 'i'.ord
  p.instr :STA, [0x09, 0x08]

  p.instr :HLT
end

# Load at 0x100
load_program(program, 0x100)
@cpu.instance_variable_set(:@pc, 0x100)
```

### Example: Factorial Calculator

```ruby
# Calculate 5! using a loop
program = Assembler.build do |p|
  p.label :start
  p.instr :LDA, 0xE       # Load N from memory
  p.instr :JZ, :halt      # If zero, halt
  p.instr :MUL, 0xF       # Multiply by result
  p.instr :STA, 0xF       # Store result
  p.instr :LDA, 0xE       # Load N again
  p.instr :SUB, 0xD       # Subtract 1
  p.instr :STA, 0xE       # Store N
  p.instr :JMP, :start    # Loop

  p.label :halt
  p.instr :HLT
end

# Initialize values
memory.write(0xE, 5)   # N = 5
memory.write(0xD, 1)   # Decrement value = 1
memory.write(0xF, 1)   # Result = 1

# Run
load_program(program)
while !cpu.halted
  cpu.step
end

puts "5! = #{memory.read(0xF)}"  # Should print "120"
```

## Running Tests

RHDL uses RSpec for testing. The recommended way to run tests:

### Using the Test Runner Script (Recommended)

```bash
# Run all tests
bin/test

# Run specific test file
bin/test spec/examples/mos6502/cpu_spec.rb

# Run all 6502 CPU tests
bin/test spec/examples/mos6502/

# Run with documentation format
bin/test --format documentation
```

### Using Rake

```bash
# Run all tests
rake spec

# Run 6502 CPU tests
rake spec_6502

# Run with documentation format
rake spec_doc
```

### Using bundle exec (if bundler works)

```bash
bundle exec rspec
bundle exec rspec spec/examples/mos6502/
```

### MOS 6502 CPU Tests

The 6502 CPU implementation has comprehensive test coverage:

```bash
# Run all 6502 tests (189 examples)
bin/test spec/examples/mos6502/
```

Test files:
- `instructions_spec.rb` - All instructions and addressing modes (129 tests)
- `cpu_spec.rb` - Core CPU operations and programs
- `alu_spec.rb` - ALU operations
- `assembler_spec.rb` - Assembly language support
- `algorithms_spec.rb` - Complex algorithms (bubble sort, Fibonacci, etc.)
- `math_spec.rb` - Mathematical operations
- `mandelbrot_spec.rb` - Mandelbrot set computation with fixed-point math
- `game_of_life_spec.rb` - Conway's Game of Life cellular automaton

### Test Suite Status

**Behavioral CPU: All 47 tests passing** ✓
**HDL CPU: All 22 tests passing** ✓

Available test files include:

**Behavioral CPU Tests:**
- `assembler_spec.rb` - Tests the assembler functionality (11 tests)
- `instructions_spec.rb` - Tests individual CPU instructions (22 tests)
- `programs_spec.rb` - Tests various sample programs (5 tests)
- `fractal_spec.rb` - Tests the CPU with a fractal generation program (1 test)
- `conway_spec.rb` - Tests Conway's Game of Life implementation (1 test)

**HDL Tests:**
- `test_hdl_cpu.rb` - Standalone HDL CPU tests (22 tests)
- `spec/rhdl/hdl/gates_spec.rb` - Logic gate tests
- `spec/rhdl/hdl/arithmetic_spec.rb` - Arithmetic component tests
- `spec/rhdl/hdl/sequential_spec.rb` - Sequential component tests
- `spec/rhdl/hdl/cpu_spec.rb` - HDL CPU unit tests

### Complex Integration Tests

The test suite includes two complex integration tests that demonstrate the CPU's capabilities:

**Fractal Test (`fractal_spec.rb`):**
- Generates a simplified Mandelbrot set visualization
- Loads program at 0x100 to avoid memory conflicts
- Writes to display memory at 0x800
- Tests position-independent code and long jumps

**Conway's Game of Life (`conway_spec.rb`):**
- Implements full Game of Life with double-buffering
- Program at 0x300, buffers at 0x100 and 0x200
- Tests subroutines, indirect addressing, and complex control flow
- Simulates multiple generations of cellular automata

## Recent Improvements

### Signal Probing & Debugging
- **SignalProbe**: Records signal transitions over time for waveform viewing
- **WaveformCapture**: Manages multiple probes with VCD export support
- **Breakpoints**: Break on custom conditions or cycle counts
- **Watchpoints**: Break on signal changes, value matches, or edge detection
- **DebugSimulator**: Enhanced simulator with step mode, pause/resume, and state inspection
- **VCD Export**: Export waveforms to Value Change Dump format for GTKWave

### Terminal GUI (TUI)
- Interactive terminal-based simulator interface
- Signal panel with live value display
- Waveform panel with ASCII waveform rendering
- Console panel for status messages
- Breakpoint panel for managing break/watch points
- Command mode for advanced operations (set signals, export VCD, etc.)

### HDL Simulation Framework
- Added complete gate-level simulation engine with signal propagation
- Implemented logic gates (AND, OR, XOR, NOT, NAND, NOR, etc.)
- Added sequential components (D/T/JK/SR flip-flops, registers, counters)
- Created arithmetic units (adders, ALU with 16 operations, comparators)
- Built combinational logic (multiplexers, decoders, encoders, shifters)
- Implemented memory components (RAM, ROM, register file, stack, FIFO)
- Created HDL CPU datapath matching behavioral CPU instruction set
- Added CPUAdapter for behavioral/HDL CPU interoperability

### Instruction Encoding Fixes
- Fixed assembler to output encoded bytes instead of symbols
- Corrected STA instruction encoding (0x20 for indirect, 0x21 for 2-byte direct, 0x2n for nibble-encoded)
- Fixed long jump instructions (JZ_LONG, JMP_LONG, JNZ_LONG) to use full 16-bit addresses
- Implemented variable-length instruction encoding with proper offset calculation

### Assembler Enhancements
- Added `base_address` parameter to `Assembler.build()` for position-independent code
- Implemented indirect addressing for STA instruction: `p.instr :STA, [high_addr, low_addr]`
- Fixed label resolution to work correctly with base addresses
- Added support for 16-bit long jump instructions

### CPU Execution
- Fixed instruction decoding for variable-length instructions
- Corrected PC increment logic for multi-byte instructions
- Improved indirect memory addressing
- Enhanced debug output for troubleshooting

### Test Infrastructure
- Updated display helper to support custom buffer addresses
- Fixed memory overlap issues in integration tests
- All test expectations updated to match corrected instruction encoding

## Known Limitations

- 8-bit ALU limits arithmetic operations (e.g., y*80 overflows for y ≥ 4)
- Fractal test limited to 3 rows due to 8-bit multiplication constraints
- Stack operations limited to 0xFF address space
- No carry/overflow flags in current implementation

### Writing Tests

CPU tests use the `CpuTestHelper` module to simplify test setup. For example:

```ruby
require 'spec_helper'

RSpec.describe RHDL::Components::CPU::CPU do
  include CpuTestHelper

  before(:each) do
    @memory = MemorySimulator::Memory.new
    @cpu = described_class.new(@memory)
    @cpu.reset
  end

  it 'executes a simple program' do
    load_program([
      [:LDI, 0x42],
      [:STA, 0x10],
      [:HLT]
    ])
    run_program
    verify_memory(0x10, 0x42)
    verify_cpu_state(acc: 0x42, pc: 3, halted: true, zero_flag: false, sp: 0xFF)
  end
end
```
