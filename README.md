# RHDL (Ruby Hardware Description Language)

RHDL is a Domain Specific Language (DSL) that allows you to design hardware using Ruby's flexible syntax and export to VHDL. It provides a comfortable environment for Ruby developers to create hardware designs with all the power of Ruby's metaprogramming capabilities.

RHDL includes a simple 8-bit CPU architecture designed for educational purposes. The CPU features:

- 8-bit data bus and 16-bit address space
- Single accumulator (ACC) register
- Simple ALU supporting basic operations (ADD, SUB, AND, OR, XOR, NOT, MUL, DIV)
- Zero flag for conditional operations
- 8-bit stack pointer (SP) with stack operations
- Program counter (PC) for instruction sequencing
- Control unit for instruction decoding and execution

### Instruction Set

The CPU implements the following instructions:

| Instruction | Description | Encoding |
|-------------|-------------|----------|
| NOP | No operation | 0x00 |
| LDA | Load accumulator from memory | 0x10 |
| STA | Store accumulator to memory | 0x21 |
| ADD | Add memory to accumulator | 0x30 |
| SUB | Subtract memory from accumulator | 0x40 |
| AND | Logical AND memory with accumulator | 0x50 |
| OR | Logical OR memory with accumulator | 0x60 |
| XOR | Logical XOR memory with accumulator | 0x70 |
| JZ | Jump if zero flag is set | 0x80 |
| JNZ | Jump if zero flag is clear | 0x90 |
| LDI | Load immediate value into accumulator | 0xA0 |
| JMP | Unconditional jump | 0xB0 |
| CALL | Call subroutine | 0xC0 |
| RET | Return from subroutine | 0xD0 |
| DIV | Divide accumulator by memory | 0xE0 |
| HLT | Halt the CPU | 0xF0 |
| MUL | Multiply accumulator by memory | 0xF1 |
| NOT | Logical NOT of accumulator | 0xF2 |

### Memory Organization

The CPU can address up to 256 memory locations (0x00-0xFF). The stack starts at 0xFF and grows downward.

### Programming the CPU

RHDL includes an assembler that allows you to write assembly code and assemble it into machine code:

```ruby
program = Assembler.build do |p|
  p.label :start
  p.instr :LDI, 0x10  # Load immediate value 0x10 into accumulator
  p.instr :STA, 0x30  # Store accumulator to memory address 0x30
  p.instr :JMP, :start  # Jump back to start
end
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

For more complex programs, you can define helper functions to make your assembly code more modular:

```ruby
program = Assembler.build do |p|
  # Define a helper function to print a character to console
  p.label :print_char
  p.instr :STA, 0x80        # Store character at display address 0x80
  p.instr :RET              # Return from function
  
  # Main program
  p.label :main
  p.instr :LDI, 'H'.ord     # Load ASCII value for 'H'
  p.instr :CALL, :print_char
  p.instr :LDI, 'i'.ord     # Load ASCII value for 'i'
  p.instr :CALL, :print_char
  p.instr :HLT              # Halt the CPU
end
```

## Running Tests

RHDL uses RSpec for testing. To run all tests:

```bash
bundle exec rspec
```

To run only the CPU-related tests:

```bash
bundle exec rspec spec/rhdl/cpu
```

Available test files include:

- `instructions_spec.rb` - Tests individual CPU instructions
- `fractal_spec.rb` - Tests the CPU with a fractal generation program
- `assembler_spec.rb` - Tests the assembler functionality
- `conway_spec.rb` - Tests the CPU with Conway's Game of Life implementation
- `programs_spec.rb` - Tests various sample programs

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
