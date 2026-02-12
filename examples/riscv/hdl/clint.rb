# Core-Local Interruptor (CLINT) - minimal machine timer subset
# Provides memory-mapped mtime/mtimecmp registers and timer interrupt output

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'
require_relative 'constants'

module RHDL
  module Examples
    module RISCV
      class Clint < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    BASE_ADDR = 0x0200_0000
    MSIP_ADDR = BASE_ADDR + 0x0000
    MTIMECMP_LOW_ADDR = BASE_ADDR + 0x4000
    MTIMECMP_HIGH_ADDR = BASE_ADDR + 0x4004
    MTIME_LOW_ADDR = BASE_ADDR + 0xBFF8
    MTIME_HIGH_ADDR = BASE_ADDR + 0xBFFC
    MASK64 = 0xFFFF_FFFF_FFFF_FFFF

    input :clk
    input :rst

    # Memory-mapped access port
    input :addr, width: 32
    input :write_data, width: 32
    input :mem_read
    input :mem_write
    input :funct3, width: 3

    output :read_data, width: 32
    output :irq_software
    output :irq_timer

    def initialize(name = nil)
      super(name)
      @msip = 0
      @mtime = 0
      @mtimecmp = MASK64
    end

    def propagate
      clk = in_val(:clk)
      rst = in_val(:rst)
      @prev_clk ||= 0

      addr = in_val(:addr) & 0xFFFF_FFFF
      write_data = in_val(:write_data) & 0xFFFF_FFFF
      mem_read = in_val(:mem_read)
      mem_write = in_val(:mem_write)
      funct3 = in_val(:funct3)

      if rst == 1
        @msip = 0
        @mtime = 0
        @mtimecmp = MASK64
        out_set(:read_data, 0)
        out_set(:irq_software, 0)
        out_set(:irq_timer, 0)
        @prev_clk = clk
        return
      end

      # mtime increments every cycle
      if @prev_clk == 0 && clk == 1
        @mtime = (@mtime + 1) & MASK64

        if mem_write == 1 && funct3 == Funct3::WORD
          case addr
          when MSIP_ADDR
            @msip = write_data & 0x1
          when MTIMECMP_LOW_ADDR
            @mtimecmp = (@mtimecmp & 0xFFFF_FFFF_0000_0000) | write_data
          when MTIMECMP_HIGH_ADDR
            @mtimecmp = ((write_data << 32) & MASK64) | (@mtimecmp & 0xFFFF_FFFF)
          when MTIME_LOW_ADDR
            @mtime = (@mtime & 0xFFFF_FFFF_0000_0000) | write_data
          when MTIME_HIGH_ADDR
            @mtime = ((write_data << 32) & MASK64) | (@mtime & 0xFFFF_FFFF)
          end
        end
      end
      @prev_clk = clk

      if mem_read == 1
        read_val = case addr
        when MSIP_ADDR then @msip
        when MTIMECMP_LOW_ADDR then @mtimecmp & 0xFFFF_FFFF
        when MTIMECMP_HIGH_ADDR then (@mtimecmp >> 32) & 0xFFFF_FFFF
        when MTIME_LOW_ADDR then @mtime & 0xFFFF_FFFF
        when MTIME_HIGH_ADDR then (@mtime >> 32) & 0xFFFF_FFFF
        else 0
        end
        out_set(:read_data, read_val)
      else
        out_set(:read_data, 0)
      end

      out_set(:irq_software, @msip)
      out_set(:irq_timer, @mtime >= @mtimecmp ? 1 : 0)
    end

      end
    end
  end
end
