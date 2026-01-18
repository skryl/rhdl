# MOS 6502 CPU - Synthesizable DSL Version
# Integrates all CPU components into a complete CPU
# Uses class-level instance/port declarations for component instantiation and wiring
# Sequential - requires always @(posedge clk) for synthesis
# FULLY DECLARATIVE - no behavioral Ruby code, only DSL constructs

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'
require_relative 'registers'
require_relative 'status_register'
require_relative 'alu'
require_relative 'address_gen'
require_relative 'instruction_decoder'
require_relative 'control_unit'

module MOS6502
  class CPU < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    # External interface
    input :clk
    input :rst
    input :rdy
    input :irq
    input :nmi

    # Memory interface
    input :data_in, width: 8
    output :data_out, width: 8
    output :addr, width: 16
    output :rw
    output :sync

    # External register load inputs (for test/debug)
    input :ext_pc_load_data, width: 16
    input :ext_pc_load_en
    input :ext_a_load_data, width: 8
    input :ext_a_load_en
    input :ext_x_load_data, width: 8
    input :ext_x_load_en
    input :ext_y_load_data, width: 8
    input :ext_y_load_en
    input :ext_sp_load_data, width: 8
    input :ext_sp_load_en

    # Debug outputs
    output :reg_a, width: 8
    output :reg_x, width: 8
    output :reg_y, width: 8
    output :reg_sp, width: 8
    output :reg_pc, width: 16
    output :reg_p, width: 8
    output :opcode, width: 8
    output :state, width: 8
    output :halted
    output :cycle_count, width: 32

    # Internal signals from subcomponents
    wire :ir_opcode, width: 8
    wire :ir_operand_lo, width: 8
    wire :ir_operand_hi, width: 8
    wire :dec_addr_mode, width: 4
    wire :dec_alu_op, width: 4
    wire :dec_instr_type, width: 4
    wire :dec_src_reg, width: 2
    wire :dec_dst_reg, width: 2
    wire :dec_branch_cond, width: 3
    wire :dec_is_read
    wire :dec_is_write
    wire :dec_is_rmw
    wire :dec_sets_nz
    wire :dec_sets_c
    wire :dec_sets_v
    wire :dec_writes_reg
    wire :dec_is_status_op
    wire :ctrl_state, width: 8
    wire :ctrl_pc_inc
    wire :ctrl_pc_load
    wire :ctrl_load_opcode
    wire :ctrl_load_operand_lo
    wire :ctrl_load_operand_hi
    wire :ctrl_load_addr_lo
    wire :ctrl_load_addr_hi
    wire :ctrl_load_data
    wire :ctrl_addr_sel, width: 3
    wire :ctrl_data_sel, width: 3
    wire :ctrl_reg_write
    wire :ctrl_sp_inc
    wire :ctrl_sp_dec
    wire :ctrl_update_flags
    wire :ctrl_mem_write
    wire :ctrl_halted
    wire :ctrl_cycle_count, width: 32
    wire :alu_result, width: 8
    wire :alu_n
    wire :alu_z
    wire :alu_c
    wire :alu_v
    wire :regs_a, width: 8
    wire :regs_x, width: 8
    wire :regs_y, width: 8
    wire :sr_p, width: 8
    wire :sr_n
    wire :sr_v
    wire :sr_z
    wire :sr_c
    wire :sr_d
    wire :pc_val, width: 16
    wire :sp_val, width: 8
    wire :agen_eff_addr, width: 16
    wire :agen_page_cross
    wire :acalc_ptr_addr_lo, width: 16
    wire :acalc_ptr_addr_hi, width: 16
    wire :alatch_addr_lo, width: 8
    wire :alatch_addr_hi, width: 8
    wire :alatch_addr, width: 16
    wire :dlatch_data, width: 8

    # Computed control signals for subcomponents
    wire :actual_load_a
    wire :actual_load_x
    wire :actual_load_y
    wire :actual_reg_data, width: 8
    wire :actual_pc_load
    wire :actual_pc_addr, width: 16
    wire :actual_sp_load
    wire :actual_sp_data, width: 8
    wire :actual_load_n
    wire :actual_load_z
    wire :actual_load_c
    wire :actual_load_v
    wire :flag_n_in
    wire :flag_z_in
    wire :flag_c_in
    wire :flag_v_in

    # Additional computed signals
    wire :stack_addr, width: 16
    wire :stack_addr_plus1, width: 16
    wire :alu_a_sel, width: 8
    wire :alu_b_sel, width: 8
    wire :pc_hi_byte, width: 8
    wire :pc_lo_byte, width: 8
    wire :is_execute_state
    wire :load_from_imm
    wire :load_from_mem

    # Component instances
    instance :registers, Registers
    instance :status_reg, StatusRegister
    instance :pc, ProgramCounter
    instance :sp, StackPointer
    instance :ir, InstructionRegister
    instance :addr_latch, AddressLatch
    instance :data_latch, DataLatch
    instance :control, ControlUnit
    instance :alu, ALU
    instance :decoder, InstructionDecoder
    instance :addr_gen, AddressGenerator
    instance :addr_calc, IndirectAddressCalc

    # Clock and reset to all sequential components
    port :clk => [[:registers, :clk], [:status_reg, :clk], [:pc, :clk],
                  [:sp, :clk], [:ir, :clk], [:addr_latch, :clk],
                  [:data_latch, :clk], [:control, :clk]]
    port :rst => [[:registers, :rst], [:status_reg, :rst], [:pc, :rst],
                  [:sp, :rst], [:ir, :rst], [:addr_latch, :rst],
                  [:data_latch, :rst], [:control, :rst]]

    # Control unit inputs
    port :rdy => [:control, :rdy]

    # IR connections
    port :data_in => [:ir, :data_in]
    port [:ir, :opcode] => :ir_opcode
    port [:ir, :operand_lo] => :ir_operand_lo
    port [:ir, :operand_hi] => :ir_operand_hi
    port :ctrl_load_opcode => [:ir, :load_opcode]
    port :ctrl_load_operand_lo => [:ir, :load_operand_lo]
    port :ctrl_load_operand_hi => [:ir, :load_operand_hi]

    # Decoder connections
    port :ir_opcode => [:decoder, :opcode]
    port [:decoder, :addr_mode] => :dec_addr_mode
    port [:decoder, :alu_op] => :dec_alu_op
    port [:decoder, :instr_type] => :dec_instr_type
    port [:decoder, :src_reg] => :dec_src_reg
    port [:decoder, :dst_reg] => :dec_dst_reg
    port [:decoder, :branch_cond] => :dec_branch_cond
    port [:decoder, :is_read] => :dec_is_read
    port [:decoder, :is_write] => :dec_is_write
    port [:decoder, :is_rmw] => :dec_is_rmw
    port [:decoder, :sets_nz] => :dec_sets_nz
    port [:decoder, :sets_c] => :dec_sets_c
    port [:decoder, :sets_v] => :dec_sets_v
    port [:decoder, :writes_reg] => :dec_writes_reg
    port [:decoder, :is_status_op] => :dec_is_status_op

    # Control unit connections
    port :dec_addr_mode => [:control, :addr_mode]
    port :dec_instr_type => [:control, :instr_type]
    port :dec_branch_cond => [:control, :branch_cond]
    port :dec_is_read => [:control, :is_read]
    port :dec_is_write => [:control, :is_write]
    port :dec_is_rmw => [:control, :is_rmw]
    port :dec_writes_reg => [:control, :writes_reg]
    port :dec_is_status_op => [:control, :is_status_op]

    port [:control, :state] => :ctrl_state
    port [:control, :pc_inc] => :ctrl_pc_inc
    port [:control, :pc_load] => :ctrl_pc_load
    port [:control, :load_opcode] => :ctrl_load_opcode
    port [:control, :load_operand_lo] => :ctrl_load_operand_lo
    port [:control, :load_operand_hi] => :ctrl_load_operand_hi
    port [:control, :load_addr_lo] => :ctrl_load_addr_lo
    port [:control, :load_addr_hi] => :ctrl_load_addr_hi
    port [:control, :load_data] => :ctrl_load_data
    port [:control, :addr_sel] => :ctrl_addr_sel
    port [:control, :data_sel] => :ctrl_data_sel
    port [:control, :reg_write] => :ctrl_reg_write
    port [:control, :sp_inc] => :ctrl_sp_inc
    port [:control, :sp_dec] => :ctrl_sp_dec
    port [:control, :update_flags] => :ctrl_update_flags
    port [:control, :mem_write] => :ctrl_mem_write
    port [:control, :halted] => :ctrl_halted
    port [:control, :cycle_count] => :ctrl_cycle_count

    # Status register connections
    port [:status_reg, :n] => :sr_n
    port [:status_reg, :v] => :sr_v
    port [:status_reg, :z] => :sr_z
    port [:status_reg, :c] => :sr_c
    port [:status_reg, :d] => :sr_d
    port [:status_reg, :p] => :sr_p
    port :sr_n => [:control, :flag_n]
    port :sr_v => [:control, :flag_v]
    port :sr_z => [:control, :flag_z]
    port :sr_c => [:control, :flag_c]
    port :actual_load_n => [:status_reg, :load_n]
    port :actual_load_z => [:status_reg, :load_z]
    port :actual_load_c => [:status_reg, :load_c]
    port :actual_load_v => [:status_reg, :load_v]
    port :flag_n_in => [:status_reg, :n_in]
    port :flag_z_in => [:status_reg, :z_in]
    port :flag_c_in => [:status_reg, :c_in]
    port :flag_v_in => [:status_reg, :v_in]

    # ALU connections
    port [:alu, :result] => :alu_result
    port [:alu, :n] => :alu_n
    port [:alu, :z] => :alu_z
    port [:alu, :c] => :alu_c
    port [:alu, :v] => :alu_v
    port :dec_alu_op => [:alu, :op]
    port :sr_c => [:alu, :c_in]
    port :sr_d => [:alu, :d_flag]
    port :alu_a_sel => [:alu, :a]
    port :alu_b_sel => [:alu, :b]

    # Register connections (use computed signals)
    port [:registers, :a] => :regs_a
    port [:registers, :x] => :regs_x
    port [:registers, :y] => :regs_y
    port :actual_load_a => [:registers, :load_a]
    port :actual_load_x => [:registers, :load_x]
    port :actual_load_y => [:registers, :load_y]
    port :actual_reg_data => [:registers, :data_in]

    # PC connections (use computed signals)
    port [:pc, :pc] => :pc_val
    port :actual_pc_load => [:pc, :load]
    port :actual_pc_addr => [:pc, :addr_in]
    port :ctrl_pc_inc => [:pc, :inc]

    # SP connections (use computed signals)
    port [:sp, :sp] => :sp_val
    port :actual_sp_load => [:sp, :load]
    port :actual_sp_data => [:sp, :data_in]
    port :ctrl_sp_inc => [:sp, :inc]
    port :ctrl_sp_dec => [:sp, :dec]

    # Address generator connections
    port :dec_addr_mode => [:addr_gen, :mode]
    port :ir_operand_lo => [:addr_gen, :operand_lo]
    port :ir_operand_hi => [:addr_gen, :operand_hi]
    port :regs_x => [:addr_gen, :x_reg]
    port :regs_y => [:addr_gen, :y_reg]
    port :pc_val => [:addr_gen, :pc]
    port :sp_val => [:addr_gen, :sp]
    port [:addr_gen, :eff_addr] => :agen_eff_addr
    port [:addr_gen, :page_cross] => :agen_page_cross
    port :agen_page_cross => [:control, :page_cross]

    # Indirect address calculator connections
    port :dec_addr_mode => [:addr_calc, :mode]
    port :ir_operand_lo => [:addr_calc, :operand_lo]
    port :ir_operand_hi => [:addr_calc, :operand_hi]
    port :regs_x => [:addr_calc, :x_reg]
    port [:addr_calc, :ptr_addr_lo] => :acalc_ptr_addr_lo
    port [:addr_calc, :ptr_addr_hi] => :acalc_ptr_addr_hi

    # Address latch connections
    port [:addr_latch, :addr_lo] => :alatch_addr_lo
    port [:addr_latch, :addr_hi] => :alatch_addr_hi
    port [:addr_latch, :addr] => :alatch_addr
    port :data_in => [:addr_latch, :data_in]
    port :agen_eff_addr => [:addr_latch, :addr_in]
    port :ctrl_load_addr_lo => [:addr_latch, :load_lo]
    port :ctrl_load_addr_hi => [:addr_latch, :load_hi]
    port :alatch_addr_lo => [:addr_gen, :indirect_lo]
    port :alatch_addr_hi => [:addr_gen, :indirect_hi]

    # Data latch connections
    port [:data_latch, :data] => :dlatch_data
    port :data_in => [:data_latch, :data_in]
    port :ctrl_load_data => [:data_latch, :load]

    # Combinational logic
    behavior do
      # Stack address computation (0x0100 + SP forms stack address in page 1)
      stack_addr <= cat(lit(0x01, width: 8), sp_val)
      stack_addr_plus1 <= cat(lit(0x01, width: 8), sp_val + lit(1, width: 8))

      # PC byte extraction
      pc_hi_byte <= pc_val[15..8]
      pc_lo_byte <= pc_val[7..0]

      # State detection
      is_execute_state <= (ctrl_state == lit(ControlUnit::STATE_EXECUTE, width: 8))

      # Addressing mode detection
      load_from_imm <= (dec_addr_mode == lit(AddressGenerator::MODE_IMMEDIATE, width: 4))
      load_from_mem <= ~load_from_imm

      # ALU input A selection (src_reg: 0=A, 1=X, 2=Y, 3=memory)
      alu_a_sel <= mux(dec_src_reg[1],
                       mux(dec_src_reg[0], dlatch_data, regs_y),
                       mux(dec_src_reg[0], regs_x, regs_a))

      # ALU input B selection
      alu_b_sel <= mux(load_from_imm, ir_operand_lo, dlatch_data)

      # Register data input selection
      # For loads: immediate uses operand, memory uses data latch
      # For transfers/ALU ops: ALU result (which passes through the value)
      actual_reg_data <= mux(ext_a_load_en | ext_x_load_en | ext_y_load_en,
                             mux(ext_a_load_en, ext_a_load_data,
                                 mux(ext_x_load_en, ext_x_load_data, ext_y_load_data)),
                             mux(load_from_imm, ir_operand_lo,
                                 mux(load_from_mem, dlatch_data, alu_result)))

      # Register load enables
      # External loads have priority, then internal writes based on dst_reg
      actual_load_a <= ext_a_load_en |
                       (ctrl_reg_write & is_execute_state &
                        (dec_dst_reg == lit(MOS6502::REG_A, width: 2)))
      actual_load_x <= ext_x_load_en |
                       (ctrl_reg_write & is_execute_state &
                        (dec_dst_reg == lit(MOS6502::REG_X, width: 2)))
      actual_load_y <= ext_y_load_en |
                       (ctrl_reg_write & is_execute_state &
                        (dec_dst_reg == lit(MOS6502::REG_Y, width: 2)))

      # PC control
      actual_pc_load <= ext_pc_load_en | ctrl_pc_load
      actual_pc_addr <= mux(ext_pc_load_en, ext_pc_load_data, agen_eff_addr)

      # SP control
      actual_sp_load <= ext_sp_load_en
      actual_sp_data <= ext_sp_load_data

      # Flag update enables
      actual_load_n <= ctrl_update_flags & is_execute_state & dec_sets_nz
      actual_load_z <= ctrl_update_flags & is_execute_state & dec_sets_nz
      actual_load_c <= ctrl_update_flags & is_execute_state & dec_sets_c
      actual_load_v <= ctrl_update_flags & is_execute_state & dec_sets_v

      # Flag input values from ALU
      flag_n_in <= alu_n
      flag_z_in <= alu_z
      flag_c_in <= alu_c
      flag_v_in <= alu_v

      # Address bus mux (8-way based on ctrl_addr_sel)
      addr <= mux(ctrl_addr_sel[2],
                  mux(ctrl_addr_sel[1],
                      mux(ctrl_addr_sel[0], lit(0xFFFE, width: 16), stack_addr_plus1),
                      mux(ctrl_addr_sel[0], stack_addr, agen_eff_addr)),
                  mux(ctrl_addr_sel[1],
                      mux(ctrl_addr_sel[0], acalc_ptr_addr_hi, acalc_ptr_addr_lo),
                      mux(ctrl_addr_sel[0], lit(0xFFFC, width: 16), pc_val)))

      # Data output mux (7-way based on ctrl_data_sel)
      data_out <= mux(ctrl_data_sel[2],
                      mux(ctrl_data_sel[1],
                          mux(ctrl_data_sel[0], regs_a, regs_y),
                          mux(ctrl_data_sel[0], regs_x, (sr_p | lit(0x30, width: 8)))),
                      mux(ctrl_data_sel[1],
                          mux(ctrl_data_sel[0], pc_lo_byte, pc_hi_byte),
                          mux(ctrl_data_sel[0], alu_result, regs_a)))

      # RW signal
      rw <= ~ctrl_mem_write

      # Sync signal
      sync <= (ctrl_state == lit(ControlUnit::STATE_FETCH, width: 8))

      # Debug outputs
      reg_a <= regs_a
      reg_x <= regs_x
      reg_y <= regs_y
      reg_sp <= sp_val
      reg_pc <= pc_val
      reg_p <= sr_p
      opcode <= ir_opcode
      state <= ctrl_state
      halted <= ctrl_halted
      cycle_count <= ctrl_cycle_count
    end

    # Override propagate to ensure correct simulation order:
    # 1. First propagate subcomponents to get their outputs (control signals, etc.)
    # 2. Run behavior block to compute derived signals from those outputs
    # 3. Propagate subcomponents again since derived signals feed into inputs
    # 4. Run behavior block again to update outputs with final values
    def propagate
      # First pass: propagate subcomponents to get control unit outputs, etc.
      propagate_subcomponents if @local_dependency_graph && !@subcomponents.empty?

      # Compute derived signals from subcomponent outputs
      execute_behavior if self.class.behavior_defined?

      # Second pass: propagate subcomponents with updated derived signals
      propagate_subcomponents if @local_dependency_graph && !@subcomponents.empty?

      # Final behavior pass to ensure outputs reflect final state
      execute_behavior if self.class.behavior_defined?
    end

    def self.verilog_module_name
      'mos6502_cpu'
    end

    def self.to_verilog(top_name: nil)
      name = top_name || verilog_module_name
      RHDL::Export::Verilog.generate(to_ir(top_name: name))
    end
  end
end
