# frozen_string_literal: true

# Port and Signal DSL for HDL Components
#
# This module provides class-level DSL methods for defining component interfaces:
# - input/output: Define I/O ports
# - wire: Define internal signals
# - parameter: Define parameterized values
#
# @example Simple component
#   class MyAnd < Component
#     include RHDL::DSL::Ports
#
#     input :a
#     input :b
#     output :y
#   end
#
# @example Parameterized component
#   class Register < Component
#     include RHDL::DSL::Ports
#
#     parameter :width, default: 8
#     input :d, width: :width
#     output :q, width: :width
#   end

require 'active_support/concern'

module RHDL
  module DSL
    module Ports
      extend ActiveSupport::Concern

      # Simple structs for port/signal definitions
      PortDef = Struct.new(:name, :direction, :width, :default)
      SignalDef = Struct.new(:name, :width)

      class_methods do
        def inherited(subclass)
          super
          # Copy definitions to subclass
          subclass.instance_variable_set(:@_port_defs, (@_port_defs || []).dup)
          subclass.instance_variable_set(:@_signal_defs, (@_signal_defs || []).dup)
          subclass.instance_variable_set(:@_parameter_defs, (@_parameter_defs || {}).dup)
        end

        def _port_defs
          @_port_defs ||= []
        end

        def _signal_defs
          @_signal_defs ||= []
        end

        def _parameter_defs
          @_parameter_defs ||= {}
        end

        # Define a component parameter with default value
        # Parameters can be referenced by symbol in width declarations
        # Supports computed defaults via Proc/lambda
        #
        # @param name [Symbol] Parameter name (becomes @name instance variable)
        # @param default [Integer, Proc] Default value or lambda for computed value
        #
        # @example Simple parameter
        #   parameter :width, default: 8
        #
        # @example Computed parameter (evaluated after other params are set)
        #   parameter :width, default: 8
        #   parameter :product_width, default: -> { @width * 2 }
        #
        def parameter(name, default:)
          _parameter_defs[name] = default
        end

        # Resolve a width value at class level using default parameter values
        # For computed (Proc) defaults, evaluates them using other defaults
        def resolve_class_width(width)
          case width
          when Integer
            width
          when Symbol
            val = _parameter_defs[width]
            case val
            when Proc
              # For class-level resolution, evaluate proc with defaults
              eval_context = Object.new
              _parameter_defs.each do |k, v|
                next if v.is_a?(Proc)
                eval_context.instance_variable_set(:"@#{k}", v)
              end
              eval_context.instance_exec(&val)
            when Integer
              val
            else
              1
            end
          else
            1
          end
        end

        # DSL-compatible _ports accessor for behavior module
        def _ports
          _port_defs.map do |pd|
            PortDef.new(pd[:name], pd[:direction], resolve_class_width(pd[:width]), pd[:default])
          end
        end

        # DSL-compatible _signals accessor for behavior module
        def _signals
          _signal_defs.map do |sd|
            SignalDef.new(sd[:name], resolve_class_width(sd[:width]))
          end
        end

        # Class-level input port definition
        # @param name [Symbol] Port name
        # @param width [Integer, Symbol] Bit width (default: 1)
        # @param default [Integer, nil] Default value for unconnected ports (Verilog only)
        def input(name, width: 1, default: nil)
          _port_defs << { name: name, direction: :in, width: width, default: default }
        end

        # Class-level output port definition
        # @param name [Symbol] Port name
        # @param width [Integer, Symbol] Bit width (default: 1)
        def output(name, width: 1)
          _port_defs << { name: name, direction: :out, width: width }
        end

        # Define an internal wire (signal)
        # Also handles backwards-compatible connection syntax when called with a Hash
        #
        # @param name [Symbol] Wire name (for signal definition)
        # @param width [Integer, Symbol] Bit width (default: 1, only for signal definition)
        # @param mappings [Hash] Connection mappings (backwards compatible)
        #
        # @example Define internal wire
        #   wire :alu_out, width: 8
        #
        # @example Connection (backwards compatible, prefer 'port' instead)
        #   wire :a => [:alu, :a]
        #
        def wire(name = nil, width: 1, **mappings)
          if name.nil? && !mappings.empty?
            # Backwards compatibility: wire :a => [:alu, :a]
            # Ruby parses :a => [...] as keyword argument, so it ends up in mappings
            port(mappings) if respond_to?(:port)
          elsif name.is_a?(Hash)
            # Explicit hash argument: wire({:a => [:alu, :a]})
            port(name) if respond_to?(:port)
          else
            # New syntax: wire :signal_name, width: 8
            _signal_defs << { name: name, width: width }
          end
        end
      end

      # Instance methods

      # Set parameter values from kwargs or use defaults from class definition
      # Handles computed defaults (Procs) by evaluating them after simple params are set
      def setup_parameters(kwargs)
        # First pass: set non-computed parameters
        self.class._parameter_defs.each do |name, default|
          next if default.is_a?(Proc)
          ivar = :"@#{name}"
          value = kwargs.fetch(name, default)
          instance_variable_set(ivar, value)
        end

        # Second pass: evaluate computed parameters
        self.class._parameter_defs.each do |name, default|
          next unless default.is_a?(Proc)
          ivar = :"@#{name}"
          # Use kwarg value if provided, otherwise compute from proc
          value = kwargs.key?(name) ? kwargs[name] : instance_exec(&default)
          instance_variable_set(ivar, value)
        end
      end

      # Resolve a width value - either an Integer or a Symbol referencing a parameter
      def resolve_width(width)
        case width
        when Integer
          width
        when Symbol
          instance_variable_get(:"@#{width}") || 1
        else
          1
        end
      end

      # Create ports from class-level definitions
      def setup_ports_from_class_defs
        self.class._port_defs.each do |pd|
          w = resolve_width(pd[:width])
          case pd[:direction]
          when :in
            input(pd[:name], width: w)
          when :out
            output(pd[:name], width: w)
          end
        end
        self.class._signal_defs.each do |sd|
          w = resolve_width(sd[:width])
          signal(sd[:name], width: w)
        end
      end
    end
  end
end
