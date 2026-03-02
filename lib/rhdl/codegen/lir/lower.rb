# frozen_string_literal: true

module RHDL
  module Codegen
    module LIR
      class Lower < RHDL::Codegen::IR::Lower
        def initialize(component_class, top_name: nil)
          super(component_class, top_name: top_name, mode: :lir)
        end
      end
    end
  end
end
