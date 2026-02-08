module apple2_disk_ii(
  input clk_14m,
  input clk_2m,
  input pre_phase_zero,
  input io_select,
  input device_select,
  input reset,
  input [15:0] a,
  input [7:0] d_in,
  output [7:0] d_out,
  output [5:0] track,
  output [13:0] track_addr,
  output d1_active,
  output d2_active,
  input [13:0] ram_write_addr,
  input [7:0] ram_di,
  input ram_we
);

  reg [3:0] motor_phase;
  reg drive_on;
  reg drive2_select;
  reg q6;
  reg q7;
  reg [7:0] phase;
  reg [14:0] track_byte_addr;
  reg [5:0] byte_delay;
  wire [7:0] rom_addr;
  wire [7:0] rom_dout;
  wire [7:0] rom__dout;
  reg [7:0] track_memory [0:6655];

  initial begin
    motor_phase = 4'd0;
    drive_on = 1'b0;
    drive2_select = 1'b0;
    q6 = 1'b0;
    q7 = 1'b0;
    phase = 8'd70;
    track_byte_addr = 15'd0;
    byte_delay = 6'd0;
  end

  assign d1_active = (drive_on & ~drive2_select);
  assign d2_active = (drive_on & drive2_select);
  assign track = phase[7:2];
  assign track_addr = track_byte_addr[14:1];
  assign rom_addr = a[7:0];
  assign d_out = (io_select ? rom_dout : (((device_select & (a[3:0] == 4'd12)) & ~track_byte_addr[0]) ? track_memory[track_byte_addr[14:1]] : 8'd0));
  assign rom_dout = rom__dout;

  always @(posedge clk_14m) begin
    if (ram_we) begin
      track_memory[ram_write_addr] <= ram_di;
    end
  end

  always @(posedge clk_2m) begin
  if (reset) begin
    motor_phase <= 4'd0;
    drive_on <= 1'b0;
    drive2_select <= 1'b0;
    q6 <= 1'b0;
    q7 <= 1'b0;
    phase <= 8'd70;
    track_byte_addr <= 15'd0;
    byte_delay <= 6'd0;
  end
  else begin
    motor_phase <= (((pre_phase_zero & device_select) & ~a[3]) ? ((motor_phase & ~(4'd1 << {{2{1'b0}}, a[2:1]})) | ((a[0] ? 4'd1 : 4'd0) << {{2{1'b0}}, a[2:1]})) : motor_phase);
    drive_on <= ((((pre_phase_zero & device_select) & a[3]) & (a[2:1] == 2'd0)) ? a[0] : drive_on);
    drive2_select <= ((((pre_phase_zero & device_select) & a[3]) & (a[2:1] == 2'd1)) ? a[0] : drive2_select);
    q6 <= ((((pre_phase_zero & device_select) & a[3]) & (a[2:1] == 2'd2)) ? a[0] : q6);
    q7 <= ((((pre_phase_zero & device_select) & a[3]) & (a[2:1] == 2'd3)) ? a[0] : q7);
    byte_delay <= (byte_delay - 6'd1);
    track_byte_addr <= ((((device_select & (a[3:0] == 4'd12)) & pre_phase_zero) | (byte_delay == 6'd0)) ? ((track_byte_addr == 15'd13310) ? 15'd0 : (track_byte_addr + 15'd1)) : track_byte_addr);
    byte_delay <= ((((device_select & (a[3:0] == 4'd12)) & pre_phase_zero) | (byte_delay == 6'd0)) ? 6'd0 : byte_delay);
  end
  end

  apple2_disk_iirom rom (
    .clk(clk_14m),
    .addr(rom_addr),
    .dout(rom__dout)
  );

endmodule