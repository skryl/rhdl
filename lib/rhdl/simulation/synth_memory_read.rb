# frozen_string_literal: true

module RHDL
  module HDL
    # Memory read expression for synthesis
    # Generates IR::MemoryRead for HDL export
    class SynthMemoryRead < SynthExpr
      attr_reader :memory_name, :addr

      def initialize(memory_name, addr, width)
        super(width)
        @memory_name = memory_name
        @addr = addr
      end

      def to_ir
        RHDL::Export::IR::MemoryRead.new(
          memory: @memory_name,
          addr: @addr.to_ir,
          width: @width
        )
      end
    end
  end
end
