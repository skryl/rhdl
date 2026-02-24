# RVV control-state register file (scoped baseline)
# Stores vl and vtype architectural state.

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module RISCV
      class VectorCSRFile < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential

        input :clk
        input :rst

        input :vl_write_data, width: 32
        input :vl_write_we
        input :vtype_write_data, width: 32
        input :vtype_write_we

        output :vl, width: 32
        output :vtype, width: 32

        sequential clock: :clk, reset: :rst, reset_values: { vl: 0, vtype: 0 } do
          vl <= mux(vl_write_we, vl_write_data, vl)
          vtype <= mux(vtype_write_we, vtype_write_data, vtype)
        end

        def read_vl
          read_reg(:vl)
        end

        def read_vtype
          read_reg(:vtype)
        end
      end
    end
  end
end
