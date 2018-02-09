class Mux2 < Rhdl::LogicComponent

  input  :a, :b
  input  :s
  output :out

  wire :not_s

  wire :t, bits: 2

  logic do
    NotGate(a: s, out: not_s)

    AndGate(a: not_s, b: a, out: t[0])
    AndGate(a: s,     b: b, out: t[1])

    OrGate(a: t[0], b: t[1], out: out)
  end

end
