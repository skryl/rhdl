require 'spec_helper'

RSpec.describe 'Gate-level backend equivalence' do
  let(:lanes) { 64 }
  let(:rng) { Random.new(1234) }

  def pack_scalar_mask(values)
    values.each_with_index.reduce(0) do |mask, (val, lane)|
      val == 1 ? (mask | (1 << lane)) : mask
    end
  end

  def unpack_scalar_mask(mask)
    lanes.times.map { |lane| (mask >> lane) & 1 }
  end

  def unpack_bus_masks(masks)
    lanes.times.map do |lane|
      masks.each_with_index.reduce(0) do |value, (mask, bit)|
        ((mask >> lane) & 1) == 1 ? (value | (1 << bit)) : value
      end
    end
  end

  it 'matches full adder outputs' do
    adder = RHDL::HDL::FullAdder.new('fa')
    sim = RHDL::Gates.gate_level([adder], backend: :cpu, lanes: lanes, name: 'full_adder')

    vectors = lanes.times.map do
      { a: rng.rand(2), b: rng.rand(2), cin: rng.rand(2) }
    end

    sim.poke('fa.a', pack_scalar_mask(vectors.map { |v| v[:a] }))
    sim.poke('fa.b', pack_scalar_mask(vectors.map { |v| v[:b] }))
    sim.poke('fa.cin', pack_scalar_mask(vectors.map { |v| v[:cin] }))
    sim.evaluate

    sum_mask = sim.peek('fa.sum')
    cout_mask = sim.peek('fa.cout')

    vectors.each_with_index do |vec, idx|
      ref = RHDL::HDL::FullAdder.new('ref')
      ref.inputs[:a].set(vec[:a])
      ref.inputs[:b].set(vec[:b])
      ref.inputs[:cin].set(vec[:cin])
      ref.propagate

      expect(unpack_scalar_mask(sum_mask)[idx]).to eq(ref.outputs[:sum].get)
      expect(unpack_scalar_mask(cout_mask)[idx]).to eq(ref.outputs[:cout].get)
    end
  end

  it 'matches ripple adder outputs' do
    adder = RHDL::HDL::RippleCarryAdder.new('ra', width: 8)
    sim = RHDL::Gates.gate_level([adder], backend: :cpu, lanes: lanes, name: 'ripple_adder')

    vectors = lanes.times.map do
      { a: rng.rand(256), b: rng.rand(256), cin: rng.rand(2) }
    end

    sim.poke('ra.a', vectors.map { |v| v[:a] })
    sim.poke('ra.b', vectors.map { |v| v[:b] })
    sim.poke('ra.cin', pack_scalar_mask(vectors.map { |v| v[:cin] }))
    sim.evaluate

    sum_masks = sim.peek('ra.sum')
    cout_mask = sim.peek('ra.cout')
    overflow_mask = sim.peek('ra.overflow')

    sum_values = unpack_bus_masks(sum_masks)
    cout_values = unpack_scalar_mask(cout_mask)
    overflow_values = unpack_scalar_mask(overflow_mask)

    vectors.each_with_index do |vec, idx|
      ref = RHDL::HDL::RippleCarryAdder.new('ref', width: 8)
      ref.inputs[:a].set(vec[:a])
      ref.inputs[:b].set(vec[:b])
      ref.inputs[:cin].set(vec[:cin])
      ref.propagate

      expect(sum_values[idx]).to eq(ref.outputs[:sum].get)
      expect(cout_values[idx]).to eq(ref.outputs[:cout].get)
      expect(overflow_values[idx]).to eq(ref.outputs[:overflow].get)
    end
  end

  it 'matches register outputs over cycles' do
    gate_dffs = 8.times.map { |i| RHDL::HDL::DFlipFlop.new("reg#{i}") }
    sim = RHDL::Gates.gate_level(gate_dffs, backend: :cpu, lanes: lanes, name: 'register')

    ref_sims = lanes.times.map do
      dffs = 8.times.map { |i| RHDL::HDL::DFlipFlop.new("reg#{i}") }
      clock = RHDL::HDL::Clock.new('clk')
      sim_ref = RHDL::HDL::Simulator.new
      dffs.each do |dff|
        RHDL::HDL::SimComponent.connect(clock, dff.inputs[:clk])
        sim_ref.add_component(dff)
      end
      sim_ref.add_clock(clock)
      { sim: sim_ref, dffs: dffs }
    end

    cycles = 8
    cycles.times do
      inputs = lanes.times.map { rng.rand(256) }
      rst_values = lanes.times.map { rng.rand(2) }
      en_values = lanes.times.map { rng.rand(2) }
      rst_mask = pack_scalar_mask(rst_values)
      en_mask = pack_scalar_mask(en_values)

      gate_dffs.each_with_index do |dff, idx|
        bit_values = inputs.map { |val| (val >> idx) & 1 }
        sim.poke("#{dff.name}.d", pack_scalar_mask(bit_values))
      end
      gate_dffs.each_index do |idx|
        sim.poke("reg#{idx}.rst", rst_mask)
        sim.poke("reg#{idx}.en", en_mask)
      end

      sim.tick

      ref_sims.each_with_index do |entry, lane|
        entry[:dffs].each_with_index do |dff, bit|
          dff.inputs[:d].set((inputs[lane] >> bit) & 1)
          dff.inputs[:rst].set(rst_values[lane])
          dff.inputs[:en].set(en_values[lane])
        end
        entry[:sim].run(1)
      end

      gate_outputs = gate_dffs.map { |dff| sim.peek("#{dff.name}.q") }
      lane_values = lanes.times.map do |lane|
        gate_outputs.each_with_index.reduce(0) do |value, (mask, bit)|
          ((mask >> lane) & 1) == 1 ? (value | (1 << bit)) : value
        end
      end

      ref_sims.each_with_index do |entry, lane|
        ref_value = entry[:dffs].each_with_index.reduce(0) do |value, (dff, bit)|
          dff.outputs[:q].get == 1 ? (value | (1 << bit)) : value
        end
        expect(lane_values[lane]).to eq(ref_value)
      end
    end
  end

  it 'matches muxed datapath outputs over cycles' do
    mux = RHDL::HDL::Mux2.new('mux', width: 1)
    adder = RHDL::HDL::FullAdder.new('adder')
    dff = RHDL::HDL::DFlipFlop.new('acc')

    RHDL::HDL::SimComponent.connect(dff.outputs[:q], adder.inputs[:a])
    RHDL::HDL::SimComponent.connect(adder.outputs[:sum], mux.inputs[:b])
    RHDL::HDL::SimComponent.connect(mux.outputs[:y], dff.inputs[:d])

    sim = RHDL::Gates.gate_level([mux, adder, dff], backend: :cpu, lanes: lanes, name: 'muxed_path')

    ref_sims = lanes.times.map do
      mux_ref = RHDL::HDL::Mux2.new('mux', width: 1)
      adder_ref = RHDL::HDL::FullAdder.new('adder')
      dff_ref = RHDL::HDL::DFlipFlop.new('acc')
      clock = RHDL::HDL::Clock.new('clk')
      sim_ref = RHDL::HDL::Simulator.new

      RHDL::HDL::SimComponent.connect(dff_ref.outputs[:q], adder_ref.inputs[:a])
      RHDL::HDL::SimComponent.connect(adder_ref.outputs[:sum], mux_ref.inputs[:b])
      RHDL::HDL::SimComponent.connect(mux_ref.outputs[:y], dff_ref.inputs[:d])
      RHDL::HDL::SimComponent.connect(clock, dff_ref.inputs[:clk])

      sim_ref.add_component(mux_ref)
      sim_ref.add_component(adder_ref)
      sim_ref.add_component(dff_ref)
      sim_ref.add_clock(clock)

      { sim: sim_ref, mux: mux_ref, adder: adder_ref, dff: dff_ref }
    end

    cycles = 8
    cycles.times do
      in_values = lanes.times.map { rng.rand(2) }
      sel_values = lanes.times.map { rng.rand(2) }

      sim.poke('mux.a', pack_scalar_mask(in_values))
      sim.poke('mux.sel', pack_scalar_mask(sel_values))
      sim.poke('adder.b', pack_scalar_mask(in_values))
      sim.poke('adder.cin', 0)
      sim.poke('acc.rst', 0)
      sim.poke('acc.en', -1)

      sim.tick

      ref_sims.each_with_index do |entry, lane|
        entry[:mux].inputs[:a].set(in_values[lane])
        entry[:mux].inputs[:sel].set(sel_values[lane])
        entry[:adder].inputs[:b].set(in_values[lane])
        entry[:adder].inputs[:cin].set(0)
        entry[:dff].inputs[:rst].set(0)
        entry[:dff].inputs[:en].set(1)
        entry[:sim].run(1)
      end

      acc_mask = sim.peek('acc.q')
      acc_values = unpack_scalar_mask(acc_mask)
      ref_sims.each_with_index do |entry, lane|
        expect(acc_values[lane]).to eq(entry[:dff].outputs[:q].get)
      end
    end
  end

  it 'has a GPU backend parity stub when enabled' do
    skip 'GPU backend not requested' unless ENV.fetch('RHDL_TEST_GPU', '0') == '1'
    skip 'GPU backend not available' unless RHDL::Gates::SimGPU.available?

    adder = RHDL::HDL::FullAdder.new('fa')
    gpu_sim = RHDL::Gates.gate_level([adder], backend: :gpu, lanes: lanes, name: 'gpu_parity')
    cpu_sim = RHDL::Gates.gate_level([adder], backend: :cpu, lanes: lanes, name: 'cpu_parity')

    values = lanes.times.map { rng.rand(2) }
    cpu_sim.poke('fa.a', pack_scalar_mask(values))
    cpu_sim.poke('fa.b', 0)
    cpu_sim.poke('fa.cin', 0)
    cpu_sim.evaluate

    gpu_sim.poke('fa.a', pack_scalar_mask(values))
    gpu_sim.poke('fa.b', 0)
    gpu_sim.poke('fa.cin', 0)
    gpu_sim.evaluate

    expect(gpu_sim.peek('fa.sum')).to eq(cpu_sim.peek('fa.sum'))
  end
end
