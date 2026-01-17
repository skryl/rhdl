# HDL Memory Components
# RAM, ROM, and memory interfaces
#
# Note: Memory components use manual propagate methods because they have
# internal state arrays. Synthesis would require memory inference or block RAM.

require_relative 'memory/ram'
require_relative 'memory/dual_port_ram'
require_relative 'memory/rom'
require_relative 'memory/register_file'
require_relative 'memory/stack'
require_relative 'memory/fifo'
