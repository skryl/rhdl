module mos6502s_status_register(
  input clk,
  input rst,
  input load_all,
  input load_flags,
  input load_n,
  input load_z,
  input load_c,
  input load_v,
  input load_i,
  input load_d,
  input load_b,
  input n_in,
  input z_in,
  input c_in,
  input v_in,
  input i_in,
  input d_in,
  input b_in,
  input [7:0] data_in,
  output reg [7:0] p,
  output n,
  output v,
  output b,
  output d,
  output i,
  output z,
  output c
);

  assign n = p[7];
  assign v = p[6];
  assign b = p[4];
  assign d = p[3];
  assign i = p[2];
  assign z = p[1];
  assign c = p[0];

  always @(posedge clk) begin
  if (rst) begin
    p <= 8'd36;
  end
  else begin
    p <= (load_all ? ((data_in | 8'd32) & 8'd239) : (load_flags ? {n_in, v_in, 1'b1, p[4], p[3], p[2], z_in, c_in} : {(load_n ? n_in : p[7]), (load_v ? v_in : p[6]), 1'b1, (load_b ? b_in : p[4]), (load_d ? d_in : p[3]), (load_i ? i_in : p[2]), (load_z ? z_in : p[1]), (load_c ? c_in : p[0])}));
  end
  end

endmodule