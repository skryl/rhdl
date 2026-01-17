# MOS 6502 ALU - Fully Synthesizable DSL Version
# Complete implementation with Binary Coded Decimal (BCD) mode
# Uses extended_behavior DSL for Verilog/VHDL export

require_relative '../../lib/rhdl'
require_relative '../../lib/rhdl/dsl/extended_behavior'

module MOS6502
  class ALU < RHDL::HDL::SimComponent
    include RHDL::DSL::ExtendedBehavior

    # ALU Operation codes (same as original ALU)
    OP_ADC = 0x00  # Add with carry
    OP_SBC = 0x01  # Subtract with borrow (carry inverted)
    OP_AND = 0x02  # Bitwise AND
    OP_ORA = 0x03  # Bitwise OR
    OP_EOR = 0x04  # Bitwise XOR
    OP_ASL = 0x05  # Arithmetic shift left
    OP_LSR = 0x06  # Logical shift right
    OP_ROL = 0x07  # Rotate left through carry
    OP_ROR = 0x08  # Rotate right through carry
    OP_INC = 0x09  # Increment
    OP_DEC = 0x0A  # Decrement
    OP_CMP = 0x0B  # Compare
    OP_BIT = 0x0C  # Bit test
    OP_TST = 0x0D  # Pass through A
    OP_NOP = 0x0F  # No operation

    port_input :a, width: 8
    port_input :b, width: 8
    port_input :c_in
    port_input :d_flag
    port_input :op, width: 4

    port_output :result, width: 8
    port_output :n
    port_output :z
    port_output :c
    port_output :v

    # Full synthesizable propagate with BCD support
    # All logic is expressed in terms that can be directly translated to Verilog
    def propagate
      a_val = in_val(:a) & 0xFF
      b_val = in_val(:b) & 0xFF
      c_in_val = in_val(:c_in) & 1
      d_flag_val = in_val(:d_flag) & 1
      op_val = in_val(:op) & 0x0F

      res = 0
      c_out = 0
      v_out = 0
      n_out = 0
      z_out = 0

      case op_val
      when OP_ADC
        if d_flag_val == 1
          # BCD addition - fully synthesizable
          # Split into nibbles
          al = a_val & 0x0F
          ah = (a_val >> 4) & 0x0F
          bl = b_val & 0x0F
          bh = (b_val >> 4) & 0x0F

          # Add low nibble with carry
          sum_l = al + bl + c_in_val

          # BCD correction for low nibble
          # If sum > 9 or half-carry, add 6
          carry_l = (sum_l > 9) ? 1 : 0
          adj_l = (sum_l > 9) ? ((sum_l + 6) & 0x0F) : (sum_l & 0x0F)

          # Add high nibble with carry from low
          sum_h = ah + bh + carry_l

          # BCD correction for high nibble
          carry_h = (sum_h > 9) ? 1 : 0
          adj_h = (sum_h > 9) ? ((sum_h + 6) & 0x0F) : (sum_h & 0x0F)

          res = (adj_h << 4) | adj_l
          c_out = carry_h

          # V flag for BCD (same as binary)
          a_sign = (a_val >> 7) & 1
          b_sign = (b_val >> 7) & 1
          r_sign = (res >> 7) & 1
          v_out = ((a_sign == b_sign) && (r_sign != a_sign)) ? 1 : 0
        else
          # Binary addition
          sum = a_val + b_val + c_in_val
          res = sum & 0xFF
          c_out = (sum >> 8) & 1

          # Overflow flag
          a_sign = (a_val >> 7) & 1
          b_sign = (b_val >> 7) & 1
          r_sign = (res >> 7) & 1
          v_out = ((a_sign == b_sign) && (r_sign != a_sign)) ? 1 : 0
        end
        n_out = (res >> 7) & 1
        z_out = (res == 0) ? 1 : 0

      when OP_SBC
        if d_flag_val == 1
          # BCD subtraction - fully synthesizable
          al = a_val & 0x0F
          ah = (a_val >> 4) & 0x0F
          bl = b_val & 0x0F
          bh = (b_val >> 4) & 0x0F

          # Borrow from carry (c_in=1 means no borrow)
          borrow_in = (c_in_val == 1) ? 0 : 1

          # Subtract low nibble
          diff_l = al - bl - borrow_in

          # BCD correction for low nibble (if negative, add 10)
          borrow_l = (diff_l < 0) ? 1 : 0
          adj_l = (diff_l < 0) ? ((diff_l + 10) & 0x0F) : (diff_l & 0x0F)

          # Subtract high nibble with borrow
          diff_h = ah - bh - borrow_l

          # BCD correction for high nibble
          borrow_h = (diff_h < 0) ? 1 : 0
          adj_h = (diff_h < 0) ? ((diff_h + 10) & 0x0F) : (diff_h & 0x0F)

          res = (adj_h << 4) | adj_l
          c_out = (borrow_h == 0) ? 1 : 0  # C set if no borrow

          # V flag
          a_sign = (a_val >> 7) & 1
          b_sign = (b_val >> 7) & 1
          r_sign = (res >> 7) & 1
          v_out = ((a_sign != b_sign) && (r_sign != a_sign)) ? 1 : 0
        else
          # Binary subtraction: A - M - !C = A + ~M + C
          b_comp = (~b_val) & 0xFF
          sum = a_val + b_comp + c_in_val
          res = sum & 0xFF
          c_out = (sum >> 8) & 1

          # V flag
          a_sign = (a_val >> 7) & 1
          b_sign = (b_val >> 7) & 1
          r_sign = (res >> 7) & 1
          v_out = ((a_sign != b_sign) && (r_sign != a_sign)) ? 1 : 0
        end
        n_out = (res >> 7) & 1
        z_out = (res == 0) ? 1 : 0

      when OP_AND
        res = a_val & b_val
        n_out = (res >> 7) & 1
        z_out = (res == 0) ? 1 : 0

      when OP_ORA
        res = a_val | b_val
        n_out = (res >> 7) & 1
        z_out = (res == 0) ? 1 : 0

      when OP_EOR
        res = a_val ^ b_val
        n_out = (res >> 7) & 1
        z_out = (res == 0) ? 1 : 0

      when OP_ASL
        res = (a_val << 1) & 0xFF
        c_out = (a_val >> 7) & 1
        n_out = (res >> 7) & 1
        z_out = (res == 0) ? 1 : 0

      when OP_LSR
        res = a_val >> 1
        c_out = a_val & 1
        n_out = 0
        z_out = (res == 0) ? 1 : 0

      when OP_ROL
        res = ((a_val << 1) | c_in_val) & 0xFF
        c_out = (a_val >> 7) & 1
        n_out = (res >> 7) & 1
        z_out = (res == 0) ? 1 : 0

      when OP_ROR
        res = (a_val >> 1) | (c_in_val << 7)
        c_out = a_val & 1
        n_out = (res >> 7) & 1
        z_out = (res == 0) ? 1 : 0

      when OP_INC
        res = (a_val + 1) & 0xFF
        n_out = (res >> 7) & 1
        z_out = (res == 0) ? 1 : 0

      when OP_DEC
        res = (a_val - 1) & 0xFF
        n_out = (res >> 7) & 1
        z_out = (res == 0) ? 1 : 0

      when OP_CMP
        diff = a_val - b_val
        res = diff & 0xFF
        c_out = (a_val >= b_val) ? 1 : 0
        n_out = (res >> 7) & 1
        z_out = (a_val == b_val) ? 1 : 0

      when OP_BIT
        res = a_val
        n_out = (b_val >> 7) & 1
        v_out = (b_val >> 6) & 1
        z_out = ((a_val & b_val) == 0) ? 1 : 0

      when OP_TST
        res = a_val
        n_out = (res >> 7) & 1
        z_out = (res == 0) ? 1 : 0

      when OP_NOP
        res = a_val
        c_out = c_in_val
      end

      out_set(:result, res)
      out_set(:n, n_out)
      out_set(:z, z_out)
      out_set(:c, c_out)
      out_set(:v, v_out)
    end

    # Generate Verilog for this ALU
    # This method produces synthesizable Verilog code
    def self.to_verilog
      <<~VERILOG
        // MOS 6502 ALU - Synthesizable Verilog
        // Generated from RHDL DSL

        module mos6502_alu (
          input  [7:0] a,
          input  [7:0] b,
          input        c_in,
          input        d_flag,
          input  [3:0] op,
          output reg [7:0] result,
          output reg       n,
          output reg       z,
          output reg       c,
          output reg       v
        );

          // Operation codes
          localparam OP_ADC = 4'h0;
          localparam OP_SBC = 4'h1;
          localparam OP_AND = 4'h2;
          localparam OP_ORA = 4'h3;
          localparam OP_EOR = 4'h4;
          localparam OP_ASL = 4'h5;
          localparam OP_LSR = 4'h6;
          localparam OP_ROL = 4'h7;
          localparam OP_ROR = 4'h8;
          localparam OP_INC = 4'h9;
          localparam OP_DEC = 4'hA;
          localparam OP_CMP = 4'hB;
          localparam OP_BIT = 4'hC;
          localparam OP_TST = 4'hD;
          localparam OP_NOP = 4'hF;

          // Internal wires for BCD arithmetic
          wire [3:0] al, ah, bl, bh;
          wire [4:0] sum_l_raw, sum_h_raw;
          wire carry_l, carry_h;
          wire [3:0] adj_l, adj_h;
          wire [4:0] diff_l_raw, diff_h_raw;
          wire borrow_l, borrow_h;
          wire [3:0] sub_adj_l, sub_adj_h;
          wire [8:0] bin_sum;
          wire [8:0] bin_diff;

          // Split operands into nibbles
          assign al = a[3:0];
          assign ah = a[7:4];
          assign bl = b[3:0];
          assign bh = b[7:4];

          // BCD addition - low nibble
          assign sum_l_raw = al + bl + c_in;
          assign carry_l = (sum_l_raw > 9) ? 1'b1 : 1'b0;
          assign adj_l = (sum_l_raw > 9) ? (sum_l_raw + 6) : sum_l_raw;

          // BCD addition - high nibble
          assign sum_h_raw = ah + bh + carry_l;
          assign carry_h = (sum_h_raw > 9) ? 1'b1 : 1'b0;
          assign adj_h = (sum_h_raw > 9) ? (sum_h_raw + 6) : sum_h_raw;

          // BCD subtraction - low nibble
          assign diff_l_raw = al - bl - (~c_in);
          assign borrow_l = diff_l_raw[4];  // Sign bit indicates borrow
          assign sub_adj_l = borrow_l ? (diff_l_raw + 10) : diff_l_raw;

          // BCD subtraction - high nibble
          assign diff_h_raw = ah - bh - borrow_l;
          assign borrow_h = diff_h_raw[4];
          assign sub_adj_h = borrow_h ? (diff_h_raw + 10) : diff_h_raw;

          // Binary arithmetic
          assign bin_sum = a + b + c_in;
          assign bin_diff = a + (~b) + c_in;

          always @* begin
            // Default outputs
            result = 8'h00;
            n = 1'b0;
            z = 1'b0;
            c = 1'b0;
            v = 1'b0;

            case (op)
              OP_ADC: begin
                if (d_flag) begin
                  // BCD addition
                  result = {adj_h, adj_l};
                  c = carry_h;
                end else begin
                  // Binary addition
                  result = bin_sum[7:0];
                  c = bin_sum[8];
                end
                n = result[7];
                z = (result == 8'h00);
                v = (a[7] == b[7]) && (result[7] != a[7]);
              end

              OP_SBC: begin
                if (d_flag) begin
                  // BCD subtraction
                  result = {sub_adj_h, sub_adj_l};
                  c = ~borrow_h;
                end else begin
                  // Binary subtraction
                  result = bin_diff[7:0];
                  c = bin_diff[8];
                end
                n = result[7];
                z = (result == 8'h00);
                v = (a[7] != b[7]) && (result[7] != a[7]);
              end

              OP_AND: begin
                result = a & b;
                n = result[7];
                z = (result == 8'h00);
              end

              OP_ORA: begin
                result = a | b;
                n = result[7];
                z = (result == 8'h00);
              end

              OP_EOR: begin
                result = a ^ b;
                n = result[7];
                z = (result == 8'h00);
              end

              OP_ASL: begin
                result = {a[6:0], 1'b0};
                c = a[7];
                n = result[7];
                z = (result == 8'h00);
              end

              OP_LSR: begin
                result = {1'b0, a[7:1]};
                c = a[0];
                n = 1'b0;
                z = (result == 8'h00);
              end

              OP_ROL: begin
                result = {a[6:0], c_in};
                c = a[7];
                n = result[7];
                z = (result == 8'h00);
              end

              OP_ROR: begin
                result = {c_in, a[7:1]};
                c = a[0];
                n = result[7];
                z = (result == 8'h00);
              end

              OP_INC: begin
                result = a + 8'h01;
                n = result[7];
                z = (result == 8'h00);
              end

              OP_DEC: begin
                result = a - 8'h01;
                n = result[7];
                z = (result == 8'h00);
              end

              OP_CMP: begin
                result = a - b;
                c = (a >= b);
                n = result[7];
                z = (a == b);
              end

              OP_BIT: begin
                result = a;
                n = b[7];
                v = b[6];
                z = ((a & b) == 8'h00);
              end

              OP_TST: begin
                result = a;
                n = result[7];
                z = (result == 8'h00);
              end

              OP_NOP: begin
                result = a;
                c = c_in;
              end

              default: begin
                result = a;
              end
            endcase
          end

        endmodule
      VERILOG
    end
  end
end
