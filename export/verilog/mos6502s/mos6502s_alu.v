// MOS 6502 ALU - Synthesizable Verilog
// Generated from RHDL Behavior DSL

module mos6502s_alu (
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
