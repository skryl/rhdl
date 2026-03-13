# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'

RSpec.describe 'IR AO486 runner extension on JIT/interpreter' do
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

  def backend_available?(backend)
    case backend
    when :jit
      RHDL::Sim::Native::IR::JIT_AVAILABLE
    when :interpreter
      RHDL::Sim::Native::IR::INTERPRETER_AVAILABLE
    else
      false
    end
  end

  def signature_json(backend)
    RHDL::Sim::Native::IR.sim_json(build_signature_package, backend: backend)
  end

  def read_harness_json(backend)
    RHDL::Sim::Native::IR.sim_json(build_read_harness_package, backend: backend)
  end

  def io_read_harness_json(backend, address: 0x64)
    RHDL::Sim::Native::IR.sim_json(build_io_read_harness_package(address: address), backend: backend)
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

  def build_io_read_harness_package(address: 0x64)
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
          assigns: io_read_harness_assigns(address: address) + [
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

  def required_ir_ports
    REQUIRED_PORTS.map do |name, direction, width|
      ir::Port.new(name: name.to_sym, direction: direction.to_sym, width: width)
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

  def io_read_harness_assigns(address: 0x64)
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
      [:io_read_address, address, 16],
      [:io_read_length, 1, 3],
      [:io_write_do, 0, 1],
      [:io_write_address, 0, 16],
      [:io_write_length, 0, 3],
      [:io_write_data, 0, 32]
    ].map do |target, value, width|
      ir::Assign.new(target: target, expr: ir::Literal.new(value: value, width: width))
    end
  end

  shared_examples 'ao486 runner backend' do |backend|
    before do
      skip "#{backend} backend not available" unless backend_available?(backend)
    end

    it "detects imported ao486 CPU-top IR as a native :ao486 runner on #{backend}" do
      sim = RHDL::Sim::Native::IR::Simulator.new(
        signature_json(backend),
        backend: backend,
        skip_signal_widths: true,
        retain_ir_json: false
      )

      expect(sim.runner_mode?).to be(true)
      expect(sim.runner_kind).to eq(:ao486)
    end

    it "supports sparse main-memory and ROM roundtrips through the runner ABI on #{backend}" do
      sim = RHDL::Sim::Native::IR::Simulator.new(
        signature_json(backend),
        backend: backend,
        skip_signal_widths: true,
        retain_ir_json: false
      )

      expect(sim.runner_load_rom([0xF0, 0x0F], 0xF0000)).to be(true)
      expect(sim.runner_load_memory([0x12, 0x34, 0x56], 0x1000, false)).to be(true)

      expect(sim.runner_read_rom(0xF0000, 2)).to eq([0xF0, 0x0F])
      expect(sim.runner_read_memory(0x1000, 3, mapped: false)).to eq([0x12, 0x34, 0x56])
      expect(sim.runner_read_memory(0xF0000, 2, mapped: true)).to eq([0xF0, 0x0F])
    end

    it "supports floppy-image roundtrips through the disk runner ABI on #{backend}" do
      sim = RHDL::Sim::Native::IR::Simulator.new(
        signature_json(backend),
        backend: backend,
        skip_signal_widths: true,
        retain_ir_json: false
      )

      expect(sim.runner_load_disk([0xF0, 0x0D, 0x12, 0x34], 0x20)).to be(true)
      expect(sim.runner_read_disk(0x20, 4)).to eq([0xF0, 0x0D, 0x12, 0x34])
    end

    it "services Avalon ROM reads through runner_run_cycles on #{backend}" do
      sim = RHDL::Sim::Native::IR::Simulator.new(
        read_harness_json(backend),
        backend: backend,
        skip_signal_widths: true,
        retain_ir_json: false
      )

      expect(sim.runner_load_rom([0x78, 0x56, 0x34, 0x12], 0xF0000)).to be(true)

      result = sim.runner_run_cycles(12)

      expect(result[:cycles_run]).to eq(12)
      expect(sim.peek('observed_word')).to eq(0x1234_5678)
    end

    it "retains AO486 IO-read probe metadata after the bus handshake on #{backend}" do
      sim = RHDL::Sim::Native::IR::Simulator.new(
        io_read_harness_json(backend, address: 0x64),
        backend: backend,
        skip_signal_widths: true,
        retain_ir_json: false
      )

      result = sim.runner_run_cycles(3)

      expect(result[:cycles_run]).to eq(3)
      expect(sim.peek('observed_done')).to eq(1)
      expect(sim.peek('observed_word')).to eq(0x18)
      expect(sim.runner_ao486_last_io_read).to eq({ address: 0x64, length: 1 })
      expect(sim.runner_ao486_last_io_write).to be_nil
    end
  end

  include_examples 'ao486 runner backend', :jit
  include_examples 'ao486 runner backend', :interpreter
end
