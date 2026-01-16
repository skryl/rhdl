# MOS 6502 CPU Registers
# Contains A, X, Y registers, Stack Pointer, and Program Counter

module MOS6502
  # Register selection constants
  REG_A  = 0
  REG_X  = 1
  REG_Y  = 2

  # 8-bit General Purpose Registers (A, X, Y)
  # Sequential - requires always @(posedge clk) for synthesis
  class Registers < RHDL::HDL::SequentialComponent
    port_input :clk
    port_input :rst

    # Data input
    port_input :data_in, width: 8

    # Load controls for each register
    port_input :load_a
    port_input :load_x
    port_input :load_y

    # Outputs
    port_output :a, width: 8
    port_output :x, width: 8
    port_output :y, width: 8

    def initialize(name = nil)
      @a = 0  # Accumulator
      @x = 0  # Index X
      @y = 0  # Index Y
      super(name)
    end

    def propagate
      if rising_edge?
        if in_val(:rst) == 1
          @a = 0
          @x = 0
          @y = 0
        else
          @a = in_val(:data_in) & 0xFF if in_val(:load_a) == 1
          @x = in_val(:data_in) & 0xFF if in_val(:load_x) == 1
          @y = in_val(:data_in) & 0xFF if in_val(:load_y) == 1
        end
      end

      out_set(:a, @a)
      out_set(:x, @x)
      out_set(:y, @y)
    end

    # Direct access for testing/debugging
    def read_a; @a; end
    def read_x; @x; end
    def read_y; @y; end
    def write_a(v); @a = v & 0xFF; end
    def write_x(v); @x = v & 0xFF; end
    def write_y(v); @y = v & 0xFF; end
  end

  # 6502 Stack Pointer
  # Stack is located at page 1 ($0100-$01FF)
  # SP points to next free location, decrements on push, increments on pop
  # Sequential - requires always @(posedge clk) for synthesis
  class StackPointer6502 < RHDL::HDL::SequentialComponent
    STACK_BASE = 0x0100  # Stack base address

    port_input :clk
    port_input :rst

    port_input :inc        # Increment (pop)
    port_input :dec        # Decrement (push)
    port_input :load       # Load new value
    port_input :data_in, width: 8

    port_output :sp, width: 8           # Stack pointer value
    port_output :addr, width: 16        # Full stack address ($01xx)
    port_output :addr_plus1, width: 16  # SP+1 address (for reading after pop)

    def initialize(name = nil)
      @state = 0xFD  # Initial SP after reset
      super(name)
    end

    def propagate
      prev_state = @state
      next_state = @state
      if rising_edge?
        if in_val(:rst) == 1
          next_state = 0xFD  # Reset value
        elsif in_val(:load) == 1
          next_state = in_val(:data_in) & 0xFF
        elsif in_val(:dec) == 1
          next_state = (prev_state - 1) & 0xFF
        elsif in_val(:inc) == 1
          next_state = (prev_state + 1) & 0xFF
        end
        @state = next_state
      end

      out_set(:sp, @state)
      out_set(:addr, STACK_BASE | prev_state)
      out_set(:addr_plus1, STACK_BASE | ((prev_state + 1) & 0xFF))
    end

    # Direct access
    def read_sp; @state; end
    def write_sp(v); @state = v & 0xFF; end
  end

  # 6502 Program Counter
  # 16-bit counter that can be loaded or incremented
  # Sequential - requires always @(posedge clk) for synthesis
  class ProgramCounter6502 < RHDL::HDL::SequentialComponent
    port_input :clk
    port_input :rst

    port_input :inc           # Increment PC
    port_input :load          # Load new address
    port_input :addr_in, width: 16

    port_output :pc, width: 16           # Current PC
    port_output :pc_hi, width: 8         # High byte
    port_output :pc_lo, width: 8         # Low byte

    def initialize(name = nil)
      @state = 0x0000
      super(name)
    end

    def propagate
      if rising_edge?
        if in_val(:rst) == 1
          @state = 0xFFFC  # Reset vector location
        elsif in_val(:load) == 1
          next_state = in_val(:addr_in) & 0xFFFF
          next_state = (next_state + 1) & 0xFFFF if in_val(:inc) == 1
          @state = next_state
        elsif in_val(:inc) == 1
          @state = (@state + 1) & 0xFFFF
        end
      end

      out_set(:pc, @state)
      out_set(:pc_hi, (@state >> 8) & 0xFF)
      out_set(:pc_lo, @state & 0xFF)
    end

    # Direct access
    def read_pc; @state; end
    def write_pc(v); @state = v & 0xFFFF; end
  end

  # Instruction Register and Operand Latches
  # Sequential - requires always @(posedge clk) for synthesis
  class InstructionRegister < RHDL::HDL::SequentialComponent
    port_input :clk
    port_input :rst

    port_input :load_opcode
    port_input :load_operand_lo
    port_input :load_operand_hi
    port_input :data_in, width: 8

    port_output :opcode, width: 8
    port_output :operand_lo, width: 8
    port_output :operand_hi, width: 8
    port_output :operand, width: 16       # Combined operand (hi << 8 | lo)

    def initialize(name = nil)
      @opcode = 0
      @operand_lo = 0
      @operand_hi = 0
      super(name)
    end

    def propagate
      if rising_edge?
        if in_val(:rst) == 1
          @opcode = 0
          @operand_lo = 0
          @operand_hi = 0
        else
          @opcode = in_val(:data_in) & 0xFF if in_val(:load_opcode) == 1
          @operand_lo = in_val(:data_in) & 0xFF if in_val(:load_operand_lo) == 1
          @operand_hi = in_val(:data_in) & 0xFF if in_val(:load_operand_hi) == 1
        end
      end

      out_set(:opcode, @opcode)
      out_set(:operand_lo, @operand_lo)
      out_set(:operand_hi, @operand_hi)
      out_set(:operand, (@operand_hi << 8) | @operand_lo)
    end

    # Direct access
    def read_opcode; @opcode; end
    def read_operand; (@operand_hi << 8) | @operand_lo; end
  end

  # Address Latch for effective address calculation
  # Sequential - requires always @(posedge clk) for synthesis
  class AddressLatch < RHDL::HDL::SequentialComponent
    port_input :clk
    port_input :rst

    port_input :load_lo
    port_input :load_hi
    port_input :load_full       # Load complete 16-bit address
    port_input :data_in, width: 8
    port_input :addr_in, width: 16

    port_output :addr, width: 16
    port_output :addr_lo, width: 8
    port_output :addr_hi, width: 8

    def initialize(name = nil)
      @addr_lo = 0
      @addr_hi = 0
      super(name)
    end

    def propagate
      if rising_edge?
        if in_val(:rst) == 1
          @addr_lo = 0
          @addr_hi = 0
        elsif in_val(:load_full) == 1
          addr = in_val(:addr_in) & 0xFFFF
          @addr_lo = addr & 0xFF
          @addr_hi = (addr >> 8) & 0xFF
        else
          @addr_lo = in_val(:data_in) & 0xFF if in_val(:load_lo) == 1
          @addr_hi = in_val(:data_in) & 0xFF if in_val(:load_hi) == 1
        end
      end

      out_set(:addr, (@addr_hi << 8) | @addr_lo)
      out_set(:addr_lo, @addr_lo)
      out_set(:addr_hi, @addr_hi)
    end
  end

  # Data Latch for temporary storage
  # Sequential - requires always @(posedge clk) for synthesis
  class DataLatch < RHDL::HDL::SequentialComponent
    port_input :clk
    port_input :rst
    port_input :load
    port_input :data_in, width: 8

    port_output :data, width: 8

    def initialize(name = nil)
      @data = 0
      super(name)
    end

    def propagate
      if rising_edge?
        if in_val(:rst) == 1
          @data = 0
        elsif in_val(:load) == 1
          @data = in_val(:data_in) & 0xFF
        end
      end

      out_set(:data, @data)
    end
  end
end
