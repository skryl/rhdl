require 'spec_helper'

RSpec.describe RHDL::Codegen::Verilog do
  def build_module(processes:, ports:, reg_ports: [], regs: [], nets: [], declaration_kinds: {})
    RHDL::Codegen::IR::ModuleDef.new(
      name: 'process_emit_test',
      ports: ports,
      nets: nets,
      regs: regs,
      assigns: [],
      processes: processes,
      reg_ports: reg_ports,
      declaration_kinds: declaration_kinds
    )
  end

  it 'emits explicit combinational sensitivity and blocking assignments' do
    ir = RHDL::Codegen::IR
    process = ir::Process.new(
      name: :comb_logic,
      clocked: false,
      sensitivity_list: %i[sel d],
      statements: [
        ir::If.new(
          condition: ir::Signal.new(name: :sel, width: 1),
          then_statements: [
            ir::SeqAssign.new(
              target: :y,
              expr: ir::Signal.new(name: :d, width: 8),
              nonblocking: false
            )
          ],
          else_statements: [
            ir::SeqAssign.new(
              target: :y,
              expr: ir::Literal.new(value: 0, width: 8),
              nonblocking: false
            )
          ]
        )
      ]
    )

    module_def = build_module(
      processes: [process],
      ports: [
        ir::Port.new(name: :sel, direction: :in, width: 1),
        ir::Port.new(name: :d, direction: :in, width: 8),
        ir::Port.new(name: :y, direction: :out, width: 8)
      ],
      reg_ports: [:y]
    )

    verilog = described_class.generate(module_def)
    expect(verilog).to include('always @(sel or d) begin')
    expect(verilog).to include('y = d;')
    expect(verilog).to include("y = 8'd0;")
  end

  it 'preserves ascending declaration ranges in emitted declarations' do
    ir = RHDL::Codegen::IR
    module_def = build_module(
      processes: [],
      ports: [],
      regs: [ir::Reg.new(name: :len_be, width: (0..6))]
    )

    verilog = described_class.generate(module_def)
    expect(verilog).to include('reg [0:6] len_be;')
  end

  it 'preserves explicit scalar ranges for range-typed ports and declarations' do
    ir = RHDL::Codegen::IR
    module_def = build_module(
      processes: [],
      ports: [
        ir::Port.new(name: :flag_in, direction: :in, width: (0..0)),
        ir::Port.new(name: :flag_out, direction: :out, width: (0..0))
      ],
      regs: [ir::Reg.new(name: :flag_reg, width: (0..0))]
    )

    verilog = described_class.generate(module_def)
    expect(verilog).to include('input [0:0] flag_in')
    expect(verilog).to include('output [0:0] flag_out')
    expect(verilog).to include('reg [0:0] flag_reg;')
  end

  it 'emits logic declarations when import declaration kind is logic' do
    ir = RHDL::Codegen::IR
    module_def = build_module(
      processes: [],
      ports: [],
      regs: [ir::Reg.new(name: :tmp_reg, width: 1)],
      nets: [ir::Net.new(name: :tmp_net, width: 4)],
      declaration_kinds: { tmp_reg: :logic, tmp_net: :logic }
    )

    verilog = described_class.generate(module_def)
    expect(verilog).to include('logic tmp_reg;')
    expect(verilog).to include('logic [3:0] tmp_net;')
    expect(verilog).not_to include('reg tmp_reg;')
    expect(verilog).not_to include('wire [3:0] tmp_net;')
  end

  it 'emits full clocked sensitivity and non-blocking assignments' do
    ir = RHDL::Codegen::IR
    process = ir::Process.new(
      name: :seq_logic,
      clocked: true,
      clock: :clk,
      sensitivity_list: %i[clk rst],
      statements: [
        ir::SeqAssign.new(
          target: :q,
          expr: ir::Signal.new(name: :d, width: 8),
          nonblocking: true
        )
      ]
    )

    module_def = build_module(
      processes: [process],
      ports: [
        ir::Port.new(name: :clk, direction: :in, width: 1),
        ir::Port.new(name: :rst, direction: :in, width: 1),
        ir::Port.new(name: :d, direction: :in, width: 8),
        ir::Port.new(name: :q, direction: :out, width: 8)
      ],
      reg_ports: [:q]
    )

    verilog = described_class.generate(module_def)
    expect(verilog).to include('always @(posedge clk or posedge rst) begin')
    expect(verilog).to include('q <= d;')
  end

  it 'emits signed literal formatting for signed IR literals' do
    ir = RHDL::Codegen::IR
    process = ir::Process.new(
      name: :comb_signed,
      clocked: false,
      sensitivity_list: %i[addr],
      statements: [
        ir::SeqAssign.new(
          target: :y,
          expr: ir::BinaryOp.new(
            op: :>>,
            left: ir::Signal.new(name: :addr, width: 7),
            right: ir::Literal.new(value: 1, width: 32, base: "h", signed: true),
            width: 7
          ),
          nonblocking: false
        )
      ]
    )

    module_def = build_module(
      processes: [process],
      ports: [
        ir::Port.new(name: :addr, direction: :in, width: 7),
        ir::Port.new(name: :y, direction: :out, width: 7)
      ],
      reg_ports: [:y]
    )

    verilog = described_class.generate(module_def)
    expect(verilog).to include("y = (addr >> 32'sh1);")
  end

  it 'honors explicit blocking override inside a clocked process' do
    ir = RHDL::Codegen::IR
    process = ir::Process.new(
      name: :seq_logic,
      clocked: true,
      clock: :clk,
      statements: [
        ir::SeqAssign.new(
          target: :q,
          expr: ir::Signal.new(name: :d, width: 8),
          nonblocking: false
        )
      ]
    )

    module_def = build_module(
      processes: [process],
      ports: [
        ir::Port.new(name: :clk, direction: :in, width: 1),
        ir::Port.new(name: :d, direction: :in, width: 8),
        ir::Port.new(name: :q, direction: :out, width: 8)
      ],
      reg_ports: [:q]
    )

    verilog = described_class.generate(module_def)
    expect(verilog).to include('always @(posedge clk) begin')
    expect(verilog).to include('q = d;')
  end

  it 'emits initial blocks for initial processes' do
    ir = RHDL::Codegen::IR
    process = ir::Process.new(
      name: :init_logic,
      clocked: false,
      initial: true,
      statements: [
        ir::SeqAssign.new(
          target: :q,
          expr: ir::Literal.new(value: 0, width: 8),
          nonblocking: false
        )
      ]
    )

    module_def = build_module(
      processes: [process],
      ports: [
        ir::Port.new(name: :q, direction: :out, width: 8)
      ],
      reg_ports: [:q]
    )

    verilog = described_class.generate(module_def)
    expect(verilog).to include('initial begin')
    expect(verilog).to include("q = 8'd0;")
    expect(verilog).not_to include('always @(*) begin')
  end

  it 'emits statement-level case blocks from IR::CaseStmt processes' do
    ir = RHDL::Codegen::IR
    process = ir::Process.new(
      name: :comb_case,
      clocked: false,
      sensitivity_list: %i[op],
      statements: [
        ir::CaseStmt.new(
          selector: ir::Signal.new(name: :op, width: 2),
          branches: [
            ir::CaseBranch.new(
              values: [ir::Literal.new(value: 0, width: 2)],
              statements: [ir::SeqAssign.new(target: :y, expr: ir::Literal.new(value: 1, width: 8), nonblocking: false)]
            ),
            ir::CaseBranch.new(
              values: [ir::Literal.new(value: 1, width: 2)],
              statements: [ir::SeqAssign.new(target: :y, expr: ir::Literal.new(value: 2, width: 8), nonblocking: false)]
            )
          ],
          default_statements: [
            ir::SeqAssign.new(target: :y, expr: ir::Literal.new(value: 3, width: 8), nonblocking: false)
          ]
        )
      ]
    )

    module_def = build_module(
      processes: [process],
      ports: [
        ir::Port.new(name: :op, direction: :in, width: 2),
        ir::Port.new(name: :y, direction: :out, width: 8)
      ],
      reg_ports: [:y]
    )

    verilog = described_class.generate(module_def)
    expect(verilog).to include('case (op)')
    expect(verilog).to include("2'd0: begin")
    expect(verilog).to include("y = 8'd1;")
    expect(verilog).to include("default: begin")
    expect(verilog).to include("y = 8'd3;")
    expect(verilog).to include('endcase')
  end

  it 'reconstructs indexed assignment targets from RMW IR patterns' do
    ir = RHDL::Codegen::IR
    width = 8
    base = ir::Signal.new(name: :acc, width: width)
    index = ir::Signal.new(name: :idx, width: width)
    one = ir::Literal.new(value: 1, width: width)
    bit_mask = ir::BinaryOp.new(op: :<<, left: one, right: index, width: width)
    clear_mask = ir::UnaryOp.new(op: :~, operand: bit_mask, width: width)
    cleared = ir::BinaryOp.new(op: :&, left: base, right: clear_mask, width: width)
    value_source = ir::Signal.new(name: :bit_in, width: width)
    value_bit = ir::BinaryOp.new(op: :&, left: value_source, right: one, width: width)
    shifted = ir::BinaryOp.new(op: :<<, left: value_bit, right: index, width: width)
    merged = ir::BinaryOp.new(op: :|, left: cleared, right: shifted, width: width)

    process = ir::Process.new(
      name: :comb_idx,
      clocked: false,
      sensitivity_list: %i[acc idx bit_in],
      statements: [
        ir::SeqAssign.new(target: :acc, expr: merged, nonblocking: false)
      ]
    )

    module_def = build_module(
      processes: [process],
      ports: [
        ir::Port.new(name: :idx, direction: :in, width: width),
        ir::Port.new(name: :bit_in, direction: :in, width: width),
        ir::Port.new(name: :acc, direction: :out, width: width)
      ],
      reg_ports: [:acc]
    )

    verilog = described_class.generate(module_def)
    expect(verilog).to include('acc[idx] = bit_in;')
  end

  it 'reconstructs static slice assignment targets from RMW IR patterns' do
    ir = RHDL::Codegen::IR
    width = 16
    low = 4
    high = 7
    mask = ((1 << (high - low + 1)) - 1) << low
    full = (1 << width) - 1

    base = ir::Signal.new(name: :acc, width: width)
    keep_mask = ir::Literal.new(value: full ^ mask, width: width)
    cleared = ir::BinaryOp.new(op: :&, left: base, right: keep_mask, width: width)
    shift_amount = ir::Literal.new(value: low, width: width)
    value_source = ir::Signal.new(name: :slice_in, width: width)
    shifted = ir::BinaryOp.new(op: :<<, left: value_source, right: shift_amount, width: width)
    update_mask = ir::Literal.new(value: mask, width: width)
    masked = ir::BinaryOp.new(op: :&, left: shifted, right: update_mask, width: width)
    merged = ir::BinaryOp.new(op: :|, left: cleared, right: masked, width: width)

    process = ir::Process.new(
      name: :comb_slice,
      clocked: false,
      sensitivity_list: %i[acc slice_in],
      statements: [
        ir::SeqAssign.new(target: :acc, expr: merged, nonblocking: false)
      ]
    )

    module_def = build_module(
      processes: [process],
      ports: [
        ir::Port.new(name: :slice_in, direction: :in, width: width),
        ir::Port.new(name: :acc, direction: :out, width: width)
      ],
      reg_ports: [:acc]
    )

    verilog = described_class.generate(module_def)
    expect(verilog).to include('acc[7:4] = slice_in;')
  end

  it 'does not reconstruct indexed targets for scalar declarations' do
    ir = RHDL::Codegen::IR
    width = 1
    base = ir::Signal.new(name: :acc, width: width)
    index = ir::Signal.new(name: :idx, width: width)
    one = ir::Literal.new(value: 1, width: width)
    bit_mask = ir::BinaryOp.new(op: :<<, left: one, right: index, width: width)
    clear_mask = ir::UnaryOp.new(op: :~, operand: bit_mask, width: width)
    cleared = ir::BinaryOp.new(op: :&, left: base, right: clear_mask, width: width)
    value_source = ir::Signal.new(name: :bit_in, width: width)
    value_bit = ir::BinaryOp.new(op: :&, left: value_source, right: one, width: width)
    shifted = ir::BinaryOp.new(op: :<<, left: value_bit, right: index, width: width)
    merged = ir::BinaryOp.new(op: :|, left: cleared, right: shifted, width: width)

    process = ir::Process.new(
      name: :comb_idx_scalar,
      clocked: false,
      sensitivity_list: %i[acc idx bit_in],
      statements: [
        ir::SeqAssign.new(target: :acc, expr: merged, nonblocking: false)
      ]
    )

    module_def = build_module(
      processes: [process],
      ports: [
        ir::Port.new(name: :idx, direction: :in, width: width),
        ir::Port.new(name: :bit_in, direction: :in, width: width),
        ir::Port.new(name: :acc, direction: :out, width: width)
      ],
      reg_ports: [:acc]
    )

    verilog = described_class.generate(module_def)
    expect(verilog).not_to include('acc[idx] =')
    expect(verilog).to include('acc =')
  end
end
