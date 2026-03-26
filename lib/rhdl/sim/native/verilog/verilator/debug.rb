# frozen_string_literal: true

require 'rhdl/sim/native/debug/trace_support'

module RHDL
  module Sim
    module Native
      module Verilog
        module Verilator
          module Debug
            module_function

            def attach(simulator, module_name: nil)
              RHDL::Sim::Native::Debug::TraceSupport.attach(simulator, module_name: module_name)
            end
          end
        end
      end
    end
  end
end
