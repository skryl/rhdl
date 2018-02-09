class Add8 < Rhdl::LogicComponent

  input  :cin

  inputs :a, :b, bits: 8

  output :s, bits: 8

  output :cout, :over

  wire :c, bits: 7

  wire :null

  logic do
    FullAdder(a: a[7], b: b[7], cin: cin, s: s[7], cout: c[0])
    FullAdder(a: a[6], b: b[6], cin: c[0], s: s[6], cout: c[1])
    FullAdder(a: a[5], b: b[5], cin: c[1], s: s[5], cout: c[2])
    FullAdder(a: a[4], b: b[4], cin: c[2], s: s[4], cout: c[3])
    FullAdder(a: a[3], b: b[3], cin: c[3], s: s[3], cout: c[4])
    FullAdder(a: a[2], b: b[2], cin: c[4], s: s[2], cout: c[5])
    FullAdder(a: a[1], b: b[1], cin: c[5], s: s[1], cout: c[6])
    FullAdder(a: a[0], b: b[0], cin: c[6], s: s[0], cout: cout)

    XorGate(a: c[6], b: cout, out: over)
  end

end
