// MOS 6502 Instruction Decoder - Synthesizable Verilog
// Generated from RHDL DSL - 151 opcodes

module mos6502s_instruction_decoder (
  input  [7:0] opcode,
  output reg [3:0] addr_mode,
  output reg [3:0] alu_op,
  output reg [3:0] instr_type,
  output reg [1:0] src_reg,
  output reg [1:0] dst_reg,
  output reg [2:0] branch_cond,
  output reg [2:0] cycles_base,
  output reg       is_read,
  output reg       is_write,
  output reg       is_rmw,
  output reg       sets_nz,
  output reg       sets_c,
  output reg       sets_v,
  output reg       writes_reg,
  output reg       is_status_op,
  output reg       illegal
);

  always @* begin
    // Default: illegal opcode
    addr_mode = 4'd0;
    alu_op = 4'd15;
    instr_type = 4'd10;
    src_reg = 2'd0;
    dst_reg = 2'd0;
    branch_cond = 3'd0;
    cycles_base = 3'd2;
    is_read = 1'b0;
    is_write = 1'b0;
    is_rmw = 1'b0;
    sets_nz = 1'b0;
    sets_c = 1'b0;
    sets_v = 1'b0;
    writes_reg = 1'b0;
    is_status_op = 1'b0;
    illegal = 1'b1;

    case (opcode)
      8'h69: begin
        addr_mode = 4'd2;
        alu_op = 4'd0;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h65: begin
        addr_mode = 4'd3;
        alu_op = 4'd0;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h75: begin
        addr_mode = 4'd4;
        alu_op = 4'd0;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h6D: begin
        addr_mode = 4'd6;
        alu_op = 4'd0;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h7D: begin
        addr_mode = 4'd7;
        alu_op = 4'd0;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h79: begin
        addr_mode = 4'd8;
        alu_op = 4'd0;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h61: begin
        addr_mode = 4'd10;
        alu_op = 4'd0;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h71: begin
        addr_mode = 4'd11;
        alu_op = 4'd0;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd5;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hE9: begin
        addr_mode = 4'd2;
        alu_op = 4'd1;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hE5: begin
        addr_mode = 4'd3;
        alu_op = 4'd1;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hF5: begin
        addr_mode = 4'd4;
        alu_op = 4'd1;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hED: begin
        addr_mode = 4'd6;
        alu_op = 4'd1;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hFD: begin
        addr_mode = 4'd7;
        alu_op = 4'd1;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hF9: begin
        addr_mode = 4'd8;
        alu_op = 4'd1;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hE1: begin
        addr_mode = 4'd10;
        alu_op = 4'd1;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hF1: begin
        addr_mode = 4'd11;
        alu_op = 4'd1;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd5;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h29: begin
        addr_mode = 4'd2;
        alu_op = 4'd2;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h25: begin
        addr_mode = 4'd3;
        alu_op = 4'd2;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h35: begin
        addr_mode = 4'd4;
        alu_op = 4'd2;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h2D: begin
        addr_mode = 4'd6;
        alu_op = 4'd2;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h3D: begin
        addr_mode = 4'd7;
        alu_op = 4'd2;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h39: begin
        addr_mode = 4'd8;
        alu_op = 4'd2;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h21: begin
        addr_mode = 4'd10;
        alu_op = 4'd2;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h31: begin
        addr_mode = 4'd11;
        alu_op = 4'd2;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd5;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h09: begin
        addr_mode = 4'd2;
        alu_op = 4'd3;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h05: begin
        addr_mode = 4'd3;
        alu_op = 4'd3;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h15: begin
        addr_mode = 4'd4;
        alu_op = 4'd3;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h0D: begin
        addr_mode = 4'd6;
        alu_op = 4'd3;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h1D: begin
        addr_mode = 4'd7;
        alu_op = 4'd3;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h19: begin
        addr_mode = 4'd8;
        alu_op = 4'd3;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h01: begin
        addr_mode = 4'd10;
        alu_op = 4'd3;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h11: begin
        addr_mode = 4'd11;
        alu_op = 4'd3;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd5;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h49: begin
        addr_mode = 4'd2;
        alu_op = 4'd4;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h45: begin
        addr_mode = 4'd3;
        alu_op = 4'd4;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h55: begin
        addr_mode = 4'd4;
        alu_op = 4'd4;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h4D: begin
        addr_mode = 4'd6;
        alu_op = 4'd4;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h5D: begin
        addr_mode = 4'd7;
        alu_op = 4'd4;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h59: begin
        addr_mode = 4'd8;
        alu_op = 4'd4;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h41: begin
        addr_mode = 4'd10;
        alu_op = 4'd4;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h51: begin
        addr_mode = 4'd11;
        alu_op = 4'd4;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd5;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hC9: begin
        addr_mode = 4'd2;
        alu_op = 4'd11;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hC5: begin
        addr_mode = 4'd3;
        alu_op = 4'd11;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hD5: begin
        addr_mode = 4'd4;
        alu_op = 4'd11;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hCD: begin
        addr_mode = 4'd6;
        alu_op = 4'd11;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hDD: begin
        addr_mode = 4'd7;
        alu_op = 4'd11;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hD9: begin
        addr_mode = 4'd8;
        alu_op = 4'd11;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hC1: begin
        addr_mode = 4'd10;
        alu_op = 4'd11;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hD1: begin
        addr_mode = 4'd11;
        alu_op = 4'd11;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd5;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hE0: begin
        addr_mode = 4'd2;
        alu_op = 4'd11;
        instr_type = 4'd0;
        src_reg = 2'd1;
        dst_reg = 2'd1;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hE4: begin
        addr_mode = 4'd3;
        alu_op = 4'd11;
        instr_type = 4'd0;
        src_reg = 2'd1;
        dst_reg = 2'd1;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hEC: begin
        addr_mode = 4'd6;
        alu_op = 4'd11;
        instr_type = 4'd0;
        src_reg = 2'd1;
        dst_reg = 2'd1;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hC0: begin
        addr_mode = 4'd2;
        alu_op = 4'd11;
        instr_type = 4'd0;
        src_reg = 2'd2;
        dst_reg = 2'd2;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hC4: begin
        addr_mode = 4'd3;
        alu_op = 4'd11;
        instr_type = 4'd0;
        src_reg = 2'd2;
        dst_reg = 2'd2;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hCC: begin
        addr_mode = 4'd6;
        alu_op = 4'd11;
        instr_type = 4'd0;
        src_reg = 2'd2;
        dst_reg = 2'd2;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h24: begin
        addr_mode = 4'd3;
        alu_op = 4'd12;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b1;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h2C: begin
        addr_mode = 4'd6;
        alu_op = 4'd12;
        instr_type = 4'd0;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b1;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hA9: begin
        addr_mode = 4'd2;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hA5: begin
        addr_mode = 4'd3;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hB5: begin
        addr_mode = 4'd4;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hAD: begin
        addr_mode = 4'd6;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hBD: begin
        addr_mode = 4'd7;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hB9: begin
        addr_mode = 4'd8;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hA1: begin
        addr_mode = 4'd10;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hB1: begin
        addr_mode = 4'd11;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd5;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hA2: begin
        addr_mode = 4'd2;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd1;
        dst_reg = 2'd1;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hA6: begin
        addr_mode = 4'd3;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd1;
        dst_reg = 2'd1;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hB6: begin
        addr_mode = 4'd5;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd1;
        dst_reg = 2'd1;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hAE: begin
        addr_mode = 4'd6;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd1;
        dst_reg = 2'd1;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hBE: begin
        addr_mode = 4'd8;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd1;
        dst_reg = 2'd1;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hA0: begin
        addr_mode = 4'd2;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd2;
        dst_reg = 2'd2;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hA4: begin
        addr_mode = 4'd3;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd2;
        dst_reg = 2'd2;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hB4: begin
        addr_mode = 4'd4;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd2;
        dst_reg = 2'd2;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hAC: begin
        addr_mode = 4'd6;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd2;
        dst_reg = 2'd2;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hBC: begin
        addr_mode = 4'd7;
        alu_op = 4'd13;
        instr_type = 4'd1;
        src_reg = 2'd2;
        dst_reg = 2'd2;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h85: begin
        addr_mode = 4'd3;
        alu_op = 4'd15;
        instr_type = 4'd2;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b0;
        is_write = 1'b1;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h95: begin
        addr_mode = 4'd4;
        alu_op = 4'd15;
        instr_type = 4'd2;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b0;
        is_write = 1'b1;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h8D: begin
        addr_mode = 4'd6;
        alu_op = 4'd15;
        instr_type = 4'd2;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b0;
        is_write = 1'b1;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h9D: begin
        addr_mode = 4'd7;
        alu_op = 4'd15;
        instr_type = 4'd2;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd5;
        is_read = 1'b0;
        is_write = 1'b1;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h99: begin
        addr_mode = 4'd8;
        alu_op = 4'd15;
        instr_type = 4'd2;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd5;
        is_read = 1'b0;
        is_write = 1'b1;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h81: begin
        addr_mode = 4'd10;
        alu_op = 4'd15;
        instr_type = 4'd2;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b0;
        is_write = 1'b1;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h91: begin
        addr_mode = 4'd11;
        alu_op = 4'd15;
        instr_type = 4'd2;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b0;
        is_write = 1'b1;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h86: begin
        addr_mode = 4'd3;
        alu_op = 4'd15;
        instr_type = 4'd2;
        src_reg = 2'd1;
        dst_reg = 2'd1;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b0;
        is_write = 1'b1;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h96: begin
        addr_mode = 4'd5;
        alu_op = 4'd15;
        instr_type = 4'd2;
        src_reg = 2'd1;
        dst_reg = 2'd1;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b0;
        is_write = 1'b1;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h8E: begin
        addr_mode = 4'd6;
        alu_op = 4'd15;
        instr_type = 4'd2;
        src_reg = 2'd1;
        dst_reg = 2'd1;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b0;
        is_write = 1'b1;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h84: begin
        addr_mode = 4'd3;
        alu_op = 4'd15;
        instr_type = 4'd2;
        src_reg = 2'd2;
        dst_reg = 2'd2;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b0;
        is_write = 1'b1;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h94: begin
        addr_mode = 4'd4;
        alu_op = 4'd15;
        instr_type = 4'd2;
        src_reg = 2'd2;
        dst_reg = 2'd2;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b0;
        is_write = 1'b1;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h8C: begin
        addr_mode = 4'd6;
        alu_op = 4'd15;
        instr_type = 4'd2;
        src_reg = 2'd2;
        dst_reg = 2'd2;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b0;
        is_write = 1'b1;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hAA: begin
        addr_mode = 4'd0;
        alu_op = 4'd13;
        instr_type = 4'd3;
        src_reg = 2'd0;
        dst_reg = 2'd1;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h8A: begin
        addr_mode = 4'd0;
        alu_op = 4'd13;
        instr_type = 4'd3;
        src_reg = 2'd1;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hA8: begin
        addr_mode = 4'd0;
        alu_op = 4'd13;
        instr_type = 4'd3;
        src_reg = 2'd0;
        dst_reg = 2'd2;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h98: begin
        addr_mode = 4'd0;
        alu_op = 4'd13;
        instr_type = 4'd3;
        src_reg = 2'd2;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hBA: begin
        addr_mode = 4'd0;
        alu_op = 4'd13;
        instr_type = 4'd3;
        src_reg = 2'd1;
        dst_reg = 2'd1;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h9A: begin
        addr_mode = 4'd0;
        alu_op = 4'd13;
        instr_type = 4'd3;
        src_reg = 2'd1;
        dst_reg = 2'd1;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hE8: begin
        addr_mode = 4'd0;
        alu_op = 4'd9;
        instr_type = 4'd4;
        src_reg = 2'd1;
        dst_reg = 2'd1;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hCA: begin
        addr_mode = 4'd0;
        alu_op = 4'd10;
        instr_type = 4'd4;
        src_reg = 2'd1;
        dst_reg = 2'd1;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hC8: begin
        addr_mode = 4'd0;
        alu_op = 4'd9;
        instr_type = 4'd4;
        src_reg = 2'd2;
        dst_reg = 2'd2;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h88: begin
        addr_mode = 4'd0;
        alu_op = 4'd10;
        instr_type = 4'd4;
        src_reg = 2'd2;
        dst_reg = 2'd2;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hE6: begin
        addr_mode = 4'd3;
        alu_op = 4'd9;
        instr_type = 4'd4;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd5;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hF6: begin
        addr_mode = 4'd4;
        alu_op = 4'd9;
        instr_type = 4'd4;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hEE: begin
        addr_mode = 4'd6;
        alu_op = 4'd9;
        instr_type = 4'd4;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hFE: begin
        addr_mode = 4'd7;
        alu_op = 4'd9;
        instr_type = 4'd4;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd7;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hC6: begin
        addr_mode = 4'd3;
        alu_op = 4'd10;
        instr_type = 4'd4;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd5;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hD6: begin
        addr_mode = 4'd4;
        alu_op = 4'd10;
        instr_type = 4'd4;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hCE: begin
        addr_mode = 4'd6;
        alu_op = 4'd10;
        instr_type = 4'd4;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hDE: begin
        addr_mode = 4'd7;
        alu_op = 4'd10;
        instr_type = 4'd4;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd7;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h0A: begin
        addr_mode = 4'd1;
        alu_op = 4'd5;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h06: begin
        addr_mode = 4'd3;
        alu_op = 4'd5;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd5;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h16: begin
        addr_mode = 4'd4;
        alu_op = 4'd5;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h0E: begin
        addr_mode = 4'd6;
        alu_op = 4'd5;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h1E: begin
        addr_mode = 4'd7;
        alu_op = 4'd5;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd7;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h4A: begin
        addr_mode = 4'd1;
        alu_op = 4'd6;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h46: begin
        addr_mode = 4'd3;
        alu_op = 4'd6;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd5;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h56: begin
        addr_mode = 4'd4;
        alu_op = 4'd6;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h4E: begin
        addr_mode = 4'd6;
        alu_op = 4'd6;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h5E: begin
        addr_mode = 4'd7;
        alu_op = 4'd6;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd7;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h2A: begin
        addr_mode = 4'd1;
        alu_op = 4'd7;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h26: begin
        addr_mode = 4'd3;
        alu_op = 4'd7;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd5;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h36: begin
        addr_mode = 4'd4;
        alu_op = 4'd7;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h2E: begin
        addr_mode = 4'd6;
        alu_op = 4'd7;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h3E: begin
        addr_mode = 4'd7;
        alu_op = 4'd7;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd7;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h6A: begin
        addr_mode = 4'd1;
        alu_op = 4'd8;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h66: begin
        addr_mode = 4'd3;
        alu_op = 4'd8;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd5;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h76: begin
        addr_mode = 4'd4;
        alu_op = 4'd8;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h6E: begin
        addr_mode = 4'd6;
        alu_op = 4'd8;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h7E: begin
        addr_mode = 4'd7;
        alu_op = 4'd8;
        instr_type = 4'd5;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd7;
        is_read = 1'b1;
        is_write = 1'b1;
        is_rmw = 1'b1;
        sets_nz = 1'b1;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h10: begin
        addr_mode = 4'd12;
        alu_op = 4'd15;
        instr_type = 4'd6;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h30: begin
        addr_mode = 4'd12;
        alu_op = 4'd15;
        instr_type = 4'd6;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd1;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h50: begin
        addr_mode = 4'd12;
        alu_op = 4'd15;
        instr_type = 4'd6;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd2;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h70: begin
        addr_mode = 4'd12;
        alu_op = 4'd15;
        instr_type = 4'd6;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd3;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h90: begin
        addr_mode = 4'd12;
        alu_op = 4'd15;
        instr_type = 4'd6;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd4;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hB0: begin
        addr_mode = 4'd12;
        alu_op = 4'd15;
        instr_type = 4'd6;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd5;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hD0: begin
        addr_mode = 4'd12;
        alu_op = 4'd15;
        instr_type = 4'd6;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd6;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hF0: begin
        addr_mode = 4'd12;
        alu_op = 4'd15;
        instr_type = 4'd6;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd7;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h4C: begin
        addr_mode = 4'd6;
        alu_op = 4'd15;
        instr_type = 4'd7;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h6C: begin
        addr_mode = 4'd9;
        alu_op = 4'd15;
        instr_type = 4'd7;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd5;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h20: begin
        addr_mode = 4'd6;
        alu_op = 4'd15;
        instr_type = 4'd7;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b0;
        is_write = 1'b1;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h60: begin
        addr_mode = 4'd0;
        alu_op = 4'd15;
        instr_type = 4'd7;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h40: begin
        addr_mode = 4'd0;
        alu_op = 4'd15;
        instr_type = 4'd7;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd6;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h48: begin
        addr_mode = 4'd0;
        alu_op = 4'd13;
        instr_type = 4'd8;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b0;
        is_write = 1'b1;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h08: begin
        addr_mode = 4'd0;
        alu_op = 4'd13;
        instr_type = 4'd8;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd3;
        is_read = 1'b0;
        is_write = 1'b1;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b1;
        illegal = 1'b0;
      end
      8'h68: begin
        addr_mode = 4'd0;
        alu_op = 4'd13;
        instr_type = 4'd8;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b1;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b1;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h28: begin
        addr_mode = 4'd0;
        alu_op = 4'd13;
        instr_type = 4'd8;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd4;
        is_read = 1'b1;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b1;
        sets_v = 1'b1;
        writes_reg = 1'b0;
        is_status_op = 1'b1;
        illegal = 1'b0;
      end
      8'h18: begin
        addr_mode = 4'd0;
        alu_op = 4'd15;
        instr_type = 4'd9;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h38: begin
        addr_mode = 4'd0;
        alu_op = 4'd15;
        instr_type = 4'd9;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b1;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h58: begin
        addr_mode = 4'd0;
        alu_op = 4'd15;
        instr_type = 4'd9;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h78: begin
        addr_mode = 4'd0;
        alu_op = 4'd15;
        instr_type = 4'd9;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hB8: begin
        addr_mode = 4'd0;
        alu_op = 4'd15;
        instr_type = 4'd9;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b1;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hD8: begin
        addr_mode = 4'd0;
        alu_op = 4'd15;
        instr_type = 4'd9;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hF8: begin
        addr_mode = 4'd0;
        alu_op = 4'd15;
        instr_type = 4'd9;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'hEA: begin
        addr_mode = 4'd0;
        alu_op = 4'd15;
        instr_type = 4'd10;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd2;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      8'h00: begin
        addr_mode = 4'd0;
        alu_op = 4'd15;
        instr_type = 4'd11;
        src_reg = 2'd0;
        dst_reg = 2'd0;
        branch_cond = 3'd0;
        cycles_base = 3'd7;
        is_read = 1'b0;
        is_write = 1'b0;
        is_rmw = 1'b0;
        sets_nz = 1'b0;
        sets_c = 1'b0;
        sets_v = 1'b0;
        writes_reg = 1'b0;
        is_status_op = 1'b0;
        illegal = 1'b0;
      end
      default: begin
        illegal = 1'b1;
      end
    endcase
  end

endmodule