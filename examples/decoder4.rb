class Decoder4 < Rhdl::LogicComponent

  input  :s, bits: 2
  output :d, bits: 4

  wire :not_s0, :not_s1

  logic do
    NotGate(a: s[0], out: not_s0)
    NotGate(a: s[1], out: not_s1)

    AndGate(a: not_s0, b: not_s1, out: d[0])
    AndGate(a: not_s0, b: s[1],   out: d[1])
    AndGate(a: s[0],   b: not_s1, out: d[2])
    AndGate(a: s[0],   b: s[1],   out: d[3])
  end

end
