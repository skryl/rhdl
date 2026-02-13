# RV32 CSR Register File - 4096 x 32-bit CSRs
# Multi-read ports, quadruple write ports
# Uses sequential component semantics and real state (not harness emulation)

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'
require_relative '../../../lib/rhdl/dsl/memory'

module RHDL
  module Examples
    module RISCV
      class CSRFile < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential
    include RHDL::DSL::Memory

    input :clk
    input :rst

    # Asynchronous read ports
    input :read_addr, width: 12
    output :read_data, width: 32
    input :read_addr2, width: 12
    output :read_data2, width: 32
    input :read_addr3, width: 12
    output :read_data3, width: 32
    input :read_addr4, width: 12
    output :read_data4, width: 32
    input :read_addr5, width: 12
    output :read_data5, width: 32
    input :read_addr6, width: 12
    output :read_data6, width: 32
    input :read_addr7, width: 12
    output :read_data7, width: 32
    input :read_addr8, width: 12
    output :read_data8, width: 32

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
    input :write_addr4, width: 12
    input :write_data4, width: 32
    input :write_we4

    # IR/codegen memory model for CSR state.
    # Custom propagate below remains the simulation source of truth for Ruby harnesses.
    memory :csrs, depth: 4096, width: 32
    wire :csr_write_en1
    wire :csr_write_en2
    wire :csr_write_en3
    wire :csr_write_en4
    sync_write :csrs, clock: :clk, enable: :csr_write_en1, addr: :write_addr, data: :write_data
    sync_write :csrs, clock: :clk, enable: :csr_write_en2, addr: :write_addr2, data: :write_data2
    sync_write :csrs, clock: :clk, enable: :csr_write_en3, addr: :write_addr3, data: :write_data3
    sync_write :csrs, clock: :clk, enable: :csr_write_en4, addr: :write_addr4, data: :write_data4

    behavior do
      csr_write_en1 <= write_we & ~rst
      csr_write_en2 <= write_we2 & ~rst
      csr_write_en3 <= write_we3 & ~rst
      csr_write_en4 <= write_we4 & ~rst

      read_data <= mem_read_expr(:csrs, read_addr, width: 32)
      read_data2 <= mem_read_expr(:csrs, read_addr2, width: 32)
      read_data3 <= mem_read_expr(:csrs, read_addr3, width: 32)
      read_data4 <= mem_read_expr(:csrs, read_addr4, width: 32)
      read_data5 <= mem_read_expr(:csrs, read_addr5, width: 32)
      read_data6 <= mem_read_expr(:csrs, read_addr6, width: 32)
      read_data7 <= mem_read_expr(:csrs, read_addr7, width: 32)
      read_data8 <= mem_read_expr(:csrs, read_addr8, width: 32)
    end

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
      read_addr4 = in_val(:read_addr4) & 0xFFF
      read_addr5 = in_val(:read_addr5) & 0xFFF
      read_addr6 = in_val(:read_addr6) & 0xFFF
      read_addr7 = in_val(:read_addr7) & 0xFFF
      read_addr8 = in_val(:read_addr8) & 0xFFF
      read_value = @csrs[read_addr]
      read_value2 = @csrs[read_addr2]
      read_value3 = @csrs[read_addr3]
      read_value4 = @csrs[read_addr4]
      read_value5 = @csrs[read_addr5]
      read_value6 = @csrs[read_addr6]
      read_value7 = @csrs[read_addr7]
      read_value8 = @csrs[read_addr8]

      if rst == 1
        @csrs = Array.new(4096, 0)
        out_set(:read_data, 0)
        out_set(:read_data2, 0)
        out_set(:read_data3, 0)
        out_set(:read_data4, 0)
        out_set(:read_data5, 0)
        out_set(:read_data6, 0)
        out_set(:read_data7, 0)
        out_set(:read_data8, 0)
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

        write_we4 = in_val(:write_we4)
        if write_we4 == 1
          write_addr4 = in_val(:write_addr4) & 0xFFF
          write_data4 = in_val(:write_data4) & 0xFFFFFFFF
          @csrs[write_addr4] = write_data4
        end
      end
      @prev_clk = clk

      # Return the value observed before this cycle's write so CSRRW/CSRRS*
      # read-before-write semantics match the ISA.
      out_set(:read_data, read_value)
      out_set(:read_data2, read_value2)
      out_set(:read_data3, read_value3)
      out_set(:read_data4, read_value4)
      out_set(:read_data5, read_value5)
      out_set(:read_data6, read_value6)
      out_set(:read_data7, read_value7)
      out_set(:read_data8, read_value8)
    end

    def update_outputs
      read_addr = in_val(:read_addr) & 0xFFF
      read_addr2 = in_val(:read_addr2) & 0xFFF
      read_addr3 = in_val(:read_addr3) & 0xFFF
      read_addr4 = in_val(:read_addr4) & 0xFFF
      read_addr5 = in_val(:read_addr5) & 0xFFF
      read_addr6 = in_val(:read_addr6) & 0xFFF
      read_addr7 = in_val(:read_addr7) & 0xFFF
      read_addr8 = in_val(:read_addr8) & 0xFFF
      out_set(:read_data, @csrs[read_addr])
      out_set(:read_data2, @csrs[read_addr2])
      out_set(:read_data3, @csrs[read_addr3])
      out_set(:read_data4, @csrs[read_addr4])
      out_set(:read_data5, @csrs[read_addr5])
      out_set(:read_data6, @csrs[read_addr6])
      out_set(:read_data7, @csrs[read_addr7])
      out_set(:read_data8, @csrs[read_addr8])
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
