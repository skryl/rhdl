# RV32I Memory Module
# Synchronous write, asynchronous read memory
# Supports byte, halfword, and word access
# Configurable size (default 64KB)

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'
require_relative 'constants'

module RHDL
  module Examples
    module RISCV
      class Memory < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    DEFAULT_SIZE = 65536  # 64KB
    SPARSE_THRESHOLD = 1 << 20 # Prefer sparse backing above 1MB.

    input :clk
    input :rst

    # Memory interface
    input :addr, width: 32       # Address (word-aligned for simplicity)
    input :write_data, width: 32 # Data to write
    input :mem_read              # Read enable
    input :mem_write             # Write enable
    input :funct3, width: 3      # Size: BYTE, HALF, WORD + unsigned variants

    output :read_data, width: 32 # Data read from memory

    def initialize(name = nil, size: DEFAULT_SIZE, sparse: nil)
      @size = size
      @sparse = sparse.nil? ? size > SPARSE_THRESHOLD : sparse
      super(name)
      # Byte-addressable backing. Sparse mode avoids huge host allocations.
      @mem = @sparse ? {} : Array.new(size, 0)
    end

    def propagate
      clk = in_val(:clk)
      rst = in_val(:rst)
      @prev_clk ||= 0

      addr = normalize_addr(in_val(:addr))
      write_data = in_val(:write_data)
      mem_read = in_val(:mem_read)
      mem_write = in_val(:mem_write)
      funct3 = in_val(:funct3)

      # Handle reset
      if rst == 1
        out_set(:read_data, 0)
        @prev_clk = clk
        return
      end

      read_before_write = mem_read == 1 ? read_value(addr, funct3) : 0
      write_happened = false

      # Synchronous write on rising edge
      if @prev_clk == 0 && clk == 1 && mem_write == 1
        write_happened = true
        case funct3
        when Funct3::BYTE, Funct3::BYTE_U
          write_byte_at(addr, write_data & 0xFF)
        when Funct3::HALF, Funct3::HALF_U
          write_byte_at(addr, write_data & 0xFF)
          write_byte_at(addr + 1, (write_data >> 8) & 0xFF)
        when Funct3::WORD
          write_byte_at(addr, write_data & 0xFF)
          write_byte_at(addr + 1, (write_data >> 8) & 0xFF)
          write_byte_at(addr + 2, (write_data >> 16) & 0xFF)
          write_byte_at(addr + 3, (write_data >> 24) & 0xFF)
        end
      end
      @prev_clk = clk

      # Asynchronous read
      if mem_read == 1
        # For AMO-style read+write in one cycle, expose pre-write value.
        read_val = write_happened ? read_before_write : read_value(addr, funct3)
        out_set(:read_data, read_val & 0xFFFFFFFF)
      else
        out_set(:read_data, 0)
      end
    end

    def read_value(addr, funct3)
      case funct3
      when Funct3::BYTE
        val = read_byte_at(addr)
        val >= 0x80 ? val | 0xFFFFFF00 : val
      when Funct3::BYTE_U
        read_byte_at(addr)
      when Funct3::HALF
        val = read_byte_at(addr) | (read_byte_at(addr + 1) << 8)
        val >= 0x8000 ? val | 0xFFFF0000 : val
      when Funct3::HALF_U
        read_byte_at(addr) | (read_byte_at(addr + 1) << 8)
      when Funct3::WORD
        read_byte_at(addr) |
          (read_byte_at(addr + 1) << 8) |
          (read_byte_at(addr + 2) << 16) |
          (read_byte_at(addr + 3) << 24)
      else
        0
      end
    end

    # Load program into memory (array of 32-bit words)
    def load_program(program, start_addr = 0)
      program.each_with_index do |word, i|
        addr = start_addr + (i * 4)
        write_byte_at(addr, word & 0xFF)
        write_byte_at(addr + 1, (word >> 8) & 0xFF)
        write_byte_at(addr + 2, (word >> 16) & 0xFF)
        write_byte_at(addr + 3, (word >> 24) & 0xFF)
      end
    end

    # Read a 32-bit word from memory (for testing/debugging)
    def read_word(addr)
      read_byte_at(addr) |
      (read_byte_at(addr + 1) << 8) |
      (read_byte_at(addr + 2) << 16) |
      (read_byte_at(addr + 3) << 24)
    end

    # Write a 32-bit word to memory (for testing/debugging)
    def write_word(addr, value)
      write_byte_at(addr, value & 0xFF)
      write_byte_at(addr + 1, (value >> 8) & 0xFF)
      write_byte_at(addr + 2, (value >> 16) & 0xFF)
      write_byte_at(addr + 3, (value >> 24) & 0xFF)
    end

    # Read byte (for testing)
    def read_byte(addr)
      read_byte_at(addr)
    end

    # Write byte (for testing)
    def write_byte(addr, value)
      write_byte_at(addr, value)
    end

    private

    def normalize_addr(addr)
      addr & (@size - 1)
    end

    def read_byte_at(addr)
      index = normalize_addr(addr)
      @sparse ? (@mem[index] || 0) : (@mem[index] || 0)
    end

    def write_byte_at(addr, value)
      index = normalize_addr(addr)
      byte = value & 0xFF
      if @sparse
        if byte == 0
          @mem.delete(index)
        else
          @mem[index] = byte
        end
      else
        @mem[index] = byte
      end
    end

      end
    end
  end
end
