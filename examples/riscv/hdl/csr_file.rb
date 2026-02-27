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
    MISA_VALUE = 0x4034_1125 # RV32 + A + C + F + I + M + S + U + V
    CYCLE_CSR_ADDR = 0xC00
    TIME_CSR_ADDR = 0xC01
    CYCLEH_CSR_ADDR = 0xC80
    TIMEH_CSR_ADDR = 0xC81
    CYCLE_CSR_INCREMENT = 1
    TIME_CSR_INCREMENT = 1

    READ_ONLY_COMPAT_CSRS = {
      0x301 => MISA_VALUE, # misa
      0xF11 => 0,          # mvendorid
      0xF12 => 0,          # marchid
      0xF13 => 0,          # mimpid
      0xF14 => 0           # mhartid
    }.freeze

    READ_ONLY_COUNTER_CSRS = [
      CYCLE_CSR_ADDR,
      TIME_CSR_ADDR,
      CYCLEH_CSR_ADDR,
      TIMEH_CSR_ADDR
    ].freeze

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
    input :read_addr9, width: 12
    output :read_data9, width: 32
    input :read_addr10, width: 12
    output :read_data10, width: 32
    input :read_addr11, width: 12
    output :read_data11, width: 32
    input :read_addr12, width: 12
    output :read_data12, width: 32
    input :read_addr13, width: 12
    output :read_data13, width: 32

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
    wire :counter_write_en_cycle
    wire :counter_write_en_cycleh
    wire :counter_write_en_time
    wire :counter_write_en_timeh
    wire :counter_write_addr_cycle, width: 12
    wire :counter_write_addr_cycleh, width: 12
    wire :counter_write_addr_time, width: 12
    wire :counter_write_addr_timeh, width: 12
    wire :counter_write_data_cycle, width: 32
    wire :counter_write_data_cycleh, width: 32
    wire :counter_write_data_time, width: 32
    wire :counter_write_data_timeh, width: 32
    sync_write :csrs, clock: :clk, enable: :csr_write_en1, addr: :write_addr, data: :write_data
    sync_write :csrs, clock: :clk, enable: :csr_write_en2, addr: :write_addr2, data: :write_data2
    sync_write :csrs, clock: :clk, enable: :csr_write_en3, addr: :write_addr3, data: :write_data3
    sync_write :csrs, clock: :clk, enable: :csr_write_en4, addr: :write_addr4, data: :write_data4
    sync_write :csrs, clock: :clk, enable: :counter_write_en_cycle, addr: :counter_write_addr_cycle, data: :counter_write_data_cycle
    sync_write :csrs, clock: :clk, enable: :counter_write_en_cycleh, addr: :counter_write_addr_cycleh, data: :counter_write_data_cycleh
    sync_write :csrs, clock: :clk, enable: :counter_write_en_time, addr: :counter_write_addr_time, data: :counter_write_data_time
    sync_write :csrs, clock: :clk, enable: :counter_write_en_timeh, addr: :counter_write_addr_timeh, data: :counter_write_data_timeh

    behavior do
      cycle_low = local(
        :cycle_low,
        mem_read_expr(:csrs, lit(CYCLE_CSR_ADDR, width: 12), width: 32),
        width: 32
      )
      cycle_high = local(
        :cycle_high,
        mem_read_expr(:csrs, lit(CYCLEH_CSR_ADDR, width: 12), width: 32),
        width: 32
      )
      cycle_low_next = local(:cycle_low_next, cycle_low + lit(CYCLE_CSR_INCREMENT, width: 32), width: 32)
      cycle_carry = local(:cycle_carry, cycle_low_next < cycle_low, width: 1)
      cycle_high_next = local(
        :cycle_high_next,
        cycle_high + mux(cycle_carry, lit(1, width: 32), lit(0, width: 32)),
        width: 32
      )

      time_low = local(
        :time_low,
        mem_read_expr(:csrs, lit(TIME_CSR_ADDR, width: 12), width: 32),
        width: 32
      )
      time_high = local(
        :time_high,
        mem_read_expr(:csrs, lit(TIMEH_CSR_ADDR, width: 12), width: 32),
        width: 32
      )
      time_low_next = local(:time_low_next, time_low + lit(TIME_CSR_INCREMENT, width: 32), width: 32)
      time_carry = local(:time_carry, time_low_next < time_low, width: 1)
      time_high_next = local(
        :time_high_next,
        time_high + mux(time_carry, lit(1, width: 32), lit(0, width: 32)),
        width: 32
      )

      counter_write_en_cycle <= ~rst
      counter_write_en_cycleh <= ~rst
      counter_write_en_time <= ~rst
      counter_write_en_timeh <= ~rst
      counter_write_addr_cycle <= lit(CYCLE_CSR_ADDR, width: 12)
      counter_write_addr_cycleh <= lit(CYCLEH_CSR_ADDR, width: 12)
      counter_write_addr_time <= lit(TIME_CSR_ADDR, width: 12)
      counter_write_addr_timeh <= lit(TIMEH_CSR_ADDR, width: 12)
      counter_write_data_cycle <= cycle_low_next
      counter_write_data_cycleh <= cycle_high_next
      counter_write_data_time <= time_low_next
      counter_write_data_timeh <= time_high_next

      writable1 = local(:writable1,
                        (write_addr != lit(0x301, width: 12)) &
                        (write_addr != lit(0xF11, width: 12)) &
                        (write_addr != lit(0xF12, width: 12)) &
                        (write_addr != lit(0xF13, width: 12)) &
                        (write_addr != lit(0xF14, width: 12)) &
                        (write_addr != lit(CYCLE_CSR_ADDR, width: 12)) &
                        (write_addr != lit(TIME_CSR_ADDR, width: 12)) &
                        (write_addr != lit(CYCLEH_CSR_ADDR, width: 12)) &
                        (write_addr != lit(TIMEH_CSR_ADDR, width: 12)),
                        width: 1)
      writable2 = local(:writable2,
                        (write_addr2 != lit(0x301, width: 12)) &
                        (write_addr2 != lit(0xF11, width: 12)) &
                        (write_addr2 != lit(0xF12, width: 12)) &
                        (write_addr2 != lit(0xF13, width: 12)) &
                        (write_addr2 != lit(0xF14, width: 12)) &
                        (write_addr2 != lit(CYCLE_CSR_ADDR, width: 12)) &
                        (write_addr2 != lit(TIME_CSR_ADDR, width: 12)) &
                        (write_addr2 != lit(CYCLEH_CSR_ADDR, width: 12)) &
                        (write_addr2 != lit(TIMEH_CSR_ADDR, width: 12)),
                        width: 1)
      writable3 = local(:writable3,
                        (write_addr3 != lit(0x301, width: 12)) &
                        (write_addr3 != lit(0xF11, width: 12)) &
                        (write_addr3 != lit(0xF12, width: 12)) &
                        (write_addr3 != lit(0xF13, width: 12)) &
                        (write_addr3 != lit(0xF14, width: 12)) &
                        (write_addr3 != lit(CYCLE_CSR_ADDR, width: 12)) &
                        (write_addr3 != lit(TIME_CSR_ADDR, width: 12)) &
                        (write_addr3 != lit(CYCLEH_CSR_ADDR, width: 12)) &
                        (write_addr3 != lit(TIMEH_CSR_ADDR, width: 12)),
                        width: 1)
      writable4 = local(:writable4,
                        (write_addr4 != lit(0x301, width: 12)) &
                        (write_addr4 != lit(0xF11, width: 12)) &
                        (write_addr4 != lit(0xF12, width: 12)) &
                        (write_addr4 != lit(0xF13, width: 12)) &
                        (write_addr4 != lit(0xF14, width: 12)) &
                        (write_addr4 != lit(CYCLE_CSR_ADDR, width: 12)) &
                        (write_addr4 != lit(TIME_CSR_ADDR, width: 12)) &
                        (write_addr4 != lit(CYCLEH_CSR_ADDR, width: 12)) &
                        (write_addr4 != lit(TIMEH_CSR_ADDR, width: 12)),
                        width: 1)

      csr_write_en1 <= write_we & ~rst & writable1
      csr_write_en2 <= write_we2 & ~rst & writable2
      csr_write_en3 <= write_we3 & ~rst & writable3
      csr_write_en4 <= write_we4 & ~rst & writable4

      read_data <= case_select(read_addr, {
        0x301 => lit(MISA_VALUE, width: 32),
        0xF11 => lit(0, width: 32),
        0xF12 => lit(0, width: 32),
        0xF13 => lit(0, width: 32),
        0xF14 => lit(0, width: 32)
      }, default: mem_read_expr(:csrs, read_addr, width: 32))
      read_data2 <= case_select(read_addr2, {
        0x301 => lit(MISA_VALUE, width: 32),
        0xF11 => lit(0, width: 32),
        0xF12 => lit(0, width: 32),
        0xF13 => lit(0, width: 32),
        0xF14 => lit(0, width: 32)
      }, default: mem_read_expr(:csrs, read_addr2, width: 32))
      read_data3 <= case_select(read_addr3, {
        0x301 => lit(MISA_VALUE, width: 32),
        0xF11 => lit(0, width: 32),
        0xF12 => lit(0, width: 32),
        0xF13 => lit(0, width: 32),
        0xF14 => lit(0, width: 32)
      }, default: mem_read_expr(:csrs, read_addr3, width: 32))
      read_data4 <= case_select(read_addr4, {
        0x301 => lit(MISA_VALUE, width: 32),
        0xF11 => lit(0, width: 32),
        0xF12 => lit(0, width: 32),
        0xF13 => lit(0, width: 32),
        0xF14 => lit(0, width: 32)
      }, default: mem_read_expr(:csrs, read_addr4, width: 32))
      read_data5 <= case_select(read_addr5, {
        0x301 => lit(MISA_VALUE, width: 32),
        0xF11 => lit(0, width: 32),
        0xF12 => lit(0, width: 32),
        0xF13 => lit(0, width: 32),
        0xF14 => lit(0, width: 32)
      }, default: mem_read_expr(:csrs, read_addr5, width: 32))
      read_data6 <= case_select(read_addr6, {
        0x301 => lit(MISA_VALUE, width: 32),
        0xF11 => lit(0, width: 32),
        0xF12 => lit(0, width: 32),
        0xF13 => lit(0, width: 32),
        0xF14 => lit(0, width: 32)
      }, default: mem_read_expr(:csrs, read_addr6, width: 32))
      read_data7 <= case_select(read_addr7, {
        0x301 => lit(MISA_VALUE, width: 32),
        0xF11 => lit(0, width: 32),
        0xF12 => lit(0, width: 32),
        0xF13 => lit(0, width: 32),
        0xF14 => lit(0, width: 32)
      }, default: mem_read_expr(:csrs, read_addr7, width: 32))
      read_data8 <= case_select(read_addr8, {
        0x301 => lit(MISA_VALUE, width: 32),
        0xF11 => lit(0, width: 32),
        0xF12 => lit(0, width: 32),
        0xF13 => lit(0, width: 32),
        0xF14 => lit(0, width: 32)
      }, default: mem_read_expr(:csrs, read_addr8, width: 32))
      read_data9 <= case_select(read_addr9, {
        0x301 => lit(MISA_VALUE, width: 32),
        0xF11 => lit(0, width: 32),
        0xF12 => lit(0, width: 32),
        0xF13 => lit(0, width: 32),
        0xF14 => lit(0, width: 32)
      }, default: mem_read_expr(:csrs, read_addr9, width: 32))
      read_data10 <= case_select(read_addr10, {
        0x301 => lit(MISA_VALUE, width: 32),
        0xF11 => lit(0, width: 32),
        0xF12 => lit(0, width: 32),
        0xF13 => lit(0, width: 32),
        0xF14 => lit(0, width: 32)
      }, default: mem_read_expr(:csrs, read_addr10, width: 32))
      read_data11 <= case_select(read_addr11, {
        0x301 => lit(MISA_VALUE, width: 32),
        0xF11 => lit(0, width: 32),
        0xF12 => lit(0, width: 32),
        0xF13 => lit(0, width: 32),
        0xF14 => lit(0, width: 32)
      }, default: mem_read_expr(:csrs, read_addr11, width: 32))
      read_data12 <= case_select(read_addr12, {
        0x301 => lit(MISA_VALUE, width: 32),
        0xF11 => lit(0, width: 32),
        0xF12 => lit(0, width: 32),
        0xF13 => lit(0, width: 32),
        0xF14 => lit(0, width: 32)
      }, default: mem_read_expr(:csrs, read_addr12, width: 32))
      read_data13 <= case_select(read_addr13, {
        0x301 => lit(MISA_VALUE, width: 32),
        0xF11 => lit(0, width: 32),
        0xF12 => lit(0, width: 32),
        0xF13 => lit(0, width: 32),
        0xF14 => lit(0, width: 32)
      }, default: mem_read_expr(:csrs, read_addr13, width: 32))
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
      read_addr9 = in_val(:read_addr9) & 0xFFF
      read_addr10 = in_val(:read_addr10) & 0xFFF
      read_addr11 = in_val(:read_addr11) & 0xFFF
      read_addr12 = in_val(:read_addr12) & 0xFFF
      read_addr13 = in_val(:read_addr13) & 0xFFF
      read_value = csr_read_value(read_addr, @csrs[read_addr])
      read_value2 = csr_read_value(read_addr2, @csrs[read_addr2])
      read_value3 = csr_read_value(read_addr3, @csrs[read_addr3])
      read_value4 = csr_read_value(read_addr4, @csrs[read_addr4])
      read_value5 = csr_read_value(read_addr5, @csrs[read_addr5])
      read_value6 = csr_read_value(read_addr6, @csrs[read_addr6])
      read_value7 = csr_read_value(read_addr7, @csrs[read_addr7])
      read_value8 = csr_read_value(read_addr8, @csrs[read_addr8])
      read_value9 = csr_read_value(read_addr9, @csrs[read_addr9])
      read_value10 = csr_read_value(read_addr10, @csrs[read_addr10])
      read_value11 = csr_read_value(read_addr11, @csrs[read_addr11])
      read_value12 = csr_read_value(read_addr12, @csrs[read_addr12])
      read_value13 = csr_read_value(read_addr13, @csrs[read_addr13])

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
        out_set(:read_data9, 0)
        out_set(:read_data10, 0)
        out_set(:read_data11, 0)
        out_set(:read_data12, 0)
        out_set(:read_data13, 0)
        @prev_clk = clk
        return
      end

      # Rising edge write
      if @prev_clk == 0 && clk == 1
        increment_counter_pair(CYCLE_CSR_ADDR, CYCLEH_CSR_ADDR, CYCLE_CSR_INCREMENT)
        increment_counter_pair(TIME_CSR_ADDR, TIMEH_CSR_ADDR, TIME_CSR_INCREMENT)

        write_we = in_val(:write_we)
        if write_we == 1
          write_addr = in_val(:write_addr) & 0xFFF
          write_data = in_val(:write_data) & 0xFFFFFFFF
          @csrs[write_addr] = write_data unless read_only_compat_csr?(write_addr)
        end

        write_we2 = in_val(:write_we2)
        if write_we2 == 1
          write_addr2 = in_val(:write_addr2) & 0xFFF
          write_data2 = in_val(:write_data2) & 0xFFFFFFFF
          @csrs[write_addr2] = write_data2 unless read_only_compat_csr?(write_addr2)
        end

        write_we3 = in_val(:write_we3)
        if write_we3 == 1
          write_addr3 = in_val(:write_addr3) & 0xFFF
          write_data3 = in_val(:write_data3) & 0xFFFFFFFF
          @csrs[write_addr3] = write_data3 unless read_only_compat_csr?(write_addr3)
        end

        write_we4 = in_val(:write_we4)
        if write_we4 == 1
          write_addr4 = in_val(:write_addr4) & 0xFFF
          write_data4 = in_val(:write_data4) & 0xFFFFFFFF
          @csrs[write_addr4] = write_data4 unless read_only_compat_csr?(write_addr4)
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
      out_set(:read_data9, read_value9)
      out_set(:read_data10, read_value10)
      out_set(:read_data11, read_value11)
      out_set(:read_data12, read_value12)
      out_set(:read_data13, read_value13)
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
      read_addr9 = in_val(:read_addr9) & 0xFFF
      read_addr10 = in_val(:read_addr10) & 0xFFF
      read_addr11 = in_val(:read_addr11) & 0xFFF
      read_addr12 = in_val(:read_addr12) & 0xFFF
      read_addr13 = in_val(:read_addr13) & 0xFFF
      out_set(:read_data, csr_read_value(read_addr, @csrs[read_addr]))
      out_set(:read_data2, csr_read_value(read_addr2, @csrs[read_addr2]))
      out_set(:read_data3, csr_read_value(read_addr3, @csrs[read_addr3]))
      out_set(:read_data4, csr_read_value(read_addr4, @csrs[read_addr4]))
      out_set(:read_data5, csr_read_value(read_addr5, @csrs[read_addr5]))
      out_set(:read_data6, csr_read_value(read_addr6, @csrs[read_addr6]))
      out_set(:read_data7, csr_read_value(read_addr7, @csrs[read_addr7]))
      out_set(:read_data8, csr_read_value(read_addr8, @csrs[read_addr8]))
      out_set(:read_data9, csr_read_value(read_addr9, @csrs[read_addr9]))
      out_set(:read_data10, csr_read_value(read_addr10, @csrs[read_addr10]))
      out_set(:read_data11, csr_read_value(read_addr11, @csrs[read_addr11]))
      out_set(:read_data12, csr_read_value(read_addr12, @csrs[read_addr12]))
      out_set(:read_data13, csr_read_value(read_addr13, @csrs[read_addr13]))
    end

    def read_csr(addr)
      index = addr & 0xFFF
      csr_read_value(index, @csrs[index])
    end

    def write_csr(addr, value)
      index = addr & 0xFFF
      return if read_only_compat_csr?(index)

      @csrs[index] = value & 0xFFFFFFFF
    end

    private

    def read_only_compat_csr?(addr)
      index = addr & 0xFFF
      READ_ONLY_COMPAT_CSRS.key?(index) || READ_ONLY_COUNTER_CSRS.include?(index)
    end

    def csr_read_value(addr, stored_value)
      READ_ONLY_COMPAT_CSRS.fetch(addr & 0xFFF, stored_value & 0xFFFF_FFFF)
    end

    def increment_counter_pair(low_addr, high_addr, increment = 1)
      full = (@csrs[low_addr] + increment.to_i) & 0x1_FFFF_FFFF
      next_low = full & 0xFFFF_FFFF
      carry = (full >> 32) & 0xFFFF_FFFF
      next_high = (@csrs[high_addr] + carry) & 0xFFFF_FFFF
      @csrs[low_addr] = next_low
      @csrs[high_addr] = next_high
    end

      end
    end
  end
end
