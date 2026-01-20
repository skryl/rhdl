# Synthesis expression tree building
# Provides expression AST classes for converting behavior blocks to IR

# Load codegen IR first (synth expressions depend on IR types)
require_relative 'codegen/behavior/ir'

# Load expression hierarchy in dependency order
require_relative 'synth/expr'
require_relative 'synth/literal'
require_relative 'synth/binary_op'
require_relative 'synth/unary_op'
require_relative 'synth/bit_select'
require_relative 'synth/slice'
require_relative 'synth/concat'
require_relative 'synth/replicate'
require_relative 'synth/mux'
require_relative 'synth/memory_read'
require_relative 'synth/signal_proxy'
require_relative 'synth/output_proxy'
require_relative 'synth/context'

# Backwards compatibility aliases for old class names
module RHDL
  module HDL
    # Alias old RHDL::HDL::Synth* names to new RHDL::Synth::* names
    SynthExpr = Synth::Expr
    SynthLiteral = Synth::Literal
    SynthBinaryOp = Synth::BinaryOp
    SynthUnaryOp = Synth::UnaryOp
    SynthBitSelect = Synth::BitSelect
    SynthSlice = Synth::Slice
    SynthConcat = Synth::Concat
    SynthReplicate = Synth::Replicate
    SynthMux = Synth::Mux
    SynthMemoryRead = Synth::MemoryRead
    SynthSignalProxy = Synth::SignalProxy
    SynthOutputProxy = Synth::OutputProxy
    BehaviorSynthContext = Synth::Context
    SynthLocal = Synth::Local
    SynthVecProxy = Synth::VecProxy
    SynthVecAccess = Synth::VecAccess
  end
end
