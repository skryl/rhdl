class OrGate4 < Rhdl::LogicComponent

  inputs :a, :b, :c, :d
  output :out

  wire :t, bits: 2

  logic do
    OrGate(a: a,    b: b,    out: t[0])
    OrGate(a: c,    b: d,    out: t[1])
    OrGate(a: t[0], b: t[1], out: out)
  end

end
