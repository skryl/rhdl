# MOS 6502 Status Register (P Register)
# Contains the processor status flags:
#   Bit 7: N - Negative
#   Bit 6: V - Overflow
#   Bit 5: - - (always 1)
#   Bit 4: B - Break
#   Bit 3: D - Decimal Mode
#   Bit 2: I - Interrupt Disable
#   Bit 1: Z - Zero
#   Bit 0: C - Carry

module MOS6502
  class StatusRegister < RHDL::HDL::SequentialComponent
    # Flag bit positions
    FLAG_C = 0  # Carry
    FLAG_Z = 1  # Zero
    FLAG_I = 2  # Interrupt Disable
    FLAG_D = 3  # Decimal Mode
    FLAG_B = 4  # Break
    FLAG_X = 5  # Unused (always 1)
    FLAG_V = 6  # Overflow
    FLAG_N = 7  # Negative

    def initialize(name = nil)
      @state = 0x24  # Initial: I=1, unused bit 5=1
      super(name)
    end

    def setup_ports
      # Control inputs
      input :clk
      input :rst

      # Load controls
      input :load_all        # Load entire register (from stack pull)
      input :load_flags      # Load N, Z, C, V from ALU
      input :load_n          # Load just N flag
      input :load_z          # Load just Z flag
      input :load_c          # Load just C flag
      input :load_v          # Load just V flag
      input :load_i          # Load just I flag
      input :load_d          # Load just D flag
      input :load_b          # Load just B flag

      # Flag inputs
      input :n_in            # Negative input
      input :z_in            # Zero input
      input :c_in            # Carry input
      input :v_in            # Overflow input
      input :i_in            # Interrupt disable input
      input :d_in            # Decimal mode input
      input :b_in            # Break flag input
      input :data_in, width: 8  # Full byte input for PLP

      # Outputs - full register and individual flags
      output :p, width: 8    # Full status register
      output :n              # Negative flag
      output :v              # Overflow flag
      output :b              # Break flag (only used when pushed)
      output :d              # Decimal mode
      output :i              # Interrupt disable
      output :z              # Zero flag
      output :c              # Carry flag
    end

    def propagate
      if rising_edge?
        if in_val(:rst) == 1
          # Reset state: I=1, unused=1
          @state = 0x24
        elsif in_val(:load_all) == 1
          # Load from data bus (PLP instruction)
          # Bit 5 is always 1, B flag is ignored on PLP
          @state = (in_val(:data_in) | 0x20) & 0xEF  # Set bit 5, clear bit 4
        elsif in_val(:load_flags) == 1
          # Load N, Z, C, V from ALU operation
          set_flag(FLAG_N, in_val(:n_in))
          set_flag(FLAG_Z, in_val(:z_in))
          set_flag(FLAG_C, in_val(:c_in))
          set_flag(FLAG_V, in_val(:v_in))
        else
          # Individual flag updates
          set_flag(FLAG_N, in_val(:n_in)) if in_val(:load_n) == 1
          set_flag(FLAG_Z, in_val(:z_in)) if in_val(:load_z) == 1
          set_flag(FLAG_C, in_val(:c_in)) if in_val(:load_c) == 1
          set_flag(FLAG_V, in_val(:v_in)) if in_val(:load_v) == 1
          set_flag(FLAG_I, in_val(:i_in)) if in_val(:load_i) == 1
          set_flag(FLAG_D, in_val(:d_in)) if in_val(:load_d) == 1
          set_flag(FLAG_B, in_val(:b_in)) if in_val(:load_b) == 1
        end

        # Bit 5 is always 1
        @state |= 0x20
      end

      # Output full register and individual flags
      out_set(:p, @state)
      out_set(:n, (@state >> FLAG_N) & 1)
      out_set(:v, (@state >> FLAG_V) & 1)
      out_set(:b, (@state >> FLAG_B) & 1)
      out_set(:d, (@state >> FLAG_D) & 1)
      out_set(:i, (@state >> FLAG_I) & 1)
      out_set(:z, (@state >> FLAG_Z) & 1)
      out_set(:c, (@state >> FLAG_C) & 1)
    end

    private

    def set_flag(bit, value)
      if value == 1
        @state |= (1 << bit)
      else
        @state &= ~(1 << bit)
      end
    end

    def get_flag(bit)
      (@state >> bit) & 1
    end
  end
end
