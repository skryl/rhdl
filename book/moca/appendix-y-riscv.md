# Appendix Y: RISC-V Implementation

*Companion appendix to [Chapter 25: RISC-V RV32I](25-riscv.md)*

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

## Cache

A direct-mapped cache for the RISC-V processor.

```ruby
module RHDL::RISCV
  # Direct-mapped cache
  # Simple but illustrates key concepts
  class DirectMappedCache < SimComponent
    parameter :cache_size, default: 1024   # Bytes
    parameter :line_size, default: 16      # Bytes per line
    parameter :addr_width, default: 32

    input :clk
    input :reset

    # CPU interface
    input :cpu_addr, width: :addr_width
    input :cpu_write_data, width: 32
    input :cpu_read
    input :cpu_write
    output :cpu_read_data, width: 32
    output :cpu_ready          # Transaction complete

    # Memory interface
    output :mem_addr, width: :addr_width
    output :mem_write_data, width: 32
    output :mem_read
    output :mem_write
    input :mem_read_data, width: 32
    input :mem_ready

    # Cache geometry (computed from parameters)
    NUM_LINES = cache_size / line_size
    OFFSET_BITS = Math.log2(line_size).to_i
    INDEX_BITS = Math.log2(NUM_LINES).to_i
    TAG_BITS = addr_width - INDEX_BITS - OFFSET_BITS

    # Cache storage
    memory :tags, depth: NUM_LINES, width: TAG_BITS
    memory :data, depth: NUM_LINES * (line_size / 4), width: 32
    memory :valid, depth: NUM_LINES, width: 1
    memory :dirty, depth: NUM_LINES, width: 1

    # State machine
    IDLE = 0
    COMPARE_TAG = 1
    WRITEBACK = 2
    ALLOCATE = 3

    wire :state, width: 3
    wire :addr_tag, width: TAG_BITS
    wire :addr_index, width: INDEX_BITS
    wire :addr_offset, width: OFFSET_BITS
    wire :line_counter, width: 4

    behavior do
      # Address breakdown
      addr_offset <= cpu_addr[OFFSET_BITS-1:0]
      addr_index <= cpu_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS]
      addr_tag <= cpu_addr[addr_width-1:OFFSET_BITS+INDEX_BITS]

      # Default outputs
      cpu_ready <= 0
      mem_read <= 0
      mem_write <= 0

      on_rising_edge(:clk) do
        if reset == 1
          state <= IDLE
          NUM_LINES.times { |i| valid[i] <= 0; dirty[i] <= 0 }
        else
          case state
          when IDLE
            if cpu_read == 1 || cpu_write == 1
              state <= COMPARE_TAG
            end

          when COMPARE_TAG
            if valid[addr_index] == 1 && tags[addr_index] == addr_tag
              # Cache hit!
              if cpu_read == 1
                word_index = addr_index * (line_size / 4) + (addr_offset >> 2)
                cpu_read_data <= data[word_index]
                cpu_ready <= 1
                state <= IDLE
              else  # Write
                word_index = addr_index * (line_size / 4) + (addr_offset >> 2)
                data[word_index] <= cpu_write_data
                dirty[addr_index] <= 1
                cpu_ready <= 1
                state <= IDLE
              end
            else
              # Cache miss
              if valid[addr_index] == 1 && dirty[addr_index] == 1
                # Need to writeback first
                state <= WRITEBACK
                line_counter <= 0
              else
                # Can allocate directly
                state <= ALLOCATE
                line_counter <= 0
              end
            end

          when WRITEBACK
            # Write dirty line back to memory
            mem_write <= 1
            old_addr = (tags[addr_index] << (INDEX_BITS + OFFSET_BITS)) |
                       (addr_index << OFFSET_BITS) |
                       (line_counter << 2)
            mem_addr <= old_addr
            word_index = addr_index * (line_size / 4) + line_counter
            mem_write_data <= data[word_index]

            if mem_ready == 1
              if line_counter == (line_size / 4) - 1
                state <= ALLOCATE
                line_counter <= 0
                dirty[addr_index] <= 0
              else
                line_counter <= line_counter + 1
              end
            end

          when ALLOCATE
            # Fetch new line from memory
            mem_read <= 1
            mem_addr <= (addr_tag << (INDEX_BITS + OFFSET_BITS)) |
                        (addr_index << OFFSET_BITS) |
                        (line_counter << 2)

            if mem_ready == 1
              word_index = addr_index * (line_size / 4) + line_counter
              data[word_index] <= mem_read_data

              if line_counter == (line_size / 4) - 1
                # Line fully loaded
                tags[addr_index] <= addr_tag
                valid[addr_index] <= 1
                state <= COMPARE_TAG  # Now will hit
              else
                line_counter <= line_counter + 1
              end
            end
          end
        end
      end
    end
  end
end
```

### Set-Associative Cache

```ruby
module RHDL::RISCV
  # N-way set-associative cache with LRU replacement
  class SetAssociativeCache < SimComponent
    parameter :cache_size, default: 4096   # Total bytes
    parameter :line_size, default: 32      # Bytes per line
    parameter :associativity, default: 4   # N-way
    parameter :addr_width, default: 32

    input :clk
    input :reset

    # CPU interface
    input :cpu_addr, width: :addr_width
    input :cpu_write_data, width: 32
    input :cpu_read, :cpu_write
    output :cpu_read_data, width: 32
    output :hit, :miss
    output :ready

    # Memory interface (same as direct-mapped)
    output :mem_addr, width: :addr_width
    output :mem_write_data, width: 32
    output :mem_read, :mem_write
    input :mem_read_data, width: 32
    input :mem_ready

    # Geometry
    NUM_SETS = cache_size / (line_size * associativity)
    OFFSET_BITS = Math.log2(line_size).to_i
    INDEX_BITS = Math.log2(NUM_SETS).to_i
    TAG_BITS = addr_width - INDEX_BITS - OFFSET_BITS
    WORDS_PER_LINE = line_size / 4

    # Storage: arrays for each way
    # tags[set][way], data[set][way][word], valid[set][way], dirty[set][way]
    memory :tags, depth: NUM_SETS * associativity, width: TAG_BITS
    memory :data, depth: NUM_SETS * associativity * WORDS_PER_LINE, width: 32
    memory :valid, depth: NUM_SETS * associativity, width: 1
    memory :dirty, depth: NUM_SETS * associativity, width: 1

    # LRU tracking (simplified: 4-way needs 3 bits per set)
    memory :lru, depth: NUM_SETS, width: 8

    wire :addr_tag, width: TAG_BITS
    wire :addr_index, width: INDEX_BITS
    wire :addr_offset, width: OFFSET_BITS

    # Hit detection wires (one per way)
    wire :way_hit, width: associativity
    wire :hit_way, width: 3  # Which way hit

    behavior do
      # Address breakdown
      addr_offset <= cpu_addr[OFFSET_BITS-1:0]
      addr_index <= cpu_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS]
      addr_tag <= cpu_addr[addr_width-1:OFFSET_BITS+INDEX_BITS]

      # Parallel tag comparison (CAM-like!)
      hit_any = 0
      associativity.times do |way|
        entry = addr_index * associativity + way
        if valid[entry] == 1 && tags[entry] == addr_tag
          way_hit[way] <= 1
          hit_way <= way
          hit_any = 1
        else
          way_hit[way] <= 0
        end
      end

      hit <= hit_any
      miss <= (cpu_read | cpu_write) & ~hit_any

      # On hit, return data immediately (combinational read)
      if hit_any == 1
        word_addr = (addr_index * associativity + hit_way) * WORDS_PER_LINE +
                    (addr_offset >> 2)
        cpu_read_data <= data[word_addr]
      end

      # LRU update and replacement logic in sequential block
      on_rising_edge(:clk) do
        if hit_any == 1
          update_lru(addr_index, hit_way)
        end
        # ... rest of cache logic (writeback, allocate, etc.)
      end
    end

    def update_lru(set, accessed_way)
      # Pseudo-LRU or true LRU implementation
      # For 4-way: use tree-based pseudo-LRU (3 bits)
    end

    def get_lru_way(set)
      # Return the least-recently-used way
    end
  end
end
```

---

## Translation Lookaside Buffer (TLB)

The TLB is essentially a **CAM** (Content-Addressable Memory) that translates virtual page numbers to physical page numbers.

```ruby
module RHDL::RISCV
  # Fully-associative TLB (pure CAM)
  class TLB < SimComponent
    parameter :num_entries, default: 32
    parameter :vpn_width, default: 20     # Virtual page number (32-bit addr, 4KB pages)
    parameter :ppn_width, default: 20     # Physical page number
    parameter :asid_width, default: 9     # Address Space ID (for process isolation)

    input :clk
    input :reset

    # Lookup interface (combinational)
    input :vpn, width: :vpn_width
    input :asid, width: :asid_width
    output :ppn, width: :ppn_width
    output :hit
    output :permission, width: 4  # R/W/X/U bits

    # Management interface
    input :write_enable
    input :write_vpn, width: :vpn_width
    input :write_ppn, width: :ppn_width
    input :write_asid, width: :asid_width
    input :write_perm, width: 4
    input :invalidate_all
    input :invalidate_asid

    # TLB entry storage
    memory :entry_vpn, depth: num_entries, width: vpn_width
    memory :entry_ppn, depth: num_entries, width: ppn_width
    memory :entry_asid, depth: num_entries, width: asid_width
    memory :entry_perm, depth: num_entries, width: 4
    memory :entry_valid, depth: num_entries, width: 1

    # Replacement pointer (round-robin or random)
    wire :replace_ptr, width: 8

    # Match results (CAM output)
    wire :match, width: num_entries

    behavior do
      # === CAM Lookup: All entries compared in parallel! ===
      hit_found = 0
      hit_entry = 0

      num_entries.times do |i|
        # Compare VPN and ASID (or global bit)
        vpn_match = (entry_vpn[i] == vpn)
        asid_match = (entry_asid[i] == asid) || (entry_perm[i][3] == 1)  # Global bit

        if entry_valid[i] == 1 && vpn_match && asid_match
          match[i] <= 1
          hit_found = 1
          hit_entry = i
        else
          match[i] <= 0
        end
      end

      # Output results
      hit <= hit_found
      if hit_found == 1
        ppn <= entry_ppn[hit_entry]
        permission <= entry_perm[hit_entry]
      else
        ppn <= 0
        permission <= 0
      end

      # === Sequential: Write and invalidate ===
      on_rising_edge(:clk) do
        if reset == 1 || invalidate_all == 1
          num_entries.times { |i| entry_valid[i] <= 0 }
          replace_ptr <= 0

        elsif invalidate_asid == 1
          # Invalidate all entries matching ASID
          num_entries.times do |i|
            if entry_asid[i] == asid && entry_perm[i][3] == 0
              entry_valid[i] <= 0
            end
          end

        elsif write_enable == 1
          # Write new entry (replace at replace_ptr)
          entry_vpn[replace_ptr] <= write_vpn
          entry_ppn[replace_ptr] <= write_ppn
          entry_asid[replace_ptr] <= write_asid
          entry_perm[replace_ptr] <= write_perm
          entry_valid[replace_ptr] <= 1

          # Advance replacement pointer
          replace_ptr <= (replace_ptr + 1) % num_entries
        end
      end
    end
  end
end
```

### RISC-V Sv32 Page Table Entry

```ruby
module RHDL::RISCV
  # Sv32 page table entry format
  # 32-bit PTE: [PPN[1] | PPN[0] | RSW | D | A | G | U | X | W | R | V]
  class PageTableEntry < SimComponent
    input :pte, width: 32

    output :ppn, width: 22      # Physical page number
    output :valid               # V bit
    output :readable            # R bit
    output :writable            # W bit
    output :executable          # X bit
    output :user                # U bit (user-mode accessible)
    output :global              # G bit (ignore ASID)
    output :accessed            # A bit
    output :dirty               # D bit
    output :is_leaf             # R|W|X != 0 means leaf

    behavior do
      valid      <= pte[0]
      readable   <= pte[1]
      writable   <= pte[2]
      executable <= pte[3]
      user       <= pte[4]
      global     <= pte[5]
      accessed   <= pte[6]
      dirty      <= pte[7]
      ppn        <= pte[31:10]

      # Leaf page if any of R/W/X set
      is_leaf <= (pte[3:1] != 0) ? 1 : 0
    end
  end
end
```

---

## Memory Management Unit (MMU)

The MMU combines TLB lookup with page table walking.

```ruby
module RHDL::RISCV
  # RISC-V MMU with Sv32 (two-level page tables)
  class MMU < SimComponent
    parameter :tlb_entries, default: 32

    input :clk
    input :reset

    # CPU interface
    input :vaddr, width: 32       # Virtual address
    input :access_type, width: 2  # 00=read, 01=write, 10=execute
    input :translate
    output :paddr, width: 34      # Physical address (Sv32 can have 34-bit PA)
    output :ready
    output :page_fault

    # Current privilege mode
    input :privilege, width: 2    # 0=U, 1=S, 3=M
    input :satp, width: 32        # Supervisor address translation register
    # satp: [MODE | ASID | PPN]  MODE=1 for Sv32

    # Memory interface (for page table walks)
    output :mem_addr, width: 34
    output :mem_read
    input :mem_data, width: 32
    input :mem_ready

    # TLB instance
    instance :tlb, TLB, num_entries: tlb_entries

    # State machine
    IDLE = 0
    TLB_LOOKUP = 1
    WALK_LEVEL1 = 2
    WALK_LEVEL0 = 3
    UPDATE_TLB = 4
    FAULT = 5

    wire :state, width: 3
    wire :vpn1, width: 10         # VPN[1] - top 10 bits
    wire :vpn0, width: 10         # VPN[0] - next 10 bits
    wire :offset, width: 12       # Page offset
    wire :pte, width: 32          # Current PTE being examined
    wire :ppn, width: 22          # Found physical page number

    behavior do
      # Virtual address breakdown for Sv32
      vpn1 <= vaddr[31:22]
      vpn0 <= vaddr[21:12]
      offset <= vaddr[11:0]

      # Connect TLB
      tlb.vpn <= vaddr[31:12]
      tlb.asid <= satp[30:22]
      tlb.clk <= clk
      tlb.reset <= reset

      ready <= 0
      page_fault <= 0
      mem_read <= 0

      on_rising_edge(:clk) do
        if reset == 1
          state <= IDLE
        else
          case state
          when IDLE
            if translate == 1
              if satp[31] == 0  # MODE=0: no translation
                paddr <= vaddr
                ready <= 1
              else
                state <= TLB_LOOKUP
              end
            end

          when TLB_LOOKUP
            if tlb.hit == 1
              # TLB hit! Check permissions
              if check_permission(tlb.permission, access_type, privilege) == 1
                paddr <= (tlb.ppn << 12) | offset
                ready <= 1
                state <= IDLE
              else
                state <= FAULT
              end
            else
              # TLB miss - walk page table
              state <= WALK_LEVEL1
              # Level 1 PTE address: satp.PPN * 4096 + VPN[1] * 4
              mem_addr <= (satp[21:0] << 12) + (vpn1 << 2)
              mem_read <= 1
            end

          when WALK_LEVEL1
            if mem_ready == 1
              pte <= mem_data
              if mem_data[0] == 0  # Invalid PTE
                state <= FAULT
              elsif mem_data[3:1] != 0  # Leaf (superpage)
                ppn <= mem_data[31:10]
                state <= UPDATE_TLB
              else  # Non-leaf, continue walk
                state <= WALK_LEVEL0
                # Level 0 PTE address
                mem_addr <= (mem_data[31:10] << 12) + (vpn0 << 2)
                mem_read <= 1
              end
            end

          when WALK_LEVEL0
            if mem_ready == 1
              pte <= mem_data
              if mem_data[0] == 0 || mem_data[3:1] == 0  # Invalid or non-leaf at level 0
                state <= FAULT
              else
                ppn <= mem_data[31:10]
                state <= UPDATE_TLB
              end
            end

          when UPDATE_TLB
            # Add translation to TLB
            tlb.write_enable <= 1
            tlb.write_vpn <= vaddr[31:12]
            tlb.write_ppn <= ppn[19:0]  # Truncate for TLB
            tlb.write_asid <= satp[30:22]
            tlb.write_perm <= pte[6:3]  # G|U|X|W|R bits (pack appropriately)

            # Return physical address
            paddr <= (ppn << 12) | offset
            ready <= 1
            state <= IDLE

          when FAULT
            page_fault <= 1
            state <= IDLE
          end
        end
      end
    end

    def check_permission(perm, access, priv)
      # Check R/W/X against access type and U bit against privilege
      # Returns 1 if allowed, 0 if fault
      r = perm[0]
      w = perm[1]
      x = perm[2]
      u = perm[3]

      case access
      when 0b00  # Read
        return 0 if r == 0
      when 0b01  # Write
        return 0 if w == 0
      when 0b10  # Execute
        return 0 if x == 0
      end

      # User mode can only access U=1 pages
      if priv == 0 && u == 0
        return 0
      end

      return 1
    end
  end
end
```

---

## Processor with Cache and MMU

```ruby
module RHDL::RISCV
  # Processor with instruction cache, data cache, and MMU
  class ProcessorWithMemoryHierarchy < SimComponent
    input :clk
    input :reset

    # External memory interface
    output :mem_addr, width: 34
    output :mem_write_data, width: 32
    output :mem_read, :mem_write
    input :mem_read_data, width: 32
    input :mem_ready

    # Core
    instance :core, SingleCycleProcessor

    # Instruction cache (no TLB for simplicity, or add I-TLB)
    instance :icache, DirectMappedCache, cache_size: 4096, line_size: 32

    # Data cache
    instance :dcache, SetAssociativeCache,
             cache_size: 8192, line_size: 32, associativity: 4

    # MMU for data accesses
    instance :mmu, MMU, tlb_entries: 32

    # Arbiter for memory access (icache vs dcache)
    wire :icache_mem_req, :dcache_mem_req
    wire :mem_grant_icache, :mem_grant_dcache

    port :clk => [[:core, :clk], [:icache, :clk], [:dcache, :clk], [:mmu, :clk]]
    port :reset => [[:core, :reset], [:icache, :reset], [:dcache, :reset], [:mmu, :reset]]

    behavior do
      # Instruction fetch path (simplified: assume identity mapped)
      icache.cpu_addr <= core.imem_addr
      icache.cpu_read <= 1
      icache.cpu_write <= 0
      core.imem_data <= icache.cpu_read_data

      # Data access path through MMU then cache
      mmu.vaddr <= core.dmem_addr
      mmu.access_type <= core.dmem_write ? 0b01 : 0b00
      mmu.translate <= core.dmem_read | core.dmem_write

      # Once MMU ready, access cache with physical address
      dcache.cpu_addr <= mmu.paddr
      dcache.cpu_read <= core.dmem_read & mmu.ready
      dcache.cpu_write <= core.dmem_write & mmu.ready
      dcache.cpu_write_data <= core.dmem_write_data
      core.dmem_read_data <= dcache.cpu_read_data

      # Memory arbiter (priority to icache for now)
      if icache_mem_req == 1
        mem_addr <= icache.mem_addr
        mem_read <= icache.mem_read
        mem_write <= icache.mem_write
        icache.mem_ready <= mem_ready
        dcache.mem_ready <= 0
      else
        mem_addr <= dcache.mem_addr
        mem_read <= dcache.mem_read
        mem_write <= dcache.mem_write
        dcache.mem_ready <= mem_ready
        icache.mem_ready <= 0
      end

      mem_write_data <= dcache.mem_write_data
    end
  end
end
```

---

## Performance Counters

```ruby
module RHDL::RISCV
  # Cache performance counters
  class CacheCounters < SimComponent
    input :clk
    input :reset
    input :hit
    input :miss

    output :hit_count, width: 32
    output :miss_count, width: 32
    output :hit_rate, width: 16  # Fixed-point 0.16

    behavior do
      on_rising_edge(:clk) do
        if reset == 1
          hit_count <= 0
          miss_count <= 0
        else
          if hit == 1
            hit_count <= hit_count + 1
          end
          if miss == 1
            miss_count <= miss_count + 1
          end
        end
      end

      # Hit rate calculation (combinational)
      total = hit_count + miss_count
      if total > 0
        hit_rate <= (hit_count << 16) / total
      else
        hit_rate <= 0
      end
    end
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

> Return to [Chapter 25](25-riscv.md) for conceptual introduction.
