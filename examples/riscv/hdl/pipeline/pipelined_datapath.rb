# Pipelined RISC-V RV32I Datapath
# 5-stage pipeline: IF -> ID -> EX -> MEM -> WB
# Includes forwarding and hazard detection

require_relative '../../../../lib/rhdl'
require_relative '../constants'
require_relative '../alu'
require_relative '../decoder'
require_relative '../imm_gen'
require_relative '../branch_cond'
require_relative '../program_counter'
require_relative '../register_file'
require_relative 'if_id_reg'
require_relative 'id_ex_reg'
require_relative 'ex_mem_reg'
require_relative 'mem_wb_reg'
require_relative 'hazard_unit'
require_relative 'forwarding_unit'

module RISCV
  module Pipeline
    class PipelinedDatapath < RHDL::HDL::Component
      input :clk
      input :rst

      # Instruction memory interface
      output :inst_addr, width: 32
      input :inst_data, width: 32

      # Data memory interface
      output :data_addr, width: 32
      output :data_wdata, width: 32
      output :data_we
      output :data_re
      output :data_funct3, width: 3
      input :data_rdata, width: 32

      # Debug outputs
      output :debug_pc, width: 32
      output :debug_inst, width: 32
      output :debug_x1, width: 32
      output :debug_x2, width: 32
      output :debug_x10, width: 32
      output :debug_x11, width: 32

      def initialize(name = nil)
        super(name)

        # Instantiate components
        @pc = RISCV::ProgramCounter.new('pc')
        @regfile = RISCV::RegisterFile.new('regfile')
        @decoder = RISCV::Decoder.new('decoder')
        @imm_gen = RISCV::ImmGen.new('imm_gen')
        @alu = RISCV::ALU.new('alu')
        @branch_cond = RISCV::BranchCond.new('branch_cond')

        # Pipeline registers
        @if_id = RISCV::Pipeline::IF_ID_Reg.new('if_id')
        @id_ex = RISCV::Pipeline::ID_EX_Reg.new('id_ex')
        @ex_mem = RISCV::Pipeline::EX_MEM_Reg.new('ex_mem')
        @mem_wb = RISCV::Pipeline::MEM_WB_Reg.new('mem_wb')

        # Control units
        @hazard_unit = RISCV::Pipeline::HazardUnit.new('hazard')
        @forward_unit = RISCV::Pipeline::ForwardingUnit.new('forward')

        # Cached values for next cycle (latched on rising edge)
        @next_cycle_values = {}

        add_subcomponent(:pc, @pc)
        add_subcomponent(:regfile, @regfile)
        add_subcomponent(:decoder, @decoder)
        add_subcomponent(:imm_gen, @imm_gen)
        add_subcomponent(:alu, @alu)
        add_subcomponent(:branch_cond, @branch_cond)
        add_subcomponent(:if_id, @if_id)
        add_subcomponent(:id_ex, @id_ex)
        add_subcomponent(:ex_mem, @ex_mem)
        add_subcomponent(:mem_wb, @mem_wb)
        add_subcomponent(:hazard_unit, @hazard_unit)
        add_subcomponent(:forward_unit, @forward_unit)
      end

      def propagate
        clk = in_val(:clk)
        rst = in_val(:rst)
        inst_data = in_val(:inst_data)
        data_rdata = in_val(:data_rdata)

        # Always update clock inputs on all sequential components
        # This ensures they can detect their own edges correctly
        update_sequential_clocks(clk, rst)

        # Compute combinational logic (which also sets up next-cycle inputs)
        compute_combinational_logic(clk, rst, inst_data, data_rdata)
      end

      private

      def update_sequential_clocks(clk, rst)
        # Update clock and reset on ALL sequential components
        # Each component detects its own rising edge internally
        @pc.set_input(:clk, clk)
        @pc.set_input(:rst, rst)
        @pc.propagate

        @regfile.set_input(:clk, clk)
        @regfile.set_input(:rst, rst)
        @regfile.propagate

        @if_id.set_input(:clk, clk)
        @if_id.set_input(:rst, rst)
        @if_id.propagate

        @id_ex.set_input(:clk, clk)
        @id_ex.set_input(:rst, rst)
        @id_ex.propagate

        @ex_mem.set_input(:clk, clk)
        @ex_mem.set_input(:rst, rst)
        @ex_mem.propagate

        @mem_wb.set_input(:clk, clk)
        @mem_wb.set_input(:rst, rst)
        @mem_wb.propagate
      end

      def compute_combinational_logic(clk, rst, inst_data, data_rdata)
        # ============================================================
        # STAGE 5: WRITE-BACK (WB) - Read from MEM/WB register
        # ============================================================
        wb_rd_addr = @mem_wb.get_output(:rd_addr_out)
        wb_reg_write = @mem_wb.get_output(:reg_write_out)
        wb_mem_to_reg = @mem_wb.get_output(:mem_to_reg_out)
        wb_jump = @mem_wb.get_output(:jump_out)
        wb_alu_result = @mem_wb.get_output(:alu_result_out)
        wb_mem_data = @mem_wb.get_output(:mem_data_out)
        wb_pc_plus4 = @mem_wb.get_output(:pc_plus4_out)

        # Select write-back data
        wb_data = if wb_jump == 1
                    wb_pc_plus4
                  elsif wb_mem_to_reg == 1
                    wb_mem_data
                  else
                    wb_alu_result
                  end

        # ============================================================
        # STAGE 4: MEMORY (MEM) - Read from EX/MEM register
        # ============================================================
        mem_alu_result = @ex_mem.get_output(:alu_result_out)
        mem_rs2_data = @ex_mem.get_output(:rs2_data_out)
        mem_rd_addr = @ex_mem.get_output(:rd_addr_out)
        mem_funct3 = @ex_mem.get_output(:funct3_out)
        mem_reg_write = @ex_mem.get_output(:reg_write_out)
        mem_mem_read = @ex_mem.get_output(:mem_read_out)
        mem_mem_write = @ex_mem.get_output(:mem_write_out)
        mem_mem_to_reg = @ex_mem.get_output(:mem_to_reg_out)
        mem_jump = @ex_mem.get_output(:jump_out)
        mem_pc_plus4 = @ex_mem.get_output(:pc_plus4_out)

        # Memory interface outputs
        out_set(:data_addr, mem_alu_result)
        out_set(:data_wdata, mem_rs2_data)
        out_set(:data_we, mem_mem_write)
        out_set(:data_re, mem_mem_read)
        out_set(:data_funct3, mem_funct3)

        # ============================================================
        # STAGE 3: EXECUTE (EX) - Read from ID/EX register
        # ============================================================
        ex_pc = @id_ex.get_output(:pc_out)
        ex_pc_plus4 = @id_ex.get_output(:pc_plus4_out)
        ex_rs1_data = @id_ex.get_output(:rs1_data_out)
        ex_rs2_data = @id_ex.get_output(:rs2_data_out)
        ex_imm = @id_ex.get_output(:imm_out)
        ex_rs1_addr = @id_ex.get_output(:rs1_addr_out)
        ex_rs2_addr = @id_ex.get_output(:rs2_addr_out)
        ex_rd_addr = @id_ex.get_output(:rd_addr_out)
        ex_funct3 = @id_ex.get_output(:funct3_out)
        ex_alu_op = @id_ex.get_output(:alu_op_out)
        ex_alu_src = @id_ex.get_output(:alu_src_out)
        ex_reg_write = @id_ex.get_output(:reg_write_out)
        ex_mem_read = @id_ex.get_output(:mem_read_out)
        ex_mem_write = @id_ex.get_output(:mem_write_out)
        ex_mem_to_reg = @id_ex.get_output(:mem_to_reg_out)
        ex_branch = @id_ex.get_output(:branch_out)
        ex_jump = @id_ex.get_output(:jump_out)
        ex_jalr = @id_ex.get_output(:jalr_out)

        # Forwarding unit
        @forward_unit.set_input(:ex_rs1_addr, ex_rs1_addr)
        @forward_unit.set_input(:ex_rs2_addr, ex_rs2_addr)
        @forward_unit.set_input(:mem_rd_addr, mem_rd_addr)
        @forward_unit.set_input(:mem_reg_write, mem_reg_write)
        @forward_unit.set_input(:wb_rd_addr, wb_rd_addr)
        @forward_unit.set_input(:wb_reg_write, wb_reg_write)
        @forward_unit.propagate

        forward_a = @forward_unit.get_output(:forward_a)
        forward_b = @forward_unit.get_output(:forward_b)

        # Apply forwarding to ALU operands
        alu_a = case forward_a
                when ForwardSel::EX_MEM then mem_alu_result
                when ForwardSel::MEM_WB then wb_data
                else ex_rs1_data
                end

        forwarded_rs2 = case forward_b
                        when ForwardSel::EX_MEM then mem_alu_result
                        when ForwardSel::MEM_WB then wb_data
                        else ex_rs2_data
                        end

        # ALU second operand
        alu_b = ex_alu_src == 1 ? ex_imm : forwarded_rs2

        # ALU computation
        @alu.set_input(:a, alu_a)
        @alu.set_input(:b, alu_b)
        @alu.set_input(:op, ex_alu_op)
        @alu.propagate
        alu_result = @alu.get_output(:result)

        # Branch condition
        @branch_cond.set_input(:rs1_data, alu_a)
        @branch_cond.set_input(:rs2_data, forwarded_rs2)
        @branch_cond.set_input(:funct3, ex_funct3)
        @branch_cond.propagate
        branch_taken = @branch_cond.get_output(:branch_taken) == 1 && ex_branch == 1

        # Branch/Jump target calculation
        branch_target = (ex_pc + ex_imm) & 0xFFFFFFFF
        jalr_target = (alu_a + ex_imm) & 0xFFFFFFFE
        jump_target = ex_jalr == 1 ? jalr_target : branch_target

        # Control hazard detection
        take_branch = branch_taken || ex_jump == 1

        # ============================================================
        # STAGE 2: INSTRUCTION DECODE (ID) - Read from IF/ID register
        # ============================================================
        id_pc = @if_id.get_output(:pc_out)
        id_inst = @if_id.get_output(:inst_out)
        id_pc_plus4 = @if_id.get_output(:pc_plus4_out)

        # Decoder
        @decoder.set_input(:inst, id_inst)
        @decoder.propagate

        rs1_addr = @decoder.get_output(:rs1)
        rs2_addr = @decoder.get_output(:rs2)
        rd_addr = @decoder.get_output(:rd)
        funct3 = @decoder.get_output(:funct3)
        funct7 = @decoder.get_output(:funct7)
        alu_op = @decoder.get_output(:alu_op)
        alu_src = @decoder.get_output(:alu_src)
        id_reg_write = @decoder.get_output(:reg_write)
        id_mem_read = @decoder.get_output(:mem_read)
        id_mem_write = @decoder.get_output(:mem_write)
        id_mem_to_reg = @decoder.get_output(:mem_to_reg)
        id_branch = @decoder.get_output(:branch)
        id_jump = @decoder.get_output(:jump)
        id_jalr = @decoder.get_output(:jalr)

        # Immediate generator
        @imm_gen.set_input(:inst, id_inst)
        @imm_gen.propagate
        imm = @imm_gen.get_output(:imm)

        # Register file read (combinational) with internal forwarding
        @regfile.set_input(:rs1_addr, rs1_addr)
        @regfile.set_input(:rs2_addr, rs2_addr)
        @regfile.set_input(:rd_addr, wb_rd_addr)
        @regfile.set_input(:rd_data, wb_data)
        @regfile.set_input(:rd_we, wb_reg_write)

        # Get outputs after setting all inputs - uses internal forwarding
        # This handles same-cycle WB->ID forwarding
        @regfile.propagate
        rs1_data = @regfile.get_output(:rs1_data)
        rs2_data = @regfile.get_output(:rs2_data)

        # Hazard detection
        @hazard_unit.set_input(:id_rs1_addr, rs1_addr)
        @hazard_unit.set_input(:id_rs2_addr, rs2_addr)
        @hazard_unit.set_input(:ex_rd_addr, ex_rd_addr)
        @hazard_unit.set_input(:ex_mem_read, ex_mem_read)
        @hazard_unit.set_input(:mem_rd_addr, mem_rd_addr)
        @hazard_unit.set_input(:mem_mem_read, mem_mem_read)
        @hazard_unit.set_input(:branch_taken, take_branch ? 1 : 0)
        @hazard_unit.set_input(:jump, ex_jump)
        @hazard_unit.propagate

        stall = @hazard_unit.get_output(:stall)
        flush_if_id = @hazard_unit.get_output(:flush_if_id)
        flush_id_ex = @hazard_unit.get_output(:flush_id_ex)

        # ============================================================
        # STAGE 1: INSTRUCTION FETCH (IF)
        # ============================================================
        current_pc = @pc.get_output(:pc)

        # Next PC calculation
        if take_branch
          next_pc = jump_target
        elsif stall == 1
          next_pc = current_pc
        else
          next_pc = (current_pc + 4) & 0xFFFFFFFF
        end

        # Set up PC for next cycle
        @pc.set_input(:pc_next, next_pc)
        @pc.set_input(:pc_we, stall == 0 ? 1 : 0)

        # Instruction memory interface
        out_set(:inst_addr, current_pc)

        # ============================================================
        # SET UP PIPELINE REGISTER INPUTS FOR NEXT CYCLE
        # ============================================================

        # IF/ID register inputs
        @if_id.set_input(:stall, stall)
        @if_id.set_input(:flush, flush_if_id)
        @if_id.set_input(:pc_in, current_pc)
        @if_id.set_input(:inst_in, inst_data)
        @if_id.set_input(:pc_plus4_in, (current_pc + 4) & 0xFFFFFFFF)

        # ID/EX register inputs
        @id_ex.set_input(:flush, flush_id_ex)
        @id_ex.set_input(:pc_in, id_pc)
        @id_ex.set_input(:pc_plus4_in, id_pc_plus4)
        @id_ex.set_input(:rs1_data_in, rs1_data)
        @id_ex.set_input(:rs2_data_in, rs2_data)
        @id_ex.set_input(:imm_in, imm)
        @id_ex.set_input(:rs1_addr_in, rs1_addr)
        @id_ex.set_input(:rs2_addr_in, rs2_addr)
        @id_ex.set_input(:rd_addr_in, rd_addr)
        @id_ex.set_input(:funct3_in, funct3)
        @id_ex.set_input(:funct7_in, funct7)
        @id_ex.set_input(:alu_op_in, alu_op)
        @id_ex.set_input(:alu_src_in, alu_src)
        @id_ex.set_input(:reg_write_in, id_reg_write)
        @id_ex.set_input(:mem_read_in, id_mem_read)
        @id_ex.set_input(:mem_write_in, id_mem_write)
        @id_ex.set_input(:mem_to_reg_in, id_mem_to_reg)
        @id_ex.set_input(:branch_in, id_branch)
        @id_ex.set_input(:jump_in, id_jump)
        @id_ex.set_input(:jalr_in, id_jalr)

        # EX/MEM register inputs
        @ex_mem.set_input(:alu_result_in, alu_result)
        @ex_mem.set_input(:rs2_data_in, forwarded_rs2)
        @ex_mem.set_input(:rd_addr_in, ex_rd_addr)
        @ex_mem.set_input(:pc_plus4_in, ex_pc_plus4)
        @ex_mem.set_input(:funct3_in, ex_funct3)
        @ex_mem.set_input(:reg_write_in, ex_reg_write)
        @ex_mem.set_input(:mem_read_in, ex_mem_read)
        @ex_mem.set_input(:mem_write_in, ex_mem_write)
        @ex_mem.set_input(:mem_to_reg_in, ex_mem_to_reg)
        @ex_mem.set_input(:jump_in, ex_jump)

        # MEM/WB register inputs
        @mem_wb.set_input(:alu_result_in, mem_alu_result)
        @mem_wb.set_input(:mem_data_in, data_rdata)
        @mem_wb.set_input(:rd_addr_in, mem_rd_addr)
        @mem_wb.set_input(:pc_plus4_in, mem_pc_plus4)
        @mem_wb.set_input(:reg_write_in, mem_reg_write)
        @mem_wb.set_input(:mem_to_reg_in, mem_mem_to_reg)
        @mem_wb.set_input(:jump_in, mem_jump)

        # ============================================================
        # DEBUG OUTPUTS
        # ============================================================
        out_set(:debug_pc, current_pc)
        out_set(:debug_inst, id_inst)
        out_set(:debug_x1, @regfile.read_reg(1))
        out_set(:debug_x2, @regfile.read_reg(2))
        out_set(:debug_x10, @regfile.read_reg(10))
        out_set(:debug_x11, @regfile.read_reg(11))
      end

      public

    end
  end
end
