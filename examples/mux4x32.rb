class Mux4x32 < Rhdl::LogicComponent

  input  :s,   bits: 2
  input  :a,   bits: 32
  input  :b,   bits: 32
  input  :c,   bits: 32
  input  :d,   bits: 32
  output :out, bits: 32

  logic do
    32.times do |n|
      Mux4(s: s, d: [a[n], b[n], c[n], d[n]], out: out[n])
    end
  end

end
