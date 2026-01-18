# CPU Datapath Architecture

This document describes the HDL implementation of the 8-bit CPU datapath.

## Overview

The CPU is an 8-bit accumulator-based architecture with:
- 8-bit data bus
- 16-bit address space (64KB)
- Single accumulator register
- Hardware stack pointer
- Zero flag for conditional branching

## Block Diagram

```
                    ┌──────────────┐
                    │   Memory     │
                    │   (64KB)     │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
        ┌──────────┐  ┌─────────┐  ┌─────────┐
        │ Program  │  │  Data   │  │  Stack  │
        │ Counter  │  │  Bus    │  │ Pointer │
        │  (16b)   │  │  (8b)   │  │  (8b)   │
        └────┬─────┘  └────┬────┘  └────┬────┘
             │             │            │
             ▼             ▼            │
        ┌─────────┐   ┌─────────┐       │
        │Instruc- │   │   ALU   │◄──────┘
        │  tion   │   │  (8b)   │
        │ Decoder │   └────┬────┘
        └────┬────┘        │
             │             ▼
             │        ┌─────────┐
             └───────►│  Accu-  │
                      │ mulator │
                      │  (8b)   │
                      └─────────┘
```

## Components

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

### Memory

64KB RAM with 8-bit data width.

```ruby
@memory = RAM.new("mem", data_width: 8, addr_width: 16)
```

### Instruction Decoder

Decodes opcode byte to control signals.

```ruby
@decoder = InstructionDecoder.new("decoder")
```

## Instruction Set

### Instruction Encoding

| Type | Format | Bytes |
|------|--------|-------|
| Nibble-encoded | `[OPCODE:4][OPERAND:4]` | 1 |
| Immediate | `[OPCODE:8][DATA:8]` | 2 |
| Long address | `[OPCODE:8][ADDR_HI:8][ADDR_LO:8]` | 3 |

### Instruction Table

| Mnemonic | Opcode | Bytes | Description |
|----------|--------|-------|-------------|
| NOP | 0x00 | 1 | No operation |
| LDA n | 0x1n | 1 | Load ACC from memory[n] |
| STA n | 0x2n | 1 | Store ACC to memory[n] |
| STA [hi,lo] | 0x20 hi lo | 3 | Store ACC indirect |
| ADD n | 0x3n | 1 | ACC = ACC + memory[n] |
| SUB n | 0x4n | 1 | ACC = ACC - memory[n] |
| AND n | 0x5n | 1 | ACC = ACC AND memory[n] |
| OR n | 0x6n | 1 | ACC = ACC OR memory[n] |
| XOR n | 0x7n | 1 | ACC = ACC XOR memory[n] |
| JZ n | 0x8n | 1 | Jump to n if zero |
| JNZ n | 0x9n | 1 | Jump to n if not zero |
| LDI imm | 0xA0 imm | 2 | Load immediate to ACC |
| JMP n | 0xBn | 1 | Unconditional jump |
| CALL n | 0xCn | 1 | Call subroutine |
| RET | 0xD0 | 1 | Return from subroutine |
| DIV n | 0xEn | 1 | ACC = ACC / memory[n] |
| HLT | 0xF0 | 1 | Halt CPU |
| MUL addr | 0xF1 addr | 2 | ACC = ACC * memory[addr] |
| NOT | 0xF2 | 1 | ACC = NOT ACC |
| CMP addr | 0xF3 addr | 2 | Compare ACC with memory[addr] |
| JZ_LONG | 0xF8 hi lo | 3 | Long jump if zero |
| JMP_LONG | 0xF9 hi lo | 3 | Long unconditional jump |
| JNZ_LONG | 0xFA hi lo | 3 | Long jump if not zero |

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
    # ALU operation or load
    result = compute_result()
    clock_register(@acc, result)
    @zero_flag = (result == 0) ? 1 : 0
  end

  if decoder.get_output(:mem_write) == 1
    # Store operation
    memory.write(address, acc)
  end

  # 5. Update PC
  new_pc = compute_next_pc()
  clock_register(@pc, new_pc, load: true)
end
```

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

## Memory Map

| Address Range | Description |
|---------------|-------------|
| 0x0000-0x00FF | Low memory (variables) |
| 0x0100-0x07FF | General purpose |
| 0x0800-0x0FFF | Display memory (28x80 chars) |
| 0x1000-0xFFFF | Extended memory |

## Using the CPU

### Direct Datapath Access

```ruby
cpu = RHDL::HDL::CPU::Datapath.new("cpu")

# Reset
cpu.set_input(:rst, 1)
cpu.set_input(:clk, 0); cpu.propagate
cpu.set_input(:clk, 1); cpu.propagate
cpu.set_input(:clk, 0); cpu.propagate
cpu.set_input(:rst, 0); cpu.propagate

# Load program
cpu.write_memory(0, 0xA0)  # LDI
cpu.write_memory(1, 0x42)  # 0x42
cpu.write_memory(2, 0xF0)  # HLT

# Run
until cpu.halted
  cpu.step
end

puts cpu.acc_value  # => 66
```

### Using the CPUAdapter

For compatibility with the behavior CPU interface:

```ruby
memory = MemorySimulator::Memory.new
cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)

# Load program
cpu.memory.load([0xA0, 0x42, 0xF0], 0)

# Run
until cpu.halted
  cpu.step
end

puts cpu.acc  # => 66
puts cpu.pc   # => 2
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

## Testing

The HDL CPU is tested against the behavior CPU using shared examples:

```ruby
# Run all HDL CPU tests
ruby test_hdl_cpu.rb

# Or use RSpec shared examples
describe RHDL::HDL::CPU::CPUAdapter do
  def setup_cpu
    use_hdl_cpu!
  end

  it_behaves_like 'a CPU implementation'
end
```

## Implementation Notes

### Clock Management

The datapath uses manual clock management to avoid issues with automatic propagation:

1. Set clock low
2. Propagate
3. Set clock high
4. Propagate

This ensures proper edge detection in sequential components.

### Reset Sequence

The reset sequence ensures clean initialization:

1. Set clock low, reset high
2. Clock cycle with reset high
3. Set clock low before clearing reset
4. Clear reset and propagate

This avoids triggering unintended cycles when reset is cleared.

### Register Updates

The `clock_register` helper handles differences between register types:

```ruby
def clock_register(reg, value, load: true)
  reg.set_input(:d, value)
  if reg.inputs.key?(:load)
    reg.set_input(:load, load ? 1 : 0)
  else
    reg.set_input(:en, 1)
  end
  # Clock cycle
  reg.set_input(:clk, 0); reg.propagate
  reg.set_input(:clk, 1); reg.propagate
  # Clear control signals
  ...
end
```
