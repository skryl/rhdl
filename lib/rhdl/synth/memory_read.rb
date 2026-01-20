# frozen_string_literal: true

module RHDL
  module Synth
    # Memory read expression for synthesis
    # Generates IR::MemoryRead for HDL export
    class MemoryRead < Expr
      attr_reader :memory_name, :addr

      def initialize(memory_name, addr, width)
        super(width)
        @memory_name = memory_name
        @addr = addr
      end

      def to_ir
        RHDL::Codegen::Behavior::IR::MemoryRead.new(
          memory: @memory_name,
          addr: @addr.to_ir,
          width: @width
        )
      end
    end
  end
end
