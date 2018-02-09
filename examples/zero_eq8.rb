class ZeroEq8 < Rhdl::LogicComponent

  input  :a, bits: 8
  output :out

  wire :temp, bits: 7

  logic do
    OrGate(a: a[0], b: a[1], out: temp[0])
    OrGate(a: a[2], b: a[3], out: temp[1])
    OrGate(a: a[4], b: a[5], out: temp[2])
    OrGate(a: a[6], b: a[7], out: temp[3])

    OrGate(a: temp[0], b: temp[1], out: temp[4])
    OrGate(a: temp[2], b: temp[3], out: temp[5])

    OrGate(a: temp[4], b: temp[5], out: temp[6])

    NotGate(a: temp[6], out: out)
  end
end
