module program_counter #(
  parameter width = 16
) (
  input clk,
  input rst,
  input en,
  input load,
  input [15:0] d,
  input [15:0] inc,
  output reg [15:0] q
);


  initial begin
    q = 16'd0;
  end

  always @(posedge clk) begin
  if (rst) begin
    q <= 16'd0;
  end
  else begin
    q <= (load ? d : (en ? (q + ((inc == 16'd0) ? 16'd1 : inc)) : q));
  end
  end

endmodule