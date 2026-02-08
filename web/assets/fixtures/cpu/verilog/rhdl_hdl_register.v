module register #(
  parameter width = 8
) (
  input [7:0] d,
  input clk,
  input rst,
  input en,
  output reg [7:0] q
);


  initial begin
    q = 8'd0;
  end

  always @(posedge clk) begin
  if (rst) begin
    q <= 8'd0;
  end
  else begin
    q <= (en ? d : q);
  end
  end

endmodule