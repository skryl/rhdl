module riscv_id_ex_reg(
  input clk,
  input rst,
  input flush,
  input [31:0] pc_in,
  input [31:0] pc_plus4_in,
  input [31:0] rs1_data_in,
  input [31:0] rs2_data_in,
  input [31:0] imm_in,
  input [4:0] rs1_addr_in,
  input [4:0] rs2_addr_in,
  input [4:0] rd_addr_in,
  input [2:0] funct3_in,
  input [6:0] funct7_in,
  input [3:0] alu_op_in,
  input alu_src_in,
  input reg_write_in,
  input mem_read_in,
  input mem_write_in,
  input mem_to_reg_in,
  input branch_in,
  input jump_in,
  input jalr_in,
  output reg [31:0] pc_out,
  output reg [31:0] pc_plus4_out,
  output reg [31:0] rs1_data_out,
  output reg [31:0] rs2_data_out,
  output reg [31:0] imm_out,
  output reg [4:0] rs1_addr_out,
  output reg [4:0] rs2_addr_out,
  output reg [4:0] rd_addr_out,
  output reg [2:0] funct3_out,
  output reg [6:0] funct7_out,
  output reg [3:0] alu_op_out,
  output reg alu_src_out,
  output reg reg_write_out,
  output reg mem_read_out,
  output reg mem_write_out,
  output reg mem_to_reg_out,
  output reg branch_out,
  output reg jump_out,
  output reg jalr_out
);

  always @(posedge clk) begin
  if (rst) begin
    pc_out <= 32'd0;
    pc_plus4_out <= 32'd4;
    rs1_data_out <= 32'd0;
    rs2_data_out <= 32'd0;
    imm_out <= 32'd0;
    rs1_addr_out <= 5'd0;
    rs2_addr_out <= 5'd0;
    rd_addr_out <= 5'd0;
    funct3_out <= 3'd0;
    funct7_out <= 7'd0;
    alu_op_out <= 4'd0;
    alu_src_out <= 1'b0;
    reg_write_out <= 1'b0;
    mem_read_out <= 1'b0;
    mem_write_out <= 1'b0;
    mem_to_reg_out <= 1'b0;
    branch_out <= 1'b0;
    jump_out <= 1'b0;
    jalr_out <= 1'b0;
  end
  else begin
    pc_out <= (flush ? 32'd0 : pc_in);
    pc_plus4_out <= (flush ? 32'd4 : pc_plus4_in);
    rs1_data_out <= (flush ? 32'd0 : rs1_data_in);
    rs2_data_out <= (flush ? 32'd0 : rs2_data_in);
    imm_out <= (flush ? 32'd0 : imm_in);
    rs1_addr_out <= (flush ? 5'd0 : rs1_addr_in);
    rs2_addr_out <= (flush ? 5'd0 : rs2_addr_in);
    rd_addr_out <= (flush ? 5'd0 : rd_addr_in);
    funct3_out <= (flush ? 3'd0 : funct3_in);
    funct7_out <= (flush ? 7'd0 : funct7_in);
    alu_op_out <= (flush ? 4'd0 : alu_op_in);
    alu_src_out <= (flush ? 1'b0 : alu_src_in);
    reg_write_out <= (flush ? 1'b0 : reg_write_in);
    mem_read_out <= (flush ? 1'b0 : mem_read_in);
    mem_write_out <= (flush ? 1'b0 : mem_write_in);
    mem_to_reg_out <= (flush ? 1'b0 : mem_to_reg_in);
    branch_out <= (flush ? 1'b0 : branch_in);
    jump_out <= (flush ? 1'b0 : jump_in);
    jalr_out <= (flush ? 1'b0 : jalr_in);
  end
  end

endmodule