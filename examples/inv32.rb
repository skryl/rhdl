class Inv32 < Rhdl::LogicComponent

  input  :a,   bits: 32
  output :out, bits: 32

  logic do
    32.times do |n|
      NotGate(a: a[n], out: out[n])
    end
  end
end
