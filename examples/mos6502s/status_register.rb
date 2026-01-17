# MOS 6502 Status Register (P Register) - Synthesizable DSL Version
# Contains the processor status flags:
#   Bit 7: N - Negative
#   Bit 6: V - Overflow
#   Bit 5: - - (always 1)
#   Bit 4: B - Break
#   Bit 3: D - Decimal Mode
#   Bit 2: I - Interrupt Disable
#   Bit 1: Z - Zero
#   Bit 0: C - Carry

require_relative '../../lib/rhdl'
require_relative '../../lib/rhdl/dsl/behavior'
require_relative '../../lib/rhdl/dsl/sequential'

module MOS6502S
  class StatusRegister < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    # Flag bit positions
    FLAG_C = 0  # Carry
    FLAG_Z = 1  # Zero
    FLAG_I = 2  # Interrupt Disable
    FLAG_D = 3  # Decimal Mode
    FLAG_B = 4  # Break
    FLAG_X = 5  # Unused (always 1)
    FLAG_V = 6  # Overflow
    FLAG_N = 7  # Negative

    # Control inputs
    port_input :clk
    port_input :rst

    # Load controls
    port_input :load_all        # Load entire register (from stack pull)
    port_input :load_flags      # Load N, Z, C, V from ALU
    port_input :load_n
    port_input :load_z
    port_input :load_c
    port_input :load_v
    port_input :load_i
    port_input :load_d
    port_input :load_b

    # Flag inputs
    port_input :n_in
    port_input :z_in
    port_input :c_in
    port_input :v_in
    port_input :i_in
    port_input :d_in
    port_input :b_in
    port_input :data_in, width: 8

    # Outputs
    port_output :p, width: 8
    port_output :n
    port_output :v
    port_output :b
    port_output :d
    port_output :i
    port_output :z
    port_output :c

    def initialize(name = nil)
      @p_reg = 0x24  # Initial: I=1, unused bit 5=1
      super(name)
    end

    # Sequential block for p register
    # Priority: reset > load_all > load_flags > individual loads
    sequential clock: :clk, reset: :rst, reset_values: { p: 0x24 } do
      # Build new_p for each priority level using mux
      # For load_all: (data_in | 0x20) & 0xEF - set bit 5, clear bit 4
      load_all_val = (data_in | lit(0x20, width: 8)) & lit(0xEF, width: 8)

      # For load_flags: (p & 0x3C) | (n << 7) | (v << 6) | 0x20 | (z << 1) | c
      # Keep bits 2,3,4,5 (I, D, B, X), update N, V, Z, C
      flags_val = cat(n_in, v_in, lit(1, width: 1), p[4], p[3], p[2], z_in, c_in)

      # For individual loads - build value with conditional updates
      # Each bit: mux(load_x, x_in, p[bit])
      ind_n = mux(load_n, n_in, p[7])
      ind_v = mux(load_v, v_in, p[6])
      ind_b = mux(load_b, b_in, p[4])
      ind_d = mux(load_d, d_in, p[3])
      ind_i = mux(load_i, i_in, p[2])
      ind_z = mux(load_z, z_in, p[1])
      ind_c = mux(load_c, c_in, p[0])
      ind_val = cat(ind_n, ind_v, lit(1, width: 1), ind_b, ind_d, ind_i, ind_z, ind_c)

      # Final priority mux
      p <= mux(load_all, load_all_val,
              mux(load_flags, flags_val, ind_val))
    end

    # Combinational outputs for individual flags
    behavior do
      n <= p[7]
      v <= p[6]
      b <= p[4]
      d <= p[3]
      i <= p[2]
      z <= p[1]
      c <= p[0]
    end

    # Override propagate to maintain internal state for testing
    def propagate
      if rising_edge?
        if in_val(:rst) == 1
          @p_reg = 0x24
        elsif in_val(:load_all) == 1
          @p_reg = (in_val(:data_in) | 0x20) & 0xEF
        elsif in_val(:load_flags) == 1
          @p_reg = (@p_reg & 0x3C) |
                   ((in_val(:n_in) & 1) << FLAG_N) |
                   ((in_val(:v_in) & 1) << FLAG_V) |
                   ((in_val(:z_in) & 1) << FLAG_Z) |
                   ((in_val(:c_in) & 1) << FLAG_C) |
                   0x20
        else
          @p_reg = set_flag_if(@p_reg, FLAG_N, in_val(:n_in), in_val(:load_n))
          @p_reg = set_flag_if(@p_reg, FLAG_Z, in_val(:z_in), in_val(:load_z))
          @p_reg = set_flag_if(@p_reg, FLAG_C, in_val(:c_in), in_val(:load_c))
          @p_reg = set_flag_if(@p_reg, FLAG_V, in_val(:v_in), in_val(:load_v))
          @p_reg = set_flag_if(@p_reg, FLAG_I, in_val(:i_in), in_val(:load_i))
          @p_reg = set_flag_if(@p_reg, FLAG_D, in_val(:d_in), in_val(:load_d))
          @p_reg = set_flag_if(@p_reg, FLAG_B, in_val(:b_in), in_val(:load_b))
        end
        @p_reg |= 0x20  # Bit 5 always 1
      end

      out_set(:p, @p_reg)
      out_set(:n, (@p_reg >> FLAG_N) & 1)
      out_set(:v, (@p_reg >> FLAG_V) & 1)
      out_set(:b, (@p_reg >> FLAG_B) & 1)
      out_set(:d, (@p_reg >> FLAG_D) & 1)
      out_set(:i, (@p_reg >> FLAG_I) & 1)
      out_set(:z, (@p_reg >> FLAG_Z) & 1)
      out_set(:c, (@p_reg >> FLAG_C) & 1)
    end

    private

    def set_flag_if(state, bit, value, load)
      return state unless load == 1
      if value == 1
        state | (1 << bit)
      else
        state & ~(1 << bit)
      end
    end

    public

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: 'mos6502s_status_register'))
    end
  end
end
