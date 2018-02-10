class RFile32 < Rhdl::LogicComponent

  inputs  :data, bits: 32

  input   :clk, :enable

  input   :dest_addr, bits: 3

  input   :src_addr_a, :src_addr_b, bits: 3

  outputs :src_a, :src_b, bits: 32

  wire :r_sel, :r_en, bits: 32

  wire :r0_data, :r1_data, :r2_data, :r3_data,
       :r4_data, :r5_data, :r6_data, :r7_data, bits: 32


  logic do
    Decoder8(s: dest_addr, d: r_sel)

    AndGate(a: enable, b: r_sel[0], out: r_en[0])
    Register8(clk: clk, w: r_en[0], d: data, q: r0_data)

    AndGate(a: enable, b: r_sel[1], out: r_en[1])
    Register8(clk: clk, w: r_en[1], d: data, q: r1_data)

    AndGate(a: enable, b: r_sel[2], out: r_en[2])
    Register8(clk: clk, w: r_en[2], d: data, q: r2_data)

    AndGate(a: enable, b: r_sel[3], out: r_en[3])
    Register8(clk: clk, w: r_en[3], d: data, q: r3_data)

    AndGate(a: enable, b: r_sel[4], out: r_en[4])
    Register8(clk: clk, w: r_en[4], d: data, q: r4_data)

    AndGate(a: enable, b: r_sel[5], out: r_en[5])
    Register8(clk: clk, w: r_en[5], d: data, q: r5_data)

    AndGate(a: enable, b: r_sel[6], out: r_en[6])
    Register8(clk: clk, w: r_en[6], d: data, q: r6_data)

    AndGate(a: enable, b: r_sel[7], out: r_en[7])
    Register8(clk: clk, w: r_en[7], d: data, q: r7_data)

    Mux8x32(a: r0_data, b: r1_data, c: r2_data, d: r3_data,
            e: r4_data, f: r5_data, g: r6_data, h: r7_data, s: src_addr_a, out: src_a)
    Mux8x32(a: r0_data, b: r1_data, c: r2_data, d: r3_data,
            e: r4_data, f: r5_data, g: r6_data, h: r7_data, s: src_addr_b, out: src_b)
  end
end
