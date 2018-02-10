class Add32 < Rhdl::LogicComponent

  input  :cin

  inputs :a, :b, bits: 32

  output :s, bits: 32

  output :over, :cout

  wire :c, bits: 32

  wire :null

  logic do
    FullAdder(a: a[31], b: b[31], cin: cin, s: s[31], cout: c[0])

    (1..30).each do |n|
      FullAdder(a: a[31-n], b: b[31-n], cin: c[n-1], s: s[31-n], cout: c[n])
    end

    FullAdder(a: a[0], b: b[0], cin: c[30], s: s[0], cout: cout)

    XorGate(a: c[30], b: cout, out: over)
  end

end
