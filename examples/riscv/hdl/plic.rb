# Platform-Level Interrupt Controller (PLIC) - minimal multi-source subset
# Provides priority/enable/threshold/claim-complete for sources 1 and 10.

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'
require_relative 'constants'

module RHDL
  module Examples
    module RISCV
      class Plic < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    BASE_ADDR = 0x0C00_0000
    PRIORITY_1_ADDR = BASE_ADDR + 0x0004
    PRIORITY_10_ADDR = BASE_ADDR + 0x0028
    PENDING_ADDR = BASE_ADDR + 0x1000
    ENABLE_ADDR = BASE_ADDR + 0x2000
    THRESHOLD_ADDR = BASE_ADDR + 0x200000
    CLAIM_COMPLETE_ADDR = BASE_ADDR + 0x200004

    input :clk
    input :rst

    # Memory-mapped access port
    input :addr, width: 32
    input :write_data, width: 32
    input :mem_read
    input :mem_write
    input :funct3, width: 3

    # Interrupt sources
    input :source1
    input :source10

    output :read_data, width: 32
    output :irq_external

    def initialize(name = nil)
      super(name)
      @priority1 = 0
      @priority10 = 0
      @pending1 = 0
      @pending10 = 0
      @enable1 = 0
      @enable10 = 0
      @threshold = 0
      @in_service_id = 0
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
      source1 = in_val(:source1)
      source10 = in_val(:source10)
      claim_id = select_claim_id
      claim_grant = mem_read == 1 && addr == CLAIM_COMPLETE_ADDR && claim_id != 0

      if rst == 1
        @priority1 = 0
        @priority10 = 0
        @pending1 = 0
        @pending10 = 0
        @enable1 = 0
        @enable10 = 0
        @threshold = 0
        @in_service_id = 0
        out_set(:read_data, 0)
        out_set(:irq_external, 0)
        @prev_clk = clk
        return
      end

      if @prev_clk == 0 && clk == 1
        # Latch pending interrupts whenever a source is asserted.
        @pending1 = 1 if source1 == 1
        @pending10 = 1 if source10 == 1

        if mem_write == 1 && funct3 == Funct3::WORD
          case addr
          when PRIORITY_1_ADDR
            @priority1 = write_data & 0x7
          when PRIORITY_10_ADDR
            @priority10 = write_data & 0x7
          when ENABLE_ADDR
            @enable1 = (write_data >> 1) & 0x1
            @enable10 = (write_data >> 10) & 0x1
          when THRESHOLD_ADDR
            @threshold = write_data & 0x7
          when CLAIM_COMPLETE_ADDR
            complete_id = write_data & 0x3FF
            @in_service_id = 0 if complete_id == @in_service_id
          end
        end

        claim_id_rise = select_claim_id
        if mem_read == 1 && addr == CLAIM_COMPLETE_ADDR && claim_id_rise != 0
          clear_pending!(claim_id_rise)
          @in_service_id = claim_id_rise
        end
      end
      @prev_clk = clk

      if mem_read == 1
        read_val = case addr
        when PRIORITY_1_ADDR then @priority1
        when PRIORITY_10_ADDR then @priority10
        when PENDING_ADDR then (@pending1 << 1) | (@pending10 << 10)
        when ENABLE_ADDR then (@enable1 << 1) | (@enable10 << 10)
        when THRESHOLD_ADDR then @threshold
        when CLAIM_COMPLETE_ADDR then claim_grant ? claim_id : select_claim_id
        else 0
        end
        out_set(:read_data, read_val & 0xFFFF_FFFF)
      else
        out_set(:read_data, 0)
      end

      out_set(:irq_external, select_claim_id != 0 ? 1 : 0)
    end

    private

    def clear_pending!(id)
      case id
      when 1
        @pending1 = 0
      when 10
        @pending10 = 0
      end
    end

    def claimable_source1?
      @pending1 == 1 && @enable1 == 1 && @priority1 > @threshold
    end

    def claimable_source10?
      @pending10 == 1 && @enable10 == 1 && @priority10 > @threshold
    end

    def select_claim_id
      return 0 unless @in_service_id == 0

      source1 = claimable_source1?
      source10 = claimable_source10?
      return 0 unless source1 || source10
      return 1 if source1 && !source10
      return 10 if source10 && !source1
      return 10 if @priority10 > @priority1

      # Tie-break lower interrupt ID first.
      1
    end

      end
    end
  end
end
