module stack_pointer #(
  parameter width = 8,
  parameter initial_rhdl = 255
) (
  input clk,
  input rst,
  input push,
  input pop,
  output reg [7:0] q,
  output empty,
  output full
);


  initial begin
    q = 8'd255;
  end

  assign empty = (q == 8'd255);
  assign full = (q == 8'd0);

  always @(posedge clk) begin
  if (rst) begin
    q <= 8'd255;
  end
  else begin
    q <= (push ? (q - 8'd1) : (pop ? (q + 8'd1) : q));
  end
  end

endmodule