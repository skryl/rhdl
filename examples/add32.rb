class Add32 < Rhdl::LogicComponent

  input  :cin

  inputs :a, :b, bits: 32

  output :s, bits: 32

  output :over

  wire :c, bits: 32

  wire :null

  logic do
    32.times do |n|
      FullAdder(a: a[31-n], b: b[31-n], cin: cin,  s: s[31-n], cout: c[n])
    end

    XorGate(a: c[30], b: c[31], out: over)
  end

end
