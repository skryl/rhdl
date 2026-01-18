# MOS 6502 Data Latch - Synthesizable DSL Version
# 8-bit data latch for holding memory data

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module MOS6502
  # Data Latch - Synthesizable via Sequential DSL
  class DataLatch < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    port_input :clk
    port_input :rst
    port_input :load
    port_input :data_in, width: 8

    port_output :data, width: 8

    # Sequential block for data register
    sequential clock: :clk, reset: :rst, reset_values: { data: 0 } do
      data <= mux(load, data_in, data)
    end

    def self.verilog_module_name
      'mos6502_data_latch'
    end

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: verilog_module_name))
    end
  end
end
