# Appendix F: Register Machine ISA

*Companion appendix to [Chapter 8: Register Machines](08-register-machines.md)*

## Overview

This appendix provides a complete 8-bit instruction set architecture with full RHDL implementation of a register-based CPU, ready to run programs.

## Instruction Set Architecture

### Instruction Formats

```
R-type: [opcode:4][rd:2][rs:2]     - Register operations
I-type: [opcode:4][rd:2][imm:2]    - Immediate operations
J-type: [opcode:4][addr:4]         - Jump operations
```

### Complete Instruction Table

| Opcode | Mnemonic | Format | Operation | Flags |
|--------|----------|--------|-----------|-------|
| 0x0 | NOP | - | No operation | - |
| 0x1 | LDI | I | rd = imm | Z |
| 0x2 | LD | R | rd = mem[rs] | Z |
| 0x3 | ST | R | mem[rd] = rs | - |
| 0x4 | MOV | R | rd = rs | Z |
| 0x5 | ADD | R | rd = rd + rs | Z, C, N |
| 0x6 | SUB | R | rd = rd - rs | Z, C, N |
| 0x7 | AND | R | rd = rd & rs | Z, N |
| 0x8 | OR | R | rd = rd \| rs | Z, N |
| 0x9 | XOR | R | rd = rd ^ rs | Z, N |
| 0xA | NOT | R | rd = ~rd | Z, N |
| 0xB | SHL | R | rd = rd << 1 | Z, C, N |
| 0xC | SHR | R | rd = rd >> 1 | Z, C, N |
| 0xD | JMP | J | PC = addr | - |
| 0xE | JZ | J | if Z: PC = addr | - |
| 0xF | HALT | - | Stop execution | - |

### Flag Register

```
┌─────────────────────────────────────────┐
│           STATUS FLAGS                   │
├─────────────────────────────────────────┤
│                                          │
│   Bit 0: Z (Zero)     - Result is zero   │
│   Bit 1: C (Carry)    - Unsigned overflow│
│   Bit 2: N (Negative) - MSB is set       │
│   Bit 3: V (Overflow) - Signed overflow  │
│                                          │
└─────────────────────────────────────────┘
```

## RHDL Implementations

### Register File

```ruby
class RegisterFile < SimComponent
  input :clk
  input :read_addr1, width: 2   # 4 registers
  input :read_addr2, width: 2
  input :write_addr, width: 2
  input :write_data, width: 8
  input :write_en
  output :read_data1, width: 8
  output :read_data2, width: 8

  register :regs, width: 8, count: 4

  behavior do
    # Reads are combinational
    read_data1 <= regs[read_addr1]
    read_data2 <= regs[read_addr2]

    # Writes are clocked
    on_rising_edge(clk) do
      if write_en
        regs[write_addr] <= write_data
      end
    end
  end
end
```

### ALU

```ruby
class ALU < SimComponent
  input :a, width: 8
  input :b, width: 8
  input :op, width: 4
  output :result, width: 8
  output :zero
  output :carry
  output :negative
  output :overflow

  ALU_ADD = 0
  ALU_SUB = 1
  ALU_AND = 2
  ALU_OR  = 3
  ALU_XOR = 4
  ALU_NOT = 5
  ALU_SHL = 6
  ALU_SHR = 7
  ALU_CMP = 8

  behavior do
    full_result = case op
    when ALU_ADD then a + b
    when ALU_SUB then a - b
    when ALU_AND then a & b
    when ALU_OR  then a | b
    when ALU_XOR then a ^ b
    when ALU_NOT then ~a
    when ALU_SHL then a << 1
    when ALU_SHR then a >> 1
    when ALU_CMP then a - b  # Compare (sets flags only)
    else 0
    end

    result <= full_result & 0xFF
    zero <= (result == 0) ? 1 : 0
    carry <= (full_result > 0xFF) ? 1 : 0
    negative <= result[7]

    # Overflow for signed arithmetic
    a_sign = a[7]
    b_sign = b[7]
    r_sign = result[7]
    overflow <= case op
    when ALU_ADD then (a_sign == b_sign) && (r_sign != a_sign)
    when ALU_SUB then (a_sign != b_sign) && (r_sign != a_sign)
    else 0
    end
  end
end
```

### Simple CPU Core

```ruby
class SimpleCPU < SimComponent
  input :clk
  input :reset
  input :mem_data_in, width: 8
  output :mem_addr, width: 8
  output :mem_data_out, width: 8
  output :mem_write
  output :halted

  # Internal state
  register :pc, width: 8
  register :ir, width: 8          # Instruction register
  register :state, width: 2       # FSM state

  # Register file
  register :regs, width: 8, count: 4

  # Flags
  register :zero_flag
  register :carry_flag
  register :neg_flag

  # State constants
  FETCH   = 0
  DECODE  = 1
  EXECUTE = 2
  HALT    = 3

  behavior do
    on_rising_edge(clk) do
      if reset
        pc <= 0
        state <= FETCH
        zero_flag <= 0
        carry_flag <= 0
        neg_flag <= 0
        4.times { |i| regs[i] <= 0 }
      else
        case state
        when FETCH
          ir <= mem_data_in
          state <= DECODE

        when DECODE
          # Decode happens combinationally
          state <= EXECUTE

        when EXECUTE
          execute_instruction
          if opcode != 0xF  # Not HALT
            pc <= next_pc
            state <= FETCH
          else
            state <= HALT
          end

        when HALT
          # Stay halted
        end
      end
    end

    # Memory interface
    mem_addr <= pc
    mem_write <= 0
    halted <= (state == HALT)
  end

  def opcode
    ir >> 4
  end

  def rd
    (ir >> 2) & 0x3
  end

  def rs
    ir & 0x3
  end

  def imm
    ir & 0x3
  end

  def addr
    ir & 0xF
  end

  def update_flags(result)
    zero_flag <= (result == 0) ? 1 : 0
    neg_flag <= result[7]
  end

  def execute_instruction
    case opcode
    when 0x0  # NOP
      # Nothing

    when 0x1  # LDI rd, imm
      regs[rd] <= imm
      update_flags(imm)

    when 0x2  # LD rd, [rs]
      # Would need additional cycle for memory access
      # Simplified: assume mem_data_in has the value
      regs[rd] <= mem_data_in
      update_flags(mem_data_in)

    when 0x3  # ST [rd], rs
      mem_data_out <= regs[rs]
      mem_addr <= regs[rd]
      mem_write <= 1

    when 0x4  # MOV rd, rs
      regs[rd] <= regs[rs]
      update_flags(regs[rs])

    when 0x5  # ADD rd, rs
      result = regs[rd] + regs[rs]
      carry_flag <= (result > 0xFF) ? 1 : 0
      regs[rd] <= result & 0xFF
      update_flags(result & 0xFF)

    when 0x6  # SUB rd, rs
      result = regs[rd] - regs[rs]
      carry_flag <= (regs[rd] < regs[rs]) ? 1 : 0
      regs[rd] <= result & 0xFF
      update_flags(result & 0xFF)

    when 0x7  # AND rd, rs
      result = regs[rd] & regs[rs]
      regs[rd] <= result
      update_flags(result)

    when 0x8  # OR rd, rs
      result = regs[rd] | regs[rs]
      regs[rd] <= result
      update_flags(result)

    when 0x9  # XOR rd, rs
      result = regs[rd] ^ regs[rs]
      regs[rd] <= result
      update_flags(result)

    when 0xA  # NOT rd
      result = ~regs[rd] & 0xFF
      regs[rd] <= result
      update_flags(result)

    when 0xB  # SHL rd
      carry_flag <= regs[rd][7]
      result = (regs[rd] << 1) & 0xFF
      regs[rd] <= result
      update_flags(result)

    when 0xC  # SHR rd
      carry_flag <= regs[rd][0]
      result = regs[rd] >> 1
      regs[rd] <= result
      update_flags(result)

    # JMP, JZ, HALT handled by next_pc
    end
  end

  def next_pc
    case opcode
    when 0xD  # JMP
      addr
    when 0xE  # JZ
      zero_flag ? addr : (pc + 1)
    else
      pc + 1
    end
  end
end
```

### Complete CPU with Memory

```ruby
class CPUSystem < SimComponent
  input :clk
  input :reset
  output :halted

  instance :cpu, SimpleCPU
  instance :memory, RAM, size: 256

  wire :addr, width: 8
  wire :data_to_mem, width: 8
  wire :data_from_mem, width: 8
  wire :write_en

  # Clock and reset
  port :clk => [[:cpu, :clk], [:memory, :clk]]
  port :reset => [:cpu, :reset]

  # Memory bus
  port [:cpu, :mem_addr] => :addr
  port :addr => [:memory, :addr]
  port [:cpu, :mem_data_out] => :data_to_mem
  port :data_to_mem => [:memory, :data_in]
  port [:memory, :data_out] => :data_from_mem
  port :data_from_mem => [:cpu, :mem_data_in]
  port [:cpu, :mem_write] => :write_en
  port :write_en => [:memory, :write_en]

  # Status
  port [:cpu, :halted] => :halted

  def load_program(bytes)
    bytes.each_with_index do |byte, addr|
      memory.write(addr, byte)
    end
  end
end
```

## Example Programs

### Add Two Numbers

```
; R0 = 5, R1 = 3, R2 = R0 + R1
LDI R0, 5      ; 0x15 - Load 5 into R0
LDI R1, 3      ; 0x19 - Load 3 into R1
MOV R2, R0     ; 0x48 - R2 = R0
ADD R2, R1     ; 0x59 - R2 = R2 + R1
HALT           ; 0xF0 - Stop

Machine code: 15 19 48 59 F0
Result: R2 = 8
```

### Count Down Loop

```
; Count from 5 to 0
LDI R0, 5      ; 0x15 - Counter
LDI R1, 1      ; 0x11 - Decrement value
loop:
SUB R0, R1     ; 0x61 - R0 = R0 - 1
JZ  done       ; 0xE7 - Jump to done if zero
JMP loop       ; 0xD3 - Loop back
done:
HALT           ; 0xF0

Machine code: 15 11 61 E7 D3 F0
```

### Multiply by Addition

```
; R2 = R0 * R1 (using repeated addition)
; Assumes R0, R1 already set
LDI R2, 0      ; 0x18 - Result = 0
LDI R3, 0      ; 0x1C - Counter
loop:
MOV R3, R1     ; 0x4D - Check if counter == R1
SUB R3, R0     ; 0x6C - (we're using R0 as counter limit)
JZ  done       ; 0xE? - If done, exit
ADD R2, R0     ; 0x58 - Result += R0
LDI R3, 1      ; ...  - Increment counter
ADD R1, R3
JMP loop
done:
HALT
```

## Extended ISA (16-bit)

For more capable programs, extend to 16-bit instructions:

### Extended Instruction Format

```
┌───────────────────────────────────────────────────┐
│           16-BIT INSTRUCTION FORMAT                │
├───────────────────────────────────────────────────┤
│                                                    │
│   R-type: [opcode:6][rd:3][rs:3][rt:3][func:1]    │
│   I-type: [opcode:6][rd:3][rs:3][imm:4]           │
│   J-type: [opcode:6][addr:10]                     │
│                                                    │
│   8 registers, larger immediates and addresses     │
│                                                    │
└───────────────────────────────────────────────────┘
```

### Additional Instructions

| Opcode | Mnemonic | Operation |
|--------|----------|-----------|
| 0x10 | ADDI | rd = rs + imm |
| 0x11 | SUBI | rd = rs - imm |
| 0x12 | MUL | rd = rs * rt |
| 0x13 | DIV | rd = rs / rt |
| 0x14 | CMP | flags = rs - rt |
| 0x15 | JNZ | if !Z: PC = addr |
| 0x16 | JC | if C: PC = addr |
| 0x17 | JN | if N: PC = addr |
| 0x18 | CALL | push PC; PC = addr |
| 0x19 | RET | PC = pop |
| 0x1A | PUSH | push rs |
| 0x1B | POP | rd = pop |

## Performance Analysis

### Cycles Per Instruction

| Instruction Type | Cycles |
|------------------|--------|
| ALU operations | 3 (fetch + decode + execute) |
| Memory load | 4 (+ memory access) |
| Memory store | 4 (+ memory access) |
| Jump (taken) | 3 |
| Jump (not taken) | 3 |

### Improving Performance

1. **Pipelining**: Overlap fetch/decode/execute
2. **Branch prediction**: Guess branch outcomes
3. **Caching**: Fast local memory for instructions/data
4. **Superscalar**: Multiple instructions per cycle

## Test Harness

```ruby
class CPUTestbench < SimComponent
  instance :system, CPUSystem

  def run_program(program, max_cycles = 1000)
    system.load_program(program)
    system.set_input(:reset, 1)
    clock_cycle
    system.set_input(:reset, 0)

    cycles = 0
    until system.get_output(:halted) || cycles >= max_cycles
      clock_cycle
      cycles += 1
    end

    cycles
  end

  def get_register(n)
    system.cpu.regs[n]
  end
end
```

## Further Resources

- Patterson & Hennessy, *Computer Organization and Design*
- RISC-V ISA specification
- MIPS architecture reference

> Return to [Chapter 8](08-register-machines.md) for conceptual introduction.
