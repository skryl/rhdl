# frozen_string_literal: true

module RHDL
  module HDL
    # Synthesis signal reference
    class SynthSignalProxy < SynthExpr
      attr_reader :name

      def initialize(name, width)
        @name = name
        super(width)
      end

      def to_ir
        RHDL::Export::IR::Signal.new(name: @name, width: @width)
      end
    end
  end
end
