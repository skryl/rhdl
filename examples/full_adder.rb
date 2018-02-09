class FullAdder < Rhdl::LogicComponent
  inputs :a, :b, :cin

  outputs :s, :cout

  wires :s1, :s2, :s3

  logic do
    XorGate(a: a, b: b, out: s1)
    HalfAdder(a: s1, b: cin, s: s, c: s2)
    AndGate(a: a, b: b, out: s3)
    OrGate(a: s2, b: s3, out: cout)
  end
end

# class FullAdder
#
#   attr_reader :a, :b, :cin, :s, :cout
#
#   def initialize(a: nil, b: nil, cin: nil)
#     @a   =   a || Wire.new
#     @b   =   b || Wire.new
#     @cin = cin || Wire.new
#
#     @s    = Wire.new
#     @cout = Wire.new
#
#     init_logic
#   end
#
#   def init_logic
#     w1 = Wire.new
#     w2 = Wire.new
#     w3 = Wire.new
#
#     XorGate.new(in0: @a, in1: @b, out: w1)
#     HalfAdder.new(a: w1, b: @cin, s: @s, c: w2)
#     AndGate.new(in0: @a, in1: @b, out: w3)
#     OrGate.new(in0: w2, in1: w3, out: @cout)
#   end
#
#   def set!(a,b,cin)
#     @a.set!(a)
#     @b.set!(b)
#     @cin.set!(cin)
#     self
#   end
#
#   def update!
#     [@a, @b, @cin].map(&:update!)
#   end
#
#   def inspect
#     "FullAdder(#{@a.value}, #{@b.value}, #{@cin.value}) => (#{@s.value}, #{@cout.value})"
#   end
# end
