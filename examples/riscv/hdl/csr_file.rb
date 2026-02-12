# RV32 CSR Register File - 4096 x 32-bit CSRs
# Dual read ports, triple write ports
# Uses sequential component semantics and real state (not harness emulation)

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module RISCV
      class CSRFile < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk
    input :rst

    # Asynchronous read ports
    input :read_addr, width: 12
    output :read_data, width: 32
    input :read_addr2, width: 12
    output :read_data2, width: 32
    input :read_addr3, width: 12
    output :read_data3, width: 32

    # Synchronous write ports
    input :write_addr, width: 12
    input :write_data, width: 32
    input :write_we
    input :write_addr2, width: 12
    input :write_data2, width: 32
    input :write_we2
    input :write_addr3, width: 12
    input :write_data3, width: 32
    input :write_we3

    def initialize(name = nil)
      super(name)
      @csrs = Array.new(4096, 0)
    end

    def propagate
      clk = in_val(:clk)
      rst = in_val(:rst)
      @prev_clk ||= 0
      read_addr = in_val(:read_addr) & 0xFFF
      read_addr2 = in_val(:read_addr2) & 0xFFF
      read_addr3 = in_val(:read_addr3) & 0xFFF
      read_value = @csrs[read_addr]
      read_value2 = @csrs[read_addr2]
      read_value3 = @csrs[read_addr3]

      if rst == 1
        @csrs = Array.new(4096, 0)
        out_set(:read_data, 0)
        out_set(:read_data2, 0)
        out_set(:read_data3, 0)
        @prev_clk = clk
        return
      end

      # Rising edge write
      if @prev_clk == 0 && clk == 1
        write_we = in_val(:write_we)
        if write_we == 1
          write_addr = in_val(:write_addr) & 0xFFF
          write_data = in_val(:write_data) & 0xFFFFFFFF
          @csrs[write_addr] = write_data
        end

        write_we2 = in_val(:write_we2)
        if write_we2 == 1
          write_addr2 = in_val(:write_addr2) & 0xFFF
          write_data2 = in_val(:write_data2) & 0xFFFFFFFF
          @csrs[write_addr2] = write_data2
        end

        write_we3 = in_val(:write_we3)
        if write_we3 == 1
          write_addr3 = in_val(:write_addr3) & 0xFFF
          write_data3 = in_val(:write_data3) & 0xFFFFFFFF
          @csrs[write_addr3] = write_data3
        end
      end
      @prev_clk = clk

      # Return the value observed before this cycle's write so CSRRW/CSRRS*
      # read-before-write semantics match the ISA.
      out_set(:read_data, read_value)
      out_set(:read_data2, read_value2)
      out_set(:read_data3, read_value3)
    end

    def update_outputs
      read_addr = in_val(:read_addr) & 0xFFF
      read_addr2 = in_val(:read_addr2) & 0xFFF
      read_addr3 = in_val(:read_addr3) & 0xFFF
      out_set(:read_data, @csrs[read_addr])
      out_set(:read_data2, @csrs[read_addr2])
      out_set(:read_data3, @csrs[read_addr3])
    end

    def read_csr(addr)
      @csrs[addr & 0xFFF]
    end

    def write_csr(addr, value)
      @csrs[addr & 0xFFF] = value & 0xFFFFFFFF
    end

      end
    end
  end
end
