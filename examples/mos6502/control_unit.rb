# MOS 6502 Control Unit
# State machine that sequences instruction execution

module MOS6502
  class ControlUnit < RHDL::HDL::SequentialComponent
    # CPU States
    STATE_RESET       = 0x00  # Reset sequence
    STATE_FETCH       = 0x01  # Fetch opcode
    STATE_DECODE      = 0x02  # Decode instruction
    STATE_FETCH_OP1   = 0x03  # Fetch first operand byte
    STATE_FETCH_OP2   = 0x04  # Fetch second operand byte
    STATE_ADDR_LO     = 0x05  # Fetch address low byte (indirect)
    STATE_ADDR_HI     = 0x06  # Fetch address high byte (indirect)
    STATE_READ_MEM    = 0x07  # Read from effective address
    STATE_EXECUTE     = 0x08  # Execute ALU operation
    STATE_WRITE_MEM   = 0x09  # Write to effective address
    STATE_PUSH        = 0x0A  # Push to stack
    STATE_PULL        = 0x0B  # Pull from stack
    STATE_BRANCH      = 0x0C  # Branch decision
    STATE_BRANCH_TAKE = 0x0D  # Branch taken, add offset
    STATE_JSR_PUSH_HI = 0x0E  # JSR: push PC high
    STATE_JSR_PUSH_LO = 0x0F  # JSR: push PC low
    STATE_RTS_PULL_LO = 0x10  # RTS: pull PC low
    STATE_RTS_PULL_HI = 0x11  # RTS: pull PC high
    STATE_RTI_PULL_P  = 0x12  # RTI: pull status
    STATE_RTI_PULL_LO = 0x13  # RTI: pull PC low
    STATE_RTI_PULL_HI = 0x14  # RTI: pull PC high
    STATE_BRK_PUSH_HI = 0x15  # BRK: push PC high
    STATE_BRK_PUSH_LO = 0x16  # BRK: push PC low
    STATE_BRK_PUSH_P  = 0x17  # BRK: push status
    STATE_BRK_VEC_LO  = 0x18  # BRK: read vector low
    STATE_BRK_VEC_HI  = 0x19  # BRK: read vector high
    STATE_HALT        = 0xFF  # Halted

    # Reset vector address
    RESET_VECTOR = 0xFFFC
    IRQ_VECTOR   = 0xFFFE
    NMI_VECTOR   = 0xFFFA

    def initialize(name = nil)
      @state = STATE_RESET
      @reset_step = 0
      @cycle_count = 0
      super(name)
    end

    def setup_ports
      input :clk
      input :rst
      input :rdy            # Ready signal (for single-stepping)

      # Decoded instruction info
      input :addr_mode, width: 4
      input :instr_type, width: 4
      input :branch_cond, width: 3
      input :is_read
      input :is_write
      input :is_rmw
      input :writes_reg             # Instruction writes to register

      # Status flags for branch decisions
      input :flag_n
      input :flag_v
      input :flag_z
      input :flag_c

      # Page crossing
      input :page_cross

      # Memory ready
      input :mem_ready

      # Control outputs
      output :state, width: 8         # Current state
      output :pc_inc                  # Increment program counter
      output :pc_load                 # Load program counter
      output :load_opcode             # Load instruction register
      output :load_operand_lo         # Load operand low byte
      output :load_operand_hi         # Load operand high byte
      output :load_addr_lo            # Load address latch low
      output :load_addr_hi            # Load address latch high
      output :load_data               # Load data latch
      output :mem_read                # Memory read enable
      output :mem_write               # Memory write enable
      output :addr_sel, width: 3      # Address source select
      output :data_sel, width: 3      # Data source select
      output :alu_enable              # Enable ALU operation
      output :reg_write               # Write to register file
      output :sp_inc                  # Increment stack pointer
      output :sp_dec                  # Decrement stack pointer
      output :update_flags            # Update status flags
      output :done                    # Instruction complete
      output :halted                  # CPU halted
      output :cycle_count, width: 32  # Total cycles executed
    end

    def propagate
      # Output control signals FIRST, based on current state
      # This ensures the signals reflect the state BEFORE any transitions
      output_control_signals

      # Then advance state machine on rising edge
      if rising_edge?
        if in_val(:rst) == 1
          @state = STATE_RESET
          @reset_step = 0
          @cycle_count = 0
        elsif in_val(:rdy) == 1
          @cycle_count += 1
          execute_state_machine
        end
      end

      # Output state AFTER transition so callers can see current state
      out_set(:state, @state)
      out_set(:cycle_count, @cycle_count)
    end

    private

    def execute_state_machine
      case @state
      when STATE_RESET
        @reset_step += 1
        if @reset_step >= 6
          @state = STATE_FETCH
        end

      when STATE_FETCH
        @state = STATE_DECODE

      when STATE_DECODE
        @state = next_state_after_decode

      when STATE_FETCH_OP1
        mode = in_val(:addr_mode)
        case mode
        when AddressGenerator::MODE_IMMEDIATE
          @state = STATE_EXECUTE
        when AddressGenerator::MODE_ZERO_PAGE,
             AddressGenerator::MODE_ZERO_PAGE_X,
             AddressGenerator::MODE_ZERO_PAGE_Y
          if needs_memory_read?
            @state = STATE_READ_MEM
          elsif in_val(:is_write) == 1
            @state = STATE_WRITE_MEM
          else
            @state = STATE_EXECUTE
          end
        when AddressGenerator::MODE_RELATIVE
          @state = STATE_BRANCH
        when AddressGenerator::MODE_INDEXED_IND,
             AddressGenerator::MODE_INDIRECT_IDX
          @state = STATE_ADDR_LO
        else
          @state = STATE_FETCH_OP2
        end

      when STATE_FETCH_OP2
        mode = in_val(:addr_mode)
        if mode == AddressGenerator::MODE_INDIRECT
          @state = STATE_ADDR_LO
        elsif needs_memory_read?
          @state = STATE_READ_MEM
        elsif in_val(:is_write) == 1
          @state = STATE_WRITE_MEM
        else
          @state = STATE_EXECUTE
        end

      when STATE_ADDR_LO
        @state = STATE_ADDR_HI

      when STATE_ADDR_HI
        mode = in_val(:addr_mode)
        if mode == AddressGenerator::MODE_INDIRECT
          # JMP indirect
          @state = STATE_EXECUTE
        elsif needs_memory_read?
          @state = STATE_READ_MEM
        elsif in_val(:is_write) == 1
          @state = STATE_WRITE_MEM
        else
          @state = STATE_EXECUTE
        end

      when STATE_READ_MEM
        if in_val(:is_rmw) == 1
          @state = STATE_EXECUTE
        else
          @state = STATE_EXECUTE
        end

      when STATE_EXECUTE
        if in_val(:is_rmw) == 1
          @state = STATE_WRITE_MEM
        else
          @state = STATE_FETCH
        end

      when STATE_WRITE_MEM
        @state = STATE_FETCH

      when STATE_BRANCH
        if branch_taken?
          @state = STATE_BRANCH_TAKE
        else
          @state = STATE_FETCH
        end

      when STATE_BRANCH_TAKE
        # Add extra cycle if page crossed
        if in_val(:page_cross) == 1
          # Extra cycle already counted, go to fetch
          @state = STATE_FETCH
        else
          @state = STATE_FETCH
        end

      when STATE_PUSH
        @state = STATE_FETCH

      when STATE_PULL
        @state = STATE_EXECUTE

      when STATE_JSR_PUSH_HI
        @state = STATE_JSR_PUSH_LO

      when STATE_JSR_PUSH_LO
        @state = STATE_EXECUTE

      when STATE_RTS_PULL_LO
        @state = STATE_RTS_PULL_HI

      when STATE_RTS_PULL_HI
        @state = STATE_FETCH

      when STATE_RTI_PULL_P
        @state = STATE_RTI_PULL_LO

      when STATE_RTI_PULL_LO
        @state = STATE_RTI_PULL_HI

      when STATE_RTI_PULL_HI
        @state = STATE_FETCH

      when STATE_BRK_PUSH_HI
        @state = STATE_BRK_PUSH_LO

      when STATE_BRK_PUSH_LO
        @state = STATE_BRK_PUSH_P

      when STATE_BRK_PUSH_P
        @state = STATE_BRK_VEC_LO

      when STATE_BRK_VEC_LO
        @state = STATE_BRK_VEC_HI

      when STATE_BRK_VEC_HI
        @state = STATE_FETCH

      when STATE_HALT
        # Stay halted
      end
    end

    def next_state_after_decode
      type = in_val(:instr_type)
      mode = in_val(:addr_mode)

      case type
      when InstructionDecoder::TYPE_ALU,
           InstructionDecoder::TYPE_LOAD,
           InstructionDecoder::TYPE_STORE,
           InstructionDecoder::TYPE_INC_DEC,
           InstructionDecoder::TYPE_SHIFT
        if mode == AddressGenerator::MODE_IMPLIED ||
           mode == AddressGenerator::MODE_ACCUMULATOR
          STATE_EXECUTE
        else
          STATE_FETCH_OP1
        end

      when InstructionDecoder::TYPE_TRANSFER,
           InstructionDecoder::TYPE_FLAG,
           InstructionDecoder::TYPE_NOP
        STATE_EXECUTE

      when InstructionDecoder::TYPE_BRANCH
        STATE_FETCH_OP1

      when InstructionDecoder::TYPE_JUMP
        handle_jump_decode

      when InstructionDecoder::TYPE_STACK
        handle_stack_decode

      when InstructionDecoder::TYPE_BRK
        STATE_BRK_PUSH_HI

      else
        STATE_FETCH  # Unknown, skip
      end
    end

    def handle_jump_decode
      # Based on the mnemonic stored during decode
      case in_val(:addr_mode)
      when AddressGenerator::MODE_IMPLIED
        # RTS or RTI
        # We need to check which one... simplified: just use RTS states
        STATE_RTS_PULL_LO
      when AddressGenerator::MODE_ABSOLUTE
        # JMP or JSR
        STATE_FETCH_OP1
      when AddressGenerator::MODE_INDIRECT
        STATE_FETCH_OP1
      else
        STATE_FETCH
      end
    end

    def handle_stack_decode
      # PHA, PHP = push, PLA, PLP = pull
      if in_val(:is_write) == 1
        STATE_PUSH
      else
        STATE_PULL
      end
    end

    def needs_memory_read?
      in_val(:is_read) == 1 || in_val(:is_rmw) == 1
    end

    def branch_taken?
      cond = in_val(:branch_cond)
      case cond
      when InstructionDecoder::BRANCH_BPL
        in_val(:flag_n) == 0
      when InstructionDecoder::BRANCH_BMI
        in_val(:flag_n) == 1
      when InstructionDecoder::BRANCH_BVC
        in_val(:flag_v) == 0
      when InstructionDecoder::BRANCH_BVS
        in_val(:flag_v) == 1
      when InstructionDecoder::BRANCH_BCC
        in_val(:flag_c) == 0
      when InstructionDecoder::BRANCH_BCS
        in_val(:flag_c) == 1
      when InstructionDecoder::BRANCH_BNE
        in_val(:flag_z) == 0
      when InstructionDecoder::BRANCH_BEQ
        in_val(:flag_z) == 1
      else
        false
      end
    end

    def output_control_signals
      # Default all outputs to 0
      # Note: :state is output at the end of propagate, after any transitions
      out_set(:pc_inc, 0)
      out_set(:pc_load, 0)
      out_set(:load_opcode, 0)
      out_set(:load_operand_lo, 0)
      out_set(:load_operand_hi, 0)
      out_set(:load_addr_lo, 0)
      out_set(:load_addr_hi, 0)
      out_set(:load_data, 0)
      out_set(:mem_read, 0)
      out_set(:mem_write, 0)
      out_set(:addr_sel, 0)
      out_set(:data_sel, 0)
      out_set(:alu_enable, 0)
      out_set(:reg_write, 0)
      out_set(:sp_inc, 0)
      out_set(:sp_dec, 0)
      out_set(:update_flags, 0)
      out_set(:done, 0)
      out_set(:halted, @state == STATE_HALT ? 1 : 0)
      # Note: :cycle_count is output at the end of propagate

      case @state
      when STATE_RESET
        out_set(:mem_read, 1)
        out_set(:addr_sel, 1)  # Reset vector address

      when STATE_FETCH
        out_set(:mem_read, 1)
        out_set(:load_opcode, 1)
        out_set(:pc_inc, 1)

      when STATE_DECODE
        # Decode happens combinationally

      when STATE_FETCH_OP1
        out_set(:mem_read, 1)
        out_set(:load_operand_lo, 1)
        out_set(:pc_inc, 1)

      when STATE_FETCH_OP2
        out_set(:mem_read, 1)
        out_set(:load_operand_hi, 1)
        out_set(:pc_inc, 1)

      when STATE_ADDR_LO
        out_set(:mem_read, 1)
        out_set(:load_addr_lo, 1)
        out_set(:addr_sel, 2)  # Indirect pointer address

      when STATE_ADDR_HI
        out_set(:mem_read, 1)
        out_set(:load_addr_hi, 1)
        out_set(:addr_sel, 3)  # Indirect pointer address + 1

      when STATE_READ_MEM
        out_set(:mem_read, 1)
        out_set(:load_data, 1)
        out_set(:addr_sel, 4)  # Effective address

      when STATE_EXECUTE
        out_set(:alu_enable, 1)
        out_set(:reg_write, needs_reg_write?)
        out_set(:update_flags, 1)
        out_set(:done, 1) unless in_val(:is_rmw) == 1

      when STATE_WRITE_MEM
        out_set(:mem_write, 1)
        out_set(:addr_sel, 4)  # Effective address
        out_set(:data_sel, 1)  # ALU result
        out_set(:done, 1)

      when STATE_BRANCH
        # Check condition - next state decision made in state machine

      when STATE_BRANCH_TAKE
        out_set(:pc_load, 1)
        out_set(:done, 1)

      when STATE_PUSH
        out_set(:mem_write, 1)
        out_set(:addr_sel, 5)  # Stack address
        out_set(:sp_dec, 1)
        out_set(:done, 1)

      when STATE_PULL
        out_set(:sp_inc, 1)
        out_set(:mem_read, 1)
        out_set(:addr_sel, 6)  # Stack address + 1
        out_set(:load_data, 1)

      when STATE_JSR_PUSH_HI
        out_set(:mem_write, 1)
        out_set(:addr_sel, 5)
        out_set(:data_sel, 2)  # PC high
        out_set(:sp_dec, 1)

      when STATE_JSR_PUSH_LO
        out_set(:mem_write, 1)
        out_set(:addr_sel, 5)
        out_set(:data_sel, 3)  # PC low
        out_set(:sp_dec, 1)

      when STATE_RTS_PULL_LO
        out_set(:sp_inc, 1)
        out_set(:mem_read, 1)
        out_set(:addr_sel, 6)
        out_set(:load_addr_lo, 1)

      when STATE_RTS_PULL_HI
        out_set(:sp_inc, 1)
        out_set(:mem_read, 1)
        out_set(:addr_sel, 6)
        out_set(:load_addr_hi, 1)
        out_set(:pc_load, 1)
        out_set(:pc_inc, 1)  # RTS adds 1 to popped address
        out_set(:done, 1)

      when STATE_RTI_PULL_P
        out_set(:sp_inc, 1)
        out_set(:mem_read, 1)
        out_set(:addr_sel, 6)
        out_set(:update_flags, 1)

      when STATE_RTI_PULL_LO
        out_set(:sp_inc, 1)
        out_set(:mem_read, 1)
        out_set(:addr_sel, 6)
        out_set(:load_addr_lo, 1)

      when STATE_RTI_PULL_HI
        out_set(:sp_inc, 1)
        out_set(:mem_read, 1)
        out_set(:addr_sel, 6)
        out_set(:load_addr_hi, 1)
        out_set(:pc_load, 1)
        out_set(:done, 1)

      when STATE_BRK_PUSH_HI
        out_set(:mem_write, 1)
        out_set(:addr_sel, 5)
        out_set(:data_sel, 2)
        out_set(:sp_dec, 1)

      when STATE_BRK_PUSH_LO
        out_set(:mem_write, 1)
        out_set(:addr_sel, 5)
        out_set(:data_sel, 3)
        out_set(:sp_dec, 1)

      when STATE_BRK_PUSH_P
        out_set(:mem_write, 1)
        out_set(:addr_sel, 5)
        out_set(:data_sel, 4)  # Status register with B set
        out_set(:sp_dec, 1)

      when STATE_BRK_VEC_LO
        out_set(:mem_read, 1)
        out_set(:addr_sel, 7)  # IRQ vector
        out_set(:load_addr_lo, 1)

      when STATE_BRK_VEC_HI
        out_set(:mem_read, 1)
        out_set(:addr_sel, 7)  # IRQ vector + 1
        out_set(:load_addr_hi, 1)
        out_set(:pc_load, 1)
        out_set(:done, 1)
      end
    end

    def needs_reg_write?
      in_val(:writes_reg)
    end

    public

    # Direct access for debugging
    def current_state
      @state
    end

    def set_state(s)
      @state = s
    end
  end
end
