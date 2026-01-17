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
      @state = 0x24  # Initial: I=1, unused bit 5=1
      @prev_clk = 0
      super(name)
    end

    def propagate
      clk = in_val(:clk)
      rising = (@prev_clk == 0 && clk == 1)
      @prev_clk = clk

      if rising
        if in_val(:rst) == 1
          @state = 0x24
        elsif in_val(:load_all) == 1
          # Load from data bus (PLP instruction)
          # Bit 5 is always 1, B flag is ignored on PLP
          @state = (in_val(:data_in) | 0x20) & 0xEF
        elsif in_val(:load_flags) == 1
          # Load N, Z, C, V from ALU operation
          @state = (@state & 0x3C) |  # Keep D, I, B, unused
                   ((in_val(:n_in) & 1) << FLAG_N) |
                   ((in_val(:v_in) & 1) << FLAG_V) |
                   ((in_val(:z_in) & 1) << FLAG_Z) |
                   ((in_val(:c_in) & 1) << FLAG_C) |
                   0x20  # Bit 5 always 1
        else
          # Individual flag updates
          @state = set_flag_if(@state, FLAG_N, in_val(:n_in), in_val(:load_n))
          @state = set_flag_if(@state, FLAG_Z, in_val(:z_in), in_val(:load_z))
          @state = set_flag_if(@state, FLAG_C, in_val(:c_in), in_val(:load_c))
          @state = set_flag_if(@state, FLAG_V, in_val(:v_in), in_val(:load_v))
          @state = set_flag_if(@state, FLAG_I, in_val(:i_in), in_val(:load_i))
          @state = set_flag_if(@state, FLAG_D, in_val(:d_in), in_val(:load_d))
          @state = set_flag_if(@state, FLAG_B, in_val(:b_in), in_val(:load_b))
        end

        # Bit 5 is always 1
        @state |= 0x20
      end

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
      <<~VERILOG
        // MOS 6502 Status Register - Synthesizable Verilog
        module mos6502_status_register (
          input        clk,
          input        rst,
          // Load controls
          input        load_all,
          input        load_flags,
          input        load_n,
          input        load_z,
          input        load_c,
          input        load_v,
          input        load_i,
          input        load_d,
          input        load_b,
          // Flag inputs
          input        n_in,
          input        z_in,
          input        c_in,
          input        v_in,
          input        i_in,
          input        d_in,
          input        b_in,
          input  [7:0] data_in,
          // Outputs
          output reg [7:0] p,
          output       n,
          output       v,
          output       b,
          output       d,
          output       i,
          output       z,
          output       c
        );

          // Flag bit positions
          localparam FLAG_C = 0;
          localparam FLAG_Z = 1;
          localparam FLAG_I = 2;
          localparam FLAG_D = 3;
          localparam FLAG_B = 4;
          localparam FLAG_X = 5;
          localparam FLAG_V = 6;
          localparam FLAG_N = 7;

          always @(posedge clk or posedge rst) begin
            if (rst) begin
              p <= 8'h24;  // I=1, unused=1
            end else if (load_all) begin
              // Load from data bus, bit 5 always 1, B ignored
              p <= (data_in | 8'h20) & 8'hEF;
            end else if (load_flags) begin
              // Load N, Z, C, V from ALU
              p[FLAG_N] <= n_in;
              p[FLAG_V] <= v_in;
              p[FLAG_Z] <= z_in;
              p[FLAG_C] <= c_in;
              p[FLAG_X] <= 1'b1;  // Always 1
            end else begin
              // Individual flag updates
              if (load_n) p[FLAG_N] <= n_in;
              if (load_v) p[FLAG_V] <= v_in;
              if (load_z) p[FLAG_Z] <= z_in;
              if (load_c) p[FLAG_C] <= c_in;
              if (load_i) p[FLAG_I] <= i_in;
              if (load_d) p[FLAG_D] <= d_in;
              if (load_b) p[FLAG_B] <= b_in;
              p[FLAG_X] <= 1'b1;  // Always 1
            end
          end

          // Individual flag outputs
          assign n = p[FLAG_N];
          assign v = p[FLAG_V];
          assign b = p[FLAG_B];
          assign d = p[FLAG_D];
          assign i = p[FLAG_I];
          assign z = p[FLAG_Z];
          assign c = p[FLAG_C];

        endmodule
      VERILOG
    end
  end
end
