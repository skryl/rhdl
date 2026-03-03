# frozen_string_literal: true

require "spec_helper"
require "json"
require "rhdl/codegen/ir/sim/ir_simulator"
require "rhdl/codegen/ir/ir"

RSpec.describe "IR simulator combinational process lowering" do
  ir = RHDL::Codegen::IR

  def step_posedge(sim)
    clk_idx = sim.get_signal_idx("clk")
    clk_list_idx = sim.get_clock_list_idx(clk_idx)

    sim.poke("clk", 0)
    sim.evaluate
    sim.poke("clk", 1)
    sim.set_prev_clock(clk_list_idx, 0) if clk_list_idx && clk_list_idx >= 0
    sim.tick_forced
    sim.poke("clk", 0)
    sim.evaluate
  end

  let(:module_ir) do
    ir::ModuleDef.new(
      name: "comb_proc",
      ports: [
        ir::Port.new(name: :a, direction: :in, width: 1),
        ir::Port.new(name: :b, direction: :in, width: 1),
        ir::Port.new(name: :sel, direction: :in, width: 1),
        ir::Port.new(name: :y, direction: :out, width: 1)
      ],
      nets: [ir::Net.new(name: :tmp, width: 1)],
      regs: [],
      assigns: [],
      processes: [
        ir::Process.new(
          name: :comb_logic,
          clocked: false,
          sensitivity_list: %i[a b sel],
          statements: [
            ir::SeqAssign.new(
              target: :tmp,
              expr: ir::Signal.new(name: :a, width: 1)
            ),
            ir::If.new(
              condition: ir::Signal.new(name: :sel, width: 1),
              then_statements: [
                ir::SeqAssign.new(
                  target: :tmp,
                  expr: ir::Signal.new(name: :b, width: 1)
                )
              ],
              else_statements: []
            ),
            ir::SeqAssign.new(
              target: :y,
              expr: ir::Signal.new(name: :tmp, width: 1)
            )
          ]
        )
      ]
    )
  end

  let(:empty_sensitivity_ir) do
    ir::ModuleDef.new(
      name: "empty_sensitivity",
      ports: [ir::Port.new(name: :y, direction: :out, width: 1)],
      nets: [],
      regs: [],
      assigns: [],
      processes: [
        ir::Process.new(
          name: :dead_comb,
          clocked: false,
          sensitivity_list: [],
          statements: [
            ir::SeqAssign.new(
              target: :y,
              expr: ir::Literal.new(value: 1, width: 1)
            )
          ]
        )
      ]
    )
  end

  let(:imported_empty_sensitivity_ir) do
    ir::ModuleDef.new(
      name: "imported_empty_sensitivity",
      ports: [ir::Port.new(name: :y, direction: :out, width: 1)],
      nets: [],
      regs: [],
      assigns: [],
      declaration_kinds: { y: :wire },
      processes: [
        ir::Process.new(
          name: :comb_imported,
          clocked: false,
          sensitivity_list: [],
          statements: [
            ir::SeqAssign.new(
              target: :y,
              expr: ir::Literal.new(value: 1, width: 1)
            )
          ]
        )
      ]
    )
  end

  let(:ordered_blocking_ir) do
    ir::ModuleDef.new(
      name: "ordered_blocking",
      ports: [
        ir::Port.new(name: :idx, direction: :in, width: 2),
        ir::Port.new(name: :y, direction: :out, width: 4)
      ],
      nets: [ir::Net.new(name: :table, width: 4)],
      regs: [],
      assigns: [],
      processes: [
        ir::Process.new(
          name: :table_update,
          clocked: false,
          sensitivity_list: [:idx],
          statements: [
            ir::SeqAssign.new(
              target: :table,
              expr: ir::Literal.new(value: 0, width: 4)
            ),
            ir::SeqAssign.new(
              target: :table,
              expr: ir::BinaryOp.new(
                op: :|,
                left: ir::Signal.new(name: :table, width: 4),
                right: ir::BinaryOp.new(
                  op: :<<,
                  left: ir::Literal.new(value: 1, width: 4),
                  right: ir::Signal.new(name: :idx, width: 2),
                  width: 4
                ),
                width: 4
              )
            ),
            ir::SeqAssign.new(
              target: :y,
              expr: ir::Signal.new(name: :table, width: 4)
            )
          ]
        )
      ]
    )
  end

  it "converts nonclocked process statements into combinational assigns" do
    json = RHDL::Codegen::IR::IRToJson.convert(module_ir)
    payload = JSON.parse(json)

    expect(payload.fetch("processes")).to eq([])
    targets = payload.fetch("assigns").map { |a| a.fetch("target") }
    expect(targets).to include("tmp", "y")
    expect(targets.length).to be >= 2
  end

  it "simulates combinational process behavior through the IR simulator" do
    json = RHDL::Codegen::IR::IRToJson.convert(module_ir)
    sim = RHDL::Codegen::IR::IrSimulator.new(json, backend: :interpreter, allow_fallback: true)

    sim.poke("a", 0)
    sim.poke("b", 1)
    sim.poke("sel", 0)
    sim.evaluate
    expect(sim.peek("y")).to eq(0)

    sim.poke("sel", 1)
    sim.evaluate
    expect(sim.peek("y")).to eq(1)
  end

  it "simulates statement-level case processes through combinational lowering" do
    case_ir = ir::ModuleDef.new(
      name: "case_proc",
      ports: [
        ir::Port.new(name: :op, direction: :in, width: 2),
        ir::Port.new(name: :y, direction: :out, width: 8)
      ],
      nets: [],
      regs: [],
      assigns: [],
      processes: [
        ir::Process.new(
          name: :comb_case,
          clocked: false,
          sensitivity_list: [:op],
          statements: [
            ir::CaseStmt.new(
              selector: ir::Signal.new(name: :op, width: 2),
              branches: [
                ir::CaseBranch.new(
                  values: [ir::Literal.new(value: 0, width: 2)],
                  statements: [ir::SeqAssign.new(target: :y, expr: ir::Literal.new(value: 1, width: 8))]
                ),
                ir::CaseBranch.new(
                  values: [ir::Literal.new(value: 1, width: 2)],
                  statements: [ir::SeqAssign.new(target: :y, expr: ir::Literal.new(value: 2, width: 8))]
                )
              ],
              default_statements: [ir::SeqAssign.new(target: :y, expr: ir::Literal.new(value: 3, width: 8))]
            )
          ]
        )
      ]
    )

    json = RHDL::Codegen::IR::IRToJson.convert(case_ir)
    sim = RHDL::Codegen::IR::RubyIrSim.new(json)

    sim.poke("op", 0)
    sim.evaluate
    expect(sim.peek("y")).to eq(1)

    sim.poke("op", 1)
    sim.evaluate
    expect(sim.peek("y")).to eq(2)

    sim.poke("op", 3)
    sim.evaluate
    expect(sim.peek("y")).to eq(3)
  end

  it "does not lower empty-sensitivity combinational processes into always-active assigns" do
    json = RHDL::Codegen::IR::IRToJson.convert(empty_sensitivity_ir)
    payload = JSON.parse(json)

    expect(payload.fetch("assigns")).to eq([])
    expect(payload.fetch("processes")).to eq([])
  end

  it "lowers empty-sensitivity combinational processes for imported modules into assigns" do
    json = RHDL::Codegen::IR::IRToJson.convert(imported_empty_sensitivity_ir)
    payload = JSON.parse(json)

    expect(payload.fetch("processes")).to eq([])
    expect(payload.fetch("assigns")).to eq([
      {
        "target" => "y",
        "expr" => { "type" => "literal", "value" => 1, "width" => 1 }
      }
    ])

    sim = RHDL::Codegen::IR::RubyIrSim.new(json)
    sim.evaluate
    expect(sim.peek("y")).to eq(1)
  end

  it "preserves blocking assignment ordering for repeated targets when flattening combinational logic" do
    json = RHDL::Codegen::IR::IRToJson.convert(ordered_blocking_ir)
    sim = RHDL::Codegen::IR::RubyIrSim.new(json)

    sim.poke("idx", 1)
    sim.evaluate
    expect(sim.peek("y")).to eq(2)

    sim.poke("idx", 2)
    sim.evaluate
    expect(sim.peek("y")).to eq(4)
  end

  it "preserves nested if gating when lowering clocked process statements" do
    clocked_ir = ir::ModuleDef.new(
      name: "nested_if",
      ports: [
        ir::Port.new(name: :clk, direction: :in, width: 1),
        ir::Port.new(name: :rst_n, direction: :in, width: 1),
        ir::Port.new(name: :set, direction: :in, width: 1),
        ir::Port.new(name: :val, direction: :in, width: 8),
        ir::Port.new(name: :q, direction: :out, width: 8)
      ],
      nets: [],
      regs: [ir::Reg.new(name: :q, width: 8, reset_value: 0)],
      assigns: [],
      processes: [
        ir::Process.new(
          name: :seq_logic,
          clocked: true,
          clock: :clk,
          statements: [
            ir::If.new(
              condition: ir::Signal.new(name: :rst_n, width: 1),
              then_statements: [
                ir::If.new(
                  condition: ir::Signal.new(name: :set, width: 1),
                  then_statements: [
                    ir::SeqAssign.new(
                      target: :q,
                      expr: ir::Signal.new(name: :val, width: 8)
                    )
                  ],
                  else_statements: [
                    ir::SeqAssign.new(
                      target: :q,
                      expr: ir::Literal.new(value: 0, width: 8)
                    )
                  ]
                )
              ],
              else_statements: []
            )
          ]
        )
      ]
    )

    json = RHDL::Codegen::IR::IRToJson.convert(clocked_ir)
    sim = RHDL::Codegen::IR::IrSimulator.new(json, backend: :interpreter, allow_fallback: true)

    sim.poke("rst_n", 1)
    sim.poke("set", 1)
    sim.poke("val", 5)
    step_posedge(sim)
    expect(sim.peek("q")).to eq(5)

    sim.poke("rst_n", 0)
    sim.poke("set", 0)
    sim.poke("val", 9)
    step_posedge(sim)
    expect(sim.peek("q")).to eq(5)
  end

  it "supports signal widths greater than 64 bits in Ruby IR simulation" do
    wide_ir = ir::ModuleDef.new(
      name: "wide_passthrough",
      ports: [
        ir::Port.new(name: :a, direction: :in, width: 96),
        ir::Port.new(name: :y, direction: :out, width: 96)
      ],
      nets: [],
      regs: [],
      assigns: [
        ir::Assign.new(
          target: :y,
          expr: ir::Signal.new(name: :a, width: 96)
        )
      ],
      processes: []
    )

    json = RHDL::Codegen::IR::IRToJson.convert(wide_ir)
    sim = RHDL::Codegen::IR::RubyIrSim.new(json)

    value = (1 << 80) + 0x1234_5678_9ABC_DEF0
    expected = value & ((1 << 96) - 1)

    sim.poke("a", value)
    sim.evaluate

    expect(sim.peek("y")).to eq(expected)
  end

  it "preserves absolute slice semantics for non-zero lsb packed ranges" do
    range_ir = ir::ModuleDef.new(
      name: "non_zero_lsb_slice",
      ports: [
        ir::Port.new(name: :a, direction: :in, width: 30),
        ir::Port.new(name: :y, direction: :out, width: 30)
      ],
      nets: [],
      regs: [],
      assigns: [
        ir::Assign.new(
          target: :y,
          expr: ir::Concat.new(
            parts: [
              ir::Slice.new(
                base: ir::Signal.new(name: :a, width: 30),
                range: (31..21),
                width: 11
              ),
              ir::Concat.new(
                parts: [
                  ir::Slice.new(
                    base: ir::Signal.new(name: :a, width: 30),
                    range: (20..20),
                    width: 1
                  ),
                  ir::Slice.new(
                    base: ir::Signal.new(name: :a, width: 30),
                    range: (19..2),
                    width: 18
                  )
                ],
                width: 19
              )
            ],
            width: 30
          )
        )
      ],
      processes: []
    )

    json = RHDL::Codegen::IR::IRToJson.convert(range_ir)
    sim = RHDL::Codegen::IR::RubyIrSim.new(json)

    value = 0x003F_FF8
    sim.poke("a", value)
    sim.evaluate

    expect(sim.peek("y")).to eq(value)
  end

  it "preserves nonblocking clocked semantics when flattening process statements" do
    seq_ir = ir::ModuleDef.new(
      name: "nb_swap",
      ports: [
        ir::Port.new(name: :clk, direction: :in, width: 1),
        ir::Port.new(name: :a, direction: :out, width: 8),
        ir::Port.new(name: :b, direction: :out, width: 8)
      ],
      nets: [],
      regs: [
        ir::Reg.new(name: :a, width: 8, reset_value: 1),
        ir::Reg.new(name: :b, width: 8, reset_value: 2)
      ],
      assigns: [],
      processes: [
        ir::Process.new(
          name: :swap_regs,
          clocked: true,
          clock: :clk,
          statements: [
            ir::SeqAssign.new(
              target: :a,
              expr: ir::Signal.new(name: :b, width: 8),
              nonblocking: true
            ),
            ir::SeqAssign.new(
              target: :b,
              expr: ir::Signal.new(name: :a, width: 8),
              nonblocking: true
            )
          ]
        )
      ]
    )

    json = RHDL::Codegen::IR::IRToJson.convert(seq_ir)
    sim = RHDL::Codegen::IR::RubyIrSim.new(json)

    expect(sim.peek("a")).to eq(1)
    expect(sim.peek("b")).to eq(2)

    sim.poke("clk", 0)
    sim.evaluate
    sim.poke("clk", 1)
    sim.tick
    sim.poke("clk", 0)
    sim.evaluate

    expect(sim.peek("a")).to eq(2)
    expect(sim.peek("b")).to eq(1)
  end
end
