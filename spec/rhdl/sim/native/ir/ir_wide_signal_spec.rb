# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'
require 'tmpdir'
require 'rbconfig'

RSpec.describe 'IR native wide signal support' do
  let(:ir) { RHDL::Codegen::CIRCT::IR }

  def build_wide_probe_package
    wide = ir::Signal.new(name: :wide_in, width: 128)
    hi = ir::Signal.new(name: :hi64, width: 64)
    lo = ir::Signal.new(name: :lo64, width: 64)

    top = ir::ModuleOp.new(
      name: 'wide_probe',
      ports: [
        ir::Port.new(name: :clk, direction: :in, width: 1),
        ir::Port.new(name: :rst, direction: :in, width: 1),
        ir::Port.new(name: :wide_in, direction: :in, width: 128),
        ir::Port.new(name: :hi64, direction: :in, width: 64),
        ir::Port.new(name: :lo64, direction: :in, width: 64),
        ir::Port.new(name: :concat_out, direction: :out, width: 128),
        ir::Port.new(name: :slice_hi, direction: :out, width: 64),
        ir::Port.new(name: :slice_lo, direction: :out, width: 64),
        ir::Port.new(name: :q, direction: :out, width: 128),
        ir::Port.new(name: :q_hi, direction: :out, width: 64),
        ir::Port.new(name: :q_lo, direction: :out, width: 64)
      ],
      nets: [],
      regs: [
        ir::Reg.new(name: :q_reg, width: 128, reset_value: 0)
      ],
      assigns: [
        ir::Assign.new(
          target: :concat_out,
          expr: ir::Concat.new(parts: [hi, lo], width: 128)
        ),
        ir::Assign.new(
          target: :slice_hi,
          expr: ir::Slice.new(base: wide, range: 127..64, width: 64)
        ),
        ir::Assign.new(
          target: :slice_lo,
          expr: ir::Slice.new(base: wide, range: 63..0, width: 64)
        ),
        ir::Assign.new(
          target: :q,
          expr: ir::Signal.new(name: :q_reg, width: 128)
        ),
        ir::Assign.new(
          target: :q_hi,
          expr: ir::Slice.new(
            base: ir::Signal.new(name: :q_reg, width: 128),
            range: 127..64,
            width: 64
          )
        ),
        ir::Assign.new(
          target: :q_lo,
          expr: ir::Slice.new(
            base: ir::Signal.new(name: :q_reg, width: 128),
            range: 63..0,
            width: 64
          )
        )
      ],
      processes: [
        ir::Process.new(
          name: 'capture',
          clocked: true,
          clock: 'clk',
          statements: [
            ir::SeqAssign.new(target: :q_reg, expr: wide)
          ]
        )
      ],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )

    ir::Package.new(modules: [top])
  end

  def run_probe(backend)
    json_payload = RHDL::Sim::Native::IR.sim_json(build_wide_probe_package, backend: backend)

    Dir.mktmpdir('ir_wide_signal_probe') do |dir|
      json_path = File.join(dir, 'wide_probe.json')
      script_path = File.join(dir, 'probe.rb')
      File.write(json_path, json_payload)
      File.write(script_path, <<~RUBY)
        require 'json'
        require 'rhdl'

        json_path = ARGV.fetch(0)
        backend = ARGV.fetch(1).to_sym

        sim = RHDL::Sim::Native::IR::Simulator.new(File.read(json_path), backend: backend)
        test_value = 0x1122_3344_5566_7788_99AA_BBCC_DDEE_FF00
        hi64 = 0x0123_4567_89AB_CDEF
        lo64 = 0xFEDC_BA98_7654_3210

        sim.reset
        sim.poke('rst', 0)
        sim.poke('wide_in', test_value)
        sim.poke('hi64', hi64)
        sim.poke('lo64', lo64)
        sim.evaluate

        comb = {
          slice_hi: sim.peek('slice_hi'),
          slice_lo: sim.peek('slice_lo'),
          concat_out: sim.peek('concat_out')
        }

        sim.poke('clk', 0)
        sim.evaluate
        sim.poke('clk', 1)
        sim.tick
        sim.poke('clk', 0)
        sim.evaluate

        seq = {
          q: sim.peek('q'),
          q_hi: sim.peek('q_hi'),
          q_lo: sim.peek('q_lo')
        }

        puts JSON.generate({ comb: comb, seq: seq })
      RUBY

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        '-Ilib',
        script_path,
        json_path,
        backend.to_s,
        chdir: File.expand_path('../../../../..', __dir__)
      )

      expect(status.success?).to be(true), stderr
      JSON.parse(stdout, symbolize_names: true)
    end
  end

  def expect_probe_to_round_trip_128_bits(backend)
    result = run_probe(backend)

    expect(result[:comb]).to eq(
      slice_hi: 0x1122_3344_5566_7788,
      slice_lo: 0x99AA_BBCC_DDEE_FF00,
      concat_out: 0x0123_4567_89AB_CDEF_FEDC_BA98_7654_3210
    )

    expect(result[:seq]).to eq(
      q: 0x1122_3344_5566_7788_99AA_BBCC_DDEE_FF00,
      q_hi: 0x1122_3344_5566_7788,
      q_lo: 0x99AA_BBCC_DDEE_FF00
    )
  end

  it 'round-trips 128-bit signals on the interpreter backend', timeout: 0 do
    skip 'IR interpreter backend unavailable' unless RHDL::Sim::Native::IR::INTERPRETER_AVAILABLE

    expect_probe_to_round_trip_128_bits(:interpreter)
  end

  it 'round-trips 128-bit signals on the JIT backend', timeout: 0 do
    skip 'IR JIT backend unavailable' unless RHDL::Sim::Native::IR::JIT_AVAILABLE

    expect_probe_to_round_trip_128_bits(:jit)
  end
end
