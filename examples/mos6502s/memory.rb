# MOS 6502 Memory Interface - Synthesizable DSL Version
# Uses MemoryDSL for Verilog/VHDL export
# 64KB addressable memory with RAM and ROM regions

require_relative '../../lib/rhdl'
require_relative '../../lib/rhdl/dsl/memory_dsl'
require_relative '../../lib/rhdl/dsl/extended_behavior'

module MOS6502S
  # Synthesizable 64KB memory for 6502
  # RAM: 0x0000 - 0x7FFF (32KB)
  # ROM: 0x8000 - 0xFFFF (32KB)
  class Memory < RHDL::HDL::SimComponent
    include RHDL::DSL::MemoryDSL
    include RHDL::DSL::ExtendedBehavior

    # Memory map constants
    RAM_START = 0x0000
    RAM_END   = 0x7FFF   # 32KB RAM
    ROM_START = 0x8000
    ROM_END   = 0xFFFF   # 32KB ROM

    # Stack region
    STACK_START = 0x0100
    STACK_END   = 0x01FF

    # Zero page
    ZP_START = 0x0000
    ZP_END   = 0x00FF

    # Vectors
    NMI_VECTOR   = 0xFFFA
    RESET_VECTOR = 0xFFFC
    IRQ_VECTOR   = 0xFFFE

    port_input :clk
    port_input :addr, width: 16
    port_input :data_in, width: 8
    port_input :rw           # 1 = read, 0 = write
    port_input :cs           # Chip select (active high)

    port_output :data_out, width: 8

    # Define memory arrays - these become Verilog reg arrays
    # In synthesis, these will be inferred as BRAM
    memory :ram, depth: 32768, width: 8  # 32KB RAM (0x0000-0x7FFF)
    memory :rom, depth: 32768, width: 8  # 32KB ROM (0x8000-0xFFFF)

    def initialize(name = nil)
      super(name)
      @prev_clk = 0
      initialize_memories
    end

    # Override the default propagate for proper memory behavior
    def propagate
      addr = in_val(:addr) & 0xFFFF
      cs = in_val(:cs)
      rw = in_val(:rw)
      clk = in_val(:clk)

      # Detect rising edge
      rising = (@prev_clk == 0 && clk == 1)
      @prev_clk = clk

      if cs == 1
        # Write on rising edge (only to RAM)
        if rising && rw == 0 && addr < ROM_START
          ram_addr = addr & 0x7FFF
          data = in_val(:data_in) & 0xFF
          mem_write(:ram, ram_addr, data, 8)
        end

        # Read (combinational)
        if addr >= ROM_START
          # ROM region
          rom_addr = addr & 0x7FFF
          out_set(:data_out, mem_read(:rom, rom_addr))
        else
          # RAM region
          ram_addr = addr & 0x7FFF
          out_set(:data_out, mem_read(:ram, ram_addr))
        end
      else
        out_set(:data_out, 0)
      end
    end

    # Direct memory access for loading programs (simulation only)
    def read(addr)
      addr = addr & 0xFFFF
      if addr >= ROM_START
        mem_read(:rom, addr & 0x7FFF)
      else
        mem_read(:ram, addr & 0x7FFF)
      end
    end

    def write(addr, data)
      addr = addr & 0xFFFF
      data = data & 0xFF
      if addr >= ROM_START
        mem_write(:rom, addr & 0x7FFF, data, 8)
      else
        mem_write(:ram, addr & 0x7FFF, data, 8)
      end
    end

    def load_program(program, start_addr = 0x8000)
      program.each_with_index do |byte, i|
        write((start_addr + i) & 0xFFFF, byte & 0xFF)
      end
    end

    def load_bytes(bytes, start_addr)
      load_program(bytes, start_addr)
    end

    def set_reset_vector(addr)
      write(RESET_VECTOR, addr & 0xFF)
      write(RESET_VECTOR + 1, (addr >> 8) & 0xFF)
    end

    def set_irq_vector(addr)
      write(IRQ_VECTOR, addr & 0xFF)
      write(IRQ_VECTOR + 1, (addr >> 8) & 0xFF)
    end

    def set_nmi_vector(addr)
      write(NMI_VECTOR, addr & 0xFF)
      write(NMI_VECTOR + 1, (addr >> 8) & 0xFF)
    end

    def dump(start_addr, length)
      result = []
      length.times do |i|
        result << read((start_addr + i) & 0xFFFF)
      end
      result
    end

    def dump_hex(start_addr, length, bytes_per_line = 16)
      lines = []
      (0...length).step(bytes_per_line) do |offset|
        addr = (start_addr + offset) & 0xFFFF
        hex = (0...bytes_per_line).map do |i|
          if offset + i < length
            format('%02X', read((addr + i) & 0xFFFF))
          else
            '  '
          end
        end.join(' ')
        ascii = (0...bytes_per_line).map do |i|
          if offset + i < length
            c = read((addr + i) & 0xFFFF)
            (c >= 32 && c < 127) ? c.chr : '.'
          else
            ' '
          end
        end.join
        lines << format('%04X: %s  %s', addr, hex, ascii)
      end
      lines.join("\n")
    end

    def clear
      32768.times { |i| mem_write(:ram, i, 0, 8) }
      32768.times { |i| mem_write(:rom, i, 0, 8) }
    end

    def fill(start_addr, length, value)
      length.times do |i|
        write((start_addr + i) & 0xFFFF, value & 0xFF)
      end
    end

    # Generate Verilog for this memory
    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Memory - Synthesizable Verilog
        // 64KB total: 32KB RAM (0x0000-0x7FFF), 32KB ROM (0x8000-0xFFFF)
        // Generated from RHDL DSL

        module mos6502s_memory (
          input         clk,
          input  [15:0] addr,
          input  [7:0]  data_in,
          input         rw,      // 1 = read, 0 = write
          input         cs,      // Chip select (active high)
          output reg [7:0] data_out
        );

          // Memory arrays - synthesize as BRAM
          reg [7:0] ram [0:32767];  // 32KB RAM
          reg [7:0] rom [0:32767];  // 32KB ROM

          // Address decoding
          wire is_rom = addr[15];
          wire [14:0] ram_addr = addr[14:0];
          wire [14:0] rom_addr = addr[14:0];

          // Synchronous write to RAM
          always @(posedge clk) begin
            if (cs && !rw && !is_rom) begin
              ram[ram_addr] <= data_in;
            end
          end

          // Asynchronous read
          always @* begin
            if (cs) begin
              if (is_rom) begin
                data_out = rom[rom_addr];
              end else begin
                data_out = ram[ram_addr];
              end
            end else begin
              data_out = 8'h00;
            end
          end

          // ROM initialization would be done via $readmemh in testbench
          // or via FPGA-specific initialization

        endmodule
      VERILOG
    end
  end
end
