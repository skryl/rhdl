class Mux8 < Rhdl::LogicComponent

  input  :s, bits: 3
  input  :d, bits: 8
  output :out

  wire :not_s0, :not_s1, :not_s2

  wire :t, bits: 10

  logic do
    NotGate(a: s[0], out: not_s0)
    NotGate(a: s[1], out: not_s1)
    NotGate(a: s[2], out: not_s2)

    AndGate4(a: not_s0, b: not_s1, c: not_s2, d: d[0], out: t[0])
    AndGate4(a: not_s0, b: not_s1, c: s[2],   d: d[1], out: t[1])
    AndGate4(a: not_s0, b: s[1],   c: not_s2, d: d[2], out: t[2])
    AndGate4(a: not_s0, b: s[1],   c: s[2],   d: d[3], out: t[3])
    AndGate4(a: s[0],   b: not_s1, c: not_s2, d: d[4], out: t[4])
    AndGate4(a: s[0],   b: not_s1, c: s[2],   d: d[5], out: t[5])
    AndGate4(a: s[0],   b: s[1],   c: not_s2, d: d[6], out: t[6])
    AndGate4(a: s[0],   b: s[1],   c: s[2],   d: d[7], out: t[7])

    OrGate4(a: t[0], b: t[1], c: t[2], d: t[3], out: t[8])
    OrGate4(a: t[4], b: t[5], c: t[6], d: t[7], out: t[9])
    OrGate(a: t[8], b: t[9], out: out)
  end

end
