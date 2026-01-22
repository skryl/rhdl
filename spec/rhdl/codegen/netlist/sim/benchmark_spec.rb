# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'
require 'benchmark'

RSpec.describe 'SimCPU vs SimCPUNative benchmark', if: RHDL::Codegen::Netlist::NATIVE_SIM_AVAILABLE do
  # Create a moderately complex circuit for benchmarking
  # This simulates a simple ALU-like structure
  def create_alu_ir(width: 8)
    ir = RHDL::Codegen::Netlist::IR.new(name: 'alu_bench')

    # Create nets for a, b, op, result
    # a and b are width-bit inputs
    # op is 2-bit operation selector
    # result is width-bit output

    net_idx = 0
    a_nets = width.times.map { ir.new_net }
    b_nets = width.times.map { ir.new_net }
    op_nets = 2.times.map { ir.new_net }

    # Intermediate results for each operation
    and_nets = width.times.map { ir.new_net }
    or_nets = width.times.map { ir.new_net }
    xor_nets = width.times.map { ir.new_net }
    not_nets = width.times.map { ir.new_net }

    # MUX intermediate stages
    mux1_nets = width.times.map { ir.new_net }
    mux2_nets = width.times.map { ir.new_net }
    result_nets = width.times.map { ir.new_net }

    ir.add_input('a', a_nets)
    ir.add_input('b', b_nets)
    ir.add_input('op', op_nets)
    ir.add_output('result', result_nets)

    schedule = []

    # AND gates
    width.times do |i|
      ir.add_gate(type: :and, inputs: [a_nets[i], b_nets[i]], output: and_nets[i])
      schedule << ir.gates.length - 1
    end

    # OR gates
    width.times do |i|
      ir.add_gate(type: :or, inputs: [a_nets[i], b_nets[i]], output: or_nets[i])
      schedule << ir.gates.length - 1
    end

    # XOR gates
    width.times do |i|
      ir.add_gate(type: :xor, inputs: [a_nets[i], b_nets[i]], output: xor_nets[i])
      schedule << ir.gates.length - 1
    end

    # NOT gates (for a)
    width.times do |i|
      ir.add_gate(type: :not, inputs: [a_nets[i]], output: not_nets[i])
      schedule << ir.gates.length - 1
    end

    # MUX tree: op[0] selects between (and, or) and (xor, not)
    # op[1] selects between those two results
    width.times do |i|
      # First level: mux between and/or
      ir.add_gate(type: :mux, inputs: [and_nets[i], or_nets[i], op_nets[0]], output: mux1_nets[i])
      schedule << ir.gates.length - 1

      # First level: mux between xor/not
      ir.add_gate(type: :mux, inputs: [xor_nets[i], not_nets[i], op_nets[0]], output: mux2_nets[i])
      schedule << ir.gates.length - 1

      # Second level: mux between the two first-level results
      ir.add_gate(type: :mux, inputs: [mux1_nets[i], mux2_nets[i], op_nets[1]], output: result_nets[i])
      schedule << ir.gates.length - 1
    end

    ir.set_schedule(schedule)
    ir
  end

  def create_register_chain_ir(width: 8, depth: 4)
    ir = RHDL::Codegen::Netlist::IR.new(name: 'reg_chain')

    d_nets = width.times.map { ir.new_net }
    ir.add_input('d', d_nets)

    prev_nets = d_nets
    (depth - 1).times do |stage|
      q_nets = width.times.map { ir.new_net }
      width.times do |i|
        ir.add_dff(d: prev_nets[i], q: q_nets[i])
      end
      prev_nets = q_nets
    end

    # Final output
    q_nets = width.times.map { ir.new_net }
    width.times do |i|
      ir.add_dff(d: prev_nets[i], q: q_nets[i])
    end
    ir.add_output('q', q_nets)

    ir.set_schedule([])
    ir
  end

  describe 'combinational logic benchmark' do
    let(:ir) { create_alu_ir(width: 16) }
    let(:ruby_sim) { RHDL::Codegen::Netlist::SimCPU.new(ir, lanes: 64) }
    let(:native_sim) { RHDL::Codegen::Netlist::SimCPUNative.new(ir.to_json, 64) }

    it 'benchmarks evaluate() performance' do
      iterations = 10_000

      # Warm up
      10.times do
        ruby_sim.poke('a', rand(0xFFFF))
        ruby_sim.poke('b', rand(0xFFFF))
        ruby_sim.poke('op', rand(4))
        ruby_sim.evaluate

        native_sim.poke('a', rand(0xFFFF))
        native_sim.poke('b', rand(0xFFFF))
        native_sim.poke('op', rand(4))
        native_sim.evaluate
      end

      ruby_time = Benchmark.measure do
        iterations.times do |i|
          ruby_sim.poke('a', i & 0xFFFF)
          ruby_sim.poke('b', (i * 7) & 0xFFFF)
          ruby_sim.poke('op', i & 3)
          ruby_sim.evaluate
        end
      end

      native_time = Benchmark.measure do
        iterations.times do |i|
          native_sim.poke('a', i & 0xFFFF)
          native_sim.poke('b', (i * 7) & 0xFFFF)
          native_sim.poke('op', i & 3)
          native_sim.evaluate
        end
      end

      puts "\n" + "=" * 60
      puts "Combinational Logic Benchmark (#{iterations} iterations)"
      puts "IR: #{ir.gates.length} gates, #{ir.net_count} nets"
      puts "=" * 60
      puts "Ruby SimCPU:        #{ruby_time.real.round(4)}s (#{(iterations / ruby_time.real).round(0)} iter/s)"
      puts "Rust SimCPUNative:  #{native_time.real.round(4)}s (#{(iterations / native_time.real).round(0)} iter/s)"
      puts "Speedup:            #{(ruby_time.real / native_time.real).round(2)}x"
      puts "=" * 60

      # Just verify they're both working
      expect(ruby_time.real).to be > 0
      expect(native_time.real).to be > 0
    end
  end

  describe 'sequential logic benchmark' do
    let(:ir) { create_register_chain_ir(width: 16, depth: 8) }
    let(:ruby_sim) { RHDL::Codegen::Netlist::SimCPU.new(ir, lanes: 64) }
    let(:native_sim) { RHDL::Codegen::Netlist::SimCPUNative.new(ir.to_json, 64) }

    it 'benchmarks tick() performance' do
      iterations = 10_000

      # Warm up
      10.times do
        ruby_sim.poke('d', rand(0xFFFF))
        ruby_sim.tick
        native_sim.poke('d', rand(0xFFFF))
        native_sim.tick
      end

      ruby_time = Benchmark.measure do
        iterations.times do |i|
          ruby_sim.poke('d', i & 0xFFFF)
          ruby_sim.tick
        end
      end

      native_time = Benchmark.measure do
        iterations.times do |i|
          native_sim.poke('d', i & 0xFFFF)
          native_sim.tick
        end
      end

      puts "\n" + "=" * 60
      puts "Sequential Logic Benchmark (#{iterations} iterations)"
      puts "IR: #{ir.dffs.length} DFFs, #{ir.net_count} nets"
      puts "=" * 60
      puts "Ruby SimCPU:        #{ruby_time.real.round(4)}s (#{(iterations / ruby_time.real).round(0)} iter/s)"
      puts "Rust SimCPUNative:  #{native_time.real.round(4)}s (#{(iterations / native_time.real).round(0)} iter/s)"
      puts "Speedup:            #{(ruby_time.real / native_time.real).round(2)}x"
      puts "=" * 60

      # Just verify they're both working
      expect(ruby_time.real).to be > 0
      expect(native_time.real).to be > 0
    end
  end

  describe 'HDL component benchmark' do
    it 'benchmarks with real HDL components' do
      # Create a more realistic circuit using actual HDL components
      components = [
        RHDL::HDL::AndGate.new('and1'),
        RHDL::HDL::OrGate.new('or1'),
        RHDL::HDL::XorGate.new('xor1'),
        RHDL::HDL::NotGate.new('not1'),
        RHDL::HDL::Mux2.new('mux1', width: 8),
        RHDL::HDL::Register.new('reg1', width: 8),
      ]

      ir = RHDL::Codegen::Netlist::Lower.from_components(components, name: 'hdl_bench')
      ruby_sim = RHDL::Codegen::Netlist::SimCPU.new(ir, lanes: 64)
      native_sim = RHDL::Codegen::Netlist::SimCPUNative.new(ir.to_json, 64)

      iterations = 10_000

      ruby_time = Benchmark.measure do
        iterations.times do
          ruby_sim.evaluate
          ruby_sim.tick
        end
      end

      native_time = Benchmark.measure do
        iterations.times do
          native_sim.evaluate
          native_sim.tick
        end
      end

      puts "\n" + "=" * 60
      puts "HDL Components Benchmark (#{iterations} iterations)"
      puts "IR: #{ir.gates.length} gates, #{ir.dffs.length} DFFs, #{ir.net_count} nets"
      puts "=" * 60
      puts "Ruby SimCPU:        #{ruby_time.real.round(4)}s (#{(iterations / ruby_time.real).round(0)} iter/s)"
      puts "Rust SimCPUNative:  #{native_time.real.round(4)}s (#{(iterations / native_time.real).round(0)} iter/s)"
      puts "Speedup:            #{(ruby_time.real / native_time.real).round(2)}x"
      puts "=" * 60

      expect(ruby_time.real).to be > 0
      expect(native_time.real).to be > 0
    end
  end
end
