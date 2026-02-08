module apple2_video_generator(
  input clk_14m,
  input clk_7m,
  input ax,
  input cas_n,
  input text_mode,
  input page2,
  input hires_mode,
  input mixed_mode,
  input h0,
  input va,
  input vb,
  input vc,
  input v2,
  input v4,
  input blank,
  input ldps_n,
  input ld194,
  input [7:0] dl,
  input flash_clk,
  output hires,
  output video,
  output color_line
);

  reg [5:0] text_shiftreg;
  reg invert_character;
  reg [7:0] graph_shiftreg;
  reg graphics_time_1;
  reg graphics_time_2;
  reg graphics_time_3;
  reg [1:0] pixel_select;
  reg hires_delayed;
  reg blank_delayed;
  reg video_sig;

  initial begin
    text_shiftreg = 6'd0;
    invert_character = 1'b0;
    graph_shiftreg = 8'd0;
    graphics_time_1 = 1'b0;
    graphics_time_2 = 1'b0;
    graphics_time_3 = 1'b0;
    pixel_select = 2'd0;
    hires_delayed = 1'b0;
    blank_delayed = 1'b0;
    video_sig = 1'b0;
  end

  assign video = video_sig;
  assign color_line = graphics_time_1;
  assign hires = (hires_mode & graphics_time_3);

  always @(posedge clk_14m) begin
  text_shiftreg <= (clk_7m ? text_shiftreg : (ldps_n ? (text_shiftreg >> {{5{1'b0}}, 1'b1}) : {5'd0, 1'b0}));
  invert_character <= (ld194 ? invert_character : ~(dl[7] | (dl[6] & flash_clk)));
  graphics_time_3 <= ((ax & ~cas_n) ? graphics_time_2 : graphics_time_3);
  graphics_time_2 <= ((ax & ~cas_n) ? graphics_time_1 : graphics_time_2);
  graphics_time_1 <= ((ax & ~cas_n) ? ~(text_mode | ((v2 & v4) & mixed_mode)) : graphics_time_1);
  pixel_select <= (ld194 ? pixel_select : ((~hires_mode & graphics_time_3) ? {vc, h0} : {graphics_time_1, dl[7]}));
  hires_delayed <= graph_shiftreg[0];
  graph_shiftreg <= (ld194 ? ((~hires_mode & graphics_time_3) ? {graph_shiftreg[4], graph_shiftreg[7:5], graph_shiftreg[0], graph_shiftreg[3:1]} : (clk_7m ? graph_shiftreg : {graph_shiftreg[4], graph_shiftreg[7:1]})) : dl);
  blank_delayed <= (ld194 ? blank_delayed : blank);
  video_sig <= (blank_delayed ? 1'b0 : ((~hires_mode & graphics_time_3) ? ((pixel_select == 2'd0)) ? graph_shiftreg[0] : ((pixel_select == 2'd1)) ? graph_shiftreg[2] : ((pixel_select == 2'd2)) ? graph_shiftreg[4] : ((pixel_select == 2'd3)) ? graph_shiftreg[6] : graph_shiftreg[0] : (pixel_select[1] ? (pixel_select[0] ? hires_delayed : graph_shiftreg[0]) : (text_shiftreg[0] ^ invert_character))));
  end

endmodule