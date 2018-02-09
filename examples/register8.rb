class Register8 < Rhdl::LogicComponent

  inputs :clk, :w
  input  :d, bits: 8

  output :q, bits: 8

  wire :write

  logic do
    AndGate(a: clk, b: w, out: write)

    MSFlipFlop(clk: write, d: d[0], q: q[0])
    MSFlipFlop(clk: write, d: d[1], q: q[1])
    MSFlipFlop(clk: write, d: d[2], q: q[2])
    MSFlipFlop(clk: write, d: d[3], q: q[3])
    MSFlipFlop(clk: write, d: d[4], q: q[4])
    MSFlipFlop(clk: write, d: d[5], q: q[5])
    MSFlipFlop(clk: write, d: d[6], q: q[6])
    MSFlipFlop(clk: write, d: d[7], q: q[7])
  end

end
