module apple2_apple2(
  input clk_14m,
  input flash_clk,
  input reset,
  output [15:0] ram_addr,
  output ram_we,
  output [7:0] d,
  input [7:0] ram_do,
  input [7:0] pd,
  output video,
  output color_line,
  output hbl,
  output vbl,
  input ps2_clk,
  input ps2_data,
  output read_key,
  output speaker,
  input [7:0] gameport,
  output pdl_strobe,
  output stb,
  output [7:0] io_select,
  output [7:0] device_select,
  output [3:0] an,
  output clk_2m,
  output pre_phase_zero,
  output [15:0] pc_debug,
  output [7:0] opcode_debug,
  output [7:0] a_debug,
  output [7:0] x_debug,
  output [7:0] y_debug,
  output [7:0] s_debug,
  output [7:0] p_debug,
  input pause
);

  reg [7:0] soft_switches;
  reg speaker_select_latch;
  reg [7:0] dl;
  wire [7:0] k;
  wire clk_7m;
  wire q3;
  wire ras_n;
  wire cas_n;
  wire ax;
  wire phi0;
  wire pre_phi0;
  wire color_ref;
  wire [15:0] video_address;
  wire h0;
  wire va;
  wire vb;
  wire vc;
  wire v2;
  wire v4;
  wire blank;
  wire ldps_n;
  wire ld194_i;
  wire hires;
  wire text_mode;
  wire mixed_mode;
  wire page2;
  wire hires_mode;
  wire [15:0] cpu_addr;
  wire cpu_we;
  wire [7:0] cpu_dout;
  wire [7:0] cpu_din;
  wire cpu_enable;
  wire nmi_n;
  wire irq_n;
  wire so_n;
  wire disk_io_select;
  wire disk_device_select;
  wire [7:0] disk_dout;
  wire timing__clk_7m;
  wire timing__q3;
  wire timing__ras_n;
  wire timing__cas_n;
  wire timing__ax;
  wire timing__phi0;
  wire timing__pre_phi0;
  wire timing__color_ref;
  wire [15:0] timing__video_address;
  wire timing__h0;
  wire timing__va;
  wire timing__vb;
  wire timing__vc;
  wire timing__v2;
  wire timing__v4;
  wire timing__hbl;
  wire timing__vbl;
  wire timing__blank;
  wire timing__ldps_n;
  wire timing__ld194;
  wire video_gen__hires;
  wire video_gen__video;
  wire video_gen__color_line;
  wire speaker_toggle__speaker;
  wire [15:0] cpu__addr;
  wire cpu__we;
  wire [7:0] cpu__do_out;
  wire [15:0] cpu__debug_pc;
  wire [7:0] cpu__debug_opcode;
  wire [7:0] cpu__debug_a;
  wire [7:0] cpu__debug_x;
  wire [7:0] cpu__debug_y;
  wire [7:0] cpu__debug_s;
  wire [7:0] cpu__debug_p;
  wire [7:0] disk__d_out;
  wire [7:0] keyboard__k;
  reg [7:0] main_rom [0:12287];

  initial begin
    soft_switches = 8'd0;
    speaker_select_latch = 1'b0;
    dl = 8'd0;
  end

  assign cpu_enable = (~pause & ~pre_phi0);
  assign nmi_n = 1'b1;
  assign irq_n = 1'b1;
  assign so_n = 1'b1;
  assign ram_addr = (phi0 ? cpu_addr : video_address);
  assign ram_we = ((cpu_we & ~ras_n) & phi0);
  assign text_mode = soft_switches[0];
  assign mixed_mode = soft_switches[1];
  assign page2 = soft_switches[2];
  assign hires_mode = soft_switches[3];
  assign an = soft_switches[7:4];
  assign clk_2m = q3;
  assign pre_phase_zero = pre_phi0;
  assign read_key = (((cpu_addr[15:12] == 4'd12) & (cpu_addr[11:8] == 4'd0)) & (cpu_addr[7:4] == 4'd1));
  assign pdl_strobe = (((cpu_addr[15:12] == 4'd12) & (cpu_addr[11:8] == 4'd0)) & (cpu_addr[7:4] == 4'd7));
  assign stb = (((cpu_addr[15:12] == 4'd12) & (cpu_addr[11:8] == 4'd0)) & (cpu_addr[7:4] == 4'd4));
  assign device_select = ((((cpu_addr[15:12] == 4'd12) & (cpu_addr[11:8] == 4'd0)) & (cpu_addr[7] == 1'b1)) ? (8'd1 << {{5{1'b0}}, cpu_addr[6:4]}) : 8'd0);
  assign io_select = ((((cpu_addr[15:12] == 4'd12) & (((cpu_addr[11:8] >> 3) & 1'b1) == 1'b0)) & (cpu_addr[11:8] != 4'd0)) ? (8'd1 << {{5{1'b0}}, cpu_addr[10:8]}) : 8'd0);
  assign disk_device_select = ((((cpu_addr[15:12] == 4'd12) & (cpu_addr[11:8] == 4'd0)) & (cpu_addr[7] == 1'b1)) & (cpu_addr[6:4] == 3'd6));
  assign disk_io_select = ((((cpu_addr[15:12] == 4'd12) & (((cpu_addr[11:8] >> 3) & 1'b1) == 1'b0)) & (cpu_addr[11:8] != 4'd0)) & (cpu_addr[10:8] == 3'd6));
  assign cpu_din = ((disk_device_select | disk_io_select) ? disk_dout : (((~cpu_addr[15] | ~cpu_addr[14]) | (((cpu_addr[15:12] == 4'd13) | (cpu_addr[15:12] == 4'd14)) | (cpu_addr[15:12] == 4'd15))) ? ram_do : ((((cpu_addr[15:12] == 4'd12) & (cpu_addr[11:8] == 4'd0)) & (cpu_addr[7:4] == 4'd0)) ? k : ((((cpu_addr[15:12] == 4'd12) & (cpu_addr[11:8] == 4'd0)) & (cpu_addr[7:4] == 4'd6)) ? {((gameport >> cpu_addr[2:0]) & 1'b1), 7'd0} : pd))));
  assign d = cpu_dout;
  assign clk_7m = timing__clk_7m;
  assign q3 = timing__q3;
  assign ras_n = timing__ras_n;
  assign cas_n = timing__cas_n;
  assign ax = timing__ax;
  assign phi0 = timing__phi0;
  assign pre_phi0 = timing__pre_phi0;
  assign color_ref = timing__color_ref;
  assign video_address = timing__video_address;
  assign h0 = timing__h0;
  assign va = timing__va;
  assign vb = timing__vb;
  assign vc = timing__vc;
  assign v2 = timing__v2;
  assign v4 = timing__v4;
  assign hbl = timing__hbl;
  assign vbl = timing__vbl;
  assign blank = timing__blank;
  assign ldps_n = timing__ldps_n;
  assign ld194_i = timing__ld194;
  assign hires = video_gen__hires;
  assign video = video_gen__video;
  assign color_line = video_gen__color_line;
  assign speaker = speaker_toggle__speaker;
  assign cpu_addr = cpu__addr;
  assign cpu_we = cpu__we;
  assign cpu_dout = cpu__do_out;
  assign pc_debug = cpu__debug_pc;
  assign opcode_debug = cpu__debug_opcode;
  assign a_debug = cpu__debug_a;
  assign x_debug = cpu__debug_x;
  assign y_debug = cpu__debug_y;
  assign s_debug = cpu__debug_s;
  assign p_debug = cpu__debug_p;
  assign disk_dout = disk__d_out;
  assign k = keyboard__k;

  always @(posedge q3) begin
  if (reset) begin
    soft_switches <= 8'd0;
    speaker_select_latch <= 1'b0;
    dl <= 8'd0;
  end
  else begin
    dl <= (((ax & ~cas_n) & ~ras_n) ? ram_do : dl);
    soft_switches <= ((pre_phi0 & (((cpu_addr[15:12] == 4'd12) & (cpu_addr[11:8] == 4'd0)) & (cpu_addr[7:4] == 4'd5))) ? ((soft_switches & ~(8'd1 << {{5{1'b0}}, cpu_addr[3:1]})) | ((cpu_addr[0] ? 8'd1 : 8'd0) << {{5{1'b0}}, cpu_addr[3:1]})) : soft_switches);
    speaker_select_latch <= (pre_phi0 & (((cpu_addr[15:12] == 4'd12) & (cpu_addr[11:8] == 4'd0)) & (cpu_addr[7:4] == 4'd3)));
  end
  end

  apple2_timing_generator timing (
    .clk_14m(clk_14m),
    .clk_7m(timing__clk_7m),
    .q3(timing__q3),
    .ras_n(timing__ras_n),
    .cas_n(timing__cas_n),
    .ax(timing__ax),
    .phi0(timing__phi0),
    .pre_phi0(timing__pre_phi0),
    .color_ref(timing__color_ref),
    .video_address(timing__video_address),
    .h0(timing__h0),
    .va(timing__va),
    .vb(timing__vb),
    .vc(timing__vc),
    .v2(timing__v2),
    .v4(timing__v4),
    .hbl(timing__hbl),
    .vbl(timing__vbl),
    .blank(timing__blank),
    .ldps_n(timing__ldps_n),
    .ld194(timing__ld194),
    .text_mode(text_mode),
    .page2(page2),
    .hires(hires)
  );

  apple2_video_generator video_gen (
    .clk_14m(clk_14m),
    .clk_7m(clk_7m),
    .ax(ax),
    .cas_n(cas_n),
    .h0(h0),
    .va(va),
    .vb(vb),
    .vc(vc),
    .v2(v2),
    .v4(v4),
    .blank(blank),
    .ldps_n(ldps_n),
    .ld194(ld194_i),
    .flash_clk(flash_clk),
    .text_mode(text_mode),
    .page2(page2),
    .hires_mode(hires_mode),
    .mixed_mode(mixed_mode),
    .dl(dl),
    .hires(video_gen__hires),
    .video(video_gen__video),
    .color_line(video_gen__color_line)
  );

  apple2_character_rom char_rom (
    .clk(clk_14m)
  );

  apple2_speaker_toggle speaker_toggle (
    .clk(q3),
    .toggle(speaker_select_latch),
    .speaker(speaker_toggle__speaker)
  );

  apple2_cpu6502 cpu (
    .clk(q3),
    .enable(cpu_enable),
    .reset(reset),
    .di(cpu_din),
    .nmi_n(nmi_n),
    .irq_n(irq_n),
    .so_n(so_n),
    .addr(cpu__addr),
    .we(cpu__we),
    .do_out(cpu__do_out),
    .debug_pc(cpu__debug_pc),
    .debug_opcode(cpu__debug_opcode),
    .debug_a(cpu__debug_a),
    .debug_x(cpu__debug_x),
    .debug_y(cpu__debug_y),
    .debug_s(cpu__debug_s),
    .debug_p(cpu__debug_p)
  );

  apple2_disk_ii disk (
    .clk_14m(clk_14m),
    .clk_2m(clk_2m),
    .pre_phase_zero(pre_phi0),
    .io_select(disk_io_select),
    .device_select(disk_device_select),
    .reset(reset),
    .a(cpu_addr),
    .d_in(cpu_dout),
    .d_out(disk__d_out)
  );

  apple2_keyboard keyboard (
    .clk_14m(clk_14m),
    .reset(reset),
    .ps2_clk(ps2_clk),
    .ps2_data(ps2_data),
    .read(read_key),
    .k(keyboard__k)
  );

endmodule