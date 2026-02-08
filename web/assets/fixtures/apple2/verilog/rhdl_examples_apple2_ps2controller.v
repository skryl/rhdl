module apple2_ps2_controller(
  input clk,
  input reset,
  input ps2_clk,
  input ps2_data,
  output [7:0] scan_code,
  output scan_dav
);

  reg [1:0] ps2_clk_sync;
  reg ps2_data_sync;
  reg [3:0] bit_count;
  reg [10:0] shift_reg;
  reg [7:0] scan_code_reg;
  reg scan_dav_reg;

  initial begin
    ps2_clk_sync = 2'd3;
    ps2_data_sync = 1'b1;
    bit_count = 4'd0;
    shift_reg = 11'd0;
    scan_code_reg = 8'd0;
    scan_dav_reg = 1'b0;
  end

  assign scan_code = scan_code_reg;
  assign scan_dav = scan_dav_reg;

  always @(posedge clk) begin
  if (reset) begin
    ps2_clk_sync <= 2'd3;
    ps2_data_sync <= 1'b1;
    bit_count <= 4'd0;
    shift_reg <= 11'd0;
    scan_code_reg <= 8'd0;
    scan_dav_reg <= 1'b0;
  end
  else begin
    ps2_clk_sync <= {ps2_clk_sync[0], ps2_clk};
    ps2_data_sync <= ps2_data;
    shift_reg <= ((ps2_clk_sync[1] & ~ps2_clk_sync[0]) ? {ps2_data_sync, shift_reg[10:1]} : shift_reg);
    bit_count <= ((ps2_clk_sync[1] & ~ps2_clk_sync[0]) ? ((bit_count == 4'd10) ? 4'd0 : (bit_count + 4'd1)) : bit_count);
    scan_code_reg <= (((ps2_clk_sync[1] & ~ps2_clk_sync[0]) & (bit_count == 4'd10)) ? ((((ps2_clk_sync[1] & ~ps2_clk_sync[0]) ? {ps2_data_sync, shift_reg[10:1]} : shift_reg) >> 1) & 8'd255) : scan_code_reg);
    scan_dav_reg <= (((ps2_clk_sync[1] & ~ps2_clk_sync[0]) & (bit_count == 4'd10)) ? 1'b1 : ((ps2_clk_sync[1] & ~ps2_clk_sync[0]) ? 1'b0 : scan_dav_reg));
  end
  end

endmodule