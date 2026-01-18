module riscv_hazard_unit(
  input [4:0] id_rs1_addr,
  input [4:0] id_rs2_addr,
  input [4:0] ex_rd_addr,
  input ex_mem_read,
  input [4:0] mem_rd_addr,
  input mem_mem_read,
  input branch_taken,
  input jump,
  output stall,
  output flush_if_id,
  output flush_id_ex
);

  assign stall = (ex_mem_read & (((id_rs1_addr != 5'd0) & (ex_rd_addr == id_rs1_addr)) | ((id_rs2_addr != 5'd0) & (ex_rd_addr == id_rs2_addr))));
  assign flush_if_id = (branch_taken | jump);
  assign flush_id_ex = ((branch_taken | jump) | (ex_mem_read & (((id_rs1_addr != 5'd0) & (ex_rd_addr == id_rs1_addr)) | ((id_rs2_addr != 5'd0) & (ex_rd_addr == id_rs2_addr)))));

endmodule