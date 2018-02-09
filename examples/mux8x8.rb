class Mux8x8 < Rhdl::LogicComponent

  input  :s,   bits: 3

  input  :a,   bits: 8
  input  :b,   bits: 8
  input  :c,   bits: 8
  input  :d,   bits: 8
  input  :e,   bits: 8
  input  :f,   bits: 8
  input  :g,   bits: 8
  input  :h,   bits: 8

  output :out, bits: 8

  logic do
    Mux8(s: s, d: [a[0], b[0], c[0], d[0], e[0], f[0], g[0], h[0]], out: out[0])
    Mux8(s: s, d: [a[1], b[1], c[1], d[1], e[1], f[1], g[1], h[1]], out: out[1])
    Mux8(s: s, d: [a[2], b[2], c[2], d[2], e[2], f[2], g[2], h[2]], out: out[2])
    Mux8(s: s, d: [a[3], b[3], c[3], d[3], e[3], f[3], g[3], h[3]], out: out[3])
    Mux8(s: s, d: [a[4], b[4], c[4], d[4], e[4], f[4], g[4], h[4]], out: out[4])
    Mux8(s: s, d: [a[5], b[5], c[5], d[5], e[5], f[5], g[5], h[5]], out: out[5])
    Mux8(s: s, d: [a[6], b[6], c[6], d[6], e[6], f[6], g[6], h[6]], out: out[6])
    Mux8(s: s, d: [a[7], b[7], c[7], d[7], e[7], f[7], g[7], h[7]], out: out[7])
  end

end
