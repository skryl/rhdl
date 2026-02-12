# RV32I Single-Cycle CPU
# Purely declarative implementation using the RHDL DSL
# Contains all datapath components and combinational control logic
#
# For testing, use the Harness class which provides a cleaner interface
# and interacts with the CPU only through ports.

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'
require_relative 'constants'
require_relative 'alu'
require_relative 'register_file'
require_relative 'csr_file'
require_relative 'imm_gen'
require_relative 'decoder'
require_relative 'branch_cond'
require_relative 'program_counter'

module RHDL
  module Examples
    module RISCV
      class CPU < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    # External interface
    input :clk
    input :rst
    input :irq_software
    input :irq_timer
    input :irq_external

    # Instruction memory interface
    output :inst_addr, width: 32    # Instruction address (PC)
    input :inst_data, width: 32     # Instruction data from memory

    # Data memory interface
    output :data_addr, width: 32    # Data address
    output :data_wdata, width: 32   # Write data
    input :data_rdata, width: 32    # Read data from memory
    output :data_we                 # Write enable
    output :data_re                 # Read enable
    output :data_funct3, width: 3   # Memory access size

    # Debug outputs
    output :debug_pc, width: 32
    output :debug_inst, width: 32
    output :debug_x1, width: 32
    output :debug_x2, width: 32
    output :debug_x10, width: 32
    output :debug_x11, width: 32

    # Internal signals - from sub-components
    wire :pc, width: 32
    wire :pc_next, width: 32
    wire :imm, width: 32
    wire :rs1_data, width: 32
    wire :rs2_data, width: 32
    wire :alu_result, width: 32
    wire :alu_zero
    wire :branch_taken

    # Decoded control signals from decoder
    wire :opcode, width: 7
    wire :rd, width: 5
    wire :funct3, width: 3
    wire :rs1, width: 5
    wire :rs2, width: 5
    wire :funct7, width: 7
    wire :reg_write
    wire :mem_read
    wire :mem_write
    wire :mem_to_reg
    wire :alu_src
    wire :branch
    wire :jump
    wire :jalr
    wire :reg_write_final
    wire :mem_read_final
    wire :mem_write_final
    wire :alu_op, width: 5

    # Internal signals - computed by behavior block
    wire :alu_a, width: 32
    wire :alu_b, width: 32
    wire :rd_data, width: 32
    wire :pc_plus4, width: 32
    wire :branch_target, width: 32
    wire :jalr_target, width: 32
    wire :pc_we  # PC write enable (always 1 for single-cycle)
    wire :csr_addr, width: 12
    wire :csr_addr2, width: 12
    wire :csr_addr3, width: 12
    wire :csr_write_addr, width: 12
    wire :csr_read_data, width: 32
    wire :csr_read_data2, width: 32
    wire :csr_read_data3, width: 32
    wire :csr_write_data, width: 32
    wire :csr_write_we
    wire :csr_write_addr2, width: 12
    wire :csr_write_data2, width: 32
    wire :csr_write_we2
    wire :csr_write_addr3, width: 12
    wire :csr_write_data3, width: 32
    wire :csr_write_we3

    # Component instances
    instance :pc_reg, ProgramCounter
    instance :regfile, RegisterFile
    instance :csrfile, CSRFile
    instance :decoder, Decoder
    instance :imm_gen, ImmGen
    instance :alu, ALU
    instance :branch_cond, BranchCond

    # Clock and reset to sequential components
    port :clk => [[:pc_reg, :clk], [:regfile, :clk], [:csrfile, :clk]]
    port :rst => [[:pc_reg, :rst], [:regfile, :rst], [:csrfile, :rst]]

    # PC connections
    port :pc_next => [:pc_reg, :pc_next]
    port [:pc_reg, :pc] => :pc

    # Instruction to decoder and immediate generator
    port :inst_data => [:decoder, :inst]
    port :inst_data => [:imm_gen, :inst]

    # Decoder outputs to internal wires
    port [:decoder, :opcode] => :opcode
    port [:decoder, :rd] => :rd
    port [:decoder, :funct3] => :funct3
    port [:decoder, :rs1] => :rs1
    port [:decoder, :rs2] => :rs2
    port [:decoder, :funct7] => :funct7
    port [:decoder, :reg_write] => :reg_write
    port [:decoder, :mem_read] => :mem_read
    port [:decoder, :mem_write] => :mem_write
    port [:decoder, :mem_to_reg] => :mem_to_reg
    port [:decoder, :alu_src] => :alu_src
    port [:decoder, :branch] => :branch
    port [:decoder, :jump] => :jump
    port [:decoder, :jalr] => :jalr
    port [:decoder, :alu_op] => :alu_op

    # Immediate generator output
    port [:imm_gen, :imm] => :imm

    # Register file connections
    port :rs1 => [:regfile, :rs1_addr]
    port :rs2 => [:regfile, :rs2_addr]
    port :rd => [:regfile, :rd_addr]
    port :rd_data => [:regfile, :rd_data]
    port :reg_write_final => [:regfile, :rd_we]
    port [:regfile, :rs1_data] => :rs1_data
    port [:regfile, :rs2_data] => :rs2_data

    # CSR file connections
    port :csr_addr => [:csrfile, :read_addr]
    port :csr_addr2 => [:csrfile, :read_addr2]
    port :csr_addr3 => [:csrfile, :read_addr3]
    port [:csrfile, :read_data] => :csr_read_data
    port [:csrfile, :read_data2] => :csr_read_data2
    port [:csrfile, :read_data3] => :csr_read_data3
    port :csr_write_addr => [:csrfile, :write_addr]
    port :csr_write_data => [:csrfile, :write_data]
    port :csr_write_we => [:csrfile, :write_we]
    port :csr_write_addr2 => [:csrfile, :write_addr2]
    port :csr_write_data2 => [:csrfile, :write_data2]
    port :csr_write_we2 => [:csrfile, :write_we2]
    port :csr_write_addr3 => [:csrfile, :write_addr3]
    port :csr_write_data3 => [:csrfile, :write_data3]
    port :csr_write_we3 => [:csrfile, :write_we3]

    # ALU connections
    port :alu_a => [:alu, :a]
    port :alu_b => [:alu, :b]
    port :alu_op => [:alu, :op]
    port [:alu, :result] => :alu_result
    port [:alu, :zero] => :alu_zero

    # Branch condition connections
    port :rs1_data => [:branch_cond, :rs1_data]
    port :rs2_data => [:branch_cond, :rs2_data]
    port :funct3 => [:branch_cond, :funct3]
    port [:branch_cond, :branch_taken] => :branch_taken

    # Debug outputs from register file
    port [:regfile, :debug_x1] => :debug_x1
    port [:regfile, :debug_x2] => :debug_x2
    port [:regfile, :debug_x10] => :debug_x10
    port [:regfile, :debug_x11] => :debug_x11

    # PC write enable connection
    port :pc_we => [:pc_reg, :pc_we]

    # Combinational control logic
    behavior do
      # PC write enable - always 1 for single-cycle CPU
      pc_we <= lit(1, width: 1)

      # PC + 4 for sequential execution and return address
      pc_plus4 <= pc + lit(4, width: 32)

      # Branch target = PC + immediate
      branch_target <= pc + imm

      # JALR target = rs1 + immediate with LSB cleared
      jalr_target <= (rs1_data + imm) & lit(0xFFFFFFFE, width: 32)

      # ALU A input mux: AUIPC uses PC, others use rs1_data
      alu_a <= mux(opcode == lit(Opcode::AUIPC, width: 7), pc, rs1_data)

      # ALU B input mux: alu_src=1 uses immediate, alu_src=0 uses rs2_data
      alu_b <= mux(alu_src, imm, rs2_data)

      # CSR and SYSTEM decode
      is_csr_instr = local(:is_csr_instr,
                           (opcode == lit(Opcode::SYSTEM, width: 7)) & (funct3 != lit(0, width: 3)),
                           width: 1)
      is_system_plain = local(:is_system_plain,
                              (opcode == lit(Opcode::SYSTEM, width: 7)) & (funct3 == lit(0, width: 3)),
                              width: 1)
      sys_imm = inst_data[31..20]
      is_ecall = local(:is_ecall, is_system_plain & (sys_imm == lit(0x000, width: 12)), width: 1)
      is_ebreak = local(:is_ebreak, is_system_plain & (sys_imm == lit(0x001, width: 12)), width: 1)
      is_mret = local(:is_mret, is_system_plain & (sys_imm == lit(0x302, width: 12)), width: 1)
      is_illegal_system = local(:is_illegal_system,
                                is_system_plain & ~(is_ecall | is_ebreak | is_mret),
                                width: 1)
      irq_pending_bits = local(:irq_pending_bits,
                               mux(irq_software, lit(0x8, width: 32), lit(0, width: 32)) |
                               mux(irq_timer, lit(0x80, width: 32), lit(0, width: 32)) |
                               mux(irq_external, lit(0x800, width: 32), lit(0, width: 32)),
                               width: 32)
      csr_use_imm = funct3[2]
      csr_src = local(:csr_src, mux(csr_use_imm, cat(lit(0, width: 27), rs1), rs1_data), width: 32)
      csr_rs1_nonzero = local(:csr_rs1_nonzero, rs1 != lit(0, width: 5), width: 1)

      global_mie_enabled = local(:global_mie_enabled,
                                 (csr_read_data2 & lit(0x8, width: 32)) != lit(0, width: 32),
                                 width: 1)
      enabled_interrupts = local(:enabled_interrupts, irq_pending_bits & csr_read_data3, width: 32)
      interrupt_pending = local(:interrupt_pending,
                                global_mie_enabled & (enabled_interrupts != lit(0, width: 32)),
                                width: 1)
      sync_trap_taken = local(:sync_trap_taken, is_ecall | is_ebreak | is_illegal_system, width: 1)
      trap_taken = local(:trap_taken, sync_trap_taken | interrupt_pending, width: 1)
      interrupt_cause = local(:interrupt_cause,
                              mux((enabled_interrupts & lit(0x800, width: 32)) != lit(0, width: 32),
                                  lit(0x8000000B, width: 32), # MEI
                                  mux((enabled_interrupts & lit(0x80, width: 32)) != lit(0, width: 32),
                                      lit(0x80000007, width: 32), # MTI
                                      lit(0x80000003, width: 32)  # MSI
                                  )),
                              width: 32)
      # CSR read address:
      # - trap entry reads mtvec
      # - mret reads mepc
      # - CSR instructions read csr from instruction imm field
      csr_addr <= mux(trap_taken, lit(0x305, width: 12),
                      mux(is_mret, lit(0x341, width: 12), inst_data[31..20]))
      # Secondary read port always tracks mstatus for trap/mret bit updates
      csr_addr2 <= lit(0x300, width: 12)
      # Third read port tracks mie for interrupt enable masking
      csr_addr3 <= lit(0x304, width: 12)

      csr_instr_write_data = local(:csr_instr_write_data, case_select(funct3, {
        0b001 => csr_src,                  # CSRRW
        0b010 => csr_read_data | csr_src,  # CSRRS
        0b011 => csr_read_data & ~csr_src, # CSRRC
        0b101 => csr_src,                  # CSRRWI
        0b110 => csr_read_data | csr_src,  # CSRRSI
        0b111 => csr_read_data & ~csr_src  # CSRRCI
      }, default: csr_read_data), width: 32)
      csr_instr_write_we = local(:csr_instr_write_we, is_csr_instr & case_select(funct3, {
        0b001 => lit(1, width: 1), # CSRRW
        0b010 => csr_rs1_nonzero,  # CSRRS
        0b011 => csr_rs1_nonzero,  # CSRRC
        0b101 => lit(1, width: 1), # CSRRWI
        0b110 => csr_rs1_nonzero,  # CSRRSI (zimm != 0)
        0b111 => csr_rs1_nonzero   # CSRRCI (zimm != 0)
      }, default: lit(0, width: 1)), width: 1)
      trap_cause = local(:trap_cause,
                         mux(interrupt_pending,
                             interrupt_cause,
                             mux(is_illegal_system,
                                 lit(2, width: 32),
                                 mux(is_ebreak, lit(3, width: 32), lit(11, width: 32)))),
                         width: 32)
      old_mie_to_mpie = local(:old_mie_to_mpie,
                              mux((csr_read_data2 & lit(0x8, width: 32)) == lit(0, width: 32),
                                  lit(0, width: 32),
                                  lit(0x80, width: 32)),
                              width: 32)
      old_mpie_to_mie = local(:old_mpie_to_mie,
                              mux((csr_read_data2 & lit(0x80, width: 32)) == lit(0, width: 32),
                                  lit(0, width: 32),
                                  lit(0x8, width: 32)),
                              width: 32)
      trap_mstatus = local(:trap_mstatus,
                           (csr_read_data2 & lit(0xFFFFE777, width: 32)) |
                           old_mie_to_mpie |
                           lit(0x1800, width: 32),
                           width: 32)
      mret_mstatus = local(:mret_mstatus,
                           (csr_read_data2 & lit(0xFFFFE777, width: 32)) |
                           old_mpie_to_mie |
                           lit(0x80, width: 32),
                           width: 32)
      trap_or_mret = local(:trap_or_mret, trap_taken | is_mret, width: 1)

      # SYSTEM side effects:
      # - Trap: write mepc, mcause, and mstatus trap-stack bits
      # - MRET: restore mstatus trap-stack bits
      # - CSR instructions: normal CSR RMW
      csr_write_addr <= mux(trap_taken, lit(0x341, width: 12),
                            mux(is_mret, lit(0x300, width: 12), inst_data[31..20]))
      csr_write_data <= mux(trap_taken, pc, mux(is_mret, mret_mstatus, csr_instr_write_data))
      csr_write_we <= mux(trap_or_mret, lit(1, width: 1), csr_instr_write_we)
      csr_write_addr2 <= lit(0x342, width: 12)
      csr_write_data2 <= trap_cause
      csr_write_we2 <= trap_taken
      csr_write_addr3 <= lit(0x300, width: 12)
      csr_write_data3 <= trap_mstatus
      csr_write_we3 <= trap_taken

      # PC next selection:
      # - jump && jalr: jalr_target
      # - jump && !jalr: pc + imm (JAL target)
      # - branch && branch_taken: branch_target
      # - mret: mepc
      # - trap: mtvec
      # - else: pc_plus4
      jal_target = local(:jal_target, pc + imm, width: 32)
      trap_target = local(:trap_target, csr_read_data & lit(0xFFFFFFFC, width: 32), width: 32)

      pc_next <= mux(trap_taken, trap_target,
                     mux(is_mret, csr_read_data,
                         mux(jump,
                             mux(jalr, jalr_target, jal_target),
                             mux(branch & branch_taken, branch_target, pc_plus4))))

      # Register write data selection:
      # - mem_to_reg: data from memory
      # - jump: return address (pc + 4)
      # - csr: old CSR value
      # - else: ALU result
      rd_data <= mux(is_csr_instr, csr_read_data,
                     mux(mem_to_reg, data_rdata,
                     mux(jump, pc_plus4, alu_result))
                     )
      reg_write_final <= reg_write & ~interrupt_pending
      mem_read_final <= mem_read & ~interrupt_pending
      mem_write_final <= mem_write & ~interrupt_pending

      # Output connections
      inst_addr <= pc
      data_addr <= alu_result
      data_wdata <= rs2_data
      data_we <= mem_write_final
      data_re <= mem_read_final
      data_funct3 <= funct3
      debug_pc <= pc
      debug_inst <= inst_data
    end

    # Helper methods for testing - these access sub-component state directly
    # They are NOT part of the synthesizable design

    def read_pc
      @pc_reg.read_pc
    end

    def write_pc(value)
      @pc_reg.write_pc(value)
    end

    def read_reg(index)
      @regfile.read_reg(index)
    end

    def write_reg(index, value)
      @regfile.write_reg(index, value)
    end

    def read_csr(index)
      @csrfile.read_csr(index)
    end

    # Generate complete Verilog hierarchy
    def self.to_verilog_hierarchy(top_name: nil)
      parts = []

      # Generate sub-modules first
      parts << ALU.to_verilog
      parts << RegisterFile.to_verilog
      parts << CSRFile.to_verilog
      parts << ImmGen.to_verilog
      parts << Decoder.to_verilog
      parts << BranchCond.to_verilog
      parts << ProgramCounter.to_verilog

      # Generate top-level last
      parts << to_verilog(top_name: top_name)

      parts.join("\n\n")
    end
      end
    end
  end
end
