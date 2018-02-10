class ZeroEq32 < Rhdl::LogicComponent

  input  :a, bits: 32
  output :out

  wire :temp1, bits: 16
  wire :temp2, bits: 8
  wire :temp3, bits: 4
  wire :temp4, bits: 2
  wire :temp5

  logic do
    16.times do |n|
      OrGate(a: a[2*n], b: a[2*n+1], out: temp1[n])
    end

    8.times do |n|
      OrGate(a: temp1[2*n], b: temp1[2*n+1], out: temp2[n])
    end

    4.times do |n|
      OrGate(a: temp2[2*n], b: temp2[2*n+1], out: temp3[n])
    end

    2.times do |n|
      OrGate(a: temp3[2*n], b: temp3[2*n+1], out: temp4[n])
    end

    OrGate(a: temp4[0], b: temp4[1], out: temp5)

    NotGate(a: temp5, out: out)
  end
end
