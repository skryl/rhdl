module riscv_forwarding_unit(
  input [4:0] ex_rs1_addr,
  input [4:0] ex_rs2_addr,
  input [4:0] mem_rd_addr,
  input mem_reg_write,
  input [4:0] wb_rd_addr,
  input wb_reg_write,
  output [1:0] forward_a,
  output [1:0] forward_b
);

  assign forward_a = (((mem_reg_write & (mem_rd_addr != 5'd0)) & (mem_rd_addr == ex_rs1_addr)) ? 2'd1 : ((((wb_reg_write & (wb_rd_addr != 5'd0)) & (wb_rd_addr == ex_rs1_addr)) & ~((mem_reg_write & (mem_rd_addr != 5'd0)) & (mem_rd_addr == ex_rs1_addr))) ? 2'd2 : 2'd0));
  assign forward_b = (((mem_reg_write & (mem_rd_addr != 5'd0)) & (mem_rd_addr == ex_rs2_addr)) ? 2'd1 : ((((wb_reg_write & (wb_rd_addr != 5'd0)) & (wb_rd_addr == ex_rs2_addr)) & ~((mem_reg_write & (mem_rd_addr != 5'd0)) & (mem_rd_addr == ex_rs2_addr))) ? 2'd2 : 2'd0));

endmodule