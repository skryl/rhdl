// MOS 6502 Program Counter - Synthesizable Verilog
// Generated from RHDL Behavior DSL
module mos6502s_program_counter (
  input         clk,
  input         rst,
  input         inc,
  input         load,
  input  [15:0] addr_in,
  output reg [15:0] pc,
  output  [7:0] pc_hi,
  output  [7:0] pc_lo
);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      pc <= 16'hFFFC;
    end else if (load) begin
      if (inc)
        pc <= addr_in + 16'h0001;
      else
        pc <= addr_in;
    end else if (inc) begin
      pc <= pc + 16'h0001;
    end
  end

  assign pc_hi = pc[15:8];
  assign pc_lo = pc[7:0];

endmodule
