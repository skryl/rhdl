module apple2_timing_generator(
  input clk_14m,
  input text_mode,
  input page2,
  input hires,
  output reg clk_7m,
  output reg q3,
  output reg ras_n,
  output reg cas_n,
  output reg ax,
  output reg phi0,
  output reg pre_phi0,
  output reg color_ref,
  output [15:0] video_address,
  output h0,
  output va,
  output vb,
  output vc,
  output v2,
  output v4,
  output hbl,
  output vbl,
  output blank,
  output ldps_n,
  output ld194
);

  reg [6:0] h;
  reg [8:0] v;

  initial begin
    h = 7'd0;
    v = 9'd250;
    clk_7m = 1'b0;
    q3 = 1'b0;
    cas_n = 1'b0;
    ax = 1'b0;
    ras_n = 1'b0;
    phi0 = 1'b0;
    pre_phi0 = 1'b0;
    color_ref = 1'b0;
  end

  assign ldps_n = ~((phi0 & ~ax) & ~cas_n);
  assign ld194 = ~(((phi0 & ~ax) & ~cas_n) & ~clk_7m);
  assign h0 = h[0];
  assign va = v[0];
  assign vb = v[1];
  assign vc = v[2];
  assign v2 = v[5];
  assign v4 = v[7];
  assign hbl = ~(h[5] | (h[3] & h[4]));
  assign vbl = (v[6] & v[7]);
  assign blank = (~(h[5] | (h[3] & h[4])) | (v[6] & v[7]));
  assign video_address = {1'b0, (hires ? {page2, ~page2, v[2:0]} : {2'd0, ~(h[5] | (h[3] & h[4])), page2, ~page2}), v[5:3], ((({~h[5], v[6], h[4], h[3]} + {v[7], ~h[5], v[7], 1'b1}) + {{1{1'b0}}, {3'd0, v[6]}}) & 4'd15), h[2:0]};

  always @(posedge clk_14m) begin
  q3 <= (q3 ? cas_n : ras_n);
  cas_n <= (q3 ? ax : ax);
  ax <= (q3 ? ras_n : ~(((~color_ref & (~ax & ~cas_n)) & phi0) & ~h[6]));
  ras_n <= (q3 ? 1'b0 : ax);
  color_ref <= (clk_7m ^ color_ref);
  clk_7m <= ~clk_7m;
  phi0 <= pre_phi0;
  pre_phi0 <= (ax ? ~(q3 ^ phi0) : pre_phi0);
  h <= (((phi0 & ~ax) & ((q3 & ras_n) | (~q3 & ~(((~color_ref & (~ax & ~cas_n)) & phi0) & ~h[6])))) ? (h[6] ? (h + 7'd1) : 7'd64) : h);
  v <= (((phi0 & ~ax) & ((q3 & ras_n) | (~q3 & ~(((~color_ref & (~ax & ~cas_n)) & phi0) & ~h[6])))) ? ((h == 7'd127) ? ((v == 9'd511) ? 9'd250 : (v + 9'd1)) : v) : v);
  end

endmodule