# HDL Simulation Engine
# Provides the core simulation infrastructure for gate-level and behavior simulation

require 'rhdl/support/concern'
require 'rhdl/support/inflections'

# Load simulation components in dependency order

# Base types (no dependencies)
require_relative 'sim/signal_value'

# Performance optimizations (no dependencies)
require_relative 'sim/mask_cache'

# Wire hierarchy (Wire depends on SignalValue, Clock extends Wire)
require_relative 'sim/wire'
require_relative 'sim/clock'

# Synthesis expression hierarchy (loaded from synth module)
require_relative 'synth'

# Simulation proxy hierarchy (OutputProxy extends SignalProxy)
# Note: ValueProxy, SignalProxy, and OutputProxy have cross-references
# in their resolve() methods, but these are runtime references not load-time
require_relative 'sim/value_proxy'
require_relative 'sim/signal_proxy'
require_relative 'sim/output_proxy'

# Proxy pooling (depends on ValueProxy being defined)
require_relative 'sim/proxy_pool'

# Behavior contexts (depend on proxy classes and pool)
require_relative 'sim/context'

# Dependency tracking for event-driven simulation
require_relative 'sim/dependency_graph'

# Aggregate types (Bundle and Vec)
require_relative 'sim/bundle'
require_relative 'sim/vec'

# Main simulation classes
require_relative 'sim/component'
require_relative 'sim/simulator'
require_relative 'sim/sequential_component'

module RHDL
  module Sim
    class << self
      # Canonical gate-level simulation entrypoint.
      # Lower components to netlist IR, then instantiate a native backend.
      def gate_level(components, backend: :interpreter, lanes: 64, name: 'design')
        require_relative 'codegen/netlist/lower'
        require_relative 'sim/native/netlist/simulator'

        ir = RHDL::Codegen::Netlist::Lower.from_components(components, name: name)
        RHDL::Sim::Native::Netlist::Simulator.new(
          ir,
          backend: normalize_gate_backend(backend),
          lanes: lanes
        )
      end

      private

      def normalize_gate_backend(backend)
        case backend.to_sym
        when :interpreter, :interpret then :interpreter
        when :jit then :jit
        when :compiler, :compile then :compiler
        else
          raise ArgumentError, "Unknown backend: #{backend}. Valid: :interpreter, :jit, :compiler"
        end
      end
    end
  end
end
