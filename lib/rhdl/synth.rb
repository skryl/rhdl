# Synthesis expression tree building
# Provides expression AST classes for converting behavior blocks to IR

# Load CIRCT IR first (synth expressions emit CIRCT nodes)
require_relative 'codegen/circt/ir'

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
