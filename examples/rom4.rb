class Rom4 < Rhdl::LogicComponent

  inputs :c,  bits: 2

  outputs :d, bits: 4

  wire :t, bits: 4

  logic do
    Decoder4(s: c, d: t)
    OrGate4(a: t[0], b: t[1], c: t[2], d: t[3])
    OrGate4(a: t[0], b: t[1], c: t[2], d: t[3])
    OrGate4(a: t[0], b: t[1], c: t[2], d: t[3])
    OrGate4(a: t[0], b: t[1], c: t[2], d: t[3])
  end

  def burn!(idx, value)

  end
end
