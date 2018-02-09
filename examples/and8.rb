class And8 < Rhdl::LogicComponent

  input  :a,   bits: 8
  input  :b,   bits: 8
  output :out, bits: 8

  logic do
    AndGate(a: a[0], b: b[0], out: out[0])
    AndGate(a: a[1], b: b[1], out: out[1])
    AndGate(a: a[2], b: b[2], out: out[2])
    AndGate(a: a[3], b: b[3], out: out[3])
    AndGate(a: a[4], b: b[4], out: out[4])
    AndGate(a: a[5], b: b[5], out: out[5])
    AndGate(a: a[6], b: b[6], out: out[6])
    AndGate(a: a[7], b: b[7], out: out[7])
  end
end
