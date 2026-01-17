# MOS 6502 CPU Registers - Synthesizable DSL Version
# Contains A, X, Y registers, Stack Pointer, Program Counter, and latches
# All components use synthesizable patterns for Verilog/VHDL export

require_relative '../../lib/rhdl'

module MOS6502
  # 8-bit General Purpose Registers (A, X, Y) - DSL Version
  class Registers_DSL < RHDL::HDL::SequentialComponent
    port_input :clk
    port_input :rst
    port_input :data_in, width: 8
    port_input :load_a
    port_input :load_x
    port_input :load_y

    port_output :a, width: 8
    port_output :x, width: 8
    port_output :y, width: 8

    def initialize(name = nil)
      @a = 0
      @x = 0
      @y = 0
      super(name)
    end

    def propagate
      clk = in_val(:clk)
      rising = (@prev_clk == 0 && clk == 1)
      @prev_clk = clk

      if rising
        if in_val(:rst) == 1
          @a = 0
          @x = 0
          @y = 0
        else
          data = in_val(:data_in) & 0xFF
          @a = data if in_val(:load_a) == 1
          @x = data if in_val(:load_x) == 1
          @y = data if in_val(:load_y) == 1
        end
      end

      out_set(:a, @a)
      out_set(:x, @x)
      out_set(:y, @y)
    end

    # Direct access for testing
    def read_a; @a; end
    def read_x; @x; end
    def read_y; @y; end
    def write_a(v); @a = v & 0xFF; end
    def write_x(v); @x = v & 0xFF; end
    def write_y(v); @y = v & 0xFF; end

    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Registers (A, X, Y) - Synthesizable Verilog
        module mos6502_registers (
          input        clk,
          input        rst,
          input  [7:0] data_in,
          input        load_a,
          input        load_x,
          input        load_y,
          output reg [7:0] a,
          output reg [7:0] x,
          output reg [7:0] y
        );

          always @(posedge clk or posedge rst) begin
            if (rst) begin
              a <= 8'h00;
              x <= 8'h00;
              y <= 8'h00;
            end else begin
              if (load_a) a <= data_in;
              if (load_x) x <= data_in;
              if (load_y) y <= data_in;
            end
          end

        endmodule
      VERILOG
    end
  end

  # 6502 Stack Pointer - DSL Version
  class StackPointer_DSL < RHDL::HDL::SequentialComponent
    STACK_BASE = 0x0100

    port_input :clk
    port_input :rst
    port_input :inc
    port_input :dec
    port_input :load
    port_input :data_in, width: 8

    port_output :sp, width: 8
    port_output :addr, width: 16
    port_output :addr_plus1, width: 16

    def initialize(name = nil)
      @sp = 0xFD
      @prev_clk = 0
      super(name)
    end

    def propagate
      clk = in_val(:clk)
      rising = (@prev_clk == 0 && clk == 1)
      @prev_clk = clk

      sp_before = @sp

      if rising
        if in_val(:rst) == 1
          @sp = 0xFD
        elsif in_val(:load) == 1
          @sp = in_val(:data_in) & 0xFF
        elsif in_val(:dec) == 1
          @sp = (@sp - 1) & 0xFF
        elsif in_val(:inc) == 1
          @sp = (@sp + 1) & 0xFF
        end
      end

      out_set(:sp, @sp)
      out_set(:addr, STACK_BASE | sp_before)
      out_set(:addr_plus1, STACK_BASE | ((sp_before + 1) & 0xFF))
    end

    def read_sp; @sp; end
    def write_sp(v); @sp = v & 0xFF; end

    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Stack Pointer - Synthesizable Verilog
        module mos6502_stack_pointer (
          input        clk,
          input        rst,
          input        inc,
          input        dec,
          input        load,
          input  [7:0] data_in,
          output reg [7:0] sp,
          output [15:0] addr,
          output [15:0] addr_plus1
        );

          localparam STACK_BASE = 16'h0100;

          always @(posedge clk or posedge rst) begin
            if (rst) begin
              sp <= 8'hFD;
            end else if (load) begin
              sp <= data_in;
            end else if (dec) begin
              sp <= sp - 8'h01;
            end else if (inc) begin
              sp <= sp + 8'h01;
            end
          end

          assign addr = STACK_BASE | {8'h00, sp};
          assign addr_plus1 = STACK_BASE | {8'h00, sp + 8'h01};

        endmodule
      VERILOG
    end
  end

  # 6502 Program Counter - DSL Version
  class ProgramCounter_DSL < RHDL::HDL::SequentialComponent
    port_input :clk
    port_input :rst
    port_input :inc
    port_input :load
    port_input :addr_in, width: 16

    port_output :pc, width: 16
    port_output :pc_hi, width: 8
    port_output :pc_lo, width: 8

    def initialize(name = nil)
      @pc = 0x0000
      @prev_clk = 0
      super(name)
    end

    def propagate
      clk = in_val(:clk)
      rising = (@prev_clk == 0 && clk == 1)
      @prev_clk = clk

      if rising
        if in_val(:rst) == 1
          @pc = 0xFFFC
        elsif in_val(:load) == 1
          next_pc = in_val(:addr_in) & 0xFFFF
          next_pc = (next_pc + 1) & 0xFFFF if in_val(:inc) == 1
          @pc = next_pc
        elsif in_val(:inc) == 1
          @pc = (@pc + 1) & 0xFFFF
        end
      end

      out_set(:pc, @pc)
      out_set(:pc_hi, (@pc >> 8) & 0xFF)
      out_set(:pc_lo, @pc & 0xFF)
    end

    def read_pc; @pc; end
    def write_pc(v); @pc = v & 0xFFFF; end

    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Program Counter - Synthesizable Verilog
        module mos6502_program_counter (
          input         clk,
          input         rst,
          input         inc,
          input         load,
          input  [15:0] addr_in,
          output reg [15:0] pc,
          output  [7:0] pc_hi,
          output  [7:0] pc_lo
        );

          always @(posedge clk or posedge rst) begin
            if (rst) begin
              pc <= 16'hFFFC;
            end else if (load) begin
              if (inc)
                pc <= addr_in + 16'h0001;
              else
                pc <= addr_in;
            end else if (inc) begin
              pc <= pc + 16'h0001;
            end
          end

          assign pc_hi = pc[15:8];
          assign pc_lo = pc[7:0];

        endmodule
      VERILOG
    end
  end

  # Instruction Register and Operand Latches - DSL Version
  class InstructionRegister_DSL < RHDL::HDL::SequentialComponent
    port_input :clk
    port_input :rst
    port_input :load_opcode
    port_input :load_operand_lo
    port_input :load_operand_hi
    port_input :data_in, width: 8

    port_output :opcode, width: 8
    port_output :operand_lo, width: 8
    port_output :operand_hi, width: 8
    port_output :operand, width: 16

    def initialize(name = nil)
      @opcode = 0
      @operand_lo = 0
      @operand_hi = 0
      @prev_clk = 0
      super(name)
    end

    def propagate
      clk = in_val(:clk)
      rising = (@prev_clk == 0 && clk == 1)
      @prev_clk = clk

      if rising
        if in_val(:rst) == 1
          @opcode = 0
          @operand_lo = 0
          @operand_hi = 0
        else
          data = in_val(:data_in) & 0xFF
          @opcode = data if in_val(:load_opcode) == 1
          @operand_lo = data if in_val(:load_operand_lo) == 1
          @operand_hi = data if in_val(:load_operand_hi) == 1
        end
      end

      out_set(:opcode, @opcode)
      out_set(:operand_lo, @operand_lo)
      out_set(:operand_hi, @operand_hi)
      out_set(:operand, (@operand_hi << 8) | @operand_lo)
    end

    def read_opcode; @opcode; end
    def read_operand; (@operand_hi << 8) | @operand_lo; end

    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Instruction Register - Synthesizable Verilog
        module mos6502_instruction_register (
          input        clk,
          input        rst,
          input        load_opcode,
          input        load_operand_lo,
          input        load_operand_hi,
          input  [7:0] data_in,
          output reg [7:0] opcode,
          output reg [7:0] operand_lo,
          output reg [7:0] operand_hi,
          output [15:0] operand
        );

          always @(posedge clk or posedge rst) begin
            if (rst) begin
              opcode <= 8'h00;
              operand_lo <= 8'h00;
              operand_hi <= 8'h00;
            end else begin
              if (load_opcode) opcode <= data_in;
              if (load_operand_lo) operand_lo <= data_in;
              if (load_operand_hi) operand_hi <= data_in;
            end
          end

          assign operand = {operand_hi, operand_lo};

        endmodule
      VERILOG
    end
  end

  # Address Latch - DSL Version
  class AddressLatch_DSL < RHDL::HDL::SequentialComponent
    port_input :clk
    port_input :rst
    port_input :load_lo
    port_input :load_hi
    port_input :load_full
    port_input :data_in, width: 8
    port_input :addr_in, width: 16

    port_output :addr, width: 16
    port_output :addr_lo, width: 8
    port_output :addr_hi, width: 8

    def initialize(name = nil)
      @addr_lo = 0
      @addr_hi = 0
      @prev_clk = 0
      super(name)
    end

    def propagate
      clk = in_val(:clk)
      rising = (@prev_clk == 0 && clk == 1)
      @prev_clk = clk

      if rising
        if in_val(:rst) == 1
          @addr_lo = 0
          @addr_hi = 0
        elsif in_val(:load_full) == 1
          addr = in_val(:addr_in) & 0xFFFF
          @addr_lo = addr & 0xFF
          @addr_hi = (addr >> 8) & 0xFF
        else
          data = in_val(:data_in) & 0xFF
          @addr_lo = data if in_val(:load_lo) == 1
          @addr_hi = data if in_val(:load_hi) == 1
        end
      end

      out_set(:addr, (@addr_hi << 8) | @addr_lo)
      out_set(:addr_lo, @addr_lo)
      out_set(:addr_hi, @addr_hi)
    end

    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Address Latch - Synthesizable Verilog
        module mos6502_address_latch (
          input         clk,
          input         rst,
          input         load_lo,
          input         load_hi,
          input         load_full,
          input   [7:0] data_in,
          input  [15:0] addr_in,
          output [15:0] addr,
          output  [7:0] addr_lo,
          output  [7:0] addr_hi
        );

          reg [7:0] addr_lo_reg;
          reg [7:0] addr_hi_reg;

          always @(posedge clk or posedge rst) begin
            if (rst) begin
              addr_lo_reg <= 8'h00;
              addr_hi_reg <= 8'h00;
            end else if (load_full) begin
              addr_lo_reg <= addr_in[7:0];
              addr_hi_reg <= addr_in[15:8];
            end else begin
              if (load_lo) addr_lo_reg <= data_in;
              if (load_hi) addr_hi_reg <= data_in;
            end
          end

          assign addr = {addr_hi_reg, addr_lo_reg};
          assign addr_lo = addr_lo_reg;
          assign addr_hi = addr_hi_reg;

        endmodule
      VERILOG
    end
  end

  # Data Latch - DSL Version
  class DataLatch_DSL < RHDL::HDL::SequentialComponent
    port_input :clk
    port_input :rst
    port_input :load
    port_input :data_in, width: 8

    port_output :data, width: 8

    def initialize(name = nil)
      @data = 0
      @prev_clk = 0
      super(name)
    end

    def propagate
      clk = in_val(:clk)
      rising = (@prev_clk == 0 && clk == 1)
      @prev_clk = clk

      if rising
        if in_val(:rst) == 1
          @data = 0
        elsif in_val(:load) == 1
          @data = in_val(:data_in) & 0xFF
        end
      end

      out_set(:data, @data)
    end

    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Data Latch - Synthesizable Verilog
        module mos6502_data_latch (
          input        clk,
          input        rst,
          input        load,
          input  [7:0] data_in,
          output reg [7:0] data
        );

          always @(posedge clk or posedge rst) begin
            if (rst) begin
              data <= 8'h00;
            end else if (load) begin
              data <= data_in;
            end
          end

        endmodule
      VERILOG
    end
  end
end
