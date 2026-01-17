# MOS 6502 Data Latch - Synthesizable DSL Version
# 8-bit data latch for holding memory data

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module MOS6502S
  # Data Latch - Synthesizable via Sequential DSL
  class DataLatch < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    port_input :clk
    port_input :rst
    port_input :load
    port_input :data_in, width: 8

    port_output :data, width: 8

    def initialize(name = nil)
      @data_reg = 0
      super(name)
    end

    # Sequential block for data register
    sequential clock: :clk, reset: :rst, reset_values: { data: 0 } do
      data <= mux(load, data_in, data)
    end

    # Override propagate to maintain internal state for testing
    def propagate
      if rising_edge?
        if in_val(:rst) == 1
          @data_reg = 0
        elsif in_val(:load) == 1
          @data_reg = in_val(:data_in) & 0xFF
        end
      end

      out_set(:data, @data_reg)
    end

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: 'mos6502s_data_latch'))
    end
  end
end
