# HDL Simulation Engine
# Provides the core simulation infrastructure for gate-level and behavior simulation

require 'active_support/concern'
require 'active_support/core_ext/string/inflections'

# Load simulation components in dependency order

# Base types (no dependencies)
require_relative 'simulation/signal_value'
require_relative 'simulation/behavior_block_def'

# Performance optimizations (no dependencies)
require_relative 'simulation/mask_cache'

# Wire hierarchy (Wire depends on SignalValue, Clock extends Wire)
require_relative 'simulation/wire'
require_relative 'simulation/clock'

# Synthesis expression hierarchy (loaded from synth module)
require_relative 'synth'

# Simulation proxy hierarchy (SimOutputProxy extends SimSignalProxy)
# Note: SimValueProxy, SimSignalProxy, and SimOutputProxy have cross-references
# in their resolve() methods, but these are runtime references not load-time
require_relative 'simulation/sim_value_proxy'
require_relative 'simulation/sim_signal_proxy'
require_relative 'simulation/sim_output_proxy'

# Proxy pooling (depends on SimValueProxy being defined)
require_relative 'simulation/proxy_pool'

# Behavior contexts (depend on proxy classes and pool)
require_relative 'simulation/behavior_sim_context'

# Dependency tracking for event-driven simulation
require_relative 'simulation/dependency_graph'

# Aggregate types (Bundle and Vec)
require_relative 'simulation/bundle'
require_relative 'simulation/vec'

# Main simulation classes
require_relative 'simulation/sim_component'
require_relative 'simulation/simulator'
