class Or32 < Rhdl::LogicComponent

  input  :a,   bits: 32
  input  :b,   bits: 32
  output :out, bits: 32

  logic do
    32.times do |n|
      OrGate(a: a[n], b: b[n], out: out[n])
    end
  end
end
