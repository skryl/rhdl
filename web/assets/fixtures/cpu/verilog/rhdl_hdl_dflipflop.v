module d_flip_flop(
  input d,
  input clk,
  input rst,
  input en,
  output reg q,
  output qn
);


  initial begin
    q = 1'b0;
  end

  assign qn = ~q;

  always @(posedge clk) begin
  if (rst) begin
    q <= 1'b0;
  end
  else begin
    q <= (en ? d : q);
  end
  end

endmodule