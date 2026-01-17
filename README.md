# RHDL (Ruby Hardware Description Language)

RHDL is a Domain Specific Language (DSL) that allows you to design hardware using Ruby's flexible syntax and export to VHDL. It provides a comfortable environment for Ruby developers to create hardware designs with all the power of Ruby's metaprogramming capabilities.

## Features

- **HDL CPU**: A complete 8-bit CPU with gate-level datapath implementation
- **MOS 6502 CPU**: Full 6502 processor implementation with 189+ instruction tests
- **HDL Simulation Framework**: Gate-level simulation with support for combinational and sequential logic
- **Gate-Level Synthesis**: Lower 53 HDL components to primitive gate netlists (AND, OR, XOR, NOT, MUX, DFF)
- **Signal Probing & Debugging**: Waveform capture, breakpoints, watchpoints, and VCD export
- **Terminal GUI**: Interactive terminal-based simulator interface
- **Component Library**: Gates, flip-flops, registers, ALU, memory, and more
- **HDL Export**: Generate synthesizable VHDL and Verilog from Ruby definitions
- **Diagram Generation**: Multi-level circuit diagrams with SVG, PNG, and DOT output
- **Apple II Support**: Memory-mapped I/O for Apple II bus emulation

## Project Structure

```
rhdl/
├── lib/rhdl/           # Core library
│   ├── dsl.rb          # VHDL DSL for component definitions
│   ├── export/         # HDL export backends
│   │   ├── vhdl.rb     # VHDL export
│   │   └── verilog.rb  # Verilog export
│   ├── hdl/            # HDL simulation framework
│   │   ├── simulation.rb    # Core simulation engine
│   │   ├── gates.rb         # Logic gate primitives
│   │   ├── sequential.rb    # Flip-flops, registers, counters
│   │   ├── arithmetic.rb    # Adders, ALU, comparators
│   │   ├── combinational.rb # Multiplexers, decoders
│   │   ├── memory.rb        # RAM, ROM, register files
│   │   ├── debug.rb         # Signal probing & debugging
│   │   ├── tui.rb           # Terminal GUI
│   │   └── cpu/             # HDL CPU (datapath, synth_datapath, decoder)
│   ├── gates/          # Gate-level synthesis (53 components)
│   │   ├── lower.rb    # HDL to gate-level lowering
│   │   ├── ir.rb       # Gate-level intermediate representation
│   │   └── primitives.rb # Gate primitives (AND, OR, XOR, NOT, MUX, DFF)
│   └── diagram/        # Diagram rendering
├── examples/           # Demo scripts
│   ├── mos6502/        # MOS 6502 behavioral CPU
│   └── mos6502s/       # MOS 6502 synthesizable CPU
├── spec/               # Test suite
├── docs/               # Documentation
├── export/             # Generated output files
│   ├── vhdl/           # Generated VHDL files
│   ├── verilog/        # Generated Verilog files
│   └── gates/          # Gate-level JSON netlists
└── diagrams/           # Generated circuit diagrams
```

## Documentation

Detailed documentation is available in the `docs/` directory:

- **[HDL Overview](docs/hdl_overview.md)** - Introduction to the HDL framework architecture
- **[Simulation Engine](docs/simulation_engine.md)** - Core simulation infrastructure and concepts
- **[Components Reference](docs/components.md)** - Complete reference for all HDL components
- **[CPU Datapath](docs/cpu_datapath.md)** - CPU architecture and instruction set details
- **[Debugging Guide](docs/debugging.md)** - Signal probing, breakpoints, and terminal GUI
- **[Diagram Generation](docs/diagrams.md)** - Multi-level circuit diagram generation
- **[HDL Export](docs/hdl_export.md)** - VHDL and Verilog export guide
- **[Gate Level Backend](docs/gate_level_backend.md)** - Gate-level simulation details
- **[Apple II I/O](docs/apple2_io.md)** - Apple II bus and memory-mapped I/O

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

## HDL CPU

RHDL includes a complete 8-bit CPU with a gate-level HDL implementation in `lib/rhdl/hdl/cpu/`. The CPU architecture features:

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

You can run your custom assembly programs on the HDL CPU using the following approach:

```ruby
require 'rhdl'

# Create the HDL CPU instance
cpu = RHDL::HDL::CPU::CPUAdapter.new
cpu.reset

# Define and assemble your program (using raw bytecode for simplicity)
program = [
  0xA0, 0x42,    # LDI 0x42 - Load immediate value 0x42 into accumulator
  0x25,          # STA 0x05 - Store it at memory location 0x05
  0xA0, 0x03,    # LDI 0x03 - Initialize counter
  # loop:
  0x45,          # SUB 0x05 - Subtract value at 0x05 (decrement counter)
  0x8C,          # JZ 0x0C - If zero, jump to done (address 0x0C)
  0xA0, 0x01,    # LDI 0x01 - Load 1
  0xB6,          # JMP 0x06 - Jump back to loop
  # done:
  0xF0           # HLT - Halt the CPU
]

# Load the program into memory at address 0
cpu.memory.load(program, 0)

# Run the program until halted
until cpu.halted
  cpu.step
end

# Check the result
puts "Final ACC: #{cpu.acc.to_s(16)}"
```

You can also debug your program by examining the CPU state after each instruction:

```ruby
# Step through your program one instruction at a time
cpu.step
puts "PC: 0x#{cpu.pc.to_s(16)}, ACC: 0x#{cpu.acc.to_s(16)}, Zero Flag: #{cpu.zero_flag}"

# Or examine memory at specific locations
puts "Memory at 0x20: 0x#{cpu.memory.read(0x20).to_s(16)}"
```

For more complex programs with subroutines and indirect addressing:

```ruby
# Example: Write characters to display using indirect addressing
cpu = RHDL::HDL::CPU::CPUAdapter.new

# Setup: Store display address (0x0800) in memory locations 0x09 (high), 0x08 (low)
program = [
  0xA0, 0x08,       # LDI 0x08 - High byte of 0x0800
  0x29,             # STA 0x09 - Store to address pointer high byte
  0xA0, 0x00,       # LDI 0x00 - Low byte
  0x28,             # STA 0x08 - Store to address pointer low byte
  0xA0, 0x48,       # LDI 0x48 - 'H' character
  0x20, 0x09, 0x08, # STA [0x09, 0x08] - Store via indirect addressing
  0xF0              # HLT
]

cpu.memory.load(program, 0)
until cpu.halted
  cpu.step
end

# Check display memory at 0x0800
puts "Display[0x800]: #{cpu.memory.read(0x800).chr}"  # Should print 'H'
```

### Example: Factorial Calculator

```ruby
# Calculate 5! using a loop
cpu = RHDL::HDL::CPU::CPUAdapter.new

# Program to calculate factorial
# Uses memory: 0x0D = decrement (1), 0x0E = N, 0x0F = result
program = [
  # start:
  0x1E,             # LDA 0x0E - Load N from memory
  0x8C,             # JZ 0x0C - If zero, jump to halt
  0xF1, 0x0F,       # MUL 0x0F - Multiply ACC by result
  0x2F,             # STA 0x0F - Store result
  0x1E,             # LDA 0x0E - Load N again
  0x4D,             # SUB 0x0D - Subtract 1
  0x2E,             # STA 0x0E - Store N
  0xB0,             # JMP 0x00 - Jump to start
  # halt:
  0xF0              # HLT
]

# Initialize values
cpu.memory.write(0x0D, 1)   # Decrement value = 1
cpu.memory.write(0x0E, 5)   # N = 5
cpu.memory.write(0x0F, 1)   # Result = 1

# Load and run
cpu.memory.load(program, 0)
until cpu.halted
  cpu.step
end

puts "5! = #{cpu.memory.read(0x0F)}"  # Should print "120"
```

## Running Tests

RHDL uses RSpec for testing with parallel execution support for faster test runs.

### Parallel Testing (Recommended)

The test suite supports parallel execution using the `parallel_tests` gem. With 16 CPU cores, tests run approximately 40% faster.

```bash
# Run all tests in parallel (auto-detects CPU count)
rake pspec

# Or using the parallel namespace
rake parallel:spec

# Run with specific number of processes
rake parallel:spec_n[8]

# Run 6502 tests in parallel
rake parallel:spec_6502

# Run HDL tests in parallel
rake parallel:spec_hdl
```

For optimal load balancing based on historical test runtimes:
```bash
# First, record test runtimes
rake parallel:prepare

# Then run with runtime-based balancing
rake parallel:spec_balanced
```

### Serial Testing

```bash
# Run all tests (serial)
rake spec

# Run 6502 CPU tests
rake spec_6502

# Run with documentation format
rake spec_doc
```

### Using the Test Runner Script

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

### Using bundle exec

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

**All 586 tests passing** ✓

The HDL CPU implementation is tested using both unit tests and shared examples that verify identical behavior between the HDL and behavioral implementations.

**HDL Tests:**
- `spec/rhdl/hdl/gates_spec.rb` - Logic gate tests
- `spec/rhdl/hdl/arithmetic_spec.rb` - Arithmetic component tests
- `spec/rhdl/hdl/sequential_spec.rb` - Sequential component tests
- `spec/rhdl/hdl/cpu_spec.rb` - HDL CPU unit tests
- `test_hdl_cpu.rb` - Standalone HDL CPU integration tests

**CPU Tests (using shared examples for HDL/behavioral parity):**
- `assembler_spec.rb` - Tests the assembler functionality
- `instructions_spec.rb` - Tests individual CPU instructions
- `programs_spec.rb` - Tests various sample programs
- `fractal_spec.rb` - Tests the CPU with a fractal generation program
- `conway_spec.rb` - Tests Conway's Game of Life implementation

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

### Latest (January 2025)

#### Gate-Level Synthesis
- Complete gate-level lowering for 53 HDL components
- Primitive gates: AND, OR, XOR, NOT, MUX, BUF, CONST, DFF
- Complex algorithms: Array multiplier, restoring divider
- Hierarchical synthesis for SynthDatapath CPU (505 gates, 24 DFFs)
- JSON netlist export with `rake gates:export`
- Statistics with `rake gates:stats`

#### Export Directory Consolidation
- All generated output now in `/export/` directory
- `/export/vhdl/` - Generated VHDL files
- `/export/verilog/` - Generated Verilog files
- `/export/gates/` - Gate-level JSON netlists

#### Multi-Level Diagram Generation
- Hierarchical component diagrams with collapsible buses
- Gate-level netlist export with SVG, PNG, and DOT formats
- Automatic layout and routing for complex circuits

#### HDL Export Enhancements
- Improved VHDL and Verilog export pipeline
- Fixed Verilog resize operations for width mismatches
- Tool-backed export tests for validation

#### MOS 6502 CPU
- Complete 6502 processor implementation
- Fixed RMW (Read-Modify-Write) timing for shift instructions
- Fixed control timing for datapath operations
- 189+ comprehensive instruction tests
- Support for algorithms: bubble sort, Fibonacci, Mandelbrot, Game of Life
- FIG Forth interpreter test coverage

#### Apple II Support
- Memory-mapped I/O for Apple II bus emulation
- Fixed 6502 stack returns and bus loading behavior

### Core Framework

#### Signal Probing & Debugging
- **SignalProbe**: Records signal transitions over time for waveform viewing
- **WaveformCapture**: Manages multiple probes with VCD export support
- **Breakpoints**: Break on custom conditions or cycle counts
- **Watchpoints**: Break on signal changes, value matches, or edge detection
- **DebugSimulator**: Enhanced simulator with step mode, pause/resume, and state inspection
- **VCD Export**: Export waveforms to Value Change Dump format for GTKWave

#### Terminal GUI (TUI)
- Interactive terminal-based simulator interface
- Signal panel with live value display
- Waveform panel with ASCII waveform rendering
- Console panel for status messages
- Breakpoint panel for managing break/watch points
- Command mode for advanced operations (set signals, export VCD, etc.)

### HDL Simulation Framework & CPU
- Complete gate-level simulation engine with signal propagation
- Logic gates (AND, OR, XOR, NOT, NAND, NOR, etc.)
- Sequential components (D/T/JK/SR flip-flops, registers, counters)
- Arithmetic units (adders, ALU with 16 operations, comparators)
- Combinational logic (multiplexers, decoders, encoders, shifters)
- Memory components (RAM, ROM, register file, stack, FIFO)
- HDL CPU datapath with instruction decoder, ALU, program counter, stack pointer
- CPUAdapter providing a clean interface for running programs on the HDL CPU

#### Instruction Encoding & Assembler
- Fixed assembler to output encoded bytes instead of symbols
- Corrected STA instruction encoding (0x20 for indirect, 0x21 for 2-byte direct, 0x2n for nibble-encoded)
- Fixed long jump instructions (JZ_LONG, JMP_LONG, JNZ_LONG) to use full 16-bit addresses
- Variable-length instruction encoding with proper offset calculation
- `base_address` parameter for position-independent code
- Indirect addressing support: `p.instr :STA, [high_addr, low_addr]`

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

CPU tests use the `CpuTestHelper` module to simplify test setup. The helper can test both the HDL CPU and the behavioral reference implementation. For example:

```ruby
require 'spec_helper'

RSpec.describe RHDL::HDL::CPU::CPUAdapter do
  include CpuTestHelper

  before(:each) do
    @memory = MemorySimulator::Memory.new
    use_hdl_cpu!  # Use HDL implementation (use_behavioral_cpu! for reference impl)
    @cpu = cpu_class.new(@memory)
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
