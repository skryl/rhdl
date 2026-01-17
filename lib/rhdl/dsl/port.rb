# frozen_string_literal: true

module RHDL
  module DSL
    # Port definition
    class Port
      attr_reader :name, :direction, :width, :default

      def initialize(name, direction, width, default: nil)
        @name = name
        @direction = direction
        @width = width
        @default = default
      end

      def to_vhdl
        type_str = width > 1 ? "std_logic_vector(#{width-1} downto 0)" : "std_logic"
        "#{name} : #{direction} #{type_str}"
      end

      def to_verilog
        dir = case direction
              when :in then "input"
              when :out then "output"
              when :inOut then "inOut"
              end
        width > 1 ? "#{dir} [#{width-1}:0] #{name}" : "#{dir} #{name}"
      end

      def to_signal_ref
        SignalRef.new(name, width: width)
      end
    end
  end
end
