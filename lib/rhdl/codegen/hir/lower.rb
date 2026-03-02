# frozen_string_literal: true

module RHDL
  module Codegen
    module HIR
      class Lower < RHDL::Codegen::IR::Lower
        def initialize(component_class, top_name: nil)
          super(component_class, top_name: top_name, mode: :hir)
        end
      end
    end
  end
end
