# Sample 8-bit CPU

This document provides comprehensive documentation for the 8-bit sample CPU implementation in RHDL, including architecture, instruction set, and datapath details.

## Overview

RHDL includes a complete 8-bit CPU with a gate-level HDL implementation in `lib/rhdl/hdl/cpu/`. The architecture features:

- 8-bit data bus and 16-bit address space (64KB addressable memory)
- Single accumulator (ACC) register
- ALU supporting basic operations (ADD, SUB, AND, OR, XOR, NOT, MUL, DIV, CMP)
- Zero flag for conditional operations
- 8-bit stack pointer (SP) with stack operations
- 16-bit program counter (PC) supporting long jumps
- Control unit for instruction decoding and execution
- Variable-length instruction encoding (1-byte, 2-byte, and 3-byte instructions)
- Nibble-encoded instructions for compact code
- Direct and indirect addressing modes

## Block Diagram

```
                    +---------------+
                    |    Memory     |
                    |    (64KB)     |
                    +-------+-------+
                            |
              +-------------+-------------+
              |             |             |
              v             v             v
        +----------+  +---------+  +---------+
        | Program  |  |  Data   |  |  Stack  |
        | Counter  |  |  Bus    |  | Pointer |
        |  (16b)   |  |  (8b)   |  |  (8b)   |
        +----+-----+  +----+----+  +----+----+
             |             |            |
             v             v            |
        +---------+   +---------+       |
        |Instruc- |   |   ALU   |<------+
        |  tion   |   |  (8b)   |
        | Decoder |   +----+----+
        +----+----+        |
             |             v
             |        +---------+
             +------->|  Accu-  |
                      | mulator |
                      |  (8b)   |
                      +---------+
```

## Datapath Components

### Program Counter (PC)

16-bit register for instruction address.

```ruby
@pc = ProgramCounter.new("pc", width: 16)
```

Operations:
- **Reset**: Set to 0
- **Load**: Load new address (for jumps)
- **Increment**: Add instruction length (1, 2, or 3)

### Accumulator (ACC)

8-bit main working register.

```ruby
@acc = Register.new("acc", width: 8)
```

All arithmetic and logical operations use the accumulator as one operand and store results back.

### ALU

8-bit arithmetic logic unit.

```ruby
@alu = ALU.new("alu", width: 8)
```

Supports:
- Arithmetic: ADD, SUB, MUL, DIV
- Logical: AND, OR, XOR, NOT
- Comparison (via SUB for flag setting)

### Stack Pointer (SP)

8-bit stack pointer initialized to 0xFF.

```ruby
@sp = StackPointer.new("sp", width: 8, initial: 0xFF)
```

Stack grows downward:
- **PUSH**: Decrement SP, write to memory[SP]
- **POP**: Read from memory[SP], increment SP

### Instruction Decoder

Decodes opcode byte to control signals.

```ruby
@decoder = InstructionDecoder.new("decoder")
```

## Instruction Set

### Nibble-Encoded Instructions

For operands 0x00-0x0F, the value is encoded in the low nibble of the opcode byte. For operands > 0x0F, a second byte is used.

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

### Multi-Byte Instructions

| Instruction | Description | Encoding | Format |
|-------------|-------------|----------|---------|
| LDI value | Load immediate value into accumulator | 0xA0 0xnn | 2 bytes |
| MUL addr | Multiply accumulator by memory | 0xF1 0xnn | 2 bytes |
| CMP addr | Compare accumulator with memory | 0xF3 0xnn | 2 bytes |
| HLT | Halt the CPU | 0xF0 | 1 byte |
| NOT | Logical NOT of accumulator | 0xF2 | 1 byte |

### Long Jump Instructions (16-bit addressing)

| Instruction | Description | Encoding | Format |
|-------------|-------------|----------|---------|
| JZ_LONG addr | Jump if zero (16-bit address) | 0xF8 0xHH 0xLL | 3 bytes |
| JMP_LONG addr | Unconditional jump (16-bit address) | 0xF9 0xHH 0xLL | 3 bytes |
| JNZ_LONG addr | Jump if not zero (16-bit address) | 0xFA 0xHH 0xLL | 3 bytes |

### Indirect Addressing

| Instruction | Description | Encoding | Format |
|-------------|-------------|----------|---------|
| STA [hi,lo] | Store via indirect addressing | 0x20 0xHH 0xLL | 3 bytes |

## Control Signals

The instruction decoder generates these control signals:

| Signal | Width | Description |
|--------|-------|-------------|
| alu_op | 4 | ALU operation code |
| alu_src | 1 | 0=memory, 1=immediate |
| reg_write | 1 | Write to accumulator |
| mem_read | 1 | Read from memory |
| mem_write | 1 | Write to memory |
| branch | 1 | Conditional branch |
| jump | 1 | Unconditional jump |
| pc_src | 2 | PC source (0=+len, 1=short, 2=long) |
| halt | 1 | Halt CPU |
| call | 1 | Call subroutine |
| ret | 1 | Return from subroutine |
| instr_length | 2 | Instruction length (1, 2, or 3) |

## Memory Organization

The CPU supports a 16-bit address space (64KB addressable memory, 0x0000-0xFFFF):

| Address Range | Description |
|---------------|-------------|
| 0x0000-0x00FF | Low memory (typically used for variables and data) |
| 0x0100-0x07FF | General purpose memory |
| 0x0800-0x0FFF | Display memory (28x80 character display at 0x0800) |
| 0x1000+ | Extended memory for programs and data |

**Best Practices:**
- Load large programs at 0x0100 or higher to avoid overwriting low memory variables
- Use the assembler's `base_address` parameter for position-independent code
- Reserve 0x0800-0x0FFF for display memory if using graphics
- Keep critical variables in low memory (0x00-0xFF) for faster access

## Execution Cycle

The CPU executes instructions in a single-cycle model:

```ruby
def execute_cycle
  # 1. Fetch instruction at PC
  instruction = memory.read(pc)

  # 2. Decode instruction
  decoder.set_input(:instruction, instruction)
  decoder.propagate

  # 3. Fetch additional bytes if needed
  case decoder.get_output(:instr_length)
  when 2 then operand = memory.read(pc + 1)
  when 3 then operand = (memory.read(pc + 1) << 8) | memory.read(pc + 2)
  end

  # 4. Execute based on control signals
  if decoder.get_output(:reg_write) == 1
    result = compute_result()
    clock_register(@acc, result)
    @zero_flag = (result == 0) ? 1 : 0
  end

  if decoder.get_output(:mem_write) == 1
    memory.write(address, acc)
  end

  # 5. Update PC
  new_pc = compute_next_pc()
  clock_register(@pc, new_pc, load: true)
end
```

## Using the CPU

### With CPUAdapter

The `CPUAdapter` provides a clean interface for running programs:

```ruby
require 'rhdl'

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

### CPUAdapter Interface

| Method | Description |
|--------|-------------|
| `reset` | Reset CPU to initial state |
| `step` | Execute one instruction |
| `acc` | Get accumulator value |
| `pc` | Get program counter |
| `sp` | Get stack pointer |
| `halted` | Check if CPU is halted |
| `zero_flag` | Get zero flag state |
| `memory` | Access memory adapter |

### Direct CPU Access

For lower-level control, access the CPU component through port methods:

```ruby
cpu = RHDL::HDL::CPU::CPU.new("cpu")

# Reset
cpu.set_input(:rst, 1)
cpu.set_input(:clk, 0); cpu.propagate
cpu.set_input(:clk, 1); cpu.propagate
cpu.set_input(:clk, 0); cpu.propagate
cpu.set_input(:rst, 0); cpu.propagate

# Set instruction and propagate
cpu.set_input(:instruction, 0xA0)  # LDI opcode
cpu.set_input(:zero_flag_in, 0)
cpu.propagate

# Read control signals from decoder outputs
puts cpu.get_output(:dec_alu_op)    # ALU operation
puts cpu.get_output(:dec_reg_write) # Register write enable
puts cpu.get_output(:pc_out)        # Program counter value
puts cpu.get_output(:acc_out)       # Accumulator value
```

For complete program execution, use the Harness which manages memory and control flow.

## Programming with the Assembler

RHDL includes an assembler for writing programs:

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

### Advanced Assembler Features

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

## Example Programs

### Simple Addition

```ruby
program = [
  0xA0, 0x05,  # LDI 5
  0x2A,        # STA 10
  0xA0, 0x03,  # LDI 3
  0x3A,        # ADD 10
  0x2B,        # STA 11
  0xF0         # HLT
]
# Result: memory[10]=5, memory[11]=8
```

### Countdown Loop

```ruby
program = [
  0xA0, 0x05,  # LDI 5        ; Start at 5
  0x2F,        # STA 15       ; Store counter
  0x4E,        # SUB 14       ; Subtract 1 (memory[14]=1)
  0x92,        # JNZ 2        ; Loop if not zero
  0xF0         # HLT
]
memory[14] = 1  # Decrement value
# Result: ACC=0 after 5 iterations
```

### Subroutine Call

```ruby
program = [
  0xA0, 0x05,  # 0: LDI 5
  0xC5,        # 2: CALL 5
  0xF0,        # 3: HLT
  0x00,        # 4: NOP (padding)
  0x3F,        # 5: ADD 15    ; Subroutine
  0xD0         # 6: RET
]
memory[15] = 10
# Result: ACC = 5 + 10 = 15
```

### Factorial Calculator

```ruby
cpu = RHDL::HDL::CPU::CPUAdapter.new

# Uses memory: 0x0D = decrement (1), 0x0E = N, 0x0F = result
program = [
  0x1E,             # LDA 0x0E - Load N from memory
  0x8C,             # JZ 0x0C - If zero, jump to halt
  0xF1, 0x0F,       # MUL 0x0F - Multiply ACC by result
  0x2F,             # STA 0x0F - Store result
  0x1E,             # LDA 0x0E - Load N again
  0x4D,             # SUB 0x0D - Subtract 1
  0x2E,             # STA 0x0E - Store N
  0xB0,             # JMP 0x00 - Jump to start
  0xF0              # HLT
]

cpu.memory.write(0x0D, 1)   # Decrement value = 1
cpu.memory.write(0x0E, 5)   # N = 5
cpu.memory.write(0x0F, 1)   # Result = 1
cpu.memory.load(program, 0)

until cpu.halted
  cpu.step
end

puts "5! = #{cpu.memory.read(0x0F)}"  # => 120
```

## Implementation Notes

### Clock Management

The datapath uses manual clock management:

1. Set clock low
2. Propagate
3. Set clock high
4. Propagate

This ensures proper edge detection in sequential components.

### Reset Sequence

1. Set clock low, reset high
2. Clock cycle with reset high
3. Set clock low before clearing reset
4. Clear reset and propagate

### Known Limitations

- 8-bit ALU limits arithmetic operations (e.g., y*80 overflows for y >= 4)
- Stack operations limited to 0xFF address space
- No carry/overflow flags in current implementation

## See Also

- [Components Reference](components.md) - All HDL components
- [Debugging Guide](debugging.md) - Signal probing and debugging
- [MOS 6502](mos6502_cpu.md) - Full 6502 implementation example
