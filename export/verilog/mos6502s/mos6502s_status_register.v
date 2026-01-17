// MOS 6502 Status Register - Synthesizable Verilog
// Generated from RHDL Behavior DSL
module mos6502s_status_register (
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
