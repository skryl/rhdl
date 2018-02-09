class SRLatch < Rhdl::LogicComponent

  inputs  :s, :r
  outputs :q, :q_not

  logic do
    NorGate(a: r, b: q_not, out: q)
    NorGate(a: s, b: q,     out: q_not)
  end

end
