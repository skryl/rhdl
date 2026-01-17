module mux4(
  input a,
  input b,
  input c,
  input d,
  input [1:0] sel,
  output y
);

  wire low_mux;
  wire high_mux;

  assign low_mux = (sel[0] ? b : a);
  assign high_mux = (sel[0] ? d : c);
  assign y = (sel[1] ? high_mux : low_mux);

endmodule