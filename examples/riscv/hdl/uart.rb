# UART (16550-like) minimal model for RV32 simulation
# Supports byte MMIO accesses used by xv6 initialization and console input paths.

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'
require_relative 'constants'

module RHDL
  module Examples
    module RISCV
      class Uart < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    BASE_ADDR = 0x1000_0000

    REG_THR_RBR_DLL = 0x0
    REG_IER_DLM = 0x1
    REG_IIR_FCR = 0x2
    REG_LCR = 0x3
    REG_MCR = 0x4
    REG_LSR = 0x5
    REG_MSR = 0x6
    REG_SCR = 0x7

    input :clk
    input :rst

    # Memory-mapped access port
    input :addr, width: 32
    input :write_data, width: 32
    input :mem_read
    input :mem_write
    input :funct3, width: 3

    # External RX injection
    input :rx_valid
    input :rx_data, width: 8

    output :read_data, width: 32
    output :irq
    output :tx_valid
    output :tx_data, width: 8
    output :rx_accept

    def initialize(name = nil)
      super(name)
      @rbr = 0
      @ier = 0
      @lcr = 0
      @mcr = 0
      @dll = 0
      @dlm = 0
      @scr = 0
      @rx_ready = 0
      @tx_data_reg = 0
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
      rx_valid = in_val(:rx_valid)
      rx_data = in_val(:rx_data) & 0xFF

      tx_valid_now = 0
      rx_accept_now = 0

      if rst == 1
        @rbr = 0
        @ier = 0
        @lcr = 0
        @mcr = 0
        @dll = 0
        @dlm = 0
        @scr = 0
        @rx_ready = 0
        @tx_data_reg = 0
        out_set(:read_data, 0)
        out_set(:irq, 0)
        out_set(:tx_valid, 0)
        out_set(:tx_data, 0)
        out_set(:rx_accept, 0)
        @prev_clk = clk
        return
      end

      reg_offset = addr & 0x7
      byte_access = funct3 == Funct3::BYTE || funct3 == Funct3::BYTE_U
      word_access = funct3 == Funct3::WORD
      access_ok = byte_access || word_access
      dlab = (@lcr & 0x80) != 0
      rbr_pop = mem_read == 1 && access_ok && reg_offset == REG_THR_RBR_DLL && !dlab && @rx_ready == 1
      rbr_pop_value = @rbr

      if @prev_clk == 0 && clk == 1
        if rx_valid == 1 && @rx_ready == 0
          @rbr = rx_data
          @rx_ready = 1
          rx_accept_now = 1
        end

        if mem_write == 1 && access_ok
          write_byte = write_data & 0xFF
          case reg_offset
          when REG_THR_RBR_DLL
            if dlab
              @dll = write_byte
            else
              @tx_data_reg = write_byte
              tx_valid_now = 1
            end
          when REG_IER_DLM
            if dlab
              @dlm = write_byte
            else
              @ier = write_byte & 0x0F
            end
          when REG_IIR_FCR
            # FCR clear RX FIFO bit
            @rx_ready = 0 if (write_byte & 0x2) != 0
          when REG_LCR
            @lcr = write_byte
          when REG_MCR
            @mcr = write_byte
          when REG_SCR
            @scr = write_byte
          end
        end

        @rx_ready = 0 if rbr_pop
      end
      @prev_clk = clk

      rx_irq_pending = ((@ier & 0x1) != 0) && @rx_ready == 1
      iir = rx_irq_pending ? 0x04 : 0x01
      lsr = 0x60 | (@rx_ready == 1 ? 0x01 : 0x00)

      if mem_read == 1 && access_ok
        read_byte = case reg_offset
                    when REG_THR_RBR_DLL
                      if dlab
                        @dll
                      else
                        rbr_pop ? rbr_pop_value : @rbr
                      end
                    when REG_IER_DLM
                      dlab ? @dlm : @ier
                    when REG_IIR_FCR
                      iir
                    when REG_LCR
                      @lcr
                    when REG_MCR
                      @mcr
                    when REG_LSR
                      lsr
                    when REG_MSR
                      0
                    when REG_SCR
                      @scr
                    else
                      0
                    end

        read_val = if funct3 == Funct3::BYTE
                     (read_byte & 0x80) != 0 ? (read_byte | 0xFFFF_FF00) : read_byte
                   else
                     read_byte
                   end
        out_set(:read_data, read_val & 0xFFFF_FFFF)
      else
        out_set(:read_data, 0)
      end

      out_set(:irq, rx_irq_pending ? 1 : 0)
      out_set(:tx_valid, tx_valid_now)
      out_set(:tx_data, @tx_data_reg)
      out_set(:rx_accept, rx_accept_now)
    end

      end
    end
  end
end
