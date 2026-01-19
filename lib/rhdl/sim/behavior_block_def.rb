# frozen_string_literal: true

module RHDL
  module Sim
    # Behavior block definition
    class BehaviorBlockDef
      attr_reader :block, :options

      def initialize(block, **options)
        @block = block
        @options = options
      end
    end
  end
end
