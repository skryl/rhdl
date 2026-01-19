# MOS 6502 Memory Interface - Synthesizable DSL Version
# Uses MemoryDSL for Verilog/VHDL export
# 64KB addressable memory with RAM and ROM regions

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/memory_dsl'

module MOS6502
  # Synthesizable 64KB memory for 6502
  # RAM: 0x0000 - 0x7FFF (32KB)
  # ROM: 0x8000 - 0xFFFF (32KB)
  class Memory < RHDL::HDL::SimComponent
    include RHDL::DSL::MemoryDSL
    include RHDL::DSL::Behavior

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

    input :clk
    input :addr, width: 16
    input :data_in, width: 8
    input :rw           # 1 = read, 0 = write
    input :cs           # Chip select (active high)

    output :data_out, width: 8

    # Define memory arrays - these become Verilog reg arrays
    # In synthesis, these will be inferred as BRAM
    memory :ram, depth: 32768, width: 8  # 32KB RAM (0x0000-0x7FFF)
    memory :rom, depth: 32768, width: 8  # 32KB ROM (0x8000-0xFFFF)

    # Behavior block for combinational read output (synthesis only)
    # Note: This must come BEFORE the custom propagate method so that
    # the custom propagate overrides the behavior-generated one for simulation
    behavior do
      is_rom = local(:is_rom, addr[15], width: 1)
      ram_addr = local(:ram_addr, addr[14..0], width: 15)
      rom_addr = local(:rom_addr, addr[14..0], width: 15)

      # data_out: mux based on cs, is_rom
      data_out <= mux(cs,
                     mux(is_rom,
                         mem_read_expr(:rom, rom_addr),
                         mem_read_expr(:ram, ram_addr)),
                     lit(0, width: 8))
    end

    def initialize(name = nil)
      super(name)
      @prev_clk = 0
      initialize_memories
    end

    # Override the behavior-generated propagate for proper memory behavior
    # This handles both reads (combinational) and writes (on rising clock edge)
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

  end
end
