class HalfAdder < Rhdl::LogicComponent
  inputs  :a, :b

  outputs :s, :c

  logic do
    XorGate(a: a, b: b, out: s)
    AndGate(a: a, b: b, out: c)
  end
end

# class HalfAdder
#   attr_reader :a, :b, :s, :c
#
#   def initialize(a: nil, b: nil, s: nil, c: nil)
#     @a = a || Wire.new
#     @b = b || Wire.new
#     @s = s || Wire.new
#     @c = c || Wire.new
#
#     init_logic
#   end
#
#   def init_logic
#     XorGate.new(in0: @a, in1: @b, out: @s)
#     AndGate.new(in0: @a, in1: @b, out: @c)
#   end
#
#   def set!(a,b)
#     @a.set!(a)
#     @b.set!(b)
#     self
#   end
#
#   def update!
#     [@a, @b].map(&:update!)
#   end
#
#   def inspect
#     "HalfAdder(#{@a.value}, #{@b.value}) => (#{@s.value}, #{@c.value})"
#   end
#
# end
