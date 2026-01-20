# HDL Sequential Logic Components
# Flip-flops, registers, and other clock-triggered elements
#
# Note: Sequential components use manual propagate methods because the current
# behavior DSL only supports combinational logic (assign statements). Sequential
# synthesis requires always @(posedge clk) blocks which are not yet implemented.

require_relative '../sim/sequential_component'
require_relative 'sequential/d_flip_flop'
require_relative 'sequential/d_flip_flop_async'
require_relative 'sequential/t_flip_flop'
require_relative 'sequential/jk_flip_flop'
require_relative 'sequential/sr_flip_flop'
require_relative 'sequential/sr_latch'
require_relative 'sequential/register'
require_relative 'sequential/register_load'
require_relative 'sequential/shift_register'
require_relative 'sequential/counter'
require_relative 'sequential/program_counter'
require_relative 'sequential/stack_pointer'
