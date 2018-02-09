class Decoder8 < Rhdl::LogicComponent

  input  :s, bits: 3
  output :d, bits: 8

  wire :not_s0, :not_s1, :not_s2

  logic do
    NotGate(a: s[0], out: not_s0)
    NotGate(a: s[1], out: not_s1)
    NotGate(a: s[2], out: not_s2)

    AndGate4(a: not_s0, b: not_s1, c: not_s2, d: 1, out: d[0])
    AndGate4(a: not_s0, b: not_s1, c: s[2],   d: 1, out: d[1])
    AndGate4(a: not_s0, b: s[1],   c: not_s2, d: 1, out: d[2])
    AndGate4(a: not_s0, b: s[1],   c: s[2],   d: 1, out: d[3])
    AndGate4(a: s[0],   b: not_s1, c: not_s2, d: 1, out: d[4])
    AndGate4(a: s[0],   b: not_s1, c: s[2],   d: 1, out: d[5])
    AndGate4(a: s[0],   b: s[1],   c: not_s2, d: 1, out: d[6])
    AndGate4(a: s[0],   b: s[1],   c: s[2],   d: 1, out: d[7])
  end

end
