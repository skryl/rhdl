class Alu8 < Rhdl::LogicComponent

  input :a, bits: 8
  input :b, bits: 8

  input :aneg, :bneg
  input :c, bits: 2

  output :out, bits: 8
  output :cout, :over, :zero

  wire :carry, :not_carry

  wire :ainv, :binv, bits: 8

  wire :aval, :bval, bits: 8

  wires :add_out, :and_out, :or_out, :null, bits: 8

  logic do
    Inv8(a: a, out: ainv)
    Inv8(a: b, out: binv)

    Mux2x8(a: a, b: ainv, s: aneg, out: aval)
    Mux2x8(a: b, b: binv, s: bneg, out: bval)

    Add8(a: aval, b: bval, s: add_out, cin: bneg, cout: carry, over: over)
    And8(a: aval, b: bval, out: and_out)
    Or8(a: aval, b: bval, out: or_out)

    Mux4x8(a: and_out, b: or_out, c: add_out, d: null, s: c, out: out)

    NotGate(a: carry, out: not_carry)
    Mux2(a: carry, b: not_carry, s: bneg, out: cout)

    ZeroEq8(a: out, out: zero)
  end

end
