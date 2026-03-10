# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'

RSpec.describe 'IR compiler AO486 runner extension' do
  let(:ir) { RHDL::Codegen::CIRCT::IR }

  REQUIRED_PORTS = [
    ['clk', 'in', 1],
    ['rst_n', 'in', 1],
    ['a20_enable', 'in', 1],
    ['cache_disable', 'in', 1],
    ['interrupt_do', 'in', 1],
    ['interrupt_vector', 'in', 8],
    ['interrupt_done', 'out', 1],
    ['avm_address', 'out', 30],
    ['avm_writedata', 'out', 32],
    ['avm_byteenable', 'out', 4],
    ['avm_burstcount', 'out', 4],
    ['avm_write', 'out', 1],
    ['avm_read', 'out', 1],
    ['avm_waitrequest', 'in', 1],
    ['avm_readdatavalid', 'in', 1],
    ['avm_readdata', 'in', 32],
    ['dma_address', 'in', 24],
    ['dma_16bit', 'in', 1],
    ['dma_write', 'in', 1],
    ['dma_writedata', 'in', 16],
    ['dma_read', 'in', 1],
    ['dma_readdata', 'out', 16],
    ['dma_readdatavalid', 'out', 1],
    ['dma_waitrequest', 'out', 1],
    ['io_read_do', 'out', 1],
    ['io_read_address', 'out', 16],
    ['io_read_length', 'out', 3],
    ['io_read_data', 'in', 32],
    ['io_read_done', 'in', 1],
    ['io_write_do', 'out', 1],
    ['io_write_address', 'out', 16],
    ['io_write_length', 'out', 3],
    ['io_write_data', 'out', 32],
    ['io_write_done', 'in', 1]
  ].freeze

  def signature_json
    RHDL::Sim::Native::IR.sim_json(build_signature_package, backend: :compiler)
  end

  def read_harness_json
    RHDL::Sim::Native::IR.sim_json(build_read_harness_package, backend: :compiler)
  end

  def io_read_harness_json
    RHDL::Sim::Native::IR.sim_json(build_io_read_harness_package, backend: :compiler)
  end

  def irq_harness_json
    RHDL::Sim::Native::IR.sim_json(build_irq_harness_package, backend: :compiler)
  end

  def build_signature_package
    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'ao486',
          ports: required_ir_ports,
          nets: [],
          regs: [],
          assigns: signature_assigns,
          processes: [],
          instances: [],
          memories: [],
          write_ports: [],
          sync_read_ports: [],
          parameters: {}
        )
      ]
    )
  end

  def build_read_harness_package
    latched_word = ir::Signal.new(name: :latched_word, width: 32)
    avm_readdatavalid = ir::Signal.new(name: :avm_readdatavalid, width: 1)
    avm_readdata = ir::Signal.new(name: :avm_readdata, width: 32)

    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'ao486',
          ports: required_ir_ports + [ir::Port.new(name: :observed_word, direction: :out, width: 32)],
          nets: [],
          regs: [
            ir::Reg.new(name: :latched_word, width: 32, reset_value: 0)
          ],
          assigns: read_harness_assigns + [
            ir::Assign.new(target: :avm_address, expr: ir::Literal.new(value: 0xF0000 >> 2, width: 30)),
            ir::Assign.new(target: :avm_byteenable, expr: ir::Literal.new(value: 0xF, width: 4)),
            ir::Assign.new(target: :avm_burstcount, expr: ir::Literal.new(value: 1, width: 4)),
            ir::Assign.new(target: :avm_read, expr: ir::Literal.new(value: 1, width: 1)),
            ir::Assign.new(target: :observed_word, expr: latched_word)
          ],
          processes: [
            ir::Process.new(
              name: 'capture_read_word',
              clocked: true,
              clock: :clk,
              sensitivity_list: [],
              statements: [
                ir::SeqAssign.new(
                  target: :latched_word,
                  expr: ir::Mux.new(
                    condition: avm_readdatavalid,
                    when_true: avm_readdata,
                    when_false: latched_word,
                    width: 32
                  )
                )
              ]
            )
          ],
          instances: [],
          memories: [],
          write_ports: [],
          sync_read_ports: [],
          parameters: {}
        )
      ]
    )
  end

  def build_io_read_harness_package
    latched_word = ir::Signal.new(name: :latched_word, width: 32)
    latched_done = ir::Signal.new(name: :latched_done, width: 1)
    io_read_data = ir::Signal.new(name: :io_read_data, width: 32)
    io_read_done = ir::Signal.new(name: :io_read_done, width: 1)

    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'ao486',
          ports: required_ir_ports + [
            ir::Port.new(name: :observed_word, direction: :out, width: 32),
            ir::Port.new(name: :observed_done, direction: :out, width: 1)
          ],
          nets: [],
          regs: [
            ir::Reg.new(name: :latched_word, width: 32, reset_value: 0),
            ir::Reg.new(name: :latched_done, width: 1, reset_value: 0)
          ],
          assigns: io_read_harness_assigns + [
            ir::Assign.new(target: :observed_word, expr: latched_word),
            ir::Assign.new(target: :observed_done, expr: latched_done)
          ],
          processes: [
            ir::Process.new(
              name: 'capture_io_read',
              clocked: true,
              clock: :clk,
              sensitivity_list: [],
              statements: [
                ir::SeqAssign.new(
                  target: :latched_word,
                  expr: ir::Mux.new(
                    condition: io_read_done,
                    when_true: io_read_data,
                    when_false: latched_word,
                    width: 32
                  )
                ),
                ir::SeqAssign.new(
                  target: :latched_done,
                  expr: ir::Mux.new(
                    condition: io_read_done,
                    when_true: ir::Literal.new(value: 1, width: 1),
                    when_false: latched_done,
                    width: 1
                  )
                )
              ]
            )
          ],
          instances: [],
          memories: [],
          write_ports: [],
          sync_read_ports: [],
          parameters: {}
        )
      ]
    )
  end

  def build_irq_harness_package
    phase = ir::Signal.new(name: :phase, width: 5)
    latched_irq = ir::Signal.new(name: :latched_irq, width: 1)
    latched_vector = ir::Signal.new(name: :latched_vector, width: 8)
    interrupt_do = ir::Signal.new(name: :interrupt_do, width: 1)
    interrupt_vector = ir::Signal.new(name: :interrupt_vector, width: 8)

    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'ao486',
          ports: required_ir_ports + [
            ir::Port.new(name: :observed_interrupt, direction: :out, width: 1),
            ir::Port.new(name: :observed_vector, direction: :out, width: 8)
          ],
          nets: [],
          regs: [
            ir::Reg.new(name: :phase, width: 5, reset_value: 0),
            ir::Reg.new(name: :latched_irq, width: 1, reset_value: 0),
            ir::Reg.new(name: :latched_vector, width: 8, reset_value: 0)
          ],
          assigns: irq_harness_assigns(phase) + [
            ir::Assign.new(target: :interrupt_done, expr: interrupt_do),
            ir::Assign.new(target: :observed_interrupt, expr: latched_irq),
            ir::Assign.new(target: :observed_vector, expr: latched_vector)
          ],
          processes: [
            ir::Process.new(
              name: 'irq_harness_phase',
              clocked: true,
              clock: :clk,
              sensitivity_list: [],
              statements: [
                ir::SeqAssign.new(
                  target: :phase,
                  expr: ir::Mux.new(
                    condition: phase_eq(phase, 31, 5),
                    when_true: phase,
                    when_false: ir::BinaryOp.new(
                      op: :+,
                      left: phase,
                      right: ir::Literal.new(value: 1, width: 5),
                      width: 5
                    ),
                    width: 5
                  )
                ),
                ir::SeqAssign.new(
                  target: :latched_irq,
                  expr: ir::Mux.new(
                    condition: interrupt_do,
                    when_true: ir::Literal.new(value: 1, width: 1),
                    when_false: latched_irq,
                    width: 1
                  )
                ),
                ir::SeqAssign.new(
                  target: :latched_vector,
                  expr: ir::Mux.new(
                    condition: interrupt_do,
                    when_true: interrupt_vector,
                    when_false: latched_vector,
                    width: 8
                  )
                )
              ]
            )
          ],
          instances: [],
          memories: [],
          write_ports: [],
          sync_read_ports: [],
          parameters: {}
        )
      ]
    )
  end

  def required_ir_ports
    REQUIRED_PORTS.map do |name, direction, width|
      ir::Port.new(name: name.to_sym, direction: direction.to_sym, width: width)
    end
  end

  def phase_eq(signal, value, width)
    ir::BinaryOp.new(
      op: :'==',
      left: signal,
      right: ir::Literal.new(value: value, width: width),
      width: 1
    )
  end

  def mux_from_cases(signal, width:, cases:, default:)
    cases.reverse_each.reduce(default) do |fallback, (value, expr)|
      ir::Mux.new(
        condition: phase_eq(signal, value, signal.width),
        when_true: expr,
        when_false: fallback,
        width: width
      )
    end
  end

  def signature_assigns
    [
      [:interrupt_done, 0, 1],
      [:avm_address, 0, 30],
      [:avm_writedata, 0, 32],
      [:avm_byteenable, 0, 4],
      [:avm_burstcount, 0, 4],
      [:avm_write, 0, 1],
      [:avm_read, 0, 1],
      [:dma_readdata, 0, 16],
      [:dma_readdatavalid, 0, 1],
      [:dma_waitrequest, 0, 1],
      [:io_read_do, 0, 1],
      [:io_read_address, 0, 16],
      [:io_read_length, 0, 3],
      [:io_write_do, 0, 1],
      [:io_write_address, 0, 16],
      [:io_write_length, 0, 3],
      [:io_write_data, 0, 32]
    ].map do |target, value, width|
      ir::Assign.new(target: target, expr: ir::Literal.new(value: value, width: width))
    end
  end

  def read_harness_assigns
    [
      [:interrupt_done, 0, 1],
      [:avm_writedata, 0, 32],
      [:avm_write, 0, 1],
      [:dma_readdata, 0, 16],
      [:dma_readdatavalid, 0, 1],
      [:dma_waitrequest, 0, 1],
      [:io_read_do, 0, 1],
      [:io_read_address, 0, 16],
      [:io_read_length, 0, 3],
      [:io_write_do, 0, 1],
      [:io_write_address, 0, 16],
      [:io_write_length, 0, 3],
      [:io_write_data, 0, 32]
    ].map do |target, value, width|
      ir::Assign.new(target: target, expr: ir::Literal.new(value: value, width: width))
    end
  end

  def io_read_harness_assigns
    [
      [:interrupt_done, 0, 1],
      [:avm_address, 0, 30],
      [:avm_writedata, 0, 32],
      [:avm_byteenable, 0, 4],
      [:avm_burstcount, 0, 4],
      [:avm_write, 0, 1],
      [:avm_read, 0, 1],
      [:dma_readdata, 0, 16],
      [:dma_readdatavalid, 0, 1],
      [:dma_waitrequest, 0, 1],
      [:io_read_do, 1, 1],
      [:io_read_address, 0x61, 16],
      [:io_read_length, 1, 3],
      [:io_write_do, 0, 1],
      [:io_write_address, 0, 16],
      [:io_write_length, 0, 3],
      [:io_write_data, 0, 32]
    ].map do |target, value, width|
      ir::Assign.new(target: target, expr: ir::Literal.new(value: value, width: width))
    end
  end

  def irq_harness_assigns(phase)
    zero1 = ir::Literal.new(value: 0, width: 1)
    zero3 = ir::Literal.new(value: 0, width: 3)
    zero16 = ir::Literal.new(value: 0, width: 16)
    zero24 = ir::Literal.new(value: 0, width: 24)
    zero30 = ir::Literal.new(value: 0, width: 30)
    zero32 = ir::Literal.new(value: 0, width: 32)
    zero4 = ir::Literal.new(value: 0, width: 4)
    zero8 = ir::Literal.new(value: 0, width: 8)

    io_write_do = mux_from_cases(
      phase,
      width: 1,
      cases: {
        1 => ir::Literal.new(value: 1, width: 1),
        3 => ir::Literal.new(value: 1, width: 1),
        5 => ir::Literal.new(value: 1, width: 1),
        7 => ir::Literal.new(value: 1, width: 1)
      },
      default: zero1
    )
    io_write_address = mux_from_cases(
      phase,
      width: 16,
      cases: {
        1 => ir::Literal.new(value: 0x21, width: 16),
        3 => ir::Literal.new(value: 0x43, width: 16),
        5 => ir::Literal.new(value: 0x40, width: 16),
        7 => ir::Literal.new(value: 0x40, width: 16)
      },
      default: zero16
    )
    io_write_data = mux_from_cases(
      phase,
      width: 32,
      cases: {
        1 => ir::Literal.new(value: 0xFE, width: 32),
        3 => ir::Literal.new(value: 0x34, width: 32),
        5 => ir::Literal.new(value: 0x04, width: 32),
        7 => ir::Literal.new(value: 0x00, width: 32)
      },
      default: zero32
    )

    [
      ir::Assign.new(target: :avm_address, expr: zero30),
      ir::Assign.new(target: :avm_writedata, expr: zero32),
      ir::Assign.new(target: :avm_byteenable, expr: zero4),
      ir::Assign.new(target: :avm_burstcount, expr: zero4),
      ir::Assign.new(target: :avm_write, expr: zero1),
      ir::Assign.new(target: :avm_read, expr: zero1),
      ir::Assign.new(target: :dma_readdata, expr: ir::Literal.new(value: 0, width: 16)),
      ir::Assign.new(target: :dma_readdatavalid, expr: zero1),
      ir::Assign.new(target: :dma_waitrequest, expr: zero1),
      ir::Assign.new(target: :io_read_do, expr: zero1),
      ir::Assign.new(target: :io_read_address, expr: zero16),
      ir::Assign.new(target: :io_read_length, expr: zero3),
      ir::Assign.new(target: :io_write_do, expr: io_write_do),
      ir::Assign.new(target: :io_write_address, expr: io_write_address),
      ir::Assign.new(target: :io_write_length, expr: ir::Literal.new(value: 1, width: 3)),
      ir::Assign.new(target: :io_write_data, expr: io_write_data)
    ]
  end

  before do
    skip 'IR Compiler not available' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE
  end

  it 'detects imported ao486 CPU-top IR as a native :ao486 runner' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      signature_json,
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.compiled?).to be(true)
    expect(sim.runner_mode?).to be(true)
    expect(sim.runner_kind).to eq(:ao486)
  end

  it 'supports sparse main-memory and ROM roundtrips through the runner ABI' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      signature_json,
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    expect(sim.runner_load_rom([0xF0, 0x0F], 0xF0000)).to be(true)
    expect(sim.runner_load_memory([0x12, 0x34, 0x56], 0x1000, false)).to be(true)

    expect(sim.runner_read_rom(0xF0000, 2)).to eq([0xF0, 0x0F])
    expect(sim.runner_read_memory(0x1000, 3, mapped: false)).to eq([0x12, 0x34, 0x56])
    expect(sim.runner_read_memory(0xF0000, 2, mapped: true)).to eq([0xF0, 0x0F])
  end

  it 'supports floppy-image roundtrips through the disk runner ABI' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      signature_json,
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    expect(sim.runner_load_disk([0xF0, 0x0D, 0x12, 0x34], 0x20)).to be(true)
    expect(sim.runner_read_disk(0x20, 4)).to eq([0xF0, 0x0D, 0x12, 0x34])
  end

  it 'services Avalon ROM reads through runner_run_cycles' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      read_harness_json,
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)
    expect(sim.runner_load_rom([0x78, 0x56, 0x34, 0x12], 0xF0000)).to be(true)

    result = sim.runner_run_cycles(12)

    expect(result[:cycles_run]).to eq(12)
    expect(sim.peek('observed_word')).to eq(0x1234_5678)
  end

  it 'services queued IO reads through the runner ABI' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      io_read_harness_json,
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    result = sim.runner_run_cycles(3)

    expect(result[:cycles_run]).to eq(3)
    expect(sim.peek('observed_done')).to eq(1)
    expect(sim.peek('observed_word')).to eq(0x20)
  end

  it 'surfaces timer IRQs after PIT/PIC programming through the runner ABI' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      irq_harness_json,
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    result = sim.runner_run_cycles(24)

    expect(result[:cycles_run]).to eq(24)
    expect(sim.peek('observed_interrupt')).to eq(1)
    expect(sim.peek('observed_vector')).to eq(0x08)
  end
end
