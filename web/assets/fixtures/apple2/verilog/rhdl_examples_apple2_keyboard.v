module apple2_keyboard(
  input clk_14m,
  input reset,
  input ps2_clk,
  input ps2_data,
  input read,
  output [7:0] k
);

  reg [3:0] state;
  reg [7:0] latched_code;
  reg key_pressed;
  reg shift;
  reg ctrl;
  reg alt;
  reg [7:0] ascii;
  reg prev_code_available;
  reg [7:0] unshifted_ascii;
  reg [7:0] shifted_ascii;
  wire [7:0] code;
  wire code_available;
  wire [7:0] ps2_ctrl__scan_code;
  wire ps2_ctrl__scan_dav;
  reg [7:0] unshifted_rom [0:255];
  reg [7:0] shifted_rom [0:255];

  initial begin
    state = 4'd0;
    latched_code = 8'd0;
    key_pressed = 1'b0;
    shift = 1'b0;
    ctrl = 1'b0;
    alt = 1'b0;
    ascii = 8'd0;
    prev_code_available = 1'b0;
  end

  assign k = (ctrl ? {key_pressed, 2'd0, ((shift ? shifted_ascii : unshifted_ascii) & 5'd31)} : {key_pressed, ((shift ? shifted_ascii : unshifted_ascii) & 7'd127)});
  assign code = ps2_ctrl__scan_code;
  assign code_available = ps2_ctrl__scan_dav;
  assign unshifted_ascii = unshifted_rom[latched_code];
  assign shifted_ascii = shifted_rom[latched_code];

  always @(posedge clk_14m) begin
  if (reset) begin
    state <= 4'd0;
    latched_code <= 8'd0;
    key_pressed <= 1'b0;
    shift <= 1'b0;
    ctrl <= 1'b0;
    alt <= 1'b0;
    ascii <= 8'd0;
    prev_code_available <= 1'b0;
  end
  else begin
    prev_code_available <= code_available;
    state <= ((state == 4'd0)) ? ((code_available & ~prev_code_available) ? 4'd1 : 4'd0) : ((state == 4'd1)) ? 4'd2 : ((state == 4'd2)) ? ((code == 8'd240) ? 4'd3 : ((code == 8'd224) ? 4'd0 : ((((code == 8'd18) | (code == 8'd89)) | (code == 8'd20)) ? 4'd0 : 4'd7))) : ((state == 4'd3)) ? 4'd4 : ((state == 4'd4)) ? 4'd5 : ((state == 4'd5)) ? ((code_available & ~prev_code_available) ? 4'd6 : 4'd5) : ((state == 4'd6)) ? 4'd0 : ((state == 4'd7)) ? 4'd0 : 4'd0;
    shift <= ((state == 4'd1) ? (((code == 8'd18) | (code == 8'd89)) ? 1'b1 : shift) : ((state == 4'd6) ? (((code == 8'd18) | (code == 8'd89)) ? 1'b0 : shift) : shift));
    ctrl <= ((state == 4'd1) ? ((code == 8'd20) ? 1'b1 : ctrl) : ((state == 4'd6) ? ((code == 8'd20) ? 1'b0 : ctrl) : ctrl));
    alt <= ((state == 4'd1) ? ((code == 8'd17) ? 1'b1 : alt) : ((state == 4'd6) ? ((code == 8'd17) ? 1'b0 : alt) : alt));
    latched_code <= ((state == 4'd7) ? code : latched_code);
    key_pressed <= ((state == 4'd7) ? 1'b1 : (read ? 1'b0 : key_pressed));
  end
  end

  apple2_ps2_controller ps2_ctrl (
    .clk(clk_14m),
    .reset(reset),
    .ps2_clk(ps2_clk),
    .ps2_data(ps2_data),
    .scan_code(ps2_ctrl__scan_code),
    .scan_dav(ps2_ctrl__scan_dav)
  );

endmodule