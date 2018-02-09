class Mux4x8 < Rhdl::LogicComponent

  input  :s,   bits: 2
  input  :a,   bits: 8
  input  :b,   bits: 8
  input  :c,   bits: 8
  input  :d,   bits: 8
  output :out, bits: 8

  logic do
    Mux4(s: s, d: [a[0], b[0], c[0], d[0]], out: out[0])
    Mux4(s: s, d: [a[1], b[1], c[1], d[1]], out: out[1])
    Mux4(s: s, d: [a[2], b[2], c[2], d[2]], out: out[2])
    Mux4(s: s, d: [a[3], b[3], c[3], d[3]], out: out[3])
    Mux4(s: s, d: [a[4], b[4], c[4], d[4]], out: out[4])
    Mux4(s: s, d: [a[5], b[5], c[5], d[5]], out: out[5])
    Mux4(s: s, d: [a[6], b[6], c[6], d[6]], out: out[6])
    Mux4(s: s, d: [a[7], b[7], c[7], d[7]], out: out[7])
  end

end
