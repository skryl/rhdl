# RISC-V RV32I CPU Implementation

The `examples/riscv/` directory contains RISC-V RV32I processor implementations demonstrating both single-cycle and pipelined CPU architectures. These examples showcase RHDL's capabilities for building modern 32-bit processors with full Verilog export support.

## Overview

The RISC-V implementation includes:

- **Single-Cycle CPU**: Simple datapath executing one instruction per clock
- **5-Stage Pipelined CPU**: IF-ID-EX-MEM-WB pipeline with hazard handling
- **Full RV32I Base Set**: All 47 base integer instructions
- **Assembler**: Two-pass assembler for RV32I programs
- **Test Harnesses**: Clean testing interfaces

## Quick Start

### Running Tests

```bash
# Run all RISC-V tests
bundle exec rspec spec/examples/riscv/

# Run specific test
bundle exec rspec spec/examples/riscv/cpu_spec.rb
bundle exec rspec spec/examples/riscv/pipeline_spec.rb
```

### Using the CPU

```ruby
require_relative 'examples/riscv/hdl/harness'

harness = RISCV::Harness.new
harness.load_program([
  0x00500093,  # addi x1, x0, 5
  0x00A00113,  # addi x2, x0, 10
  0x002081B3,  # add x3, x1, x2
])
harness.reset!
harness.run_cycles(10)

puts "x1 = #{harness.read_reg(1)}"  # => 5
puts "x2 = #{harness.read_reg(2)}"  # => 10
puts "x3 = #{harness.read_reg(3)}"  # => 15
```

## Architecture: Single-Cycle CPU

### Block Diagram

```
+-----------------------------------------------------------------------------+
|                      RV32I Single-Cycle Datapath                             |
+-----------------------------------------------------------------------------+
|                                                                             |
|  +--------+     +--------+     +----------+     +--------+                  |
|  |   PC   |---->| Inst   |---->| Decoder  |---->|Control |                  |
|  |Register|     | Memory |     |          |     |Signals |                  |
|  +---+----+     +--------+     +----------+     +---+----+                  |
|      |              |                               |                        |
|      |              v                               |                        |
|      |         +--------+                           |                        |
|      |         | ImmGen |                           |                        |
|      |         +---+----+                           |                        |
|      |             |                                |                        |
|  +---+-------------+--------------------------------+----+                   |
|  |                     Datapath Muxes                    |                   |
|  +---+-----------+-------------------+-------------------+                   |
|      |           |                   |                                       |
|      v           v                   v                                       |
|  +-------+   +-------+           +-------+     +--------+                   |
|  |  PC   |   | Reg   |  rs1/rs2  |  ALU  |---->|  Data  |                   |
|  | +4/Br |   | File  |---------->|       |     | Memory |                   |
|  +-------+   | 32x32 |           +-------+     +--------+                   |
|              +-------+               |              |                        |
|                  ^                   v              v                        |
|                  |           +------+------+       |                        |
|                  +-----------| Write Back |<------+                        |
|                              +-------------+                                 |
|                                                                             |
+-----------------------------------------------------------------------------+
```

### Components

| Component | File | Description |
|-----------|------|-------------|
| CPU | `hdl/cpu.rb` | Top-level single-cycle CPU |
| ALU | `hdl/alu.rb` | 32-bit ALU with 12 operations |
| Decoder | `hdl/decoder.rb` | Instruction decoder |
| RegisterFile | `hdl/register_file.rb` | 32x32-bit register file |
| ImmGen | `hdl/imm_gen.rb` | Immediate value generator |
| BranchCond | `hdl/branch_cond.rb` | Branch condition evaluator |
| ProgramCounter | `hdl/program_counter.rb` | PC register |
| Memory | `hdl/memory.rb` | Unified memory model |
| Harness | `hdl/harness.rb` | Test wrapper |

### CPU (`hdl/cpu.rb`)

The main CPU integrates all components using RHDL's declarative DSL.

**Ports:**
```ruby
input :clk
input :rst

# Instruction memory interface
output :inst_addr, width: 32
input :inst_data, width: 32

# Data memory interface
output :data_addr, width: 32
output :data_wdata, width: 32
input :data_rdata, width: 32
output :data_we
output :data_re
output :data_funct3, width: 3

# Debug outputs
output :debug_pc, width: 32
output :debug_inst, width: 32
output :debug_x1, width: 32
output :debug_x2, width: 32
output :debug_x10, width: 32
output :debug_x11, width: 32
```

### ALU (`hdl/alu.rb`)

32-bit ALU supporting all RV32I operations.

**Operations:**

| Code | Operation | Description |
|------|-----------|-------------|
| 0 | ADD | Addition |
| 1 | SUB | Subtraction |
| 2 | SLL | Shift left logical |
| 3 | SLT | Set less than (signed) |
| 4 | SLTU | Set less than (unsigned) |
| 5 | XOR | Bitwise XOR |
| 6 | SRL | Shift right logical |
| 7 | SRA | Shift right arithmetic |
| 8 | OR | Bitwise OR |
| 9 | AND | Bitwise AND |
| 10 | PASS_A | Pass through A |
| 11 | PASS_B | Pass through B |

### Decoder (`hdl/decoder.rb`)

Decodes instructions into control signals.

**Control Signals:**

| Signal | Width | Description |
|--------|-------|-------------|
| opcode | 7 | Instruction opcode |
| rd | 5 | Destination register |
| funct3 | 3 | Function code 3 |
| rs1 | 5 | Source register 1 |
| rs2 | 5 | Source register 2 |
| funct7 | 7 | Function code 7 |
| reg_write | 1 | Register write enable |
| mem_read | 1 | Memory read enable |
| mem_write | 1 | Memory write enable |
| mem_to_reg | 1 | Write memory data to register |
| alu_src | 1 | ALU source select |
| branch | 1 | Branch instruction |
| jump | 1 | Jump instruction |
| jalr | 1 | JALR instruction |
| alu_op | 4 | ALU operation code |

### Immediate Generator (`hdl/imm_gen.rb`)

Generates sign-extended immediate values for all instruction formats.

**Formats:**

| Type | Bits | Used By |
|------|------|---------|
| I | imm[11:0] | Load, ALU immediate, JALR |
| S | imm[11:5], imm[4:0] | Store |
| B | imm[12], imm[10:5], imm[4:1], imm[11] | Branch |
| U | imm[31:12] | LUI, AUIPC |
| J | imm[20], imm[10:1], imm[11], imm[19:12] | JAL |

### Register File (`hdl/register_file.rb`)

32 general-purpose 32-bit registers.

**Features:**
- x0 is hardwired to zero
- Two read ports (rs1, rs2)
- One write port (rd)
- Synchronous write, asynchronous read

## Architecture: Pipelined CPU

### 5-Stage Pipeline

```
+------+    +------+    +------+    +------+    +------+
|  IF  |--->|  ID  |--->|  EX  |--->| MEM  |--->|  WB  |
+------+    +------+    +------+    +------+    +------+
   |           |           |           |           |
   v           v           v           v           v
 Fetch      Decode      Execute     Memory     Write
 Inst       Regs/Imm    ALU/Br      Access     Back
```

### Pipeline Stages

| Stage | Description | Operations |
|-------|-------------|------------|
| IF | Instruction Fetch | PC -> Memory, fetch instruction |
| ID | Instruction Decode | Decode, read registers, generate immediate |
| EX | Execute | ALU operation, branch/jump calculation |
| MEM | Memory Access | Load/store operations |
| WB | Write Back | Write result to register file |

### Pipeline Registers

| Register | File | Contents |
|----------|------|----------|
| IF/ID | `if_id_reg.rb` | PC, instruction |
| ID/EX | `id_ex_reg.rb` | Control signals, rs1/rs2 data, immediate |
| EX/MEM | `ex_mem_reg.rb` | ALU result, memory data, control |
| MEM/WB | `mem_wb_reg.rb` | Memory/ALU result, write enable |

### Hazard Handling

**Data Hazards:**
- **Forwarding Unit** (`forwarding_unit.rb`): Forwards ALU results from EX/MEM and MEM/WB stages
- **Stall Detection**: Detects load-use hazards requiring pipeline stall

**Control Hazards:**
- **Branch Prediction**: Predict not-taken
- **Pipeline Flush**: Flush IF/ID on taken branch

### Pipelined Components

| Component | File | Description |
|-----------|------|-------------|
| PipelinedCPU | `pipeline/pipelined_cpu.rb` | Top-level pipelined CPU |
| PipelinedDatapath | `pipeline/pipelined_datapath.rb` | Datapath with pipeline registers |
| HazardUnit | `pipeline/hazard_unit.rb` | Stall and flush control |
| ForwardingUnit | `pipeline/forwarding_unit.rb` | Data forwarding logic |
| IF/ID Reg | `pipeline/if_id_reg.rb` | IF/ID pipeline register |
| ID/EX Reg | `pipeline/id_ex_reg.rb` | ID/EX pipeline register |
| EX/MEM Reg | `pipeline/ex_mem_reg.rb` | EX/MEM pipeline register |
| MEM/WB Reg | `pipeline/mem_wb_reg.rb` | MEM/WB pipeline register |

## RV32I Instruction Set

### Instruction Formats

```
R-type:  |  funct7  |  rs2  |  rs1  | funct3 |   rd   | opcode |
         |  31-25   | 24-20 | 19-15 | 14-12  |  11-7  |  6-0   |

I-type:  |     imm[11:0]    |  rs1  | funct3 |   rd   | opcode |
         |      31-20       | 19-15 | 14-12  |  11-7  |  6-0   |

S-type:  |imm[11:5] |  rs2  |  rs1  | funct3 |imm[4:0]| opcode |
         |  31-25   | 24-20 | 19-15 | 14-12  |  11-7  |  6-0   |

B-type:  |imm[12|10:5]| rs2 |  rs1  | funct3 |imm[4:1|11]| opcode |
         |   31-25    |24-20| 19-15 | 14-12  |   11-7    |  6-0   |

U-type:  |          imm[31:12]          |   rd   | opcode |
         |            31-12             |  11-7  |  6-0   |

J-type:  |imm[20|10:1|11|19:12]|   rd   | opcode |
         |        31-12        |  11-7  |  6-0   |
```

### Supported Instructions

**R-Type (Register-Register):**

| Instruction | funct7 | funct3 | Description |
|-------------|--------|--------|-------------|
| ADD | 0000000 | 000 | rd = rs1 + rs2 |
| SUB | 0100000 | 000 | rd = rs1 - rs2 |
| SLL | 0000000 | 001 | rd = rs1 << rs2[4:0] |
| SLT | 0000000 | 010 | rd = (rs1 < rs2) ? 1 : 0 (signed) |
| SLTU | 0000000 | 011 | rd = (rs1 < rs2) ? 1 : 0 (unsigned) |
| XOR | 0000000 | 100 | rd = rs1 ^ rs2 |
| SRL | 0000000 | 101 | rd = rs1 >> rs2[4:0] (logical) |
| SRA | 0100000 | 101 | rd = rs1 >> rs2[4:0] (arithmetic) |
| OR | 0000000 | 110 | rd = rs1 | rs2 |
| AND | 0000000 | 111 | rd = rs1 & rs2 |

**I-Type (Immediate):**

| Instruction | funct3 | Description |
|-------------|--------|-------------|
| ADDI | 000 | rd = rs1 + imm |
| SLTI | 010 | rd = (rs1 < imm) ? 1 : 0 (signed) |
| SLTIU | 011 | rd = (rs1 < imm) ? 1 : 0 (unsigned) |
| XORI | 100 | rd = rs1 ^ imm |
| ORI | 110 | rd = rs1 | imm |
| ANDI | 111 | rd = rs1 & imm |
| SLLI | 001 | rd = rs1 << shamt |
| SRLI | 101 | rd = rs1 >> shamt (logical) |
| SRAI | 101 | rd = rs1 >> shamt (arithmetic) |

**Load (I-Type):**

| Instruction | funct3 | Description |
|-------------|--------|-------------|
| LB | 000 | Load byte (sign-extend) |
| LH | 001 | Load halfword (sign-extend) |
| LW | 010 | Load word |
| LBU | 100 | Load byte (zero-extend) |
| LHU | 101 | Load halfword (zero-extend) |

**Store (S-Type):**

| Instruction | funct3 | Description |
|-------------|--------|-------------|
| SB | 000 | Store byte |
| SH | 001 | Store halfword |
| SW | 010 | Store word |

**Branch (B-Type):**

| Instruction | funct3 | Description |
|-------------|--------|-------------|
| BEQ | 000 | Branch if rs1 == rs2 |
| BNE | 001 | Branch if rs1 != rs2 |
| BLT | 100 | Branch if rs1 < rs2 (signed) |
| BGE | 101 | Branch if rs1 >= rs2 (signed) |
| BLTU | 110 | Branch if rs1 < rs2 (unsigned) |
| BGEU | 111 | Branch if rs1 >= rs2 (unsigned) |

**Upper Immediate (U-Type):**

| Instruction | Description |
|-------------|-------------|
| LUI | rd = imm << 12 |
| AUIPC | rd = PC + (imm << 12) |

**Jump:**

| Instruction | Type | Description |
|-------------|------|-------------|
| JAL | J | rd = PC+4; PC = PC + imm |
| JALR | I | rd = PC+4; PC = (rs1 + imm) & ~1 |

## Assembler

The assembler (`utilities/assembler.rb`) supports the full RV32I instruction set.

### Usage

```ruby
require_relative 'examples/riscv/utilities/assembler'

source = <<~ASM
  .text
  .globl _start

  _start:
      addi x1, x0, 5      # x1 = 5
      addi x2, x0, 10     # x2 = 10
      add  x3, x1, x2     # x3 = x1 + x2

  loop:
      beq  x3, x0, done   # if x3 == 0, jump to done
      addi x3, x3, -1     # x3 = x3 - 1
      j    loop           # jump to loop

  done:
      nop
ASM

program = RISCV::Assembler.assemble(source)
# => Array of 32-bit instruction words
```

### Supported Directives

| Directive | Description |
|-----------|-------------|
| `.text` | Code section |
| `.data` | Data section |
| `.globl` | Export symbol |
| `.word` | 32-bit data |
| `.half` | 16-bit data |
| `.byte` | 8-bit data |
| `.space` | Reserve bytes |

### Pseudo-Instructions

| Pseudo | Expansion |
|--------|-----------|
| `nop` | `addi x0, x0, 0` |
| `li rd, imm` | `lui rd, imm[31:12]; addi rd, rd, imm[11:0]` |
| `mv rd, rs` | `addi rd, rs, 0` |
| `j offset` | `jal x0, offset` |
| `jr rs` | `jalr x0, rs, 0` |
| `ret` | `jalr x0, x1, 0` |
| `call offset` | `auipc x1, offset[31:12]; jalr x1, x1, offset[11:0]` |

## Verilog Export

Both CPU implementations support Verilog export.

### Single-Cycle CPU

```ruby
require_relative 'examples/riscv/hdl/cpu'

# Generate full hierarchy
verilog = RISCV::CPU.to_verilog_hierarchy(top_name: 'rv32i_cpu')
File.write('rv32i_cpu.v', verilog)
```

### Pipelined CPU

```ruby
require_relative 'examples/riscv/hdl/pipeline/pipelined_cpu'

verilog = RISCV::Pipeline::PipelinedDatapath.to_verilog
File.write('rv32i_pipeline.v', verilog)
```

### Generated Module Example

```verilog
module riscv_alu(
  input [31:0] a,
  input [31:0] b,
  input [3:0] op,
  output [31:0] result,
  output zero
);
  wire [31:0] add_result = a + b;
  wire [31:0] sub_result = a - b;
  wire [31:0] xor_result = a ^ b;
  // ... (full implementation)

  assign result = (op == 4'd0) ? add_result :
                  (op == 4'd1) ? sub_result :
                  // ... case select
                  add_result;

  assign zero = (result == 32'd0);
endmodule
```

## File Structure

```
examples/riscv/
+-- hdl/                        # Single-cycle CPU
|   +-- cpu.rb                  # Top-level CPU
|   +-- alu.rb                  # 32-bit ALU
|   +-- decoder.rb              # Instruction decoder
|   +-- register_file.rb        # 32x32 register file
|   +-- imm_gen.rb              # Immediate generator
|   +-- branch_cond.rb          # Branch condition
|   +-- program_counter.rb      # PC register
|   +-- memory.rb               # Memory model
|   +-- harness.rb              # Test harness
|   +-- constants.rb            # ISA constants
|   +-- pipeline/               # Pipelined CPU
|       +-- pipelined_cpu.rb    # Top-level pipelined
|       +-- pipelined_datapath.rb # Pipeline datapath
|       +-- hazard_unit.rb      # Hazard detection
|       +-- forwarding_unit.rb  # Data forwarding
|       +-- if_id_reg.rb        # IF/ID register
|       +-- id_ex_reg.rb        # ID/EX register
|       +-- ex_mem_reg.rb       # EX/MEM register
|       +-- mem_wb_reg.rb       # MEM/WB register
|       +-- harness.rb          # Pipeline test harness
+-- utilities/
|   +-- assembler.rb            # RV32I assembler
```

## Performance Comparison

| CPU Type | CPI | Complexity | Use Case |
|----------|-----|------------|----------|
| Single-Cycle | 1 | Low | Education, small designs |
| Pipelined | ~1.2* | Medium | Production, performance |

*Includes stalls for hazards

## Example Programs

### Fibonacci

```asm
    # Compute Fibonacci sequence
    addi x1, x0, 0      # fib(0) = 0
    addi x2, x0, 1      # fib(1) = 1
    addi x3, x0, 10     # n = 10

loop:
    beq  x3, x0, done
    add  x4, x1, x2     # fib(n) = fib(n-1) + fib(n-2)
    mv   x1, x2
    mv   x2, x4
    addi x3, x3, -1
    j    loop

done:
    # x2 contains fib(10) = 55
```

### Memory Copy

```asm
    # Copy 16 bytes from src to dst
    li   x1, 0x1000     # src
    li   x2, 0x2000     # dst
    addi x3, x0, 16     # count

loop:
    beq  x3, x0, done
    lb   x4, 0(x1)      # Load byte
    sb   x4, 0(x2)      # Store byte
    addi x1, x1, 1
    addi x2, x2, 1
    addi x3, x3, -1
    j    loop

done:
    nop
```

## References

- [RISC-V Specification](https://riscv.org/technical/specifications/)
- [Patterson & Hennessy: Computer Organization and Design, RISC-V Edition](https://www.elsevier.com/books/computer-organization-and-design-risc-v-edition/patterson/978-0-12-820331-6)
- [RISC-V Reader](http://www.riscvbook.com/)

## See Also

- [MOS 6502 CPU](mos6502_cpu.md) - 8-bit 6502 implementation
- [Game Boy Emulation](gameboy.md) - SM83 CPU implementation
- [DSL Reference](dsl.md) - RHDL DSL documentation
- [Export](export.md) - Verilog export guide
