# HDL Simulation Engine
# Provides the core simulation infrastructure for gate-level and behavior simulation

require 'active_support/concern'
require 'active_support/core_ext/string/inflections'

# Load simulation components in dependency order

# Base types (no dependencies)
require_relative 'sim/signal_value'
require_relative 'sim/behavior_block_def'

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
require_relative 'sim/behavior_context'

# Dependency tracking for event-driven simulation
require_relative 'sim/dependency_graph'

# Aggregate types (Bundle and Vec)
require_relative 'sim/bundle'
require_relative 'sim/vec'

# Main simulation classes
require_relative 'sim/component'
require_relative 'sim/simulator'
require_relative 'sim/sequential_component'

# Backwards compatibility aliases for old class names in RHDL::HDL
module RHDL
  module HDL
    # Alias old RHDL::HDL::Sim* names to new RHDL::Sim::* names
    SignalValue = Sim::SignalValue
    BehaviorBlockDef = Sim::BehaviorBlockDef
    MaskCache = Sim::MaskCache
    Wire = Sim::Wire
    Clock = Sim::Clock
    SimValueProxy = Sim::ValueProxy
    SimSignalProxy = Sim::SignalProxy
    SimOutputProxy = Sim::OutputProxy
    ValueProxy = Sim::ValueProxy
    SignalProxy = Sim::SignalProxy
    OutputProxy = Sim::OutputProxy
    ProxyPool = Sim::ProxyPool
    ProxyPoolAccessor = Sim::ProxyPoolAccessor
    BehaviorSimContext = Sim::BehaviorContext
    BehaviorContext = Sim::BehaviorContext
    SimLocalProxy = Sim::LocalProxy
    LocalProxy = Sim::LocalProxy
    SimVecProxy = Sim::VecProxy
    VecProxy = Sim::VecProxy
    SimBundleProxy = Sim::BundleProxy
    BundleProxy = Sim::BundleProxy
    DependencyGraph = Sim::DependencyGraph
    Bundle = Sim::Bundle
    FlippedBundle = Sim::FlippedBundle
    BundleInstance = Sim::BundleInstance
    Vec = Sim::Vec
    VecInstance = Sim::VecInstance
    SimComponent = Sim::Component
    Component = Sim::Component
    Simulator = Sim::Simulator
    SequentialComponent = Sim::SequentialComponent
  end
end
