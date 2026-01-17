# MOS 6502 CPU Datapath - Synthesizable DSL Version
# Integrates all CPU components into a complete datapath
# Sequential - requires always @(posedge clk) for synthesis

require_relative '../../lib/rhdl'
require_relative '../../lib/rhdl/dsl/behavior'
require_relative 'registers'
require_relative 'status_register'
require_relative 'alu'
require_relative 'address_gen'
require_relative 'instruction_decoder'
require_relative 'control_unit'

module MOS6502S
  class Datapath < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    attr_reader :registers, :status_reg, :pc, :sp, :ir, :alu
    attr_reader :control, :decoder, :addr_gen, :addr_latch, :data_latch

    # External interface
    port_input :clk
    port_input :rst
    port_input :rdy              # Ready/halt input
    port_input :irq              # Interrupt request
    port_input :nmi              # Non-maskable interrupt

    # Memory interface
    port_input :data_in, width: 8     # Data from memory
    port_output :data_out, width: 8   # Data to memory
    port_output :addr, width: 16      # Address bus
    port_output :rw                   # Read/Write (1=read, 0=write)
    port_output :sync                 # Opcode fetch cycle

    # Debug outputs
    port_output :reg_a, width: 8
    port_output :reg_x, width: 8
    port_output :reg_y, width: 8
    port_output :reg_sp, width: 8
    port_output :reg_pc, width: 16
    port_output :reg_p, width: 8
    port_output :opcode, width: 8
    port_output :state, width: 8
    port_output :halted
    port_output :cycle_count, width: 32

    def initialize(name = nil)
      super(name)
      create_subcomponents
      @rmw_result_latch = 0  # Holds ALU result during RMW operations
    end

    def create_subcomponents
      # Create all subcomponents
      @registers = add_subcomponent(:registers, Registers.new("regs"))
      @status_reg = add_subcomponent(:status_reg, StatusRegister.new("sr"))
      @pc = add_subcomponent(:pc, ProgramCounter6502.new("pc"))
      @sp = add_subcomponent(:sp, StackPointer6502.new("sp"))
      @ir = add_subcomponent(:ir, InstructionRegister.new("ir"))
      @alu = add_subcomponent(:alu, ALU.new("alu"))
      @control = add_subcomponent(:control, ControlUnit.new("ctrl"))
      @decoder = add_subcomponent(:decoder, InstructionDecoder.new("dec"))
      @addr_gen = add_subcomponent(:addr_gen, AddressGenerator.new("agen"))
      @addr_calc = add_subcomponent(:addr_calc, IndirectAddressCalc.new("acalc"))
      @addr_latch = add_subcomponent(:addr_latch, AddressLatch.new("alat"))
      @data_latch = add_subcomponent(:data_latch, DataLatch.new("dlat"))
    end

    def propagate
      clk = in_val(:clk)
      rst = in_val(:rst)
      rdy = in_val(:rdy)
      data_in = in_val(:data_in)

      # Connect clock and reset to all sequential components
      [@registers, @status_reg, @pc, @sp, @ir, @control, @addr_latch, @data_latch].each do |comp|
        comp.set_input(:clk, clk)
        comp.set_input(:rst, rst)
      end

      @control.set_input(:rdy, rdy)

      # CRITICAL: Sample control signals BEFORE propagating control unit
      # In real hardware, all flip-flops sample their D inputs at the same clock edge.
      # By sampling first, we ensure components see signals from the PREVIOUS state,
      # not the state after the control unit transitions.
      sampled_load_opcode = @control.get_output(:load_opcode)
      sampled_load_operand_lo = @control.get_output(:load_operand_lo)
      sampled_load_operand_hi = @control.get_output(:load_operand_hi)
      sampled_state = @control.get_output(:state)
      sampled_reg_write = @control.get_output(:reg_write)
      sampled_update_flags = @control.get_output(:update_flags)
      sampled_load_data = @control.get_output(:load_data)
      sampled_load_addr_lo = @control.get_output(:load_addr_lo)
      sampled_load_addr_hi = @control.get_output(:load_addr_hi)
      sampled_sp_inc = @control.get_output(:sp_inc)
      sampled_sp_dec = @control.get_output(:sp_dec)
      sampled_pc_inc = @control.get_output(:pc_inc)
      sampled_pc_load = @control.get_output(:pc_load)

      # Now propagate control unit (which will update its state and outputs)
      @control.set_input(:mem_ready, 1)
      @control.propagate

      # Instruction Register - use SAMPLED control signals (from previous state)
      @ir.set_input(:load_opcode, sampled_load_opcode)
      @ir.set_input(:load_operand_lo, sampled_load_operand_lo)
      @ir.set_input(:load_operand_hi, sampled_load_operand_hi)
      @ir.set_input(:data_in, data_in)
      @ir.propagate

      opcode = @ir.get_output(:opcode)
      operand_lo = @ir.get_output(:operand_lo)
      operand_hi = @ir.get_output(:operand_hi)

      # Instruction Decoder
      @decoder.set_input(:opcode, opcode)
      @decoder.propagate

      addr_mode = @decoder.get_output(:addr_mode)
      alu_op = @decoder.get_output(:alu_op)
      instr_type = @decoder.get_output(:instr_type)
      src_reg = @decoder.get_output(:src_reg)
      dst_reg = @decoder.get_output(:dst_reg)

      # Connect decoder outputs to control unit
      @control.set_input(:addr_mode, addr_mode)
      @control.set_input(:instr_type, instr_type)
      @control.set_input(:branch_cond, @decoder.get_output(:branch_cond))
      @control.set_input(:is_read, @decoder.get_output(:is_read))
      @control.set_input(:is_write, @decoder.get_output(:is_write))
      @control.set_input(:is_rmw, @decoder.get_output(:is_rmw))
      @control.set_input(:writes_reg, @decoder.get_output(:writes_reg))
      @control.set_input(:is_status_op, @decoder.get_output(:is_status_op))

      if clk == 0
        @status_reg.propagate  # Get current status first
        @registers.propagate
        @pc.propagate
        @sp.propagate
      end

      # Status flags to control unit (for branch decisions)
      @control.set_input(:flag_n, @status_reg.get_output(:n))
      @control.set_input(:flag_v, @status_reg.get_output(:v))
      @control.set_input(:flag_z, @status_reg.get_output(:z))
      @control.set_input(:flag_c, @status_reg.get_output(:c))

      # Read current register values (don't propagate here - that would cause
      # early rising edge update before ALU computes new values)
      reg_a = @registers.get_output(:a)
      reg_x = @registers.get_output(:x)
      reg_y = @registers.get_output(:y)
      sp_val = @sp.read_sp
      pc_val = @pc.read_pc

      # Address Generation
      @addr_gen.set_input(:mode, addr_mode)
      @addr_gen.set_input(:operand_lo, operand_lo)
      @addr_gen.set_input(:operand_hi, operand_hi)
      @addr_gen.set_input(:x_reg, reg_x)
      @addr_gen.set_input(:y_reg, reg_y)
      @addr_gen.set_input(:pc, pc_val)  # PC already points to next instruction after fetch
      @addr_gen.set_input(:sp, sp_val)
      @addr_gen.set_input(:indirect_lo, @addr_latch.get_output(:addr_lo))
      @addr_gen.set_input(:indirect_hi, @addr_latch.get_output(:addr_hi))
      @addr_gen.propagate

      eff_addr = @addr_gen.get_output(:eff_addr)
      page_cross = @addr_gen.get_output(:page_cross)

      @control.set_input(:page_cross, page_cross)

      # Indirect address calculation
      @addr_calc.set_input(:mode, addr_mode)
      @addr_calc.set_input(:operand_lo, operand_lo)
      @addr_calc.set_input(:operand_hi, operand_hi)
      @addr_calc.set_input(:x_reg, reg_x)
      @addr_calc.propagate

      # Use sampled state as state_before (the state BEFORE control unit transitions)
      state_before = sampled_state
      state = @control.get_output(:state)
      state_pre = sampled_state

      # Address bus multiplexer based on addr_sel (use current, not sampled - address is combinational)
      addr_sel = @control.get_output(:addr_sel)
      addr_out = select_address(addr_sel, pc_val, eff_addr, @addr_calc, sp_val)

      # Data latch - use sampled load signal
      @data_latch.set_input(:load, sampled_load_data)
      @data_latch.set_input(:data_in, data_in)
      @data_latch.propagate

      # Address latch for indirect addressing - use sampled load signals
      @addr_latch.set_input(:load_lo, sampled_load_addr_lo)
      @addr_latch.set_input(:load_hi, sampled_load_addr_hi)
      @addr_latch.set_input(:load_full, 0)
      @addr_latch.set_input(:data_in, data_in)
      @addr_latch.set_input(:addr_in, eff_addr)
      @addr_latch.propagate

      # ALU inputs
      # For LOAD instructions, alu_a should be the value being loaded (for N/Z flag computation)
      # For RMW operations (INC/DEC/shift on memory), alu_a should be the memory data
      # For other instructions, use the source register
      if instr_type == InstructionDecoder::TYPE_LOAD
        alu_a = if addr_mode == AddressGenerator::MODE_IMMEDIATE
          operand_lo
        else
          @data_latch.get_output(:data)
        end
      elsif instr_type == InstructionDecoder::TYPE_STACK && opcode == 0x68
        # PLA: use pulled value for flag computation
        alu_a = @data_latch.get_output(:data)
      elsif (instr_type == InstructionDecoder::TYPE_INC_DEC || instr_type == InstructionDecoder::TYPE_SHIFT) &&
            addr_mode != AddressGenerator::MODE_ACCUMULATOR &&
            addr_mode != AddressGenerator::MODE_IMPLIED
        # RMW on memory: use memory data as ALU input
        alu_a = @data_latch.get_output(:data)
      else
        alu_a = select_alu_input_a(src_reg, reg_a, reg_x, reg_y, @data_latch.get_output(:data))
      end
      alu_b = select_alu_input_b(addr_mode, operand_lo, @data_latch.get_output(:data))

      @alu.set_input(:a, alu_a)
      @alu.set_input(:b, alu_b)
      @alu.set_input(:c_in, @status_reg.get_output(:c))
      @alu.set_input(:d_flag, @status_reg.get_output(:d))
      @alu.set_input(:op, alu_op)
      @alu.propagate

      alu_result = @alu.get_output(:result)

      # For RMW operations, latch the ALU result during EXECUTE
      # so we can use it during WRITE (after flags are updated)
      is_rmw = @decoder.get_output(:is_rmw)
      if state_before == ControlUnit::STATE_EXECUTE && is_rmw == 1
        @rmw_result_latch = alu_result
      end

      # Update registers based on control signals - use sampled reg_write
      update_registers(dst_reg, alu_result, data_in, instr_type, addr_mode, state_before, sampled_reg_write)

      # Update status register - use sampled update_flags
      update_status_flags(instr_type, addr_mode, state_before, sampled_update_flags)

      # Program counter updates - use sampled signals
      @pc.set_input(:inc, sampled_pc_inc)
      @pc.set_input(:load, sampled_pc_load)

      # PC load address: from address latch for jumps, or computed for branches
      pc_load_addr = select_pc_load_addr(
        state_before,
        eff_addr,
        @addr_latch.get_output(:addr),
        @addr_latch.get_output(:addr_lo),
        data_in
      )
      @pc.set_input(:addr_in, pc_load_addr)
      @pc.propagate

      # Stack pointer updates - use sampled signals
      @sp.set_input(:inc, sampled_sp_inc)
      @sp.set_input(:dec, sampled_sp_dec)
      @sp.set_input(:load, 0)
      @sp.set_input(:data_in, 0)

      # Handle TXS instruction specially
      if instr_type == InstructionDecoder::TYPE_TRANSFER &&
         state_before == ControlUnit::STATE_EXECUTE &&
         opcode == 0x9A  # TXS
        @sp.set_input(:load, 1)
        @sp.set_input(:data_in, reg_x)
      end

      @sp.propagate

      # Data output multiplexer
      # For RMW operations in WRITE state, use the latched result from EXECUTE
      data_sel = @control.get_output(:data_sel)
      effective_alu_result = if state_before == ControlUnit::STATE_WRITE_MEM && is_rmw == 1
        @rmw_result_latch
      else
        alu_result
      end
      pc_for_data = if state_before == ControlUnit::STATE_JSR_PUSH_HI || state_before == ControlUnit::STATE_JSR_PUSH_LO
        (pc_val - 1) & 0xFFFF
      else
        pc_val
      end
      data_out = select_data_out(data_sel, effective_alu_result, reg_a, reg_x, reg_y,
                                 pc_for_data, @status_reg.get_output(:p))

      # Output signals
      out_set(:addr, addr_out)
      out_set(:data_out, data_out)
      out_set(:rw, @control.get_output(:mem_write) == 1 ? 0 : 1)
      out_set(:sync, state_before == ControlUnit::STATE_FETCH ? 1 : 0)

      # Debug outputs
      out_set(:reg_a, reg_a)
      out_set(:reg_x, reg_x)
      out_set(:reg_y, reg_y)
      out_set(:reg_sp, @sp.read_sp)
      out_set(:reg_pc, @pc.read_pc)
      out_set(:reg_p, @status_reg.get_output(:p))
      out_set(:opcode, opcode)
      out_set(:state, state)
      out_set(:halted, @control.get_output(:halted))
      out_set(:cycle_count, @control.get_output(:cycle_count))
    end

    private

    def select_address(sel, pc, eff_addr, addr_calc, sp_val)
      case sel
      when 0 then pc                                    # Program counter
      when 1 then ControlUnit::RESET_VECTOR            # Reset vector
      when 2 then addr_calc.get_output(:ptr_addr_lo)   # Indirect pointer low
      when 3 then addr_calc.get_output(:ptr_addr_hi)   # Indirect pointer high
      when 4 then eff_addr                             # Effective address
      when 5 then StackPointer6502::STACK_BASE | sp_val                # Stack address
      when 6 then StackPointer6502::STACK_BASE | ((sp_val + 1) & 0xFF) # Stack address + 1
      when 7 then ControlUnit::IRQ_VECTOR              # IRQ vector
      else pc
      end
    end

    def select_alu_input_a(src_reg, a, x, y, mem_data)
      case src_reg
      when REG_A then a
      when REG_X then x
      when REG_Y then y
      else a
      end
    end

    def select_alu_input_b(mode, operand_lo, mem_data)
      if mode == AddressGenerator::MODE_IMMEDIATE
        operand_lo
      else
        mem_data
      end
    end

    def select_data_out(sel, alu_result, a, x, y, pc, status)
      case sel
      when 0 then a              # Accumulator
      when 1 then alu_result     # ALU result
      when 2 then (pc >> 8) & 0xFF  # PC high byte
      when 3 then pc & 0xFF         # PC low byte
      when 4 then status | 0x30     # Status with B and unused set
      when 5 then x              # X register
      when 6 then y              # Y register
      else a
      end
    end

    def select_pc_load_addr(state, eff_addr, latch_addr, latch_lo, data_in)
      case state
      when ControlUnit::STATE_BRANCH_TAKE
        eff_addr
      when ControlUnit::STATE_RTS_PULL_HI
        # Return address from stack - the +1 is handled by pc_inc signal
        ((data_in & 0xFF) << 8) | latch_lo
      when ControlUnit::STATE_RTI_PULL_HI,
           ControlUnit::STATE_BRK_VEC_HI
        ((data_in & 0xFF) << 8) | latch_lo
      else
        eff_addr
      end
    end

    def update_registers(dst_reg, alu_result, data_in, instr_type, addr_mode, state_before, sampled_reg_write)
      reg_write = sampled_reg_write

      @registers.set_input(:load_a, 0)
      @registers.set_input(:load_x, 0)
      @registers.set_input(:load_y, 0)

      if reg_write == 1 && state_before == ControlUnit::STATE_EXECUTE
        # Determine what data to write
        write_data = if instr_type == InstructionDecoder::TYPE_LOAD
          if addr_mode == AddressGenerator::MODE_IMMEDIATE
            @ir.get_output(:operand_lo)
          else
            @data_latch.get_output(:data)
          end
        elsif instr_type == InstructionDecoder::TYPE_STACK && @ir.get_output(:opcode) == 0x68
          @data_latch.get_output(:data)
        elsif instr_type == InstructionDecoder::TYPE_TRANSFER
          handle_transfer_data
        else
          alu_result
        end

        @registers.set_input(:data_in, write_data)

        # Set the appropriate load signal
        actual_dst = get_actual_dst_reg(instr_type, dst_reg)
        case actual_dst
        when REG_A then @registers.set_input(:load_a, 1)
        when REG_X then @registers.set_input(:load_x, 1)
        when REG_Y then @registers.set_input(:load_y, 1)
        end
      end

      @registers.propagate
    end

    def handle_transfer_data
      opcode = @ir.get_output(:opcode)
      case opcode
      when 0xAA then @registers.get_output(:a)   # TAX: A -> X
      when 0x8A then @registers.get_output(:x)   # TXA: X -> A
      when 0xA8 then @registers.get_output(:a)   # TAY: A -> Y
      when 0x98 then @registers.get_output(:y)   # TYA: Y -> A
      when 0xBA then @sp.read_sp                 # TSX: S -> X
      else 0
      end
    end

    def get_actual_dst_reg(instr_type, decoded_dst)
      if instr_type == InstructionDecoder::TYPE_TRANSFER
        opcode = @ir.get_output(:opcode)
        case opcode
        when 0xAA, 0xBA then REG_X  # TAX, TSX -> X
        when 0x8A, 0x98 then REG_A  # TXA, TYA -> A
        when 0xA8 then REG_Y        # TAY -> Y
        else decoded_dst
        end
      else
        decoded_dst
      end
    end

    def update_status_flags(instr_type, addr_mode, state_before, sampled_update_flags)
      update = sampled_update_flags

      @status_reg.set_input(:load_all, 0)
      @status_reg.set_input(:load_flags, 0)
      @status_reg.set_input(:load_n, 0)
      @status_reg.set_input(:load_z, 0)
      @status_reg.set_input(:load_c, 0)
      @status_reg.set_input(:load_v, 0)
      @status_reg.set_input(:load_i, 0)
      @status_reg.set_input(:load_d, 0)
      @status_reg.set_input(:load_b, 0)

      if update == 1 && state_before == ControlUnit::STATE_EXECUTE
        if instr_type == InstructionDecoder::TYPE_FLAG
          # Handle flag instructions
          handle_flag_instruction
        else
          # Update flags from ALU
          sets_nz = @decoder.get_output(:sets_nz)
          sets_c = @decoder.get_output(:sets_c)
          sets_v = @decoder.get_output(:sets_v)

          if sets_nz == 1 || sets_c == 1 || sets_v == 1
            @status_reg.set_input(:n_in, @alu.get_output(:n))
            @status_reg.set_input(:z_in, @alu.get_output(:z))
            @status_reg.set_input(:c_in, @alu.get_output(:c))
            @status_reg.set_input(:v_in, @alu.get_output(:v))

            @status_reg.set_input(:load_n, sets_nz)
            @status_reg.set_input(:load_z, sets_nz)
            @status_reg.set_input(:load_c, sets_c)
            @status_reg.set_input(:load_v, sets_v)
          end
        end
      end

      # Handle PLP instruction after pull completes
      if state_before == ControlUnit::STATE_EXECUTE && instr_type == InstructionDecoder::TYPE_STACK
        opcode = @ir.get_output(:opcode)
        if opcode == 0x28  # PLP
          @status_reg.set_input(:data_in, @data_latch.get_output(:data))
          @status_reg.set_input(:load_all, 1)
        end
      end

      @status_reg.propagate
    end

    def handle_flag_instruction
      opcode = @ir.get_output(:opcode)
      case opcode
      when 0x18  # CLC
        @status_reg.set_input(:c_in, 0)
        @status_reg.set_input(:load_c, 1)
      when 0x38  # SEC
        @status_reg.set_input(:c_in, 1)
        @status_reg.set_input(:load_c, 1)
      when 0x58  # CLI
        @status_reg.set_input(:i_in, 0)
        @status_reg.set_input(:load_i, 1)
      when 0x78  # SEI
        @status_reg.set_input(:i_in, 1)
        @status_reg.set_input(:load_i, 1)
      when 0xB8  # CLV
        @status_reg.set_input(:v_in, 0)
        @status_reg.set_input(:load_v, 1)
      when 0xD8  # CLD
        @status_reg.set_input(:d_in, 0)
        @status_reg.set_input(:load_d, 1)
      when 0xF8  # SED
        @status_reg.set_input(:d_in, 1)
        @status_reg.set_input(:load_d, 1)
      end
    end

    public

    # Public accessors for testing
    def read_a; @registers.read_a; end
    def read_x; @registers.read_x; end
    def read_y; @registers.read_y; end
    def read_sp; @sp.read_sp; end
    def read_pc; @pc.read_pc; end
    def read_p; @status_reg.read_p; end

    def write_a(v); @registers.write_a(v); end
    def write_x(v); @registers.write_x(v); end
    def write_y(v); @registers.write_y(v); end
    def write_sp(v); @sp.write_sp(v); end
    def write_pc(v); @pc.write_pc(v); end
  end
end
