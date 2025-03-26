require 'active_support'
require 'active_support/concern'
require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/string/inflections'

module RHDL
  module DSL
    extend ActiveSupport::Concern

    included do
      class_attribute :ports, :signals, :components
      self.ports = []
      self.signals = []
      self.components = []
    end

    class_methods do
      def input(name, width: 1)
        ports << Port.new(name, :in, width)
      end

      def output(name, width: 1)
        ports << Port.new(name, :out, width)
      end

      def signal(name, width: 1)
        signals << Signal.new(name, width)
      end

      def architecture(&block)
        class_eval(&block) if block_given?
      end
    end
  end

  class Port
    attr_reader :name, :direction, :width

    def initialize(name, direction, width)
      @name = name
      @direction = direction
      @width = width
    end

    def to_vhdl
      width_str = width > 1 ? "(#{width-1} downto 0)" : ""
      "#{name} : #{direction} std_logic#{width_str};"
    end
  end

  class Signal
    attr_reader :name, :width

    def initialize(name, width)
      @name = name
      @width = width
    end

    def to_vhdl
      width_str = width > 1 ? "(#{width-1} downto 0)" : ""
      "signal #{name} : std_logic#{width_str};"
    end
  end
end
