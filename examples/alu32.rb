class Alu32 < Rhdl::LogicComponent

  input :a, bits: 32
  input :b, bits: 32

  input :aneg, :bneg
  input :c, bits: 2

  output :out, bits: 32
  output :cout, :over, :zero

  wire :carry, :not_carry

  wire :ainv, :binv, bits: 32

  wire :aval, :bval, bits: 32

  wires :add_out, :and_out, :or_out, :null, bits: 32

  logic do
    Inv32(a: a, out: ainv)
    Inv32(a: b, out: binv)

    Mux2x32(a: a, b: ainv, s: aneg, out: aval)
    Mux2x32(a: b, b: binv, s: bneg, out: bval)

    Add32(a: aval, b: bval, s: add_out, cin: bneg, cout: carry, over: over)
    And32(a: aval, b: bval, out: and_out)
    Or32(a: aval, b: bval, out: or_out)

    Mux4x32(a: and_out, b: or_out, c: add_out, d: null, s: c, out: out)

    NotGate(a: carry, out: not_carry)
    Mux2(a: carry, b: not_carry, s: bneg, out: cout)

    ZeroEq32(a: out, out: zero)
  end

end
