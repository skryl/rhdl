class MSFlipFlop < Rhdl::LogicComponent

  inputs :clk, :d
  output :q

  wire :not_clk, :d_tmp

  logic do
    NotGate(a: clk, out: not_clk)

    DLatch(clk: clk,     d: d,     q: d_tmp)
    DLatch(clk: not_clk, d: d_tmp, q: q)
  end

end
