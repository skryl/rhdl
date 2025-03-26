require 'rhdl'

class FullAdder < RHDL::Component
  # Port declarations
  input :a
  input :b
  input :cin
  output :sum
  output :cout

  # Internal signals
  signal :ab_xor

  architecture do
    # Architecture implementation will go here
    # This will be enhanced with actual logic implementation
  end
end

# Usage example:
if __FILE__ == $0
  puts FullAdder.to_vhdl
end
