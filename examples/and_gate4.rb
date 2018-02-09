class AndGate4 < Rhdl::LogicComponent

  inputs :a, :b, :c, :d
  output :out

  wire :t, bits: 2

  logic do
    AndGate(a: a,    b: b,    out: t[0])
    AndGate(a: c,    b: d,    out: t[1])
    AndGate(a: t[0], b: t[1], out: out)
  end

end
