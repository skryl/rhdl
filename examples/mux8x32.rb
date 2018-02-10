class Mux8x32 < Rhdl::LogicComponent

  input  :s,   bits: 3

  input  :a,   bits: 32
  input  :b,   bits: 32
  input  :c,   bits: 32
  input  :d,   bits: 32
  input  :e,   bits: 32
  input  :f,   bits: 32
  input  :g,   bits: 32
  input  :h,   bits: 32

  output :out, bits: 32

  logic do
    32.times do |n|
      Mux8(s: s, d: [a[n], b[n], c[n], d[n], e[n], f[n], g[n], h[n]], out: out[n])
    end
  end

end
