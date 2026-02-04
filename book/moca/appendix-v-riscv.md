# Appendix V: RISC-V Implementation

*Companion appendix to [Chapter 22: RISC-V RV32I](22-riscv.md)*

## Overview

This appendix provides a complete RV32I implementation in RHDL, from instruction decoder to pipelined processor.

---

## Instruction Decoder

```ruby
module RHDL::RISCV
  # RV32I Opcodes
  module Opcodes
    LUI    = 0b0110111
    AUIPC  = 0b0010111
    JAL    = 0b1101111
    JALR   = 0b1100111
    BRANCH = 0b1100011
    LOAD   = 0b0000011
    STORE  = 0b0100011
    OP_IMM = 0b0010011
    OP     = 0b0110011
    FENCE  = 0b0001111
    SYSTEM = 0b1110011
  end

  # Instruction decoder
  class Decoder < SimComponent
    input :instr, width: 32

    # Decoded fields
    output :opcode, width: 7
    output :rd, width: 5
    output :rs1, width: 5
    output :rs2, width: 5
    output :funct3, width: 3
    output :funct7, width: 7

    # Decoded immediate (sign-extended to 32 bits)
    output :imm, width: 32

    # Instruction type signals
    output :is_r_type
    output :is_i_type
    output :is_s_type
    output :is_b_type
    output :is_u_type
    output :is_j_type

    # Control signals
    output :reg_write      # Write to register file
    output :mem_read       # Memory read
    output :mem_write      # Memory write
    output :mem_to_reg     # Memory data to register
    output :alu_src        # ALU source: 0=reg, 1=imm
    output :branch         # Branch instruction
    output :jump           # Jump instruction

    behavior do
      # Extract fixed fields
      opcode <= instr[6:0]
      rd     <= instr[11:7]
      rs1    <= instr[19:15]
      rs2    <= instr[24:20]
      funct3 <= instr[14:12]
      funct7 <= instr[31:25]

      # Determine instruction type
      is_r_type <= (opcode == Opcodes::OP)
      is_i_type <= (opcode == Opcodes::OP_IMM) ||
                   (opcode == Opcodes::LOAD) ||
                   (opcode == Opcodes::JALR)
      is_s_type <= (opcode == Opcodes::STORE)
      is_b_type <= (opcode == Opcodes::BRANCH)
      is_u_type <= (opcode == Opcodes::LUI) ||
                   (opcode == Opcodes::AUIPC)
      is_j_type <= (opcode == Opcodes::JAL)

      # Immediate extraction
      imm <= case opcode
             when Opcodes::OP_IMM, Opcodes::LOAD, Opcodes::JALR
               # I-type: imm[11:0]
               sign_extend(instr[31:20], 12)

             when Opcodes::STORE
               # S-type: imm[11:5|4:0]
               sign_extend((instr[31:25] << 5) | instr[11:7], 12)

             when Opcodes::BRANCH
               # B-type: imm[12|10:5|4:1|11]
               sign_extend((instr[31] << 12) | (instr[7] << 11) |
                          (instr[30:25] << 5) | (instr[11:8] << 1), 13)

             when Opcodes::LUI, Opcodes::AUIPC
               # U-type: imm[31:12]
               instr[31:12] << 12

             when Opcodes::JAL
               # J-type: imm[20|10:1|11|19:12]
               sign_extend((instr[31] << 20) | (instr[19:12] << 12) |
                          (instr[20] << 11) | (instr[30:21] << 1), 21)

             else
               0
             end

      # Control signals
      reg_write  <= is_r_type || is_i_type || is_u_type || is_j_type
      mem_read   <= (opcode == Opcodes::LOAD)
      mem_write  <= (opcode == Opcodes::STORE)
      mem_to_reg <= (opcode == Opcodes::LOAD)
      alu_src    <= is_i_type || is_s_type || is_u_type
      branch     <= (opcode == Opcodes::BRANCH)
      jump       <= (opcode == Opcodes::JAL) || (opcode == Opcodes::JALR)
    end

    private

    def sign_extend(val, bits)
      sign_bit = (val >> (bits - 1)) & 1
      if sign_bit == 1
        val | (~0 << bits)
      else
        val & ((1 << bits) - 1)
      end
    end
  end
end
```

---

## Register File

```ruby
module RHDL::RISCV
  # 32x32-bit register file with x0 hardwired to 0
  class RegisterFile < SimComponent
    input :clk
    input :reset

    # Read ports (combinational)
    input :read_reg1, width: 5
    input :read_reg2, width: 5
    output :read_data1, width: 32
    output :read_data2, width: 32

    # Write port (synchronous)
    input :write_reg, width: 5
    input :write_data, width: 32
    input :write_enable

    # Register storage
    memory :regs, depth: 32, width: 32

    behavior do
      # Reads are combinational
      # x0 always returns 0
      read_data1 <= (read_reg1 == 0) ? 0 : regs[read_reg1]
      read_data2 <= (read_reg2 == 0) ? 0 : regs[read_reg2]

      # Writes on clock edge
      on_rising_edge(:clk) do
        if reset == 1
          32.times { |i| regs[i] <= 0 }
        elsif write_enable == 1 && write_reg != 0
          # Never write to x0
          regs[write_reg] <= write_data
        end
      end
    end
  end
end
```

---

## ALU

```ruby
module RHDL::RISCV
  # ALU operations
  module AluOp
    ADD  = 0b0000
    SUB  = 0b1000
    SLL  = 0b0001
    SLT  = 0b0010
    SLTU = 0b0011
    XOR  = 0b0100
    SRL  = 0b0101
    SRA  = 0b1101
    OR   = 0b0110
    AND  = 0b0111
  end

  class ALU < SimComponent
    input :operand_a, width: 32
    input :operand_b, width: 32
    input :alu_op, width: 4

    output :result, width: 32
    output :zero        # result == 0

    behavior do
      result <= case alu_op
                when AluOp::ADD  then operand_a + operand_b
                when AluOp::SUB  then operand_a - operand_b
                when AluOp::SLL  then operand_a << (operand_b & 0x1F)
                when AluOp::SLT  then signed_lt(operand_a, operand_b) ? 1 : 0
                when AluOp::SLTU then operand_a < operand_b ? 1 : 0
                when AluOp::XOR  then operand_a ^ operand_b
                when AluOp::SRL  then operand_a >> (operand_b & 0x1F)
                when AluOp::SRA  then arithmetic_shr(operand_a, operand_b & 0x1F)
                when AluOp::OR   then operand_a | operand_b
                when AluOp::AND  then operand_a & operand_b
                else 0
                end

      zero <= (result == 0) ? 1 : 0
    end

    private

    def signed_lt(a, b)
      # Convert to signed comparison
      a_signed = (a[31] == 1) ? (a - (1 << 32)) : a
      b_signed = (b[31] == 1) ? (b - (1 << 32)) : b
      a_signed < b_signed
    end

    def arithmetic_shr(val, shamt)
      sign = val[31]
      result = val >> shamt
      if sign == 1
        # Fill with 1s
        mask = ((1 << shamt) - 1) << (32 - shamt)
        result | mask
      else
        result
      end
    end
  end

  # ALU Control unit
  class ALUControl < SimComponent
    input :alu_op, width: 2      # From main control
    input :funct3, width: 3
    input :funct7, width: 7

    output :alu_control, width: 4

    behavior do
      case alu_op
      when 0b00  # Load/Store: ADD
        alu_control <= AluOp::ADD

      when 0b01  # Branch: SUB for comparison
        alu_control <= AluOp::SUB

      when 0b10  # R-type or I-type arithmetic
        case funct3
        when 0b000  # ADD/SUB
          if funct7[5] == 1
            alu_control <= AluOp::SUB
          else
            alu_control <= AluOp::ADD
          end
        when 0b001  # SLL
          alu_control <= AluOp::SLL
        when 0b010  # SLT
          alu_control <= AluOp::SLT
        when 0b011  # SLTU
          alu_control <= AluOp::SLTU
        when 0b100  # XOR
          alu_control <= AluOp::XOR
        when 0b101  # SRL/SRA
          if funct7[5] == 1
            alu_control <= AluOp::SRA
          else
            alu_control <= AluOp::SRL
          end
        when 0b110  # OR
          alu_control <= AluOp::OR
        when 0b111  # AND
          alu_control <= AluOp::AND
        end
      end
    end
  end
end
```

---

## Branch Comparator

```ruby
module RHDL::RISCV
  # Branch condition comparator
  class BranchComparator < SimComponent
    input :rs1_data, width: 32
    input :rs2_data, width: 32
    input :funct3, width: 3

    output :branch_taken

    behavior do
      branch_taken <= case funct3
                      when 0b000  # BEQ
                        rs1_data == rs2_data ? 1 : 0
                      when 0b001  # BNE
                        rs1_data != rs2_data ? 1 : 0
                      when 0b100  # BLT (signed)
                        signed_lt(rs1_data, rs2_data) ? 1 : 0
                      when 0b101  # BGE (signed)
                        !signed_lt(rs1_data, rs2_data) ? 1 : 0
                      when 0b110  # BLTU (unsigned)
                        rs1_data < rs2_data ? 1 : 0
                      when 0b111  # BGEU (unsigned)
                        rs1_data >= rs2_data ? 1 : 0
                      else
                        0
                      end
    end

    private

    def signed_lt(a, b)
      a_signed = (a[31] == 1) ? (a - (1 << 32)) : a
      b_signed = (b[31] == 1) ? (b - (1 << 32)) : b
      a_signed < b_signed
    end
  end
end
```

---

## Single-Cycle Datapath

```ruby
module RHDL::RISCV
  # Single-cycle RV32I processor
  class SingleCycleProcessor < SimComponent
    input :clk
    input :reset

    # Memory interface
    output :imem_addr, width: 32
    input :imem_data, width: 32

    output :dmem_addr, width: 32
    output :dmem_write_data, width: 32
    output :dmem_read, :dmem_write
    input :dmem_read_data, width: 32

    # Debug
    output :pc, width: 32
    output :instr, width: 32

    # Components
    instance :decoder, Decoder
    instance :regfile, RegisterFile
    instance :alu, ALU
    instance :alu_ctrl, ALUControl
    instance :branch_cmp, BranchComparator

    # Program counter
    wire :pc_reg, width: 32
    wire :pc_next, width: 32
    wire :pc_plus_4, width: 32
    wire :pc_branch, width: 32
    wire :pc_jump, width: 32

    # Internal signals
    wire :alu_result, width: 32
    wire :write_back_data, width: 32

    behavior do
      # PC logic
      pc_plus_4 <= pc_reg + 4
      pc_branch <= pc_reg + decoder.imm
      pc_jump <= (decoder.opcode == Opcodes::JALR) ?
                 (alu_result & ~1) : pc_branch

      # Next PC selection
      branch_taken = decoder.branch & branch_cmp.branch_taken
      if decoder.jump == 1
        pc_next <= pc_jump
      elsif branch_taken == 1
        pc_next <= pc_branch
      else
        pc_next <= pc_plus_4
      end

      on_rising_edge(:clk) do
        if reset == 1
          pc_reg <= 0
        else
          pc_reg <= pc_next
        end
      end

      # Instruction fetch
      imem_addr <= pc_reg
      instr <= imem_data
      pc <= pc_reg

      # Decode
      decoder.instr <= imem_data

      # Register read
      regfile.read_reg1 <= decoder.rs1
      regfile.read_reg2 <= decoder.rs2

      # ALU
      alu_ctrl.funct3 <= decoder.funct3
      alu_ctrl.funct7 <= decoder.funct7
      alu_ctrl.alu_op <= decoder.is_r_type ? 0b10 :
                         (decoder.branch ? 0b01 : 0b00)

      alu.operand_a <= regfile.read_data1
      alu.operand_b <= decoder.alu_src ? decoder.imm : regfile.read_data2
      alu.alu_op <= alu_ctrl.alu_control
      alu_result <= alu.result

      # Branch comparison
      branch_cmp.rs1_data <= regfile.read_data1
      branch_cmp.rs2_data <= regfile.read_data2
      branch_cmp.funct3 <= decoder.funct3

      # Memory access
      dmem_addr <= alu_result
      dmem_write_data <= regfile.read_data2
      dmem_read <= decoder.mem_read
      dmem_write <= decoder.mem_write

      # Write back
      write_back_data <= case
                         when decoder.mem_to_reg == 1
                           dmem_read_data
                         when decoder.jump == 1
                           pc_plus_4
                         when decoder.opcode == Opcodes::LUI
                           decoder.imm
                         when decoder.opcode == Opcodes::AUIPC
                           pc_reg + decoder.imm
                         else
                           alu_result
                         end

      regfile.write_reg <= decoder.rd
      regfile.write_data <= write_back_data
      regfile.write_enable <= decoder.reg_write
      regfile.clk <= clk
      regfile.reset <= reset
    end
  end
end
```

---

## 5-Stage Pipeline

```ruby
module RHDL::RISCV
  # Pipeline registers
  class IFIDRegister < SimComponent
    input :clk, :reset, :stall, :flush
    input :pc_in, width: 32
    input :instr_in, width: 32

    output :pc_out, width: 32
    output :instr_out, width: 32

    behavior do
      on_rising_edge(:clk) do
        if reset == 1 || flush == 1
          pc_out <= 0
          instr_out <= 0x00000013  # NOP (addi x0, x0, 0)
        elsif stall == 0
          pc_out <= pc_in
          instr_out <= instr_in
        end
      end
    end
  end

  # Hazard detection unit
  class HazardUnit < SimComponent
    input :id_rs1, width: 5
    input :id_rs2, width: 5
    input :ex_rd, width: 5
    input :ex_mem_read
    input :ex_reg_write

    output :stall
    output :forward_a, width: 2
    output :forward_b, width: 2

    behavior do
      # Load-use hazard detection
      if ex_mem_read == 1 &&
         (ex_rd == id_rs1 || ex_rd == id_rs2) &&
         ex_rd != 0
        stall <= 1
      else
        stall <= 0
      end

      # Forwarding logic would go here
      # forward_a/b: 00=reg, 01=EX/MEM, 10=MEM/WB
    end
  end

  # Pipelined processor (simplified)
  class PipelinedProcessor < SimComponent
    input :clk
    input :reset

    # Memory interfaces
    output :imem_addr, width: 32
    input :imem_data, width: 32
    output :dmem_addr, width: 32
    output :dmem_write_data, width: 32
    output :dmem_read, :dmem_write
    input :dmem_read_data, width: 32

    # Pipeline registers
    instance :if_id, IFIDRegister
    # instance :id_ex, IDEXRegister
    # instance :ex_mem, EXMEMRegister
    # instance :mem_wb, MEMWBRegister

    instance :hazard, HazardUnit
    instance :decoder, Decoder
    instance :regfile, RegisterFile
    instance :alu, ALU

    # Full implementation would include all stages
    # with forwarding and hazard handling
  end
end
```

---

## Sample Programs

### Fibonacci Test

```ruby
describe "RV32I Fibonacci" do
  it "computes fibonacci sequence" do
    cpu = RHDL::RISCV::SingleCycleProcessor.new
    mem = TestMemory.new

    # Load program
    program = assemble(<<~ASM)
      # Fibonacci: compute fib(10)
      addi x10, x0, 10     # n = 10
      addi x11, x0, 0      # fib_prev = 0
      addi x12, x0, 1      # fib_curr = 1
      addi x13, x0, 0      # counter = 0

    loop:
      beq  x13, x10, done  # if counter == n, done
      add  x14, x11, x12   # temp = prev + curr
      addi x11, x12, 0     # prev = curr
      addi x12, x14, 0     # curr = temp
      addi x13, x13, 1     # counter++
      jal  x0, loop        # repeat

    done:
      addi x0, x0, 0       # NOP (result in x12)
    ASM

    mem.load_program(program)
    sim = Simulator.new(cpu, mem)

    sim.run(100)  # Run 100 cycles

    expect(cpu.regfile.regs[12]).to eq(55)  # fib(10) = 55
  end
end
```

---

## Further Resources

- RISC-V Specifications: riscv.org/specifications
- "The RISC-V Reader" by Patterson & Waterman
- PicoRV32 reference implementation

> Return to [Chapter 22](22-riscv.md) for conceptual introduction.
