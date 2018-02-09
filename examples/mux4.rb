class Mux4 < Rhdl::LogicComponent

  input  :s, bits: 2
  input  :d, bits: 4
  output :out

  wire :not_s0, :not_s1

  wire :t, bits: 4

  logic do
    NotGate(a: s[0], out: not_s0)
    NotGate(a: s[1], out: not_s1)

    AndGate4(a: not_s0, b: not_s1, c: d[0], d: 1, out: t[0])
    AndGate4(a: not_s0, b: s[1],   c: d[1], d: 1, out: t[1])
    AndGate4(a: s[0],   b: not_s1, c: d[2], d: 1, out: t[2])
    AndGate4(a: s[0],   b: s[1],   c: d[3], d: 1, out: t[3])

    OrGate4(a: t[0], b: t[1], c: t[2], d: t[3], out: out)
  end

end
