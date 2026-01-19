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

# Synthesis expression hierarchy (all extend SynthExpr)
require_relative 'simulation/synth_expr'
require_relative 'simulation/synth_literal'
require_relative 'simulation/synth_binary_op'
require_relative 'simulation/synth_unary_op'
require_relative 'simulation/synth_bit_select'
require_relative 'simulation/synth_slice'
require_relative 'simulation/synth_concat'
require_relative 'simulation/synth_replicate'
require_relative 'simulation/synth_mux'
require_relative 'simulation/synth_memory_read'
require_relative 'simulation/synth_signal_proxy'
require_relative 'simulation/synth_output_proxy'

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
require_relative 'simulation/behavior_synth_context'

# Dependency tracking for event-driven simulation
require_relative 'simulation/dependency_graph'

# Aggregate types (Bundle and Vec)
require_relative 'simulation/bundle'
require_relative 'simulation/vec'

# Main simulation classes
require_relative 'simulation/sim_component'
require_relative 'simulation/simulator'
