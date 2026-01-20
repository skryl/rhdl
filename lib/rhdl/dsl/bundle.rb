# frozen_string_literal: true

# Bundle DSL for HDL Components
#
# This module provides class-level DSL methods for defining Bundle (aggregate interface) ports:
# - input_bundle: Define an input bundle port
# - output_bundle: Define an output bundle port (flipped by default)
#
# @example Define a bundle type
#   class AxiLite < Bundle
#     field :awaddr, width: 32, direction: :output
#     field :awvalid, width: 1, direction: :output
#     field :awready, width: 1, direction: :input
#   end
#
# @example Use as input (producer interface)
#   input_bundle :axi, AxiLite
#
# @example Use as output (consumer interface - flipped)
#   output_bundle :axi, AxiLite  # equivalent to flipped: true

require 'active_support/concern'

module RHDL
  module DSL
    module Bundle
      extend ActiveSupport::Concern

      class_methods do
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@_bundle_defs, (@_bundle_defs || []).dup)
        end

        def _bundle_defs
          @_bundle_defs ||= []
        end

        # Define a Bundle port (aggregate interface type)
        #
        # Bundles group multiple related signals into a single interface.
        # Fields are flattened to individual ports in the generated Verilog.
        #
        # @param name [Symbol] Bundle instance name
        # @param bundle_class [Class] Bundle class (must inherit from Bundle)
        # @param direction [Symbol] :input or :output (default: :input)
        # @param flipped [Boolean] Reverse all field directions (default: false)
        #
        # @example Define a bundle
        #   class AxiLite < Bundle
        #     field :awaddr, width: 32, direction: :output
        #     field :awvalid, width: 1, direction: :output
        #     field :awready, width: 1, direction: :input
        #   end
        #
        # @example Use as input (producer interface)
        #   input_bundle :axi, AxiLite
        #
        # @example Use as output (consumer interface - flipped)
        #   output_bundle :axi, AxiLite  # equivalent to flipped: true
        #
        def input_bundle(name, bundle_class, flipped: false)
          _bundle_defs << {
            name: name,
            bundle_class: bundle_class,
            direction: :input,
            flipped: flipped
          }

          # Add flattened ports
          bundle_class.fields.each do |field|
            effective_dir = flipped ? field.flipped_direction : field.direction
            port_name = "#{name}_#{field.name}".to_sym

            if effective_dir == :input
              _port_defs << { name: port_name, direction: :in, width: field.width, default: nil }
            else
              _port_defs << { name: port_name, direction: :out, width: field.width }
            end
          end
        end

        # Define an output Bundle port (flipped by default for consumer interface)
        #
        # @param name [Symbol] Bundle instance name
        # @param bundle_class [Class] Bundle class
        # @param flipped [Boolean] Reverse field directions (default: true for output)
        #
        def output_bundle(name, bundle_class, flipped: true)
          _bundle_defs << {
            name: name,
            bundle_class: bundle_class,
            direction: :output,
            flipped: flipped
          }

          # Add flattened ports
          bundle_class.fields.each do |field|
            effective_dir = flipped ? field.flipped_direction : field.direction
            port_name = "#{name}_#{field.name}".to_sym

            if effective_dir == :input
              _port_defs << { name: port_name, direction: :in, width: field.width, default: nil }
            else
              _port_defs << { name: port_name, direction: :out, width: field.width }
            end
          end
        end
      end

      # Instance methods

      # Setup Bundle instances from class-level definitions
      def setup_bundles_from_class_defs
        @bundles = {}

        self.class._bundle_defs.each do |bd|
          bundle_inst = RHDL::Sim::BundleInstance.new(
            bd[:name],
            bd[:bundle_class],
            self,
            flipped: bd[:flipped]
          )

          @bundles[bd[:name]] = bundle_inst
          instance_variable_set(:"@#{bd[:name]}", bundle_inst)
        end
      end
    end
  end
end
