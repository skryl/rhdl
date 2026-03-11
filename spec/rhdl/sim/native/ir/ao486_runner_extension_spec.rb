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

  def mixed_read_harness_json
    RHDL::Sim::Native::IR.sim_json(build_mixed_read_harness_package, backend: :compiler)
  end

  def io_read_harness_json(address: 0x61)
    RHDL::Sim::Native::IR.sim_json(build_io_read_harness_package(address: address), backend: :compiler)
  end

  def io_read_once_harness_json(address: 0x61)
    RHDL::Sim::Native::IR.sim_json(build_io_read_once_harness_package(address: address), backend: :compiler)
  end

  def irq_harness_json
    RHDL::Sim::Native::IR.sim_json(build_irq_harness_package, backend: :compiler)
  end

  def fdc_dma_harness_json
    RHDL::Sim::Native::IR.sim_json(build_fdc_dma_harness_package, backend: :compiler)
  end

  def dos_int13_harness_json(ax: 0x0201, bx: 0x0000, cx: 0x0002, es: 0x0060, dx: 0x0000)
    RHDL::Sim::Native::IR.sim_json(
      build_dos_int13_harness_package(ax: ax, bx: bx, cx: cx, es: es, dx: dx),
      backend: :compiler
    )
  end

  def dos_int10_harness_json
    RHDL::Sim::Native::IR.sim_json(build_dos_int10_harness_package, backend: :compiler)
  end

  def dos_int10_string_harness_json
    RHDL::Sim::Native::IR.sim_json(build_dos_int10_string_harness_package, backend: :compiler)
  end

  def dos_int16_harness_json(ax: 0x0000)
    RHDL::Sim::Native::IR.sim_json(build_dos_int16_harness_package(ax: ax), backend: :compiler)
  end

  def dos_int1a_harness_json(ax: 0x0000, cx: 0x0000, dx: 0x0000)
    RHDL::Sim::Native::IR.sim_json(build_dos_int1a_harness_package(ax: ax, cx: cx, dx: dx), backend: :compiler)
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

  def build_mixed_read_harness_package
    latched_word = ir::Signal.new(name: :latched_word, width: 32)
    code_read_do = ir::Signal.new(name: :'memory_inst__icache_inst__readcode_do', width: 1)
    code_read_address = ir::Signal.new(name: :'memory_inst__icache_inst__readcode_address', width: 32)
    avm_readdatavalid = ir::Signal.new(name: :avm_readdatavalid, width: 1)
    avm_readdata = ir::Signal.new(name: :avm_readdata, width: 32)

    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'ao486',
          ports: required_ir_ports + [
            ir::Port.new(name: :'memory_inst__icache_inst__readcode_do', direction: :out, width: 1),
            ir::Port.new(name: :'memory_inst__icache_inst__readcode_address', direction: :out, width: 32),
            ir::Port.new(name: :observed_word, direction: :out, width: 32)
          ],
          nets: [],
          regs: [
            ir::Reg.new(name: :latched_word, width: 32, reset_value: 0)
          ],
          assigns: read_harness_assigns + [
            ir::Assign.new(target: :'memory_inst__icache_inst__readcode_do', expr: ir::Literal.new(value: 1, width: 1)),
            ir::Assign.new(
              target: :'memory_inst__icache_inst__readcode_address',
              expr: ir::Literal.new(value: 0x2000, width: 32)
            ),
            ir::Assign.new(target: :avm_address, expr: ir::Literal.new(value: 0x1000 >> 2, width: 30)),
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

  def build_io_read_harness_package(address: 0x61)
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

  def build_io_read_once_harness_package(address: 0x61)
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
              name: 'capture_first_io_read',
              clocked: true,
              clock: :clk,
              sensitivity_list: [],
              statements: [
                ir::SeqAssign.new(
                  target: :latched_word,
                  expr: ir::Mux.new(
                    condition: latched_done,
                    when_true: latched_word,
                    when_false: ir::Mux.new(
                      condition: io_read_done,
                      when_true: io_read_data,
                      when_false: latched_word,
                      width: 32
                    ),
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

  def build_fdc_dma_harness_package
    phase = ir::Signal.new(name: :phase, width: 6)

    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'ao486',
          ports: required_ir_ports,
          nets: [],
          regs: [
            ir::Reg.new(name: :phase, width: 6, reset_value: 0)
          ],
          assigns: fdc_dma_harness_assigns(phase),
          processes: [
            ir::Process.new(
              name: 'fdc_dma_harness_phase',
              clocked: true,
              clock: :clk,
              sensitivity_list: [],
              statements: [
                ir::SeqAssign.new(
                  target: :phase,
                  expr: ir::Mux.new(
                    condition: phase_eq(phase, 63, 6),
                    when_true: phase,
                    when_false: ir::BinaryOp.new(
                      op: :+,
                      left: phase,
                      right: ir::Literal.new(value: 1, width: 6),
                      width: 6
                    ),
                    width: 6
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

  def build_dos_int13_harness_package(ax: 0x0201, bx: 0x0000, cx: 0x0002, es: 0x0060, dx: 0x0000)
    phase = ir::Signal.new(name: :phase, width: 5)
    latched_word = ir::Signal.new(name: :latched_word, width: 32)
    latched_bx = ir::Signal.new(name: :latched_bx, width: 32)
    latched_cx = ir::Signal.new(name: :latched_cx, width: 32)
    latched_dx = ir::Signal.new(name: :latched_dx, width: 32)
    latched_flags = ir::Signal.new(name: :latched_flags, width: 32)
    latched_done = ir::Signal.new(name: :latched_done, width: 1)
    read_index = ir::Signal.new(name: :read_index, width: 3)
    io_read_data = ir::Signal.new(name: :io_read_data, width: 32)
    io_read_done = ir::Signal.new(name: :io_read_done, width: 1)

    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'ao486',
          ports: required_ir_ports + [
            ir::Port.new(name: :observed_word, direction: :out, width: 32),
            ir::Port.new(name: :observed_bx, direction: :out, width: 32),
            ir::Port.new(name: :observed_cx, direction: :out, width: 32),
            ir::Port.new(name: :observed_dx, direction: :out, width: 32),
            ir::Port.new(name: :observed_flags, direction: :out, width: 32),
            ir::Port.new(name: :observed_done, direction: :out, width: 1)
          ],
          nets: [],
          regs: [
            ir::Reg.new(name: :phase, width: 5, reset_value: 0),
            ir::Reg.new(name: :latched_word, width: 32, reset_value: 0),
            ir::Reg.new(name: :latched_bx, width: 32, reset_value: 0),
            ir::Reg.new(name: :latched_cx, width: 32, reset_value: 0),
            ir::Reg.new(name: :latched_dx, width: 32, reset_value: 0),
            ir::Reg.new(name: :latched_flags, width: 32, reset_value: 0),
            ir::Reg.new(name: :read_index, width: 3, reset_value: 0),
            ir::Reg.new(name: :latched_done, width: 1, reset_value: 0)
          ],
          assigns: dos_int13_harness_assigns(phase, ax: ax, bx: bx, cx: cx, es: es, dx: dx) + [
            ir::Assign.new(target: :observed_word, expr: latched_word),
            ir::Assign.new(target: :observed_bx, expr: latched_bx),
            ir::Assign.new(target: :observed_cx, expr: latched_cx),
            ir::Assign.new(target: :observed_dx, expr: latched_dx),
            ir::Assign.new(target: :observed_flags, expr: latched_flags),
            ir::Assign.new(target: :observed_done, expr: latched_done)
          ],
          processes: [
            ir::Process.new(
              name: 'dos_int13_harness_phase',
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
                  target: :read_index,
                  expr: ir::Mux.new(
                    condition: io_read_done,
                    when_true: ir::Mux.new(
                      condition: phase_eq(read_index, 4, 3),
                      when_true: read_index,
                      when_false: ir::BinaryOp.new(
                        op: :+,
                        left: read_index,
                        right: ir::Literal.new(value: 1, width: 3),
                        width: 3
                      ),
                      width: 3
                    ),
                    when_false: read_index,
                    width: 3
                  )
                ),
                ir::SeqAssign.new(
                  target: :latched_word,
                  expr: ir::Mux.new(
                    condition: ir::BinaryOp.new(
                      op: :&,
                      left: io_read_done,
                      right: phase_eq(read_index, 0, 3),
                      width: 1
                    ),
                    when_true: io_read_data,
                    when_false: latched_word,
                    width: 32
                  )
                ),
                ir::SeqAssign.new(
                  target: :latched_bx,
                  expr: ir::Mux.new(
                    condition: ir::BinaryOp.new(
                      op: :&,
                      left: io_read_done,
                      right: phase_eq(read_index, 1, 3),
                      width: 1
                    ),
                    when_true: io_read_data,
                    when_false: latched_bx,
                    width: 32
                  )
                ),
                ir::SeqAssign.new(
                  target: :latched_cx,
                  expr: ir::Mux.new(
                    condition: ir::BinaryOp.new(
                      op: :&,
                      left: io_read_done,
                      right: phase_eq(read_index, 2, 3),
                      width: 1
                    ),
                    when_true: io_read_data,
                    when_false: latched_cx,
                    width: 32
                  )
                ),
                ir::SeqAssign.new(
                  target: :latched_dx,
                  expr: ir::Mux.new(
                    condition: ir::BinaryOp.new(
                      op: :&,
                      left: io_read_done,
                      right: phase_eq(read_index, 3, 3),
                      width: 1
                    ),
                    when_true: io_read_data,
                    when_false: latched_dx,
                    width: 32
                  )
                ),
                ir::SeqAssign.new(
                  target: :latched_flags,
                  expr: ir::Mux.new(
                    condition: ir::BinaryOp.new(
                      op: :&,
                      left: io_read_done,
                      right: phase_eq(read_index, 4, 3),
                      width: 1
                    ),
                    when_true: io_read_data,
                    when_false: latched_flags,
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

  def build_dos_int10_harness_package
    phase = ir::Signal.new(name: :phase, width: 5)

    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'ao486',
          ports: required_ir_ports,
          nets: [],
          regs: [
            ir::Reg.new(name: :phase, width: 5, reset_value: 0)
          ],
          assigns: dos_int10_harness_assigns(phase),
          processes: [
            ir::Process.new(
              name: 'dos_int10_harness_phase',
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

  def build_dos_int10_string_harness_package
    phase = ir::Signal.new(name: :phase, width: 5)

    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'ao486',
          ports: required_ir_ports,
          nets: [],
          regs: [
            ir::Reg.new(name: :phase, width: 5, reset_value: 0)
          ],
          assigns: dos_int10_string_harness_assigns(phase),
          processes: [
            ir::Process.new(
              name: 'dos_int10_string_harness_phase',
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

  def build_dos_int16_harness_package(ax: 0x0000)
    phase = ir::Signal.new(name: :phase, width: 5)
    io_read_done = ir::Signal.new(name: :io_read_done, width: 1)
    io_read_data = ir::Signal.new(name: :io_read_data, width: 32)
    latched_word = ir::Signal.new(name: :latched_word, width: 32)
    latched_flags = ir::Signal.new(name: :latched_flags, width: 32)

    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'ao486',
          ports: required_ir_ports + [
            ir::Port.new(name: :observed_word, direction: :out, width: 32),
            ir::Port.new(name: :observed_flags, direction: :out, width: 32)
          ],
          nets: [],
          regs: [
            ir::Reg.new(name: :phase, width: 5, reset_value: 0),
            ir::Reg.new(name: :latched_word, width: 32, reset_value: 0),
            ir::Reg.new(name: :latched_flags, width: 32, reset_value: 0)
          ],
          assigns: dos_int16_harness_assigns(phase, ax: ax) + [
            ir::Assign.new(target: :observed_word, expr: latched_word),
            ir::Assign.new(target: :observed_flags, expr: latched_flags)
          ],
          processes: [
            ir::Process.new(
              name: 'dos_int16_harness_phase',
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
                  target: :latched_word,
                  expr: ir::Mux.new(
                    condition: ir::BinaryOp.new(
                      op: :&,
                      left: io_read_done,
                      right: phase_eq(phase, 6, 5),
                      width: 1
                    ),
                    when_true: io_read_data,
                    when_false: latched_word,
                    width: 32
                  )
                ),
                ir::SeqAssign.new(
                  target: :latched_flags,
                  expr: ir::Mux.new(
                    condition: ir::BinaryOp.new(
                      op: :&,
                      left: io_read_done,
                      right: phase_eq(phase, 8, 5),
                      width: 1
                    ),
                    when_true: io_read_data,
                    when_false: latched_flags,
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

  def build_dos_int1a_harness_package(ax: 0x0000, cx: 0x0000, dx: 0x0000)
    phase = ir::Signal.new(name: :phase, width: 5)
    io_read_done = ir::Signal.new(name: :io_read_done, width: 1)
    io_read_data = ir::Signal.new(name: :io_read_data, width: 32)
    latched_ax = ir::Signal.new(name: :latched_ax, width: 32)
    latched_cx = ir::Signal.new(name: :latched_cx, width: 32)
    latched_dx = ir::Signal.new(name: :latched_dx, width: 32)
    latched_flags = ir::Signal.new(name: :latched_flags, width: 32)

    ir::Package.new(
      modules: [
        ir::ModuleOp.new(
          name: 'ao486',
          ports: required_ir_ports + [
            ir::Port.new(name: :observed_ax, direction: :out, width: 32),
            ir::Port.new(name: :observed_cx, direction: :out, width: 32),
            ir::Port.new(name: :observed_dx, direction: :out, width: 32),
            ir::Port.new(name: :observed_flags, direction: :out, width: 32)
          ],
          nets: [],
          regs: [
            ir::Reg.new(name: :phase, width: 5, reset_value: 0),
            ir::Reg.new(name: :latched_ax, width: 32, reset_value: 0),
            ir::Reg.new(name: :latched_cx, width: 32, reset_value: 0),
            ir::Reg.new(name: :latched_dx, width: 32, reset_value: 0),
            ir::Reg.new(name: :latched_flags, width: 32, reset_value: 0)
          ],
          assigns: dos_int1a_harness_assigns(phase, ax: ax, cx: cx, dx: dx) + [
            ir::Assign.new(target: :observed_ax, expr: latched_ax),
            ir::Assign.new(target: :observed_cx, expr: latched_cx),
            ir::Assign.new(target: :observed_dx, expr: latched_dx),
            ir::Assign.new(target: :observed_flags, expr: latched_flags)
          ],
          processes: [
            ir::Process.new(
              name: 'dos_int1a_harness_phase',
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
                  target: :latched_ax,
                  expr: ir::Mux.new(
                    condition: ir::BinaryOp.new(
                      op: :&,
                      left: io_read_done,
                      right: phase_eq(phase, 10, 5),
                      width: 1
                    ),
                    when_true: io_read_data,
                    when_false: latched_ax,
                    width: 32
                  )
                ),
                ir::SeqAssign.new(
                  target: :latched_cx,
                  expr: ir::Mux.new(
                    condition: ir::BinaryOp.new(
                      op: :&,
                      left: io_read_done,
                      right: phase_eq(phase, 12, 5),
                      width: 1
                    ),
                    when_true: io_read_data,
                    when_false: latched_cx,
                    width: 32
                  )
                ),
                ir::SeqAssign.new(
                  target: :latched_dx,
                  expr: ir::Mux.new(
                    condition: ir::BinaryOp.new(
                      op: :&,
                      left: io_read_done,
                      right: phase_eq(phase, 14, 5),
                      width: 1
                    ),
                    when_true: io_read_data,
                    when_false: latched_dx,
                    width: 32
                  )
                ),
                ir::SeqAssign.new(
                  target: :latched_flags,
                  expr: ir::Mux.new(
                    condition: ir::BinaryOp.new(
                      op: :&,
                      left: io_read_done,
                      right: phase_eq(phase, 16, 5),
                      width: 1
                    ),
                    when_true: io_read_data,
                    when_false: latched_flags,
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

  def io_read_harness_assigns(address: 0x61)
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

  def dos_int10_harness_assigns(phase)
    zero1 = ir::Literal.new(value: 0, width: 1)
    zero3 = ir::Literal.new(value: 0, width: 3)
    zero16 = ir::Literal.new(value: 0, width: 16)
    zero24 = ir::Literal.new(value: 0, width: 24)
    zero30 = ir::Literal.new(value: 0, width: 30)
    zero32 = ir::Literal.new(value: 0, width: 32)
    zero4 = ir::Literal.new(value: 0, width: 4)

    io_write_do = mux_from_cases(
      phase,
      width: 1,
      cases: {
        1 => ir::Literal.new(value: 1, width: 1),
        3 => ir::Literal.new(value: 1, width: 1),
        5 => ir::Literal.new(value: 1, width: 1),
        7 => ir::Literal.new(value: 1, width: 1),
        9 => ir::Literal.new(value: 1, width: 1)
      },
      default: zero1
    )

    io_write_address = mux_from_cases(
      phase,
      width: 16,
      cases: {
        1 => ir::Literal.new(value: 0x0EE0, width: 16),
        3 => ir::Literal.new(value: 0x0EE8, width: 16),
        5 => ir::Literal.new(value: 0x0EE0, width: 16),
        7 => ir::Literal.new(value: 0x0EE6, width: 16),
        9 => ir::Literal.new(value: 0x0EE8, width: 16)
      },
      default: zero16
    )

    io_write_length = mux_from_cases(
      phase,
      width: 3,
      cases: {
        1 => ir::Literal.new(value: 2, width: 3),
        3 => ir::Literal.new(value: 1, width: 3),
        5 => ir::Literal.new(value: 2, width: 3),
        7 => ir::Literal.new(value: 2, width: 3),
        9 => ir::Literal.new(value: 1, width: 3)
      },
      default: zero3
    )

    io_write_data = mux_from_cases(
      phase,
      width: 32,
      cases: {
        1 => ir::Literal.new(value: 0x0003, width: 32),
        3 => ir::Literal.new(value: 0x0000, width: 32),
        5 => ir::Literal.new(value: 0x0E41, width: 32),
        7 => ir::Literal.new(value: 0x0000, width: 32),
        9 => ir::Literal.new(value: 0x0000, width: 32)
      },
      default: zero32
    )

    [
      ir::Assign.new(target: :interrupt_done, expr: zero1),
      ir::Assign.new(target: :avm_address, expr: zero30),
      ir::Assign.new(target: :avm_writedata, expr: zero32),
      ir::Assign.new(target: :avm_byteenable, expr: zero4),
      ir::Assign.new(target: :avm_burstcount, expr: zero4),
      ir::Assign.new(target: :avm_write, expr: zero1),
      ir::Assign.new(target: :avm_read, expr: zero1),
      ir::Assign.new(target: :dma_address, expr: zero24),
      ir::Assign.new(target: :dma_16bit, expr: zero1),
      ir::Assign.new(target: :dma_write, expr: zero1),
      ir::Assign.new(target: :dma_writedata, expr: zero16),
      ir::Assign.new(target: :dma_read, expr: zero1),
      ir::Assign.new(target: :dma_readdata, expr: zero16),
      ir::Assign.new(target: :dma_readdatavalid, expr: zero1),
      ir::Assign.new(target: :dma_waitrequest, expr: zero1),
      ir::Assign.new(target: :io_read_do, expr: zero1),
      ir::Assign.new(target: :io_read_address, expr: zero16),
      ir::Assign.new(target: :io_read_length, expr: zero3),
      ir::Assign.new(target: :io_write_do, expr: io_write_do),
      ir::Assign.new(target: :io_write_address, expr: io_write_address),
      ir::Assign.new(target: :io_write_length, expr: io_write_length),
      ir::Assign.new(target: :io_write_data, expr: io_write_data)
    ]
  end

  def dos_int10_string_harness_assigns(phase)
    zero1 = ir::Literal.new(value: 0, width: 1)
    zero3 = ir::Literal.new(value: 0, width: 3)
    zero16 = ir::Literal.new(value: 0, width: 16)
    zero24 = ir::Literal.new(value: 0, width: 24)
    zero30 = ir::Literal.new(value: 0, width: 30)
    zero32 = ir::Literal.new(value: 0, width: 32)
    zero4 = ir::Literal.new(value: 0, width: 4)

    io_write_do = mux_from_cases(
      phase,
      width: 1,
      cases: {
        1 => ir::Literal.new(value: 1, width: 1),
        3 => ir::Literal.new(value: 1, width: 1),
        5 => ir::Literal.new(value: 1, width: 1),
        7 => ir::Literal.new(value: 1, width: 1),
        9 => ir::Literal.new(value: 1, width: 1),
        11 => ir::Literal.new(value: 1, width: 1),
        13 => ir::Literal.new(value: 1, width: 1)
      },
      default: zero1
    )

    io_write_address = mux_from_cases(
      phase,
      width: 16,
      cases: {
        1 => ir::Literal.new(value: 0x0EE0, width: 16),
        3 => ir::Literal.new(value: 0x0EE2, width: 16),
        5 => ir::Literal.new(value: 0x0EE4, width: 16),
        7 => ir::Literal.new(value: 0x0EE6, width: 16),
        9 => ir::Literal.new(value: 0x0EF2, width: 16),
        11 => ir::Literal.new(value: 0x0EF4, width: 16),
        13 => ir::Literal.new(value: 0x0EE8, width: 16)
      },
      default: zero16
    )

    io_write_length = mux_from_cases(
      phase,
      width: 3,
      cases: {
        1 => ir::Literal.new(value: 2, width: 3),
        3 => ir::Literal.new(value: 2, width: 3),
        5 => ir::Literal.new(value: 2, width: 3),
        7 => ir::Literal.new(value: 2, width: 3),
        9 => ir::Literal.new(value: 2, width: 3),
        11 => ir::Literal.new(value: 2, width: 3),
        13 => ir::Literal.new(value: 1, width: 3)
      },
      default: zero3
    )

    io_write_data = mux_from_cases(
      phase,
      width: 32,
      cases: {
        1 => ir::Literal.new(value: 0x1301, width: 32),
        3 => ir::Literal.new(value: 0x0007, width: 32),
        5 => ir::Literal.new(value: 0x0003, width: 32),
        7 => ir::Literal.new(value: 0x0000, width: 32),
        9 => ir::Literal.new(value: 0x0600, width: 32),
        11 => ir::Literal.new(value: 0x0000, width: 32),
        13 => ir::Literal.new(value: 0x0000, width: 32)
      },
      default: zero32
    )

    [
      ir::Assign.new(target: :interrupt_done, expr: zero1),
      ir::Assign.new(target: :avm_address, expr: zero30),
      ir::Assign.new(target: :avm_writedata, expr: zero32),
      ir::Assign.new(target: :avm_byteenable, expr: zero4),
      ir::Assign.new(target: :avm_burstcount, expr: zero4),
      ir::Assign.new(target: :avm_write, expr: zero1),
      ir::Assign.new(target: :avm_read, expr: zero1),
      ir::Assign.new(target: :dma_address, expr: zero24),
      ir::Assign.new(target: :dma_16bit, expr: zero1),
      ir::Assign.new(target: :dma_write, expr: zero1),
      ir::Assign.new(target: :dma_writedata, expr: zero16),
      ir::Assign.new(target: :dma_read, expr: zero1),
      ir::Assign.new(target: :dma_readdata, expr: zero16),
      ir::Assign.new(target: :dma_readdatavalid, expr: zero1),
      ir::Assign.new(target: :dma_waitrequest, expr: zero1),
      ir::Assign.new(target: :io_read_do, expr: zero1),
      ir::Assign.new(target: :io_read_address, expr: zero16),
      ir::Assign.new(target: :io_read_length, expr: zero3),
      ir::Assign.new(target: :io_write_do, expr: io_write_do),
      ir::Assign.new(target: :io_write_address, expr: io_write_address),
      ir::Assign.new(target: :io_write_length, expr: io_write_length),
      ir::Assign.new(target: :io_write_data, expr: io_write_data)
    ]
  end

  def dos_int16_harness_assigns(phase, ax: 0x0000)
    zero1 = ir::Literal.new(value: 0, width: 1)
    zero3 = ir::Literal.new(value: 0, width: 3)
    zero16 = ir::Literal.new(value: 0, width: 16)
    zero24 = ir::Literal.new(value: 0, width: 24)
    zero30 = ir::Literal.new(value: 0, width: 30)
    zero32 = ir::Literal.new(value: 0, width: 32)
    zero4 = ir::Literal.new(value: 0, width: 4)

    io_write_do = mux_from_cases(
      phase,
      width: 1,
      cases: {
        1 => ir::Literal.new(value: 1, width: 1),
        3 => ir::Literal.new(value: 1, width: 1)
      },
      default: zero1
    )

    io_write_address = mux_from_cases(
      phase,
      width: 16,
      cases: {
        1 => ir::Literal.new(value: 0x0EF8, width: 16),
        3 => ir::Literal.new(value: 0x0EFA, width: 16)
      },
      default: zero16
    )

    io_write_length = mux_from_cases(
      phase,
      width: 3,
      cases: {
        1 => ir::Literal.new(value: 2, width: 3),
        3 => ir::Literal.new(value: 1, width: 3)
      },
      default: zero3
    )

    io_write_data = mux_from_cases(
      phase,
      width: 32,
      cases: {
        1 => ir::Literal.new(value: ax, width: 32),
        3 => ir::Literal.new(value: 0x0000, width: 32)
      },
      default: zero32
    )

    io_read_do = mux_from_cases(
      phase,
      width: 1,
      cases: {
        5 => ir::Literal.new(value: 1, width: 1),
        7 => ir::Literal.new(value: 1, width: 1)
      },
      default: zero1
    )

    io_read_address = mux_from_cases(
      phase,
      width: 16,
      cases: {
        5 => ir::Literal.new(value: 0x0EFC, width: 16),
        7 => ir::Literal.new(value: 0x0EFE, width: 16)
      },
      default: zero16
    )

    io_read_length = mux_from_cases(
      phase,
      width: 3,
      cases: {
        5 => ir::Literal.new(value: 2, width: 3),
        7 => ir::Literal.new(value: 1, width: 3)
      },
      default: zero3
    )

    [
      ir::Assign.new(target: :interrupt_done, expr: zero1),
      ir::Assign.new(target: :avm_address, expr: zero30),
      ir::Assign.new(target: :avm_writedata, expr: zero32),
      ir::Assign.new(target: :avm_byteenable, expr: zero4),
      ir::Assign.new(target: :avm_burstcount, expr: zero4),
      ir::Assign.new(target: :avm_write, expr: zero1),
      ir::Assign.new(target: :avm_read, expr: zero1),
      ir::Assign.new(target: :dma_address, expr: zero24),
      ir::Assign.new(target: :dma_16bit, expr: zero1),
      ir::Assign.new(target: :dma_write, expr: zero1),
      ir::Assign.new(target: :dma_writedata, expr: zero16),
      ir::Assign.new(target: :dma_read, expr: zero1),
      ir::Assign.new(target: :dma_readdata, expr: zero16),
      ir::Assign.new(target: :dma_readdatavalid, expr: zero1),
      ir::Assign.new(target: :dma_waitrequest, expr: zero1),
      ir::Assign.new(target: :io_read_do, expr: io_read_do),
      ir::Assign.new(target: :io_read_address, expr: io_read_address),
      ir::Assign.new(target: :io_read_length, expr: io_read_length),
      ir::Assign.new(target: :io_write_do, expr: io_write_do),
      ir::Assign.new(target: :io_write_address, expr: io_write_address),
      ir::Assign.new(target: :io_write_length, expr: io_write_length),
      ir::Assign.new(target: :io_write_data, expr: io_write_data)
    ]
  end

  def dos_int1a_harness_assigns(phase, ax: 0x0000, cx: 0x0000, dx: 0x0000)
    zero1 = ir::Literal.new(value: 0, width: 1)
    zero3 = ir::Literal.new(value: 0, width: 3)
    zero16 = ir::Literal.new(value: 0, width: 16)
    zero24 = ir::Literal.new(value: 0, width: 24)
    zero30 = ir::Literal.new(value: 0, width: 30)
    zero32 = ir::Literal.new(value: 0, width: 32)
    zero4 = ir::Literal.new(value: 0, width: 4)

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
        1 => ir::Literal.new(value: 0x0F00, width: 16),
        3 => ir::Literal.new(value: 0x0F02, width: 16),
        5 => ir::Literal.new(value: 0x0F04, width: 16),
        7 => ir::Literal.new(value: 0x0F06, width: 16)
      },
      default: zero16
    )

    io_write_length = mux_from_cases(
      phase,
      width: 3,
      cases: {
        1 => ir::Literal.new(value: 2, width: 3),
        3 => ir::Literal.new(value: 2, width: 3),
        5 => ir::Literal.new(value: 2, width: 3),
        7 => ir::Literal.new(value: 1, width: 3)
      },
      default: zero3
    )

    io_write_data = mux_from_cases(
      phase,
      width: 32,
      cases: {
        1 => ir::Literal.new(value: ax, width: 32),
        3 => ir::Literal.new(value: cx, width: 32),
        5 => ir::Literal.new(value: dx, width: 32),
        7 => ir::Literal.new(value: 0x0000, width: 32)
      },
      default: zero32
    )

    io_read_do = mux_from_cases(
      phase,
      width: 1,
      cases: {
        9 => ir::Literal.new(value: 1, width: 1),
        11 => ir::Literal.new(value: 1, width: 1),
        13 => ir::Literal.new(value: 1, width: 1),
        15 => ir::Literal.new(value: 1, width: 1)
      },
      default: zero1
    )

    io_read_address = mux_from_cases(
      phase,
      width: 16,
      cases: {
        9 => ir::Literal.new(value: 0x0F08, width: 16),
        11 => ir::Literal.new(value: 0x0F0A, width: 16),
        13 => ir::Literal.new(value: 0x0F0C, width: 16),
        15 => ir::Literal.new(value: 0x0F0E, width: 16)
      },
      default: zero16
    )

    io_read_length = mux_from_cases(
      phase,
      width: 3,
      cases: {
        9 => ir::Literal.new(value: 2, width: 3),
        11 => ir::Literal.new(value: 2, width: 3),
        13 => ir::Literal.new(value: 2, width: 3),
        15 => ir::Literal.new(value: 1, width: 3)
      },
      default: zero3
    )

    [
      ir::Assign.new(target: :interrupt_done, expr: zero1),
      ir::Assign.new(target: :avm_address, expr: zero30),
      ir::Assign.new(target: :avm_writedata, expr: zero32),
      ir::Assign.new(target: :avm_byteenable, expr: zero4),
      ir::Assign.new(target: :avm_burstcount, expr: zero4),
      ir::Assign.new(target: :avm_write, expr: zero1),
      ir::Assign.new(target: :avm_read, expr: zero1),
      ir::Assign.new(target: :dma_address, expr: zero24),
      ir::Assign.new(target: :dma_16bit, expr: zero1),
      ir::Assign.new(target: :dma_write, expr: zero1),
      ir::Assign.new(target: :dma_writedata, expr: zero16),
      ir::Assign.new(target: :dma_read, expr: zero1),
      ir::Assign.new(target: :dma_readdata, expr: zero16),
      ir::Assign.new(target: :dma_readdatavalid, expr: zero1),
      ir::Assign.new(target: :dma_waitrequest, expr: zero1),
      ir::Assign.new(target: :io_read_do, expr: io_read_do),
      ir::Assign.new(target: :io_read_address, expr: io_read_address),
      ir::Assign.new(target: :io_read_length, expr: io_read_length),
      ir::Assign.new(target: :io_write_do, expr: io_write_do),
      ir::Assign.new(target: :io_write_address, expr: io_write_address),
      ir::Assign.new(target: :io_write_length, expr: io_write_length),
      ir::Assign.new(target: :io_write_data, expr: io_write_data)
    ]
  end

  def fdc_dma_harness_assigns(phase)
    zero1 = ir::Literal.new(value: 0, width: 1)
    zero3 = ir::Literal.new(value: 0, width: 3)
    zero16 = ir::Literal.new(value: 0, width: 16)
    zero30 = ir::Literal.new(value: 0, width: 30)
    zero32 = ir::Literal.new(value: 0, width: 32)
    zero4 = ir::Literal.new(value: 0, width: 4)

    io_write_do = mux_from_cases(
      phase,
      width: 1,
      cases: {
        1 => ir::Literal.new(value: 1, width: 1),
        3 => ir::Literal.new(value: 1, width: 1),
        5 => ir::Literal.new(value: 1, width: 1),
        7 => ir::Literal.new(value: 1, width: 1),
        9 => ir::Literal.new(value: 1, width: 1),
        11 => ir::Literal.new(value: 1, width: 1),
        13 => ir::Literal.new(value: 1, width: 1),
        15 => ir::Literal.new(value: 1, width: 1),
        17 => ir::Literal.new(value: 1, width: 1),
        19 => ir::Literal.new(value: 1, width: 1),
        21 => ir::Literal.new(value: 1, width: 1),
        23 => ir::Literal.new(value: 1, width: 1),
        25 => ir::Literal.new(value: 1, width: 1),
        27 => ir::Literal.new(value: 1, width: 1),
        29 => ir::Literal.new(value: 1, width: 1),
        31 => ir::Literal.new(value: 1, width: 1),
        33 => ir::Literal.new(value: 1, width: 1),
        35 => ir::Literal.new(value: 1, width: 1),
        37 => ir::Literal.new(value: 1, width: 1)
      },
      default: zero1
    )
    io_write_address = mux_from_cases(
      phase,
      width: 16,
      cases: {
        1 => ir::Literal.new(value: 0x000C, width: 16),
        3 => ir::Literal.new(value: 0x0004, width: 16),
        5 => ir::Literal.new(value: 0x0004, width: 16),
        7 => ir::Literal.new(value: 0x000C, width: 16),
        9 => ir::Literal.new(value: 0x0005, width: 16),
        11 => ir::Literal.new(value: 0x0005, width: 16),
        13 => ir::Literal.new(value: 0x0081, width: 16),
        15 => ir::Literal.new(value: 0x000B, width: 16),
        17 => ir::Literal.new(value: 0x000A, width: 16),
        19 => ir::Literal.new(value: 0x03F2, width: 16),
        21 => ir::Literal.new(value: 0x03F5, width: 16),
        23 => ir::Literal.new(value: 0x03F5, width: 16),
        25 => ir::Literal.new(value: 0x03F5, width: 16),
        27 => ir::Literal.new(value: 0x03F5, width: 16),
        29 => ir::Literal.new(value: 0x03F5, width: 16),
        31 => ir::Literal.new(value: 0x03F5, width: 16),
        33 => ir::Literal.new(value: 0x03F5, width: 16),
        35 => ir::Literal.new(value: 0x03F5, width: 16),
        37 => ir::Literal.new(value: 0x03F5, width: 16)
      },
      default: zero16
    )
    io_write_data = mux_from_cases(
      phase,
      width: 32,
      cases: {
        1 => ir::Literal.new(value: 0x00, width: 32),
        3 => ir::Literal.new(value: 0x00, width: 32),
        5 => ir::Literal.new(value: 0x7C, width: 32),
        7 => ir::Literal.new(value: 0x00, width: 32),
        9 => ir::Literal.new(value: 0xFF, width: 32),
        11 => ir::Literal.new(value: 0x01, width: 32),
        13 => ir::Literal.new(value: 0x00, width: 32),
        15 => ir::Literal.new(value: 0x46, width: 32),
        17 => ir::Literal.new(value: 0x02, width: 32),
        19 => ir::Literal.new(value: 0x1C, width: 32),
        21 => ir::Literal.new(value: 0xE6, width: 32),
        23 => ir::Literal.new(value: 0x00, width: 32),
        25 => ir::Literal.new(value: 0x00, width: 32),
        27 => ir::Literal.new(value: 0x00, width: 32),
        29 => ir::Literal.new(value: 0x01, width: 32),
        31 => ir::Literal.new(value: 0x02, width: 32),
        33 => ir::Literal.new(value: 0x01, width: 32),
        35 => ir::Literal.new(value: 0x1B, width: 32),
        37 => ir::Literal.new(value: 0xFF, width: 32)
      },
      default: zero32
    )

    [
      ir::Assign.new(target: :interrupt_done, expr: zero1),
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

  def dos_int13_harness_assigns(phase, ax: 0x0201, bx: 0x0000, cx: 0x0002, es: 0x0060, dx: 0x0000)
    zero1 = ir::Literal.new(value: 0, width: 1)
    zero3 = ir::Literal.new(value: 0, width: 3)
    zero16 = ir::Literal.new(value: 0, width: 16)
    zero30 = ir::Literal.new(value: 0, width: 30)
    zero32 = ir::Literal.new(value: 0, width: 32)
    zero4 = ir::Literal.new(value: 0, width: 4)

    io_write_do = mux_from_cases(
      phase,
      width: 1,
      cases: {
        1 => ir::Literal.new(value: 1, width: 1),
        3 => ir::Literal.new(value: 1, width: 1),
        5 => ir::Literal.new(value: 1, width: 1),
        7 => ir::Literal.new(value: 1, width: 1),
        9 => ir::Literal.new(value: 1, width: 1),
        11 => ir::Literal.new(value: 1, width: 1)
      },
      default: zero1
    )
    io_write_address = mux_from_cases(
      phase,
      width: 16,
      cases: {
        1 => ir::Literal.new(value: 0x0ED0, width: 16),
        3 => ir::Literal.new(value: 0x0ED2, width: 16),
        5 => ir::Literal.new(value: 0x0ED4, width: 16),
        7 => ir::Literal.new(value: 0x0ED8, width: 16),
        9 => ir::Literal.new(value: 0x0ED6, width: 16),
        11 => ir::Literal.new(value: 0x0EDA, width: 16)
      },
      default: zero16
    )
    io_write_length = mux_from_cases(
      phase,
      width: 3,
      cases: {
        1 => ir::Literal.new(value: 2, width: 3),
        3 => ir::Literal.new(value: 2, width: 3),
        5 => ir::Literal.new(value: 2, width: 3),
        7 => ir::Literal.new(value: 2, width: 3),
        9 => ir::Literal.new(value: 2, width: 3),
        11 => ir::Literal.new(value: 1, width: 3)
      },
      default: zero3
    )
    io_write_data = mux_from_cases(
      phase,
      width: 32,
      cases: {
        1 => ir::Literal.new(value: ax, width: 32),
        3 => ir::Literal.new(value: bx, width: 32),
        5 => ir::Literal.new(value: cx, width: 32),
        7 => ir::Literal.new(value: es, width: 32),
        9 => ir::Literal.new(value: dx, width: 32),
        11 => ir::Literal.new(value: 0x0000, width: 32)
      },
      default: zero32
    )
    io_read_do = mux_from_cases(
      phase,
      width: 1,
      cases: {
        13 => ir::Literal.new(value: 1, width: 1),
        15 => ir::Literal.new(value: 1, width: 1),
        17 => ir::Literal.new(value: 1, width: 1),
        19 => ir::Literal.new(value: 1, width: 1),
        21 => ir::Literal.new(value: 1, width: 1)
      },
      default: zero1
    )
    io_read_address = mux_from_cases(
      phase,
      width: 16,
      cases: {
        13 => ir::Literal.new(value: 0x0EDC, width: 16),
        15 => ir::Literal.new(value: 0x0F10, width: 16),
        17 => ir::Literal.new(value: 0x0F12, width: 16),
        19 => ir::Literal.new(value: 0x0F14, width: 16),
        21 => ir::Literal.new(value: 0x0F16, width: 16)
      },
      default: zero16
    )
    io_read_length = mux_from_cases(
      phase,
      width: 3,
      cases: {
        13 => ir::Literal.new(value: 2, width: 3),
        15 => ir::Literal.new(value: 2, width: 3),
        17 => ir::Literal.new(value: 2, width: 3),
        19 => ir::Literal.new(value: 2, width: 3),
        21 => ir::Literal.new(value: 1, width: 3)
      },
      default: zero3
    )

    [
      ir::Assign.new(target: :interrupt_done, expr: zero1),
      ir::Assign.new(target: :avm_address, expr: zero30),
      ir::Assign.new(target: :avm_writedata, expr: zero32),
      ir::Assign.new(target: :avm_byteenable, expr: zero4),
      ir::Assign.new(target: :avm_burstcount, expr: zero4),
      ir::Assign.new(target: :avm_write, expr: zero1),
      ir::Assign.new(target: :avm_read, expr: zero1),
      ir::Assign.new(target: :dma_readdata, expr: ir::Literal.new(value: 0, width: 16)),
      ir::Assign.new(target: :dma_readdatavalid, expr: zero1),
      ir::Assign.new(target: :dma_waitrequest, expr: zero1),
      ir::Assign.new(target: :io_read_do, expr: io_read_do),
      ir::Assign.new(target: :io_read_address, expr: io_read_address),
      ir::Assign.new(target: :io_read_length, expr: io_read_length),
      ir::Assign.new(target: :io_write_do, expr: io_write_do),
      ir::Assign.new(target: :io_write_address, expr: io_write_address),
      ir::Assign.new(target: :io_write_length, expr: io_write_length),
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

  it 'classifies single-beat Avalon data reads from avm_burstcount, not a concurrent icache request' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      mixed_read_harness_json,
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)
    expect(sim.runner_load_memory([0x44, 0x33, 0x22, 0x11], 0x1000, false)).to be(true)
    expect(sim.runner_load_memory([0xDD, 0xCC, 0xBB, 0xAA], 0x2000, false)).to be(true)

    result = sim.runner_run_cycles(12)

    expect(result[:cycles_run]).to eq(12)
    expect(sim.peek('observed_word')).to eq(0x1122_3344)
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

  it 'reports the reference-reset PS/2 controller status through queued IO reads' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      io_read_harness_json(address: 0x64),
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    result = sim.runner_run_cycles(3)

    expect(result[:cycles_run]).to eq(3)
    expect(sim.peek('observed_done')).to eq(1)
    expect(sim.peek('observed_word')).to eq(0x18)
  end

  it 'retains the last AO486 IO-read metadata after the bus handshake completes' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      io_read_harness_json(address: 0x64),
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    result = sim.runner_run_cycles(3)

    expect(result[:cycles_run]).to eq(3)
    expect(sim.runner_ao486_last_io_read).to eq({ address: 0x64, length: 1 })
    expect(sim.runner_ao486_last_io_write).to be_nil
  end

  it 'reports a queued PS/2 output-buffer-ready status through IO port 0x64' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      io_read_harness_json(address: 0x64),
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    result = sim.runner_run_cycles(3, 'd'.ord, true)

    expect(result[:cycles_run]).to eq(3)
    expect(sim.peek('observed_word')).to eq(0x19)
    expect(sim.runner_ao486_last_io_read).to eq({ address: 0x64, length: 1 })
  end

  it 'returns a queued PS/2 scan code through IO port 0x60' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      io_read_once_harness_json(address: 0x60),
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    result = sim.runner_run_cycles(3, 'd'.ord, true)

    expect(result[:cycles_run]).to eq(3)
    expect(sim.peek('observed_done')).to eq(1)
    expect(sim.peek('observed_word')).to eq(0x20)
    expect(sim.runner_ao486_last_io_read).to eq({ address: 0x60, length: 1 })
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
    expect(sim.runner_ao486_last_irq_vector).to eq(0x08)
  end

  it 'copies a floppy boot sector into RAM through DMA channel 2 and the FDC command path' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      fdc_dma_harness_json,
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    boot_sector = Array.new(512) { |idx| (idx * 7) & 0xFF }
    expect(sim.runner_load_disk(boot_sector, 0)).to be(true)

    result = sim.runner_run_cycles(48)

    expect(result[:cycles_run]).to eq(48)
    expect(sim.runner_read_memory(0x7C00, 16, mapped: false)).to eq(boot_sector.first(16))
  end

  it 'copies DOS stage data into RAM through the private INT 13h runner bridge' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      dos_int13_harness_json,
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    boot_sector = Array.new(512, 0)
    stage_sector = Array.new(512) { |idx| (idx * 11) & 0xFF }
    expect(sim.runner_load_disk(boot_sector + stage_sector, 0)).to be(true)

    result = sim.runner_run_cycles(40)

    expect(result[:cycles_run]).to eq(40)
    expect(sim.peek('observed_done')).to eq(1)
    expect(sim.peek('observed_word')).to eq(0x0001)
    expect(sim.peek('observed_bx')).to eq(0x0000)
    expect(sim.peek('observed_cx')).to eq(0x0002)
    expect(sim.peek('observed_dx')).to eq(0x0000)
    expect(sim.peek('observed_flags')).to eq(0)
    expect(sim.runner_ao486_last_io_write).to eq({ address: 0x0EDA, length: 1, data: 0x0000_0000 })
    expect(sim.runner_ao486_dos_int13_state).to eq(
      { ax: 0x0201, bx: 0x0000, cx: 0x0002, dx: 0x0000, es: 0x0060, result_ax: 0x0001, flags: 0 }
    )
    expect(sim.runner_read_memory(0x0600, 16, mapped: false)).to eq(stage_sector.first(16))
  end

  it 'records BIOS-compatible diskette controller result bytes for private INT 13h reads' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      dos_int13_harness_json(ax: 0x0202, bx: 0x0100, cx: 0x0205, es: 0x0080, dx: 0x0100),
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    lba = ((2 * 2 + 1) * 18) + (0x05 - 1)
    disk_image = Array.new((lba + 2) * 512, 0)
    first_sector = Array.new(512) { |idx| (0x20 + idx) & 0xFF }
    second_sector = Array.new(512) { |idx| (0x60 + idx) & 0xFF }
    disk_image[lba * 512, 512] = first_sector
    disk_image[(lba + 1) * 512, 512] = second_sector
    expect(sim.runner_load_disk(disk_image, 0)).to be(true)

    result = sim.runner_run_cycles(40)

    expect(result[:cycles_run]).to eq(40)
    expect(sim.peek('observed_done')).to eq(1)
    expect(sim.peek('observed_word')).to eq(0x0002)
    expect(sim.peek('observed_flags')).to eq(0)
    expect(sim.runner_read_memory(0x0441, 8, mapped: false)).to eq([0x00, 0x21, 0x00, 0x00, 0x02, 0x01, 0x06, 0x02])
    expect(sim.runner_read_memory(0x0494, 1, mapped: false)).to eq([0x02])
    expect(sim.runner_read_memory(0x0900, 16, mapped: false)).to eq(first_sector.first(16))
    expect(sim.runner_read_memory(0x0B00, 16, mapped: false)).to eq(second_sector.first(16))
  end

  it 'ignores CL high cylinder bits on floppy DOS bridge reads used by the FreeDOS loader trace' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      dos_int13_harness_json(ax: 0x0201, bx: 0x0000, cx: 0x1AC5, es: 0x0080, dx: 0x0100),
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    lba = ((0x1A * 2 + 1) * 18) + (0x05 - 1)
    disk_image = Array.new((lba + 1) * 512, 0)
    stage_sector = Array.new(512) { |idx| (0xA0 + idx) & 0xFF }
    disk_image[lba * 512, 512] = stage_sector
    expect(sim.runner_load_disk(disk_image, 0)).to be(true)

    result = sim.runner_run_cycles(40)

    expect(result[:cycles_run]).to eq(40)
    expect(sim.peek('observed_done')).to eq(1)
    expect(sim.peek('observed_word')).to eq(0x0001)
    expect(sim.peek('observed_flags')).to eq(0)
    expect(sim.runner_read_memory(0x0800, 16, mapped: false)).to eq(stage_sector.first(16))
  end

  it 'aliases DOS bridge drive 1 reads onto the single mounted floppy image' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      dos_int13_harness_json(ax: 0x0201, bx: 0x0000, cx: 0x0101, es: 0x0080, dx: 0x0001),
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    lba = ((1 * 2) * 18)
    disk_image = Array.new((lba + 1) * 512, 0)
    stage_sector = Array.new(512) { |idx| (0x50 + idx) & 0xFF }
    disk_image[lba * 512, 512] = stage_sector
    expect(sim.runner_load_disk(disk_image, 0)).to be(true)

    result = sim.runner_run_cycles(40)

    expect(result[:cycles_run]).to eq(40)
    expect(sim.peek('observed_done')).to eq(1)
    expect(sim.peek('observed_word')).to eq(0x0001)
    expect(sim.peek('observed_flags')).to eq(0)
    expect(sim.runner_read_memory(0x0800, 16, mapped: false)).to eq(stage_sector.first(16))
  end

  it 'aliases DOS bridge drive-count rebound reads onto the mounted floppy image' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      dos_int13_harness_json(ax: 0x0201, bx: 0x0000, cx: 0x0101, es: 0x0080, dx: 0x0002),
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    lba = ((1 * 2) * 18)
    disk_image = Array.new((lba + 1) * 512, 0)
    stage_sector = Array.new(512) { |idx| (0x30 + idx) & 0xFF }
    disk_image[lba * 512, 512] = stage_sector
    expect(sim.runner_load_disk(disk_image, 0)).to be(true)

    result = sim.runner_run_cycles(40)

    expect(result[:cycles_run]).to eq(40)
    expect(sim.peek('observed_done')).to eq(1)
    expect(sim.peek('observed_word')).to eq(0x0001)
    expect(sim.peek('observed_flags')).to eq(0)
    expect(sim.runner_read_memory(0x0800, 16, mapped: false)).to eq(stage_sector.first(16))
  end

  it 'returns floppy geometry through the private INT 13h AH=08 runner bridge' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      dos_int13_harness_json(ax: 0x0800, bx: 0x0000, cx: 0x0000, es: 0x0000, dx: 0x0000),
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    result = sim.runner_run_cycles(40)

    expect(result[:cycles_run]).to eq(40)
    expect(sim.peek('observed_done')).to eq(1)
    expect(sim.peek('observed_word')).to eq(0x0000)
    expect(sim.peek('observed_bx')).to eq(0x0400)
    expect(sim.peek('observed_cx')).to eq(0x4F12)
    expect(sim.peek('observed_dx')).to eq(0x0102)
    expect(sim.peek('observed_flags')).to eq(0)
  end

  it 'returns the current floppy status through the private INT 13h AH=01 runner bridge' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      dos_int13_harness_json(ax: 0x0100, bx: 0x0000, cx: 0x0000, es: 0x0000, dx: 0x0000),
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    result = sim.runner_run_cycles(40)

    expect(result[:cycles_run]).to eq(40)
    expect(sim.peek('observed_done')).to eq(1)
    expect(sim.peek('observed_word')).to eq(0x0000)
    expect(sim.peek('observed_flags')).to eq(0)
  end

  it 'returns the floppy drive type through the private INT 13h AH=15 runner bridge without setting carry' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      dos_int13_harness_json(ax: 0x1500, bx: 0x0000, cx: 0x0000, es: 0x0000, dx: 0x0000),
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    result = sim.runner_run_cycles(40)

    expect(result[:cycles_run]).to eq(40)
    expect(sim.peek('observed_done')).to eq(1)
    expect(sim.peek('observed_word')).to eq(0x0100)
    expect(sim.peek('observed_flags')).to eq(0)
  end

  it 'returns unsupported change-line status through the private INT 13h AH=16 runner bridge' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      dos_int13_harness_json(ax: 0x1600, bx: 0x0000, cx: 0x0000, es: 0x0000, dx: 0x0000),
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    result = sim.runner_run_cycles(40)

    expect(result[:cycles_run]).to eq(40)
    expect(sim.peek('observed_done')).to eq(1)
    expect(sim.peek('observed_word')).to eq(0x0600)
    expect(sim.peek('observed_flags')).to eq(1)
  end

  it 'renders DOS INT 10h teletype output into text memory through the runner bridge' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      dos_int10_harness_json,
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    result = sim.runner_run_cycles(16)

    expect(result[:cycles_run]).to eq(16)
    expect(sim.runner_read_memory(0xB8000, 4, mapped: false)).to eq([0x41, 0x07, 0x20, 0x07])
    expect(sim.runner_read_memory(0x0450, 2, mapped: false)).to eq([0x01, 0x00])
  end

  it 'renders DOS INT 10h write-string output through the runner bridge' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      dos_int10_string_harness_json,
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)
    expect(sim.runner_load_memory('DOS'.bytes, 0x0600, false)).to be(true)

    result = sim.runner_run_cycles(24)

    expect(result[:cycles_run]).to eq(24)
    expect(sim.runner_read_memory(0xB8000, 6, mapped: false)).to eq(['D'.ord, 0x07, 'O'.ord, 0x07, 'S'.ord, 0x07])
    expect(sim.runner_read_memory(0x0450, 2, mapped: false)).to eq([0x03, 0x00])
  end

  it 'consumes queued keyboard input through the DOS INT 16h runner bridge' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      dos_int16_harness_json(ax: 0x0000),
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)

    result = sim.runner_run_cycles(12, 'd'.ord, true)

    expect(result[:cycles_run]).to eq(12)
    expect(result[:key_cleared]).to be(true)
    expect(sim.peek('observed_word')).to eq(0x2064)
    expect(sim.peek('observed_flags')).to eq(0x01)
  end

  it 'returns BIOS tick state through the DOS INT 1Ah runner bridge' do
    sim = RHDL::Sim::Native::IR::Simulator.new(
      dos_int1a_harness_json(ax: 0x0000),
      backend: :compiler,
      skip_signal_widths: true,
      retain_ir_json: false
    )

    expect(sim.runner_kind).to eq(:ao486)
    expect(sim.runner_load_memory([0x34, 0x12, 0x78, 0x56, 0x01], 0x046C, false)).to be(true)

    result = sim.runner_run_cycles(24)

    expect(result[:cycles_run]).to eq(24)
    expect(sim.peek('observed_ax')).to eq(0x0001)
    expect(sim.peek('observed_cx')).to eq(0x5678)
    expect(sim.peek('observed_dx')).to eq(0x1234)
    expect(sim.peek('observed_flags')).to eq(0x00)
    expect(sim.runner_read_memory(0x0470, 1, mapped: false)).to eq([0x00])
  end
end
