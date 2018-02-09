class DLatch < Rhdl::LogicComponent

  inputs  :d, :clk
  outputs :q, :q_not

  wire :not_d, :s, :r

  logic do
    NotGate(a: d, out: not_d)

    AndGate(a: not_d, b: clk, out: r)
    AndGate(a: d,     b: clk, out: s)

    SRLatch(s: s, r: r, q: q, q_not: q_not)
  end

end
