# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'

RSpec.describe 'IR compiler overwide runtime-only support' do
  let(:ir) { RHDL::Codegen::CIRCT::IR }

  def build_packet_probe_package
    flag = ir::Signal.new(name: :flag, width: 1)
    opcode = ir::Signal.new(name: :opcode, width: 4)
    tag = ir::Signal.new(name: :tag, width: 12)
    payload_hi = ir::Signal.new(name: :payload_hi, width: 64)
    payload_lo = ir::Signal.new(name: :payload_lo, width: 64)
    packet_reg = ir::Signal.new(name: :packet_reg, width: 145)

    packet_value = ir::Concat.new(
      parts: [flag, opcode, tag, payload_hi, payload_lo],
      width: 145
    )

    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'compiler_overwide_packet_probe',
          ports: [
            ir::Port.new(name: :clk, direction: :in, width: 1),
            ir::Port.new(name: :rst, direction: :in, width: 1),
            ir::Port.new(name: :load, direction: :in, width: 1),
            ir::Port.new(name: :flag, direction: :in, width: 1),
            ir::Port.new(name: :opcode, direction: :in, width: 4),
            ir::Port.new(name: :tag, direction: :in, width: 12),
            ir::Port.new(name: :payload_hi, direction: :in, width: 64),
            ir::Port.new(name: :payload_lo, direction: :in, width: 64),
            ir::Port.new(name: :packet_msb, direction: :out, width: 1),
            ir::Port.new(name: :packet_opcode, direction: :out, width: 4),
            ir::Port.new(name: :packet_tag, direction: :out, width: 12),
            ir::Port.new(name: :packet_hi, direction: :out, width: 64),
            ir::Port.new(name: :packet_lo, direction: :out, width: 64)
          ],
          nets: [],
          regs: [
            ir::Reg.new(name: :packet_reg, width: 145, reset_value: 0)
          ],
          assigns: [
            ir::Assign.new(
              target: :packet_msb,
              expr: ir::Slice.new(base: packet_reg, range: 144..144, width: 1)
            ),
            ir::Assign.new(
              target: :packet_opcode,
              expr: ir::Slice.new(base: packet_reg, range: 143..140, width: 4)
            ),
            ir::Assign.new(
              target: :packet_tag,
              expr: ir::Slice.new(base: packet_reg, range: 139..128, width: 12)
            ),
            ir::Assign.new(
              target: :packet_hi,
              expr: ir::Slice.new(base: packet_reg, range: 127..64, width: 64)
            ),
            ir::Assign.new(
              target: :packet_lo,
              expr: ir::Slice.new(base: packet_reg, range: 63..0, width: 64)
            )
          ],
          processes: [
            ir::Process.new(
              name: 'capture_packet',
              clocked: true,
              clock: 'clk',
              statements: [
                ir::SeqAssign.new(
                  target: :packet_reg,
                  expr: ir::Mux.new(
                    condition: ir::Signal.new(name: :load, width: 1),
                    when_true: packet_value,
                    when_false: packet_reg,
                    width: 145
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

  def build_packet256_probe_package
    word3 = ir::Signal.new(name: :word3, width: 64)
    word2 = ir::Signal.new(name: :word2, width: 64)
    word1 = ir::Signal.new(name: :word1, width: 64)
    word0 = ir::Signal.new(name: :word0, width: 64)
    packet_reg = ir::Signal.new(name: :packet256_reg, width: 256)

    packet_value = ir::Concat.new(
      parts: [word3, word2, word1, word0],
      width: 256
    )

    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'compiler_overwide_packet256_probe',
          ports: [
            ir::Port.new(name: :clk, direction: :in, width: 1),
            ir::Port.new(name: :rst, direction: :in, width: 1),
            ir::Port.new(name: :load, direction: :in, width: 1),
            ir::Port.new(name: :word3, direction: :in, width: 64),
            ir::Port.new(name: :word2, direction: :in, width: 64),
            ir::Port.new(name: :word1, direction: :in, width: 64),
            ir::Port.new(name: :word0, direction: :in, width: 64),
            ir::Port.new(name: :packet_word3, direction: :out, width: 64),
            ir::Port.new(name: :packet_word2, direction: :out, width: 64),
            ir::Port.new(name: :packet_word1, direction: :out, width: 64),
            ir::Port.new(name: :packet_word0, direction: :out, width: 64)
          ],
          nets: [],
          regs: [
            ir::Reg.new(name: :packet256_reg, width: 256, reset_value: 0)
          ],
          assigns: [
            ir::Assign.new(
              target: :packet_word3,
              expr: ir::Slice.new(base: packet_reg, range: 255..192, width: 64)
            ),
            ir::Assign.new(
              target: :packet_word2,
              expr: ir::Slice.new(base: packet_reg, range: 191..128, width: 64)
            ),
            ir::Assign.new(
              target: :packet_word1,
              expr: ir::Slice.new(base: packet_reg, range: 127..64, width: 64)
            ),
            ir::Assign.new(
              target: :packet_word0,
              expr: ir::Slice.new(base: packet_reg, range: 63..0, width: 64)
            )
          ],
          processes: [
            ir::Process.new(
              name: 'capture_packet256',
              clocked: true,
              clock: 'clk',
              statements: [
                ir::SeqAssign.new(
                  target: :packet256_reg,
                  expr: ir::Mux.new(
                    condition: ir::Signal.new(name: :load, width: 1),
                    when_true: packet_value,
                    when_false: packet_reg,
                    width: 256
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

  def build_mul_acc_probe_package
    a = ir::Signal.new(name: :a, width: 65)
    b = ir::Signal.new(name: :b, width: 65)
    load = ir::Signal.new(name: :load, width: 1)
    product = ir::BinaryOp.new(op: :*, left: a, right: b, width: 130)
    acc_value = ir::BinaryOp.new(
      op: :+,
      left: ir::Resize.new(expr: product, width: 139),
      right: ir::Literal.new(value: 3, width: 139),
      width: 139
    )
    acc_reg = ir::Signal.new(name: :acc_reg, width: 139)

    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'compiler_overwide_mul_acc_probe',
          ports: [
            ir::Port.new(name: :clk, direction: :in, width: 1),
            ir::Port.new(name: :rst, direction: :in, width: 1),
            ir::Port.new(name: :load, direction: :in, width: 1),
            ir::Port.new(name: :a, direction: :in, width: 65),
            ir::Port.new(name: :b, direction: :in, width: 65),
            ir::Port.new(name: :acc_hi, direction: :out, width: 11),
            ir::Port.new(name: :acc_mid, direction: :out, width: 64),
            ir::Port.new(name: :acc_lo, direction: :out, width: 64)
          ],
          nets: [],
          regs: [
            ir::Reg.new(name: :acc_reg, width: 139, reset_value: 0)
          ],
          assigns: [
            ir::Assign.new(
              target: :acc_hi,
              expr: ir::Slice.new(base: acc_reg, range: 138..128, width: 11)
            ),
            ir::Assign.new(
              target: :acc_mid,
              expr: ir::Slice.new(base: acc_reg, range: 127..64, width: 64)
            ),
            ir::Assign.new(
              target: :acc_lo,
              expr: ir::Slice.new(base: acc_reg, range: 63..0, width: 64)
            )
          ],
          processes: [
            ir::Process.new(
              name: 'capture_acc',
              clocked: true,
              clock: 'clk',
              statements: [
                ir::SeqAssign.new(
                  target: :acc_reg,
                  expr: ir::Mux.new(
                    condition: load,
                    when_true: acc_value,
                    when_false: acc_reg,
                    width: 139
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

  def build_negative_literal_probe_package
    value = -((1 << 140) - 0x1234)
    literal = ir::Literal.new(value: value, width: 145)

    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'compiler_overwide_negative_literal_probe',
          ports: [
            ir::Port.new(name: :literal_top, direction: :out, width: 17),
            ir::Port.new(name: :literal_low, direction: :out, width: 64)
          ],
          nets: [],
          regs: [],
          assigns: [
            ir::Assign.new(
              target: :literal_top,
              expr: ir::Slice.new(base: literal, range: 144..128, width: 17)
            ),
            ir::Assign.new(
              target: :literal_low,
              expr: ir::Slice.new(base: literal, range: 63..0, width: 64)
            )
          ],
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

  def build_overwide_memory_probe_package
    write_addr = ir::Signal.new(name: :write_addr, width: 2)
    read_addr = ir::Signal.new(name: :read_addr, width: 2)
    flag = ir::Signal.new(name: :flag, width: 2)
    payload_hi = ir::Signal.new(name: :payload_hi, width: 64)
    payload_lo = ir::Signal.new(name: :payload_lo, width: 64)
    packet = ir::Concat.new(parts: [flag, payload_hi, payload_lo], width: 130)
    mem_read = ir::MemoryRead.new(memory: 'packet_mem', addr: read_addr, width: 130)
    sync_packet = ir::Signal.new(name: :sync_packet, width: 130)

    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'compiler_overwide_memory_probe',
          ports: [
            ir::Port.new(name: :clk, direction: :in, width: 1),
            ir::Port.new(name: :rst, direction: :in, width: 1),
            ir::Port.new(name: :we, direction: :in, width: 1),
            ir::Port.new(name: :write_addr, direction: :in, width: 2),
            ir::Port.new(name: :read_addr, direction: :in, width: 2),
            ir::Port.new(name: :flag, direction: :in, width: 2),
            ir::Port.new(name: :payload_hi, direction: :in, width: 64),
            ir::Port.new(name: :payload_lo, direction: :in, width: 64),
            ir::Port.new(name: :sync_flag, direction: :out, width: 2),
            ir::Port.new(name: :sync_hi, direction: :out, width: 64),
            ir::Port.new(name: :sync_lo, direction: :out, width: 64),
            ir::Port.new(name: :comb_flag, direction: :out, width: 2),
            ir::Port.new(name: :comb_hi, direction: :out, width: 64),
            ir::Port.new(name: :comb_lo, direction: :out, width: 64)
          ],
          nets: [
            ir::Net.new(name: :sync_packet, width: 130)
          ],
          regs: [],
          assigns: [
            ir::Assign.new(
              target: :sync_flag,
              expr: ir::Slice.new(base: sync_packet, range: 129..128, width: 2)
            ),
            ir::Assign.new(
              target: :sync_hi,
              expr: ir::Slice.new(base: sync_packet, range: 127..64, width: 64)
            ),
            ir::Assign.new(
              target: :sync_lo,
              expr: ir::Slice.new(base: sync_packet, range: 63..0, width: 64)
            ),
            ir::Assign.new(
              target: :comb_flag,
              expr: ir::Slice.new(base: mem_read, range: 129..128, width: 2)
            ),
            ir::Assign.new(
              target: :comb_hi,
              expr: ir::Slice.new(base: mem_read, range: 127..64, width: 64)
            ),
            ir::Assign.new(
              target: :comb_lo,
              expr: ir::Slice.new(base: mem_read, range: 63..0, width: 64)
            )
          ],
          processes: [],
          instances: [],
          memories: [
            ir::Memory.new(name: :packet_mem, depth: 4, width: 130, initial_data: [])
          ],
          write_ports: [
            ir::MemoryWritePort.new(
              memory: :packet_mem,
              clock: :clk,
              addr: write_addr,
              data: packet,
              enable: ir::Signal.new(name: :we, width: 1)
            )
          ],
          sync_read_ports: [
            ir::MemorySyncReadPort.new(
              memory: :packet_mem,
              clock: :clk,
              addr: read_addr,
              data: :sync_packet
            )
          ],
          parameters: {}
        )
      ]
    )
  end

  def create_compiler(ir_package)
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runtime_json = RHDL::Sim::Native::IR.sim_json(ir_package, backend: :compiler)
    RHDL::Sim::Native::IR::Simulator.new(runtime_json, backend: :compiler)
  end

  def step(sim)
    sim.poke('clk', 0)
    sim.evaluate
    sim.poke('clk', 1)
    sim.tick
    sim.poke('clk', 0)
    sim.evaluate
  end

  it 'captures and slices a 145-bit packet register on the compiler backend' do
    sim = create_compiler(build_packet_probe_package)
    sim.reset

    sim.poke('rst', 0)
    sim.poke('load', 1)
    sim.poke('flag', 1)
    sim.poke('opcode', 0xA)
    sim.poke('tag', 0xBEE)
    sim.poke('payload_hi', 0x0123_4567_89AB_CDEF)
    sim.poke('payload_lo', 0xFEDC_BA98_7654_3210)

    step(sim)

    aggregate_failures do
      expect(sim.compiled?).to be(true)
      expect(sim.peek('packet_msb')).to eq(1)
      expect(sim.peek('packet_opcode')).to eq(0xA)
      expect(sim.peek('packet_tag')).to eq(0xBEE)
      expect(sim.peek('packet_hi')).to eq(0x0123_4567_89AB_CDEF)
      expect(sim.peek('packet_lo')).to eq(0xFEDC_BA98_7654_3210)
    end
  end

  it 'captures and slices a 256-bit packet register on the compiler backend' do
    sim = create_compiler(build_packet256_probe_package)
    sim.reset

    sim.poke('rst', 0)
    sim.poke('load', 1)
    sim.poke('word3', 0x0123_4567_89AB_CDEF)
    sim.poke('word2', 0x1111_2222_3333_4444)
    sim.poke('word1', 0x5555_6666_7777_8888)
    sim.poke('word0', 0x9999_AAAA_BBBB_CCCC)

    step(sim)

    aggregate_failures do
      expect(sim.compiled?).to be(true)
      expect(sim.peek('packet_word3')).to eq(0x0123_4567_89AB_CDEF)
      expect(sim.peek('packet_word2')).to eq(0x1111_2222_3333_4444)
      expect(sim.peek('packet_word1')).to eq(0x5555_6666_7777_8888)
      expect(sim.peek('packet_word0')).to eq(0x9999_AAAA_BBBB_CCCC)
    end
  end

  it 'evaluates overwide multiply-plus-resize expressions on the compiler backend' do
    sim = create_compiler(build_mul_acc_probe_package)
    sim.reset

    a = (1 << 64) + 3
    b = (1 << 64) + 5
    acc = (a * b) + 3

    sim.poke('rst', 0)
    sim.poke('load', 1)
    sim.poke('a', a)
    sim.poke('b', b)

    step(sim)

    aggregate_failures do
      expect(sim.compiled?).to be(true)
      expect(sim.peek('acc_hi')).to eq((acc >> 128) & 0x7FF)
      expect(sim.peek('acc_mid')).to eq((acc >> 64) & 0xFFFF_FFFF_FFFF_FFFF)
      expect(sim.peek('acc_lo')).to eq(acc & 0xFFFF_FFFF_FFFF_FFFF)
    end
  end

  it 'parses and evaluates overwide negative literals on the compiler backend' do
    sim = create_compiler(build_negative_literal_probe_package)
    sim.reset
    sim.evaluate

    value = -((1 << 140) - 0x1234)
    masked = value & ((1 << 145) - 1)

    aggregate_failures do
      expect(sim.compiled?).to be(true)
      expect(sim.peek('literal_top')).to eq((masked >> 128) & 0x1_FFFF)
      expect(sim.peek('literal_low')).to eq(masked & 0xFFFF_FFFF_FFFF_FFFF)
    end
  end

  it 'stores and reads back 130-bit memory values on the compiler backend' do
    sim = create_compiler(build_overwide_memory_probe_package)
    sim.reset

    flag = 0b10
    payload_hi = 0x0123_4567_89AB_CDEF
    payload_lo = 0xFEDC_BA98_7654_3210

    step(sim)

    sim.poke('rst', 0)
    sim.poke('we', 1)
    sim.poke('write_addr', 2)
    sim.poke('read_addr', 0)
    sim.poke('flag', flag)
    sim.poke('payload_hi', payload_hi)
    sim.poke('payload_lo', payload_lo)
    step(sim)

    sim.poke('we', 0)
    sim.poke('read_addr', 2)
    step(sim)

    aggregate_failures do
      expect(sim.compiled?).to be(true)
      expect(sim.peek('sync_flag')).to eq(flag)
      expect(sim.peek('sync_hi')).to eq(payload_hi)
      expect(sim.peek('sync_lo')).to eq(payload_lo)
      expect(sim.peek('comb_flag')).to eq(flag)
      expect(sim.peek('comb_hi')).to eq(payload_hi)
      expect(sim.peek('comb_lo')).to eq(payload_lo)
    end
  end

  it 'can force the full rustc compiler path for overwide plain-core runtime state' do
    previous = ENV['RHDL_IR_COMPILER_FORCE_RUSTC']
    ENV['RHDL_IR_COMPILER_FORCE_RUSTC'] = '1'

    sim = create_compiler(build_packet_probe_package)
    sim.reset

    sim.poke('rst', 0)
    sim.poke('load', 1)
    sim.poke('flag', 1)
    sim.poke('opcode', 0xA)
    sim.poke('tag', 0xBEE)
    sim.poke('payload_hi', 0x0123_4567_89AB_CDEF)
    sim.poke('payload_lo', 0xFEDC_BA98_7654_3210)

    step(sim)

    aggregate_failures do
      expect(sim.compiled?).to be(true)
      expect(sim.peek('packet_msb')).to eq(1)
      expect(sim.peek('packet_opcode')).to eq(0xA)
      expect(sim.peek('packet_tag')).to eq(0xBEE)
      expect(sim.peek('packet_hi')).to eq(0x0123_4567_89AB_CDEF)
      expect(sim.peek('packet_lo')).to eq(0xFEDC_BA98_7654_3210)
    end
  ensure
    if previous.nil?
      ENV.delete('RHDL_IR_COMPILER_FORCE_RUSTC')
    else
      ENV['RHDL_IR_COMPILER_FORCE_RUSTC'] = previous
    end
  end
end
