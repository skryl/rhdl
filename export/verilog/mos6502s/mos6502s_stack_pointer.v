module mos6502s_stack_pointer(
  input clk,
  input rst,
  input inc,
  input dec,
  input load,
  input [7:0] data_in,
  output reg [7:0] sp,
  output [15:0] addr,
  output [15:0] addr_plus1
);

  assign addr = {8'd1, sp};
  assign addr_plus1 = {8'd1, (sp + 8'd1)[7:0]};

  always @(posedge clk) begin
  if (rst) begin
    sp <= 8'd253;
  end
  else begin
    sp <= (load ? data_in : (dec ? (sp - 8'd1) : (inc ? (sp + 8'd1) : sp)));
  end
  end

endmodule