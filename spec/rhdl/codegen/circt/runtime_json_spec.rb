# frozen_string_literal: true

require 'spec_helper'
require 'timeout'
require 'json'
require 'stringio'

RSpec.describe RHDL::Codegen::CIRCT::RuntimeJSON do
  let(:ir) { RHDL::Codegen::CIRCT::IR }

  def build_wide_bus_runtime_module
    a = ir::Signal.new(name: :a, width: 64)
    c = ir::Signal.new(name: :c, width: 64)
    sel8 = ir::Signal.new(name: :sel8, width: 8)
    choose = ir::Signal.new(name: :choose, width: 1)
    we = ir::Signal.new(name: :we, width: 1)
    cab = ir::Signal.new(name: :cab, width: 1)
    cyc = ir::Signal.new(name: :cyc, width: 1)
    stb = ir::Signal.new(name: :stb, width: 1)
    bus_mux = ir::Signal.new(name: :bus_mux, width: 140)

    bus0 = ir::Concat.new(parts: [a, sel8, c, we, cab, cyc, stb], width: 140)
    bus1 = ir::Concat.new(parts: [c, sel8, a, cab, we, stb, cyc], width: 140)

    ir::ModuleOp.new(
      name: 'runtime_wide_bus',
      ports: [
        ir::Port.new(name: :choose, direction: :in, width: 1),
        ir::Port.new(name: :a, direction: :in, width: 64),
        ir::Port.new(name: :sel8, direction: :in, width: 8),
        ir::Port.new(name: :c, direction: :in, width: 64),
        ir::Port.new(name: :we, direction: :in, width: 1),
        ir::Port.new(name: :cab, direction: :in, width: 1),
        ir::Port.new(name: :cyc, direction: :in, width: 1),
        ir::Port.new(name: :stb, direction: :in, width: 1),
        ir::Port.new(name: :adr, direction: :out, width: 64),
        ir::Port.new(name: :byte_sel, direction: :out, width: 8),
        ir::Port.new(name: :data_o, direction: :out, width: 64),
        ir::Port.new(name: :cyc_o, direction: :out, width: 1),
        ir::Port.new(name: :stb_o, direction: :out, width: 1)
      ],
      nets: [
        ir::Net.new(name: :bus_mux, width: 140)
      ],
      regs: [],
      assigns: [
        ir::Assign.new(
          target: :bus_mux,
          expr: ir::Mux.new(condition: choose, when_true: bus1, when_false: bus0, width: 140)
        ),
        ir::Assign.new(
          target: :adr,
          expr: ir::Slice.new(base: bus_mux, range: 139..76, width: 64)
        ),
        ir::Assign.new(
          target: :byte_sel,
          expr: ir::Slice.new(base: bus_mux, range: 75..68, width: 8)
        ),
        ir::Assign.new(
          target: :data_o,
          expr: ir::Slice.new(base: bus_mux, range: 67..4, width: 64)
        ),
        ir::Assign.new(
          target: :cyc_o,
          expr: ir::Slice.new(base: bus_mux, range: 1..1, width: 1)
        ),
        ir::Assign.new(
          target: :stb_o,
          expr: ir::Slice.new(base: bus_mux, range: 0..0, width: 1)
        )
      ],
      processes: [],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )
  end

  def build_shared_wide_subexpr_runtime_module
    a = ir::Signal.new(name: :a, width: 64)
    b = ir::Signal.new(name: :b, width: 64)
    c = ir::Signal.new(name: :c, width: 32)
    choose = ir::Signal.new(name: :choose, width: 1)

    packed = ir::Concat.new(parts: [a, b, c], width: 160)
    upper = ir::Slice.new(base: packed, range: 159..96, width: 64)
    lower = ir::Slice.new(base: packed, range: 95..32, width: 64)

    ir::ModuleOp.new(
      name: 'runtime_shared_wide_subexpr',
      ports: [
        ir::Port.new(name: :choose, direction: :in, width: 1),
        ir::Port.new(name: :a, direction: :in, width: 64),
        ir::Port.new(name: :b, direction: :in, width: 64),
        ir::Port.new(name: :c, direction: :in, width: 32),
        ir::Port.new(name: :y, direction: :out, width: 64)
      ],
      nets: [],
      regs: [],
      assigns: [
        ir::Assign.new(
          target: :y,
          expr: ir::Mux.new(condition: choose, when_true: upper, when_false: lower, width: 64)
        )
      ],
      processes: [],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )
  end

  def build_hierarchical_probe_runtime_module
    a = ir::Signal.new(name: :a, width: 64)
    c = ir::Signal.new(name: :c, width: 64)
    sel8 = ir::Signal.new(name: :sel8, width: 8)
    choose = ir::Signal.new(name: :choose, width: 1)
    bus_mux = ir::Signal.new(name: :bus_mux, width: 140)

    bus0 = ir::Concat.new(
      parts: [a, sel8, c, ir::Literal.new(value: 0, width: 4)],
      width: 140
    )
    bus1 = ir::Concat.new(
      parts: [c, sel8, a, ir::Literal.new(value: 0b1010, width: 4)],
      width: 140
    )

    ir::ModuleOp.new(
      name: 'runtime_hierarchical_probe',
      ports: [
        ir::Port.new(name: :choose, direction: :in, width: 1),
        ir::Port.new(name: :a, direction: :in, width: 64),
        ir::Port.new(name: :sel8, direction: :in, width: 8),
        ir::Port.new(name: :c, direction: :in, width: 64),
        ir::Port.new(name: :y, direction: :out, width: 1)
      ],
      nets: [
        ir::Net.new(name: :bus_mux, width: 140),
        ir::Net.new(name: :'u__probe', width: 1)
      ],
      regs: [],
      assigns: [
        ir::Assign.new(
          target: :bus_mux,
          expr: ir::Mux.new(condition: choose, when_true: bus1, when_false: bus0, width: 140)
        ),
        ir::Assign.new(
          target: :'u__probe',
          expr: ir::Slice.new(base: bus_mux, range: 1..1, width: 1)
        ),
        ir::Assign.new(
          target: :y,
          expr: ir::Signal.new(name: :'u__probe', width: 1)
        )
      ],
      processes: [],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )
  end

  def build_wide_runtime_bridge_module
    pkt = ir::Signal.new(name: :pkt, width: 145)
    en = ir::Signal.new(name: :en, width: 1)
    bridge_out = ir::Signal.new(name: :bridge_out, width: 145)
    q_reg = ir::Signal.new(name: :q_reg, width: 145)

    select_code = ir::Concat.new(
      parts: [
        ir::Signal.new(name: :'bridge__sel3_l', width: 1),
        ir::Signal.new(name: :'bridge__sel2_l', width: 1),
        ir::Signal.new(name: :'bridge__sel1_l', width: 1),
        ir::Signal.new(name: :'bridge__sel0_l', width: 1)
      ],
      width: 4
    )

    bridge_mux = ir::Mux.new(
      condition: ir::BinaryOp.new(
        op: :==,
        left: select_code,
        right: ir::Literal.new(value: 7, width: 4),
        width: 1
      ),
      when_true: ir::Signal.new(name: :'bridge__in3', width: 145),
      when_false: ir::Literal.new(value: 0, width: 145),
      width: 145
    )

    ir::ModuleOp.new(
      name: 'runtime_wide_bridge',
      ports: [
        ir::Port.new(name: :clk, direction: :in, width: 1),
        ir::Port.new(name: :en, direction: :in, width: 1),
        ir::Port.new(name: :pkt, direction: :in, width: 145),
        ir::Port.new(name: :sel0_l, direction: :in, width: 1),
        ir::Port.new(name: :sel1_l, direction: :in, width: 1),
        ir::Port.new(name: :sel2_l, direction: :in, width: 1),
        ir::Port.new(name: :sel3_l, direction: :in, width: 1),
        ir::Port.new(name: :q, direction: :out, width: 145),
        ir::Port.new(name: :vld, direction: :out, width: 1)
      ],
      nets: [
        ir::Net.new(name: :bridge_out, width: 145),
        ir::Net.new(name: :'bridge__dout', width: 145),
        ir::Net.new(name: :'bridge__in3', width: 145),
        ir::Net.new(name: :'bridge__sel0_l', width: 1),
        ir::Net.new(name: :'bridge__sel1_l', width: 1),
        ir::Net.new(name: :'bridge__sel2_l', width: 1),
        ir::Net.new(name: :'bridge__sel3_l', width: 1)
      ],
      regs: [
        ir::Reg.new(name: :q_reg, width: 145, reset_value: 0)
      ],
      assigns: [
        ir::Assign.new(target: :'bridge__in3', expr: pkt),
        ir::Assign.new(target: :'bridge__sel0_l', expr: ir::Signal.new(name: :sel0_l, width: 1)),
        ir::Assign.new(target: :'bridge__sel1_l', expr: ir::Signal.new(name: :sel1_l, width: 1)),
        ir::Assign.new(target: :'bridge__sel2_l', expr: ir::Signal.new(name: :sel2_l, width: 1)),
        ir::Assign.new(target: :'bridge__sel3_l', expr: ir::Signal.new(name: :sel3_l, width: 1)),
        ir::Assign.new(target: :'bridge__dout', expr: bridge_mux),
        ir::Assign.new(target: :bridge_out, expr: ir::Signal.new(name: :'bridge__dout', width: 145)),
        ir::Assign.new(target: :q, expr: q_reg),
        ir::Assign.new(target: :vld, expr: ir::Slice.new(base: q_reg, range: 144..144, width: 1))
      ],
      processes: [
        ir::Process.new(
          name: 'capture',
          clocked: true,
          clock: 'clk',
          statements: [
            ir::SeqAssign.new(
              target: :q_reg,
              expr: ir::Mux.new(
                condition: en,
                when_true: bridge_out,
                when_false: q_reg,
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
  end

  def build_dead_wide_assign_runtime_module(dead_assign_count:)
    a = ir::Signal.new(name: :a, width: 64)
    choose = ir::Signal.new(name: :choose, width: 1)

    dead_nets = []
    dead_assigns = Array.new(dead_assign_count) do |idx|
      target = :"dead_#{idx}"
      dead_nets << ir::Net.new(name: target, width: 140)

      when_false = ir::Concat.new(
        parts: [a, a, ir::Literal.new(value: idx & 0xff, width: 8), ir::Literal.new(value: 0, width: 4)],
        width: 140
      )
      when_true = ir::Concat.new(
        parts: [a, a, ir::Literal.new(value: (~idx) & 0xff, width: 8), ir::Literal.new(value: 0xf, width: 4)],
        width: 140
      )

      ir::Assign.new(
        target: target,
        expr: ir::Mux.new(condition: choose, when_true: when_true, when_false: when_false, width: 140)
      )
    end

    ir::ModuleOp.new(
      name: 'runtime_dead_wide_assigns',
      ports: [
        ir::Port.new(name: :choose, direction: :in, width: 1),
        ir::Port.new(name: :a, direction: :in, width: 64),
        ir::Port.new(name: :y, direction: :out, width: 64)
      ],
      nets: dead_nets,
      regs: [],
      assigns: [
        ir::Assign.new(target: :y, expr: a),
        *dead_assigns
      ],
      processes: [],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )
  end

  def build_duplicate_live_assign_runtime_module
    a = ir::Signal.new(name: :a, width: 8)

    ir::ModuleOp.new(
      name: 'runtime_duplicate_live_assigns',
      ports: [
        ir::Port.new(name: :a, direction: :in, width: 8),
        ir::Port.new(name: :y, direction: :out, width: 8)
      ],
      nets: [],
      regs: [],
      assigns: [
        ir::Assign.new(target: :y, expr: a),
        ir::Assign.new(target: :y, expr: a)
      ],
      processes: [],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )
  end

  def expr_signal_names(expr)
    case expr
    when ir::Signal
      [expr.name.to_s]
    when ir::UnaryOp
      expr_signal_names(expr.operand)
    when ir::BinaryOp
      expr_signal_names(expr.left) + expr_signal_names(expr.right)
    when ir::Mux
      expr_signal_names(expr.condition) + expr_signal_names(expr.when_true) + expr_signal_names(expr.when_false)
    when ir::Slice
      expr_signal_names(expr.base)
    when ir::Concat
      expr.parts.flat_map { |part| expr_signal_names(part) }
    when ir::Resize
      expr_signal_names(expr.expr)
    when ir::Case
      expr_signal_names(expr.selector) + expr_signal_names(expr.default) +
        expr.cases.values.flat_map { |value| expr_signal_names(value) }
    when ir::MemoryRead
      expr_signal_names(expr.addr)
    else
      []
    end
  end

  def max_expr_width(expr)
    return 0 unless expr

    child_width = case expr
                  when ir::UnaryOp
                    max_expr_width(expr.operand)
                  when ir::BinaryOp
                    [max_expr_width(expr.left), max_expr_width(expr.right)].max
                  when ir::Mux
                    [max_expr_width(expr.condition), max_expr_width(expr.when_true), max_expr_width(expr.when_false)].max
                  when ir::Slice
                    max_expr_width(expr.base)
                  when ir::Concat
                    expr.parts.map { |part| max_expr_width(part) }.max.to_i
                  when ir::Resize
                    max_expr_width(expr.expr)
                  when ir::Case
                    [max_expr_width(expr.selector), max_expr_width(expr.default),
                     expr.cases.values.map { |value| max_expr_width(value) }.max.to_i].max
                  when ir::MemoryRead
                    max_expr_width(expr.addr)
                  else
                    0
                  end

    [expr.respond_to?(:width) ? expr.width.to_i : 0, child_width].max
  end

  it 'dumps shared expression DAGs without timing out' do
    sel = ir::Signal.new(name: :sel, width: 1)
    shared = ir::Signal.new(name: :a, width: 8)
    100.times do |idx|
      shared = ir::Mux.new(
        condition: idx.even? ? sel : ir::UnaryOp.new(op: :'~', operand: sel, width: 1),
        when_true: shared,
        when_false: shared,
        width: 8
      )
    end

    mod = ir::ModuleOp.new(
      name: 'runtime_shared_dag',
      ports: [
        ir::Port.new(name: :sel, direction: :in, width: 1),
        ir::Port.new(name: :a, direction: :in, width: 8),
        ir::Port.new(name: :y, direction: :out, width: 8)
      ],
      nets: [],
      regs: [],
      assigns: [ir::Assign.new(target: :y, expr: shared)],
      processes: [],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )

    json = nil
    expect do
      Timeout.timeout(2) do
        json = described_class.dump(mod)
      end
    end.not_to raise_error

    payload = JSON.parse(json)
    expect(payload.fetch('circt_json_version')).to eq(1)
    runtime_mod = payload.fetch('modules').fetch(0)
    expect(runtime_mod.fetch('nets')).not_to be_empty
    expect(runtime_mod.fetch('assigns').length).to be > 1
  end

  it 'can serialize shared runtime DAGs with compact expression refs' do
    sel = ir::Signal.new(name: :sel, width: 1)
    shared = ir::Mux.new(
      condition: sel,
      when_true: ir::BinaryOp.new(op: :+, left: ir::Signal.new(name: :a, width: 8), right: ir::Signal.new(name: :b, width: 8), width: 8),
      when_false: ir::BinaryOp.new(op: :-, left: ir::Signal.new(name: :a, width: 8), right: ir::Signal.new(name: :b, width: 8), width: 8),
      width: 8
    )

    mod = ir::ModuleOp.new(
      name: 'runtime_shared_dag_compact',
      ports: [
        ir::Port.new(name: :sel, direction: :in, width: 1),
        ir::Port.new(name: :a, direction: :in, width: 8),
        ir::Port.new(name: :b, direction: :in, width: 8),
        ir::Port.new(name: :y0, direction: :out, width: 8),
        ir::Port.new(name: :y1, direction: :out, width: 8)
      ],
      nets: [],
      regs: [],
      assigns: [
        ir::Assign.new(target: :y0, expr: shared),
        ir::Assign.new(target: :y1, expr: shared)
      ],
      processes: [],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )

    runtime_mod = JSON.parse(described_class.dump(mod, compact_exprs: true)).fetch('modules').fetch(0)

    expect(runtime_mod.fetch('exprs')).not_to be_empty
    expect(runtime_mod.fetch('exprs')).to include(
      a_hash_including('kind' => 'mux')
    )
    assign_expr = runtime_mod.fetch('assigns').first.fetch('expr')
    expect(assign_expr.fetch('kind')).to eq('expr_ref')
    expect(runtime_mod.fetch('exprs').fetch(assign_expr.fetch('id')).fetch('kind')).to eq('mux')
  end

  it 'streams the same compact payload as dump(compact_exprs: true)' do
    sel = ir::Signal.new(name: :sel, width: 1)
    shared = ir::Mux.new(
      condition: sel,
      when_true: ir::BinaryOp.new(op: :+, left: ir::Signal.new(name: :a, width: 8), right: ir::Signal.new(name: :b, width: 8), width: 8),
      when_false: ir::BinaryOp.new(op: :-, left: ir::Signal.new(name: :a, width: 8), right: ir::Signal.new(name: :b, width: 8), width: 8),
      width: 8
    )

    mod = ir::ModuleOp.new(
      name: 'runtime_shared_dag_compact_streamed',
      ports: [
        ir::Port.new(name: :sel, direction: :in, width: 1),
        ir::Port.new(name: :a, direction: :in, width: 8),
        ir::Port.new(name: :b, direction: :in, width: 8),
        ir::Port.new(name: :y0, direction: :out, width: 8),
        ir::Port.new(name: :y1, direction: :out, width: 8)
      ],
      nets: [],
      regs: [],
      assigns: [
        ir::Assign.new(target: :y0, expr: shared),
        ir::Assign.new(target: :y1, expr: shared)
      ],
      processes: [],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )

    expected = JSON.parse(described_class.dump(mod, compact_exprs: true))
    io = StringIO.new
    described_class.dump_to_io(mod, io, compact_exprs: true)

    expect(JSON.parse(io.string)).to eq(expected)
  end

  it 'dumps modules with large dead wide assign sets by pruning them before normalization' do
    mod = build_dead_wide_assign_runtime_module(dead_assign_count: 50_000)
    json = nil

    expect do
      Timeout.timeout(1.0) do
        json = described_class.dump(mod)
      end
    end.not_to raise_error

    runtime_mod = JSON.parse(json).fetch('modules').fetch(0)
    expect(runtime_mod.fetch('assigns')).to eq(
      [
        {
          'target' => 'y',
          'expr' => { 'kind' => 'signal', 'name' => 'a', 'width' => 64 }
        }
      ]
    )
    expect(runtime_mod.fetch('nets')).to eq([])
  end

  it 'collapses duplicate live assigns with identical targets during dump export' do
    runtime_mod = JSON.parse(described_class.dump(build_duplicate_live_assign_runtime_module)).fetch('modules').fetch(0)

    expect(runtime_mod.fetch('assigns')).to eq(
      [
        {
          'target' => 'y',
          'expr' => { 'kind' => 'signal', 'name' => 'a', 'width' => 8 }
        }
      ]
    )
  end

  it 'hoists shared root expressions reused across multiple assigns before dump serialization' do
    sel = ir::Signal.new(name: :sel, width: 1)
    a = ir::Signal.new(name: :a, width: 8)
    b = ir::Signal.new(name: :b, width: 8)
    shared = ir::Mux.new(
      condition: sel,
      when_true: ir::BinaryOp.new(op: :+, left: a, right: b, width: 8),
      when_false: ir::BinaryOp.new(op: :-, left: a, right: b, width: 8),
      width: 8
    )

    mod = ir::ModuleOp.new(
      name: 'runtime_shared_root_assign',
      ports: [
        ir::Port.new(name: :sel, direction: :in, width: 1),
        ir::Port.new(name: :a, direction: :in, width: 8),
        ir::Port.new(name: :b, direction: :in, width: 8),
        ir::Port.new(name: :y0, direction: :out, width: 8),
        ir::Port.new(name: :y1, direction: :out, width: 8)
      ],
      nets: [],
      regs: [],
      assigns: [
        ir::Assign.new(target: :y0, expr: shared),
        ir::Assign.new(target: :y1, expr: shared)
      ],
      processes: [],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )

    runtime_mod = JSON.parse(described_class.dump(mod)).fetch('modules').fetch(0)
    assigns_by_target = runtime_mod.fetch('assigns').to_h { |assign| [assign.fetch('target'), assign.fetch('expr')] }
    y0_expr = assigns_by_target.fetch('y0')
    y1_expr = assigns_by_target.fetch('y1')

    expect(y0_expr.fetch('kind')).to eq('signal')
    expect(y1_expr.fetch('kind')).to eq('signal')
    expect(y0_expr.fetch('name')).to eq(y1_expr.fetch('name'))
    expect(runtime_mod.fetch('nets').map { |net| net.fetch('name') }).to include(y0_expr.fetch('name'))
  end

  it 'rewrites wide packed-bus slices into narrow runtime-safe expressions' do
    runtime_mod = described_class.normalize_modules_for_runtime([build_wide_bus_runtime_module]).first
    output_exprs = runtime_mod.assigns.to_h { |assign| [assign.target.to_s, assign.expr] }

    %w[adr byte_sel data_o cyc_o stb_o].each do |target|
      expr = output_exprs.fetch(target)
      expect(expr_signal_names(expr)).not_to include('bus_mux')
      expect(max_expr_width(expr)).to be <= 64
    end

    expect(runtime_mod.assigns.map { |assign| assign.target.to_s }).not_to include('bus_mux')
    expect(runtime_mod.nets.map { |net| net.name.to_s }).not_to include('bus_mux')
    expect(runtime_mod.nets).to all(satisfy { |net| net.width.to_i <= 128 })
  end

  it 'treats 128-bit passthrough signals as runtime-safe and only flags truly over-wide signals' do
    assign_map = {
      'fit' => ir::Signal.new(name: :fit_in, width: 128),
      'too_wide' => ir::Signal.new(name: :too_wide_in, width: 129)
    }
    signal_widths = {
      'fit' => 128,
      'fit_in' => 128,
      'too_wide' => 129,
      'too_wide_in' => 129
    }

    sensitive = described_class.send(
      :runtime_sensitive_signal_names,
      assign_map: assign_map,
      signal_widths: signal_widths
    )

    expect(sensitive).not_to include('fit')
    expect(sensitive).to include('too_wide')
  end

  it 'reuses cached simplifications for equivalent slice rewrites over the same wide source' do
    packed = ir::Signal.new(name: :packed, width: 128)
    upper = ir::Signal.new(name: :upper, width: 64)
    lower = ir::Signal.new(name: :lower, width: 64)
    cache = {}
    needs_cache = {}
    assign_map = {
      'packed' => ir::Concat.new(parts: [upper, lower], width: 128)
    }
    slice_a = ir::Slice.new(base: packed, range: 95..32, width: 64)
    slice_b = ir::Slice.new(base: packed, range: 95..32, width: 64)

    result_a = described_class.send(
      :simplify_expr_for_runtime,
      slice_a,
      assign_map: assign_map,
      inlineable_names: Set['packed'],
      cache: cache,
      needs_cache: needs_cache,
      runtime_sensitive_names: Set['packed']
    )
    result_b = described_class.send(
      :simplify_expr_for_runtime,
      slice_b,
      assign_map: assign_map,
      inlineable_names: Set['packed'],
      cache: cache,
      needs_cache: needs_cache,
      runtime_sensitive_names: Set['packed']
    )

    expect(result_a).to be_a(ir::Concat)
    expect(result_b).to equal(result_a)
  end

  it 'does not hoist shared expressions wider than the native runtime ceiling' do
    runtime_mod = described_class.normalize_modules_for_runtime([build_shared_wide_subexpr_runtime_module]).first

    expect(runtime_mod.nets).to all(satisfy { |net| net.width.to_i <= 128 })
    expect(runtime_mod.assigns).to all(satisfy do |assign|
      !assign.target.to_s.include?('_rt_tmp_') || assign.expr.width.to_i <= 128
    end)
  end

  it 'preserves hierarchical intermediate probes even when wide runtime simplification inlines their consumers' do
    runtime_mod = described_class.normalize_modules_for_runtime([build_hierarchical_probe_runtime_module]).first
    assign_targets = runtime_mod.assigns.map { |assign| assign.target.to_s }
    probe_assign = runtime_mod.assigns.find { |assign| assign.target.to_s == 'u__probe' }

    expect(assign_targets).to include('u__probe')
    expect(runtime_mod.nets.map { |net| net.name.to_s }).to include('u__probe')
    expect(probe_assign).not_to be_nil
    expect(expr_signal_names(probe_assign.expr)).not_to include('bus_mux')
  end

  it 'keeps wide bridge assigns live when a >128-bit sequential path still consumes the raw bridge net' do
    runtime_mod = described_class.normalize_modules_for_runtime([build_wide_runtime_bridge_module]).first
    assign_targets = runtime_mod.assigns.map { |assign| assign.target.to_s }
    net_names = runtime_mod.nets.map { |net| net.name.to_s }

    expect(assign_targets).to include('bridge_out', 'bridge__dout', 'bridge__in3')
    expect(net_names).to include('bridge_out', 'bridge__dout', 'bridge__in3')

    q_process = runtime_mod.processes.find { |process| process.name == 'capture' }
    q_assign = Array(q_process&.statements).grep(ir::SeqAssign).find { |stmt| stmt.target.to_s == 'q_reg' }

    expect(q_assign).not_to be_nil
    expect(expr_signal_names(q_assign.expr)).to include('bridge_out')
  end

  it 'serializes wide literal and reset values beyond serde_json integer range as decimal strings' do
    huge_positive = 1 << 111
    huge_negative = -(1 << 111)

    mod = ir::ModuleOp.new(
      name: 'runtime_wide_integer_literals',
      ports: [
        ir::Port.new(name: :y, direction: :out, width: 112, default: huge_positive)
      ],
      nets: [],
      regs: [
        ir::Reg.new(name: :state, width: 112, reset_value: huge_positive)
      ],
      assigns: [
        ir::Assign.new(target: :y, expr: ir::Literal.new(value: huge_negative, width: 112))
      ],
      processes: [],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )

    payload = JSON.parse(described_class.dump(mod))
    runtime_mod = payload.fetch('modules').fetch(0)

    expect(runtime_mod.fetch('ports').fetch(0).fetch('default')).to eq(huge_positive.to_s)
    expect(runtime_mod.fetch('regs').fetch(0).fetch('reset_value')).to eq(huge_positive.to_s)
    expect(runtime_mod.fetch('assigns').fetch(0).fetch('expr').fetch('value')).to eq(huge_negative.to_s)
  end

  it 'can stream the runtime payload to an IO without changing JSON content' do
    mod = build_duplicate_live_assign_runtime_module
    io = StringIO.new

    described_class.dump_to_io(mod, io)

    expect(JSON.parse(io.string)).to eq(JSON.parse(described_class.dump(mod)))
  end
end
