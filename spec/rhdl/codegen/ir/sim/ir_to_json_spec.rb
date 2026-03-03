# frozen_string_literal: true

require "json"
require "spec_helper"

require "rhdl/codegen/ir/sim/ir_simulator"

RSpec.describe RHDL::Codegen::IR::IRToJson do
  it "normalizes large literal integers into i64-compatible JSON values" do
    huge_value = (1 << 80) + (1 << 63) + 5

    module_ir = RHDL::Codegen::IR::ModuleDef.new(
      name: "big_literal",
      ports: [
        RHDL::Codegen::IR::Port.new(name: :y, direction: :out, width: 128)
      ],
      nets: [],
      regs: [],
      assigns: [
        RHDL::Codegen::IR::Assign.new(
          target: :y,
          expr: RHDL::Codegen::IR::Literal.new(value: huge_value, width: 128)
        )
      ],
      processes: [],
      memories: [],
      write_ports: [],
      sync_read_ports: []
    )

    json = described_class.convert(module_ir)
    parsed = JSON.parse(json)
    literal = parsed.fetch("assigns").first.fetch("expr")

    expect(literal.fetch("type")).to eq("literal")
    expect(literal.fetch("width")).to eq(128)
    expect(literal.fetch("value")).to eq(-9_223_372_036_854_775_803)
  end

  it "keeps simple initial seq-assign blocks as ordered initial_assigns without expression blow-up" do
    reg_signal = RHDL::Codegen::IR::Signal.new(name: :r, width: 8)

    module_ir = RHDL::Codegen::IR::ModuleDef.new(
      name: "initial_seq_assign",
      ports: [],
      nets: [],
      regs: [
        RHDL::Codegen::IR::Reg.new(name: :r, width: 8)
      ],
      assigns: [],
      processes: [
        RHDL::Codegen::IR::Process.new(
          name: :init,
          clocked: false,
          initial: true,
          statements: [
            RHDL::Codegen::IR::SeqAssign.new(
              target: :r,
              expr: RHDL::Codegen::IR::Literal.new(value: 1, width: 8)
            ),
            RHDL::Codegen::IR::SeqAssign.new(
              target: :r,
              expr: RHDL::Codegen::IR::BinaryOp.new(
                op: :+,
                left: reg_signal,
                right: RHDL::Codegen::IR::Literal.new(value: 2, width: 8),
                width: 8
              )
            )
          ]
        )
      ],
      memories: [],
      write_ports: [],
      sync_read_ports: []
    )

    json = described_class.convert(module_ir)
    parsed = JSON.parse(json)
    initial_assigns = parsed.fetch("initial_assigns")

    expect(initial_assigns.length).to eq(2)
    expect(initial_assigns.map { |entry| entry.fetch("target") }).to eq(["r", "r"])
    second_expr = initial_assigns.fetch(1).fetch("expr")
    expect(second_expr.fetch("type")).to eq("binary_op")
    expect(second_expr.fetch("left")).to include("type" => "signal", "name" => "r")
  end
end
