class Inv8 < Rhdl::LogicComponent

  input  :a,   bits: 8
  output :out, bits: 8

  logic do
    NotGate(a: a[0], out: out[0])
    NotGate(a: a[1], out: out[1])
    NotGate(a: a[2], out: out[2])
    NotGate(a: a[3], out: out[3])
    NotGate(a: a[4], out: out[4])
    NotGate(a: a[5], out: out[5])
    NotGate(a: a[6], out: out[6])
    NotGate(a: a[7], out: out[7])
  end
end
