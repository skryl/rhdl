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

    input :clk
    input :rst

    # Memory interface
    input :addr, width: 32       # Address (word-aligned for simplicity)
    input :write_data, width: 32 # Data to write
    input :mem_read              # Read enable
    input :mem_write             # Write enable
    input :funct3, width: 3      # Size: BYTE, HALF, WORD + unsigned variants

    output :read_data, width: 32 # Data read from memory

    def initialize(name = nil, size: DEFAULT_SIZE)
      @size = size
      super(name)
      # Initialize memory array (byte-addressable)
      @mem = Array.new(size, 0)
    end

    def propagate
      clk = in_val(:clk)
      rst = in_val(:rst)
      @prev_clk ||= 0

      addr = in_val(:addr) & (@size - 1)  # Mask address to valid range
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

      # Synchronous write on rising edge
      if @prev_clk == 0 && clk == 1 && mem_write == 1
        case funct3
        when Funct3::BYTE, Funct3::BYTE_U
          @mem[addr] = write_data & 0xFF
        when Funct3::HALF, Funct3::HALF_U
          @mem[addr] = write_data & 0xFF
          @mem[addr + 1] = (write_data >> 8) & 0xFF
        when Funct3::WORD
          @mem[addr] = write_data & 0xFF
          @mem[addr + 1] = (write_data >> 8) & 0xFF
          @mem[addr + 2] = (write_data >> 16) & 0xFF
          @mem[addr + 3] = (write_data >> 24) & 0xFF
        end
      end
      @prev_clk = clk

      # Asynchronous read
      if mem_read == 1
        read_val = case funct3
        when Funct3::BYTE
          # Sign-extend byte
          val = @mem[addr] || 0
          val >= 0x80 ? val | 0xFFFFFF00 : val
        when Funct3::BYTE_U
          # Zero-extend byte
          @mem[addr] || 0
        when Funct3::HALF
          # Sign-extend halfword
          val = (@mem[addr] || 0) | ((@mem[addr + 1] || 0) << 8)
          val >= 0x8000 ? val | 0xFFFF0000 : val
        when Funct3::HALF_U
          # Zero-extend halfword
          (@mem[addr] || 0) | ((@mem[addr + 1] || 0) << 8)
        when Funct3::WORD
          (@mem[addr] || 0) |
          ((@mem[addr + 1] || 0) << 8) |
          ((@mem[addr + 2] || 0) << 16) |
          ((@mem[addr + 3] || 0) << 24)
        else
          0
        end
        out_set(:read_data, read_val & 0xFFFFFFFF)
      else
        out_set(:read_data, 0)
      end
    end

    # Load program into memory (array of 32-bit words)
    def load_program(program, start_addr = 0)
      program.each_with_index do |word, i|
        addr = start_addr + (i * 4)
        @mem[addr] = word & 0xFF
        @mem[addr + 1] = (word >> 8) & 0xFF
        @mem[addr + 2] = (word >> 16) & 0xFF
        @mem[addr + 3] = (word >> 24) & 0xFF
      end
    end

    # Read a 32-bit word from memory (for testing/debugging)
    def read_word(addr)
      (@mem[addr] || 0) |
      ((@mem[addr + 1] || 0) << 8) |
      ((@mem[addr + 2] || 0) << 16) |
      ((@mem[addr + 3] || 0) << 24)
    end

    # Write a 32-bit word to memory (for testing/debugging)
    def write_word(addr, value)
      @mem[addr] = value & 0xFF
      @mem[addr + 1] = (value >> 8) & 0xFF
      @mem[addr + 2] = (value >> 16) & 0xFF
      @mem[addr + 3] = (value >> 24) & 0xFF
    end

    # Read byte (for testing)
    def read_byte(addr)
      @mem[addr] || 0
    end

    # Write byte (for testing)
    def write_byte(addr, value)
      @mem[addr] = value & 0xFF
    end

      end
    end
  end
end
