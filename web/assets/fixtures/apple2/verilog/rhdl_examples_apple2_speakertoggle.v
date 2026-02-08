module apple2_speaker_toggle(
  input clk,
  input toggle,
  output speaker
);

  reg speaker_state;

  initial begin
    speaker_state = 1'b0;
  end

  assign speaker = speaker_state;

  always @(posedge clk) begin
  speaker_state <= (toggle ? ~speaker_state : speaker_state);
  end

endmodule