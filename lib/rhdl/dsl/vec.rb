# frozen_string_literal: true

# Vec DSL for HDL Components
#
# This module provides class-level DSL methods for defining Vec (hardware arrays):
# - vec: Define internal array of signals
# - input_vec: Define input array ports
# - output_vec: Define output array ports
#
# @example Internal Vec (array of wires)
#   vec :regs, count: 32, width: 64
#
# @example Input Vec (array of input ports)
#   input_vec :data_in, count: 4, width: 8
#
# @example Output Vec (array of output ports)
#   output_vec :data_out, count: 4, width: 8
#
# @example Parameterized Vec
#   parameter :depth, default: 32
#   vec :registers, count: :depth, width: 64

require 'rhdl/support/concern'

module RHDL
  module DSL
    module Vec
      extend RHDL::Support::Concern

      class_methods do
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@_vec_defs, (@_vec_defs || []).dup)
        end

        def _vec_defs
          @_vec_defs ||= []
        end

        # Define a Vec (hardware array) port or signal
        #
        # Vec creates an array of signals that can be indexed at runtime
        # (generates mux/demux logic) or at elaboration time (constant index).
        #
        # @param name [Symbol] Vec instance name
        # @param count [Integer, Symbol] Number of elements (can reference parameter)
        # @param width [Integer, Symbol] Width of each element (default: 1)
        # @param direction [Symbol] :input, :output, or nil for internal (default: nil)
        #
        # @example Internal Vec (array of wires)
        #   vec :regs, count: 32, width: 64
        #
        # @example Input Vec (array of input ports)
        #   input_vec :data_in, count: 4, width: 8
        #
        # @example Output Vec (array of output ports)
        #   output_vec :data_out, count: 4, width: 8
        #
        # @example Parameterized Vec
        #   parameter :depth, default: 32
        #   vec :registers, count: :depth, width: 64
        #
        def vec(name, count:, width: 1, direction: nil)
          _vec_defs << {
            name: name,
            count: count,
            width: width,
            direction: direction
          }

          # For ports, add flattened individual ports
          resolved_count = resolve_class_width(count)
          if direction == :input || direction == :output
            resolved_count.times do |i|
              port_name = "#{name}_#{i}".to_sym
              if direction == :input
                _port_defs << { name: port_name, direction: :in, width: width, default: nil }
              else
                _port_defs << { name: port_name, direction: :out, width: width }
              end
            end
          end
        end

        # Define an input Vec (array of input ports)
        #
        # @param name [Symbol] Vec instance name
        # @param count [Integer, Symbol] Number of elements
        # @param width [Integer, Symbol] Width of each element
        #
        # @example
        #   input_vec :data_in, count: 4, width: 8
        #   # Creates: data_in_0, data_in_1, data_in_2, data_in_3 (all 8-bit inputs)
        #
        def input_vec(name, count:, width: 1)
          vec(name, count: count, width: width, direction: :input)
        end

        # Define an output Vec (array of output ports)
        #
        # @param name [Symbol] Vec instance name
        # @param count [Integer, Symbol] Number of elements
        # @param width [Integer, Symbol] Width of each element
        #
        # @example
        #   output_vec :data_out, count: 4, width: 8
        #   # Creates: data_out_0, data_out_1, data_out_2, data_out_3 (all 8-bit outputs)
        #
        def output_vec(name, count:, width: 1)
          vec(name, count: count, width: width, direction: :output)
        end
      end

      # Instance methods

      # Setup Vec instances from class-level definitions
      def setup_vecs_from_class_defs
        @vecs = {}

        self.class._vec_defs.each do |vd|
          count = resolve_width(vd[:count])
          width = resolve_width(vd[:width])
          direction = vd[:direction]

          vec_inst = RHDL::Sim::VecInstance.new(
            vd[:name],
            count: count,
            width: width,
            component: self,
            direction: direction
          )

          @vecs[vd[:name]] = vec_inst
          instance_variable_set(:"@#{vd[:name]}", vec_inst)
        end
      end
    end
  end
end
