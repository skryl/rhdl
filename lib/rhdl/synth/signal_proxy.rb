# frozen_string_literal: true

module RHDL
  module Synth
    # Synthesis signal reference
    class SignalProxy < Expr
      attr_reader :name

      def initialize(name, width)
        @name = name
        super(width)
      end

      # For synthesis context, .value just returns self (the signal proxy)
      # This allows behavior blocks to use .value for simulation
      # while still generating correct IR for synthesis
      def value
        self
      end

      def to_ir
        RHDL::Codegen::Verilog::IR::Signal.new(name: @name, width: @width)
      end
    end
  end
end
