# MOS 6502 Data Latch - Synthesizable DSL Version
# 8-bit data latch for holding memory data

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module MOS6502
      # Data Latch - Synthesizable via Sequential DSL
      class DataLatch < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk
    input :rst
    input :load
    input :data_in, width: 8

    output :data, width: 8

    # Sequential block for data register
    sequential clock: :clk, reset: :rst, reset_values: { data: 0 } do
      data <= mux(load, data_in, data)
    end

    end
  end
end
end
