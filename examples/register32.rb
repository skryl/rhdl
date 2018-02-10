class Register32 < Rhdl::LogicComponent

  inputs :clk, :w
  input  :d, bits: 32

  output :q, bits: 32

  wire :write

  logic do
    AndGate(a: clk, b: w, out: write)

    32.times do |n|
      MSFlipFlop(clk: write, d: d[n], q: q[n])
    end
  end

end
