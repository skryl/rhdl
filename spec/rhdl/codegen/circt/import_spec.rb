# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::Codegen::CIRCT::Import do
  def with_import_expr_caches
    previous_signature_cache = Thread.current[:rhdl_circt_import_expr_signature_cache]
    previous_signature_active = Thread.current[:rhdl_circt_import_expr_signature_active]
    previous_simplify_cache = Thread.current[:rhdl_circt_import_simplify_expr_cache]
    previous_simplify_active = Thread.current[:rhdl_circt_import_simplify_expr_active]
    previous_equivalent_cache = Thread.current[:rhdl_circt_import_expr_equivalent_cache]

    Thread.current[:rhdl_circt_import_expr_signature_cache] = {}
    Thread.current[:rhdl_circt_import_expr_signature_active] = {}
    Thread.current[:rhdl_circt_import_simplify_expr_cache] = {}
    Thread.current[:rhdl_circt_import_simplify_expr_active] = {}
    Thread.current[:rhdl_circt_import_expr_equivalent_cache] = {}
    yield
  ensure
    Thread.current[:rhdl_circt_import_expr_signature_cache] = previous_signature_cache
    Thread.current[:rhdl_circt_import_expr_signature_active] = previous_signature_active
    Thread.current[:rhdl_circt_import_simplify_expr_cache] = previous_simplify_cache
    Thread.current[:rhdl_circt_import_simplify_expr_active] = previous_simplify_active
    Thread.current[:rhdl_circt_import_expr_equivalent_cache] = previous_equivalent_cache
  end

  describe '.from_mlir' do
    it 'imports combinational and sequential modules' do
      mlir = <<~MLIR
        hw.module @adder(%a: i8, %b: i8) -> (y: i8) {
          %eq = comb.icmp eq %a, %b : i8
          %sum = comb.add %a, %b : i8
          %out = comb.mux %eq, %sum, %b : i8
          hw.output %out : i8
        }

        hw.module @regwrap(%d: i8, %clk: i1) -> (q: i8) {
          %q = seq.compreg %d, %clk : i8
          hw.output %q : i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.modules.map(&:name)).to eq(%w[adder regwrap])

      adder = result.modules.find { |m| m.name == 'adder' }
      expect(adder.assigns.length).to eq(1)
      expect(adder.assigns.first.target).to eq('y')
      expect(adder.assigns.first.expr).to be_a(RHDL::Codegen::CIRCT::IR::Mux)
      expect(adder.assigns.first.expr.when_true.left.width).to eq(8)
      expect(adder.assigns.first.expr.when_true.right.width).to eq(8)

      regwrap = result.modules.find { |m| m.name == 'regwrap' }
      expect(regwrap.regs.map(&:name)).to include('q')
      process = regwrap.processes.first
      expect(process).to be_a(RHDL::Codegen::CIRCT::IR::Process)
      expect(process.clocked).to be(true)
      expect(process.clock).to eq('clk')
      expect(process.statements.first).to be_a(RHDL::Codegen::CIRCT::IR::SeqAssign)
      expect(process.statements.first.expr.width).to eq(8)
    end

    it 'imports comb.parity and ignores llhd.halt in strict mode' do
      mlir = <<~MLIR
        hw.module @parity_mod(%a: i2) -> (y: i1) {
          %p = comb.parity %a : i2
          llhd.halt
          hw.output %p : i1
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      mod = result.modules.first
      expect(mod.assigns.length).to eq(1)
      expect(mod.assigns.first.target).to eq('y')
      expect(mod.assigns.first.expr).to be_a(RHDL::Codegen::CIRCT::IR::BinaryOp)
      expect(mod.assigns.first.expr.op).to eq(:^)
    end

    it 'builds balanced mux depth for dynamic array selects' do
      const_lines = (0...64).map { |idx| "  %c#{idx} = hw.constant #{idx} : i8" }.join("\n")
      elem_tokens = (0...64).map { |idx| "%c#{idx}" }.join(', ')

      mlir = <<~MLIR
        hw.module @array_sel(%idx: i6) -> (y: i8) {
      #{const_lines}
          %arr = hw.array_create #{elem_tokens} : i8
          %v = hw.array_get %arr[%idx] : !hw.array<64xi8>, i6
          hw.output %v : i8
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      mod = result.modules.first
      expr = mod.assigns.first.expr

      mux_depth = lambda do |node|
        next 0 unless node.is_a?(RHDL::Codegen::CIRCT::IR::Mux)

        1 + [mux_depth.call(node.when_true), mux_depth.call(node.when_false)].max
      end
      expect(mux_depth.call(expr)).to be <= 20
    end

    it 'imports modules with multiline hw.module signatures' do
      mlir = <<~MLIR
        hw.module @wide_adder(
          %a: i8,
          %b: i8
        ) -> (
          y: i8
        ) {
          %sum = comb.add %a, %b : i8
          hw.output %sum : i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.modules.length).to eq(1)

      mod = result.modules.first
      expect(mod.name).to eq('wide_adder')
      expect(mod.assigns.length).to eq(1)
      expect(mod.assigns.first.target).to eq('y')
      expect(mod.assigns.first.expr).to be_a(RHDL::Codegen::CIRCT::IR::BinaryOp)
      expect(mod.assigns.first.expr.left.width).to eq(8)
      expect(mod.assigns.first.expr.right.width).to eq(8)
    end

    it 'imports hw.module headers with attributes blocks' do
      mlir = <<~MLIR
        hw.module @attr_mod(%a: i8) -> (y: i8) attributes {output_file = "attr_mod.sv"} {
          hw.output %a : i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.modules.length).to eq(1)
      mod = result.modules.first
      expect(mod.name).to eq('attr_mod')
      expect(mod.assigns.length).to eq(1)
      expect(mod.assigns.first.target).to eq('y')
      expect(mod.assigns.first.expr).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(mod.assigns.first.expr.name).to eq('a')
      expect(mod.assigns.first.expr.width).to eq(8)
    end

    it 'imports hw.module headers with multiline attributes blocks' do
      mlir = <<~MLIR
        hw.module @attr_multiline(
          %a: i8
        ) -> (
          y: i8
        )
        attributes {
          output_file = "attr_multiline.sv"
        } {
          hw.output %a : i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.modules.length).to eq(1)
      mod = result.modules.first
      expect(mod.name).to eq('attr_multiline')
      expect(mod.assigns.length).to eq(1)
      expect(mod.assigns.first.target).to eq('y')
      expect(mod.assigns.first.expr).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(mod.assigns.first.expr.name).to eq('a')
      expect(mod.assigns.first.expr.width).to eq(8)
    end

    it 'imports hw.module headers with nested attribute dictionaries' do
      mlir = <<~MLIR
        hw.module @attr_nested(%a: i8) -> (y: i8)
        attributes {
          output_file = "attr_nested.sv",
          sv.module.flags = { keep = true, note = "x,y" }
        } {
          hw.output %a : i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.modules.length).to eq(1)
      mod = result.modules.first
      expect(mod.name).to eq('attr_nested')
      expect(mod.assigns.length).to eq(1)
      expect(mod.assigns.first.target).to eq('y')
      expect(mod.assigns.first.expr).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(mod.assigns.first.expr.name).to eq('a')
      expect(mod.assigns.first.expr.width).to eq(8)
    end

    it 'imports parameterized hw.module headers' do
      mlir = <<~MLIR
        hw.module @param_mod<WIDTH: i32 = 8, ENABLE: i1 = 1>(%a: i8) -> (y: i8) {
          hw.output %a : i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.modules.length).to eq(1)
      mod = result.modules.first
      expect(mod.name).to eq('param_mod')
      expect(mod.parameters).to eq({ 'WIDTH' => 8, 'ENABLE' => 1 })
      expect(mod.assigns.length).to eq(1)
      expect(mod.assigns.first.target).to eq('y')
    end

    it 'imports input/output ports with inline attributes' do
      mlir = <<~MLIR
        hw.module @port_attrs(%a: i8 {sv.namehint = "a"}) -> (y: i8 {sv.namehint = "y"}) {
          hw.output %a : i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.modules.length).to eq(1)
      mod = result.modules.first
      expect(mod.ports.map(&:name)).to eq(%w[a y])
      expect(mod.ports.map(&:width)).to eq([8, 8])
      expect(mod.assigns.length).to eq(1)
      expect(mod.assigns.first.target).to eq('y')
    end

    it 'imports module ports with nested attribute dictionaries' do
      mlir = <<~MLIR
        hw.module @port_nested_attrs(
          %a: i8 {sv.meta = {keep = true, note = "a,b"}},
          %b: i8
        ) -> (
          y: i8 {sv.meta = {tag = "out"}}
        ) {
          %sum = comb.add %a, %b : i8
          hw.output %sum : i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.modules.length).to eq(1)
      mod = result.modules.first
      expect(mod.name).to eq('port_nested_attrs')
      expect(mod.ports.map(&:name)).to eq(%w[a b y])
      expect(mod.ports.map(&:width)).to eq([8, 8, 8])
      expect(mod.assigns.length).to eq(1)
      expect(mod.assigns.first.target).to eq('y')
    end

    it 'imports ports when attribute strings include commas' do
      mlir = <<~MLIR
        hw.module @port_attr_commas(%a: i8 {sv.attributes = "keep,mark"}) -> (y: i8 {sv.attributes = "out,mark"}) {
          hw.output %a : i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.modules.length).to eq(1)
      mod = result.modules.first
      expect(mod.name).to eq('port_attr_commas')
      expect(mod.ports.map(&:name)).to eq(%w[a y])
      expect(mod.ports.map(&:width)).to eq([8, 8])
      expect(mod.assigns.length).to eq(1)
      expect(mod.assigns.first.target).to eq('y')
    end

    it 'imports seq.compreg reset form into muxed sequential assignment' do
      mlir = <<~MLIR
        hw.module @reg_with_reset(%d: i8, %clk: i1, %rst: i1) -> (q: i8) {
          %c0 = hw.constant 0 : i8
          %q = seq.compreg %d, %clk reset %rst, %c0 : i8
          hw.output %q : i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      mod = result.modules.first
      expect(mod.regs.length).to eq(1)
      expect(mod.regs.first.name).to eq('q')
      expect(mod.regs.first.reset_value).to eq(0)

      process = mod.processes.first
      expect(process.reset).to eq('rst')
      expect(process.reset_active_low).to be(false)
      expect(process.reset_values).to eq('q' => 0)
      stmt = process.statements.first
      expect(stmt).to be_a(RHDL::Codegen::CIRCT::IR::SeqAssign)
      expect(stmt.expr).to be_a(RHDL::Codegen::CIRCT::IR::Mux)
      expect(stmt.expr.condition).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(stmt.expr.condition.name).to eq('rst')
      expect(stmt.expr.when_true).to be_a(RHDL::Codegen::CIRCT::IR::Literal)
      expect(stmt.expr.when_true.value).to eq(0)
      expect(stmt.expr.when_false).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(stmt.expr.when_false.name).to eq('d')
    end

    it 'imports seq.compreg with trailing attributes' do
      mlir = <<~MLIR
        hw.module @reg_attr(%d: i8, %clk: i1, %rst: i1) -> (q: i8) {
          %c0 = hw.constant 0 : i8
          %q = seq.compreg %d, %clk reset %rst, %c0 {sv.namehint = "q"} : i8
          hw.output %q : i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.modules.first.regs.first.name).to eq('q')
      expect(result.modules.first.processes.first.statements.first.expr).to be_a(RHDL::Codegen::CIRCT::IR::Mux)
    end

    it 'captures active-low LLHD wait/reset metadata on imported clocked processes' do
      mlir = <<~MLIR
        hw.module @result_yield_bind(in %din : i1, in %clk : i1, in %rst_l : i1, in %se : i1, in %si : i1, out q : i1) {
          %t0 = llhd.constant_time <0ns, 1d, 0e>
          %true = hw.constant true
          %false = hw.constant false
          %q_sig = llhd.sig %false : i1
          %proc:2 = llhd.process -> i1, i1 {
            cf.br ^bb1(%clk, %rst_l, %false, %false : i1, i1, i1, i1)
          ^bb1(%prev_clk: i1, %prev_rst_l: i1, %value: i1, %enable: i1):
            llhd.wait yield (%value, %enable : i1, i1), (%clk, %rst_l : i1, i1), ^bb2(%prev_clk, %prev_rst_l : i1, i1)
          ^bb2(%seen_clk: i1, %seen_rst_l: i1):
            %edge_clk = comb.xor bin %seen_clk, %true : i1
            %posedge_clk = comb.and bin %edge_clk, %clk : i1
            %rst_low = comb.xor bin %rst_l, %true : i1
            %negedge_rst_l = comb.and bin %seen_rst_l, %rst_low : i1
            %trigger = comb.or bin %posedge_clk, %negedge_rst_l : i1
            cf.cond_br %trigger, ^bb3, ^bb1(%clk, %rst_l, %false, %false : i1, i1, i1, i1)
          ^bb3:
            %selected = comb.mux %se, %si, %din : i1
            %next_q = comb.and %rst_l, %selected : i1
            cf.br ^bb1(%clk, %rst_l, %next_q, %true : i1, i1, i1, i1)
          }
          llhd.drv %q_sig, %proc#0 after %t0 if %proc#1 : i1
          %q_value = llhd.prb %q_sig : i1
          hw.output %q_value : i1
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")

      process = result.modules.first.processes.first
      expect(process.clock).to eq('clk')
      expect(process.reset).to eq('rst_l')
      expect(process.reset_active_low).to be(true)
      expect(process.reset_values.values).to eq([0])
    end

    it 'preserves memory IR across one-shot resultful llhd array init processes' do
      mlir = <<~MLIR
        hw.module @resultful_array_init(in %clk : i1, in %rd : i1, out y : i8) {
          %t0 = llhd.constant_time <0ns, 1d, 0e>
          %c0_i32 = hw.constant 0 : i32
          %c1_i32 = hw.constant 1 : i32
          %c2_i32 = hw.constant 2 : i32
          %c0_i8 = hw.constant 0 : i8
          %true = hw.constant true
          %false = hw.constant false
          %zero_arr = hw.aggregate_constant [0 : i8, 0 : i8] : !hw.array<2xi8>
          %q_sig = llhd.sig %c0_i8 : i8
          %mem = llhd.sig %zero_arr : !hw.array<2xi8>
          %proc:2 = llhd.process -> i32, !hw.array<2xi8>, i1 {
            cf.br ^bb1(%c0_i32, %zero_arr, %false : i32, !hw.array<2xi8>, i1)
          ^bb1(%i: i32, %acc: !hw.array<2xi8>, %done: i1):
            %lt = comb.icmp slt %i, %c2_i32 : i32
            cf.cond_br %lt, ^bb2, ^bb3
          ^bb2:
            %idx = comb.extract %i from 0 : (i32) -> i1
            %next = hw.array_inject %acc[%idx], %c0_i8 : !hw.array<2xi8>, i1
            %i_next = comb.add %i, %c1_i32 : i32
            cf.br ^bb1(%i_next, %next, %true : i32, !hw.array<2xi8>, i1)
          ^bb3:
            llhd.halt %i, %acc, %done : i32, !hw.array<2xi8>, i1
          }
          llhd.drv %q_sig, %c0_i8 after %t0 : i8
          llhd.drv %mem, %proc#1 after %t0 if %proc#2 : !hw.array<2xi8>
          %read = hw.array_get %mem[%rd] : !hw.array<2xi8>, i1
          %next_arr = hw.array_inject %mem[%rd], %c0_i8 : !hw.array<2xi8>, i1
          %clock = seq.to_clock %clk
          %mem_next = seq.firreg %next_arr clock %clock : !hw.array<2xi8>
          llhd.drv %mem, %mem_next after %t0 : !hw.array<2xi8>
          hw.output %read : i8
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")

      mod = result.modules.first
      expect(mod.memories.map(&:name)).to eq(['mem'])
      expect(mod.regs.map(&:name)).not_to include('mem')
      expect(mod.write_ports.length).to eq(1)
      y_assign = mod.assigns.find { |assign| assign.target == 'y' }
      expect(y_assign).not_to be_nil
      expect(y_assign.expr).to be_a(RHDL::Codegen::CIRCT::IR::MemoryRead)
      expect(y_assign.expr.memory).to eq('mem')
    end

    it 'captures implicit active-low reset wrappers around seq.compreg state' do
      mlir = <<~MLIR
        hw.module @dffrl_async(in %din : i1, in %clk : i1, in %rst_l : i1, in %se : i1, in %si : i1, out q : i1, out so : i1) {
          %clock = seq.to_clock %clk
          %c0 = hw.constant 0 : i1
          %c1 = hw.constant 1 : i1
          %clk_gate = comb.and %c1, %clk : i1
          %rst_not = comb.xor %rst_l, %c1 : i1
          %rst_gate = comb.and %c0, %rst_not : i1
          %trigger = comb.or %clk_gate, %rst_gate : i1
          %armed = comb.mux %trigger, %c1, %c0 : i1
          %next = comb.and %rst_l, %din : i1
          %selected = comb.mux %trigger, %next, %c0 : i1
          %q_next = comb.mux %armed, %selected, %q : i1
          %q = seq.compreg %q_next, %clock : i1
          hw.output %q, %c0 : i1, i1
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")

      process = result.modules.first.processes.first
      expect(process.clock).to eq('clk')
      expect(process.reset).to eq('rst_l')
      expect(process.reset_active_low).to be(true)
      expect(process.reset_values.values).to eq([0])
    end

    it 'imports seq.to_clock plus seq.firreg as sequential state' do
      mlir = <<~MLIR
        hw.module @firreg_wrap(in %clk: i1, in %d: i8, out q: i8) {
          %clock = seq.to_clock %clk
          %q = seq.firreg %d clock %clock : i8
          hw.output %q : i8
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")

      mod = result.modules.first
      expect(mod.regs.map(&:name)).to include('q')
      process = mod.processes.first
      expect(process.clocked).to be(true)
      expect(process.clock).to eq('clk')
      expect(process.statements.first).to be_a(RHDL::Codegen::CIRCT::IR::SeqAssign)
      expect(process.statements.first.expr).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(process.statements.first.expr.name).to eq('d')
    end

    it 'preserves expression-based seq.to_clock values as real clock nets' do
      mlir = <<~MLIR
        hw.module @inv_clock_wrap(in %clk: i1, in %d: i8, out q: i8) {
          %one = hw.constant 1 : i1
          %nclk = comb.xor %clk, %one : i1
          %clock = seq.to_clock %nclk
          %q = seq.firreg %d clock %clock : i8
          hw.output %q : i8
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")

      mod = result.modules.first
      expect(mod.nets.map(&:name)).to include('clock')
      clock_assign = mod.assigns.find { |assign| assign.target.to_s == 'clock' }
      expect(clock_assign).not_to be_nil
      expect(clock_assign.expr).to be_a(RHDL::Codegen::CIRCT::IR::BinaryOp)
      expect(clock_assign.expr.op).to eq(:^)

      process = mod.processes.first
      expect(process.clocked).to be(true)
      expect(process.clock).to eq('clock')
    end

    it 'imports hw.instance lines and maps instance result values to outputs' do
      mlir = <<~MLIR
        hw.module @child(%a: i8) -> (y: i8) {
          hw.output %a : i8
        }

        hw.module @top(%a: i8) -> (y: i8) {
          %u_y = hw.instance "u" sym @u @child<width: i8 = 8, enable: i1 = 1>(a: %a: i8) -> (y: i8)
          hw.output %u_y : i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.modules.map(&:name)).to include('child', 'top')

      top = result.modules.find { |m| m.name == 'top' }
      expect(top.instances.length).to eq(1)
      inst = top.instances.first
      expect(inst.name).to eq('u')
      expect(inst.module_name).to eq('child')
      expect(inst.parameters).to eq({ 'width' => 8, 'enable' => 1 })
      expect(inst.connections.map(&:direction)).to include(:in, :out)

      out_assign = top.assigns.find { |a| a.target == 'y' }
      expect(out_assign).not_to be_nil
      expect(out_assign.expr).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(out_assign.expr.name).to eq('u_y')
      expect(out_assign.expr.width).to eq(8)
    end

    it 'imports multiline hw.instance operations' do
      mlir = <<~MLIR
        hw.module @child(%a: i8, %b: i8) -> (y: i8) {
          %sum = comb.add %a, %b : i8
          hw.output %sum : i8
        }

        hw.module @top(%a: i8, %b: i8) -> (y: i8) {
          %u_y = hw.instance "u" @child(
            a: %a: i8,
            b: %b: i8
          ) -> (
            y: i8
          )
          hw.output %u_y : i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      top = result.modules.find { |m| m.name == 'top' }
      expect(top).not_to be_nil
      expect(top.instances.length).to eq(1)

      inst = top.instances.first
      expect(inst.name).to eq('u')
      expect(inst.module_name).to eq('child')
      expect(inst.connections.map(&:port_name)).to include('a', 'b', 'y')
      expect(top.assigns.find { |a| a.target == 'y' }).not_to be_nil
    end

    it 'imports hw.instance ports with inline attributes' do
      mlir = <<~MLIR
        hw.module @child(%a: i8) -> (y: i8) {
          hw.output %a : i8
        }

        hw.module @top(%a: i8) -> (y: i8) {
          %u_y = hw.instance "u" @child(a: %a: i8 {sv.namehint = "ain"}) -> (y: i8 {sv.namehint = "yout"})
          hw.output %u_y : i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      top = result.modules.find { |m| m.name == 'top' }
      expect(top).not_to be_nil
      expect(top.instances.length).to eq(1)
      inst = top.instances.first
      expect(inst.connections.map(&:port_name)).to include('a', 'y')

      assign = top.assigns.find { |a| a.target == 'y' }
      expect(assign).not_to be_nil
      expect(assign.expr).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(assign.expr.name).to eq('u_y')
      expect(assign.expr.width).to eq(8)
    end

    it 'imports hw.instance ports with nested attribute dictionaries' do
      mlir = <<~MLIR
        hw.module @child(%a: i8) -> (y: i8) {
          hw.output %a : i8
        }

        hw.module @top(%a: i8) -> (y: i8) {
          %u_y = hw.instance "u" @child(
            a: %a: i8 {sv.meta = {keep = true, note = "in,a"}}
          ) -> (
            y: i8 {sv.meta = {tag = "out"}}
          )
          hw.output %u_y : i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      top = result.modules.find { |m| m.name == 'top' }
      expect(top).not_to be_nil
      expect(top.instances.length).to eq(1)
      inst = top.instances.first
      expect(inst.connections.map(&:port_name)).to include('a', 'y')
      expect(top.assigns.find { |a| a.target == 'y' }).not_to be_nil
    end

    it 'imports comb.extract and comb.concat expressions' do
      mlir = <<~MLIR
        hw.module @slice_concat(%a: i8, %b: i8) -> (y: i12) {
          %a_low = comb.extract %a from 0 : (i8) -> i4
          %cat = comb.concat %a_low, %b : i4, i8
          hw.output %cat : i12
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      mod = result.modules.first
      expect(mod.assigns.length).to eq(1)
      expr = mod.assigns.first.expr
      expect(expr).to be_a(RHDL::Codegen::CIRCT::IR::Concat)
      expect(expr.parts.first).to be_a(RHDL::Codegen::CIRCT::IR::Slice)
      expect(expr.width).to eq(12)
    end

    it 'imports additional arithmetic ops including div/mod/signed shift-right' do
      mlir = <<~MLIR
        hw.module @arith_ops(%a: i8, %b: i8) -> (q: i8, r: i8, s: i8) {
          %qv = comb.divu %a, %b : i8
          %rv = comb.modu %a, %b : i8
          %sv = comb.shr_s %a, %b : i8
          hw.output %qv, %rv, %sv : i8, i8, i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      mod = result.modules.first
      by_target = mod.assigns.each_with_object({}) { |a, h| h[a.target] = a.expr }
      expect(by_target['q'].op).to eq(:/)
      expect(by_target['r'].op).to eq(:%)
      expect(by_target['s'].op).to eq(:'>>')
    end

    it 'imports lines with trailing loc annotations' do
      mlir = <<~MLIR
        hw.module @passthrough(%a: i8) -> (y: i8) {
          hw.output %a : i8 loc("rtl.sv":10:3)
        }

        hw.module @loc_annotated(%a: i8, %b: i8, %clk: i1) -> (y: i8, q: i8) {
          %sum = comb.add %a, %b : i8 loc("rtl.sv":20:5)
          %qv = seq.compreg %sum, %clk : i8 loc("rtl.sv":21:5)
          %iy = hw.instance "u" @passthrough(a: %a: i8) -> (y: i8) loc("rtl.sv":22:5)
          hw.output %iy, %qv : i8, i8 loc("rtl.sv":23:5)
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      mod = result.modules.find { |m| m.name == 'loc_annotated' }
      expect(mod).not_to be_nil
      expect(mod.instances.length).to eq(1)
      expect(mod.regs.map(&:name)).to include('qv')
      expect(mod.assigns.map(&:target)).to include('y', 'q')
    end

    it 'imports lines with trailing attribute dictionaries' do
      mlir = <<~MLIR
        hw.module @attr_line_ops(%a: i8, %b: i8) -> (y: i8) {
          %sum = comb.add %a, %b : i8 {sv.namehint = "sum"}
          hw.output %sum : i8 {sv.namehint = "y"}
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.modules.length).to eq(1)
      mod = result.modules.first
      expect(mod.assigns.length).to eq(1)
      expect(mod.assigns.first.target).to eq('y')
      expect(mod.assigns.first.expr).to be_a(RHDL::Codegen::CIRCT::IR::BinaryOp)
      expect(mod.assigns.first.expr.op).to eq(:+)
      expect(mod.assigns.first.expr.width).to eq(8)
    end

    it 'preserves comb.icmp predicates as comparison operators' do
      mlir = <<~MLIR
        hw.module @cmp_ops(%a: i8, %b: i8) -> (lt: i1, gt: i1, ne: i1) {
          %ltv = comb.icmp ult %a, %b : i8
          %gtv = comb.icmp ugt %a, %b : i8
          %nev = comb.icmp ne %a, %b : i8
          hw.output %ltv, %gtv, %nev : i1, i1, i1
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      mod = result.modules.first
      expect(mod.assigns.length).to eq(3)

      by_target = mod.assigns.each_with_object({}) { |a, h| h[a.target] = a.expr }
      expect(by_target['lt'].op).to eq(:<)
      expect(by_target['gt'].op).to eq(:>)
      expect(by_target['ne'].op).to eq(:'!=')
    end

    it 'warns on unknown comb.icmp predicates and defaults to eq' do
      mlir = <<~MLIR
        hw.module @cmp_unknown(%a: i8, %b: i8) -> (y: i1) {
          %v = comb.icmp weird %a, %b : i8
          hw.output %v : i1
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.modules.first.assigns.first.expr.op).to eq(:==)
      expect(result.diagnostics.any? { |d| d.op == 'comb.icmp' && d.message.include?("Unsupported comb.icmp predicate 'weird'") }).to be(true)
    end

    it 'records warnings for unsupported lines but still succeeds' do
      mlir = <<~MLIR
        hw.module @warn_mod(%a: i1) -> (y: i1) {
          comb.unknown %a : i1
          hw.output %a : i1
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.diagnostics.any? { |d| d.severity.to_s == 'warning' }).to be(true)
      expect(result.diagnostics.map(&:message).join("\n")).to include('Unsupported MLIR line, skipped')
    end

    it 'treats unsupported lines as errors in strict mode' do
      mlir = <<~MLIR
        hw.module @strict_mod(%a: i1) -> (y: i1) {
          comb.unknown %a : i1
          hw.output %a : i1
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(false)
      expect(result.diagnostics.any? { |d| d.op == 'parser' && d.severity.to_s == 'error' }).to be(true)
      expect(result.diagnostics.map(&:message).join("\n")).to include('Unsupported MLIR line, skipped')
    end

    it 'builds an operation census from MLIR text' do
      mlir = <<~MLIR
        hw.module @census(%a: i8, %b: i8) -> (y: i8) {
          %sum = comb.add %a, %b : i8
          %clk_sig = llhd.sig name "clk_sig" %a : i8
          %sampled = llhd.prb %clk_sig : i8
          hw.output %sampled : i8
        }
      MLIR

      census = described_class.op_census(mlir)
      expect(census['hw.module']).to eq(1)
      expect(census['comb.add']).to eq(1)
      expect(census['llhd.sig']).to eq(1)
      expect(census['llhd.prb']).to eq(1)
      expect(census['hw.output']).to eq(1)
    end

    it 'reports errors for invalid ports and unterminated modules' do
      mlir = <<~MLIR
        hw.module @broken(%a i8) -> (y: i8) {
          hw.output %a : i8
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(false)

      messages = result.diagnostics.map(&:message).join("\n")
      expect(messages).to include('Invalid input port syntax')
      expect(messages).to include('Unterminated hw.module @broken')
    end

    it 'accepts hw.output with no values for modules without outputs' do
      mlir = <<~MLIR
        hw.module @no_outputs(%a: i1) {
          hw.output
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.modules.length).to eq(1)
      expect(result.modules.first.assigns).to be_empty
    end

    it 'imports multiline hw.output where values are on following lines' do
      mlir = <<~MLIR
        hw.module @wrapped_output(%a: i8, %b: i8) -> (y: i8) {
          %sum = comb.add %a, %b : i8
          hw.output
            %sum
            : i8
        }
      MLIR

      result = described_class.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.modules.length).to eq(1)

      mod = result.modules.first
      expect(mod.assigns.length).to eq(1)
      expect(mod.assigns.first.target).to eq('y')
      expect(mod.assigns.first.expr).to be_a(RHDL::Codegen::CIRCT::IR::BinaryOp)
      expect(mod.assigns.first.expr.op).to eq(:+)
      expect(mod.assigns.first.expr.width).to eq(8)
    end

    it 'preserves module body parsing across nested llhd.process regions' do
      mlir = <<~MLIR
        hw.module @proc_wrap(%a: i1) -> (y: i1) {
          %false = hw.constant false
          %sig = llhd.sig %false : i1
          llhd.process {
          ^bb0:
            %t0 = llhd.constant_time <0s, 1ns>
            llhd.drv %sig, %a after %t0 : i1
            llhd.wait %t0, ^bb0
          }
          %sample = llhd.prb %sig : i1
          hw.output %sample : i1
        }

        hw.module @after(%a: i1) -> (y: i1) {
          hw.output %a : i1
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true)
      expect(result.modules.map(&:name)).to eq(%w[proc_wrap after])
      expect(result.module_spans['proc_wrap']).not_to be_nil
      expect(result.module_spans['after']).not_to be_nil

      first_mod = result.modules.find { |m| m.name == 'proc_wrap' }
      expect(first_mod.assigns.map(&:target)).to include('sig', 'y')
    end

    it 'imports variadic comb.or/comb.and operations' do
      mlir = <<~MLIR
        hw.module @variadic_logic(%a: i1, %b: i1, %c: i1) -> (yo: i1, ya: i1) {
          %orv = comb.or %a, %b, %c : i1
          %andv = comb.and %a, %b, %c : i1
          hw.output %orv, %andv : i1, i1
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true)
      mod = result.modules.first

      by_target = mod.assigns.each_with_object({}) { |assign, h| h[assign.target] = assign.expr }
      expect(by_target['yo']).to be_a(RHDL::Codegen::CIRCT::IR::BinaryOp)
      expect(by_target['yo'].op).to eq(:|)
      expect(by_target['ya']).to be_a(RHDL::Codegen::CIRCT::IR::BinaryOp)
      expect(by_target['ya'].op).to eq(:&)
    end

    it 'parses comb.icmp operands when rhs has an inline attribute dict' do
      mlir = <<~MLIR
        hw.module @icmp_rhs_attr(%a: i8) -> (y: i1) {
          %c-16_i8 = hw.constant -16 : i8
          %cmp = comb.icmp eq %a, %c-16_i8 {sv.namehint = "cmp_rhs"} : i8
          hw.output %cmp : i1
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true)
      assign = result.modules.first.assigns.first
      expect(assign.target).to eq('y')
      expect(assign.expr).to be_a(RHDL::Codegen::CIRCT::IR::BinaryOp)
      expect(assign.expr.op).to eq(:==)
    end

    it 'accepts untyped boolean hw.constant forms' do
      mlir = <<~MLIR
        hw.module @bool_const_untyped() -> (y: i1) {
          %false = hw.constant false
          hw.output %false : i1
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true)
      assign = result.modules.first.assigns.first
      expect(assign.target).to eq('y')
      expect(assign.expr).to be_a(RHDL::Codegen::CIRCT::IR::Literal)
      expect(assign.expr.value).to eq(0)
      expect(assign.expr.width).to eq(1)
    end

    it 'fails strict closure checks for unresolved instance targets when importing a top' do
      mlir = <<~MLIR
        hw.module @top(%a: i1) -> (y: i1) {
          %child_y = hw.instance "u_child" @child(a: %a: i1) -> (y: i1)
          hw.output %child_y : i1
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true, top: 'top')
      expect(result.success?).to be(false)
      expect(
        result.diagnostics.any? do |diag|
          diag.op == 'import.closure' && diag.message.include?('Unresolved instance target @child')
        end
      ).to be(true)
    end

    it 'allows unresolved instance targets declared as extern modules' do
      mlir = <<~MLIR
        hw.module @top(%a: i1) -> (y: i1) {
          %child_y = hw.instance "u_child" @child(a: %a: i1) -> (y: i1)
          hw.output %child_y : i1
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true, top: 'top', extern_modules: ['child'])
      expect(result.success?).to be(true)
      expect(result.diagnostics.any? { |diag| diag.op == 'import.closure' }).to be(false)
    end

    it 'ignores dbg.variable lines as non-semantic metadata' do
      mlir = <<~MLIR
        hw.module @dbg_ignored(%a: i1) -> (y: i1) {
          dbg.variable "STATE_IDLE", %a : i1
          hw.output %a : i1
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true)
      expect(result.diagnostics.any? { |diag| diag.op == 'parser' }).to be(false)
    end

    it 'parses attr-bearing comb.mux and comb.extract operations' do
      mlir = <<~MLIR
        hw.module @attr_ops(%sel: i1, %a: i8, %b: i8) -> (y: i1) {
          %m = comb.mux %sel, %a, %b {sv.namehint = "mx"} : i8
          %bit = comb.extract %m from 3 {sv.namehint = "bit3"} : (i8) -> i1
          hw.output %bit : i1
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      expect(result.diagnostics.any? { |diag| diag.op == 'parser' }).to be(false)
      assign = result.modules.first.assigns.first
      expect(assign.expr).to be_a(RHDL::Codegen::CIRCT::IR::Slice)
    end

    it 'parses comb.mux bin syntax emitted by circt-verilog' do
      mlir = <<~MLIR
        hw.module @bin_mux(%sel: i1, %a: i8, %b: i8) -> (y: i8) {
          %m = comb.mux bin %sel, %a, %b : i8
          hw.output %m : i8
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      assign = result.modules.first.assigns.first
      expect(assign.expr).to be_a(RHDL::Codegen::CIRCT::IR::Mux)
      expect(assign.expr.condition).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(assign.expr.condition.name).to eq('sel')
    end

    it 'parses attr-bearing llhd.prb operations' do
      mlir = <<~MLIR
        hw.module @attr_prb(%a: i8) -> (y: i8) {
          %sig = llhd.sig %a : i8
          %sample = llhd.prb %sig {sv.namehint = "sample"} : i8
          hw.output %sample : i8
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      expect(result.diagnostics.any? { |diag| diag.op == 'parser' }).to be(false)
      assign = result.modules.first.assigns.first
      expect(assign.expr).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(assign.expr.name).to eq('sig')
    end

    it 'parses comb.replicate by lowering to concat expression' do
      mlir = <<~MLIR
        hw.module @replicate(%a: i1) -> (y: i4) {
          %rep = comb.replicate %a : (i1) -> i4
          hw.output %rep : i4
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      expect(result.diagnostics.any? { |diag| diag.op == 'parser' }).to be(false)
      expr = result.modules.first.assigns.first.expr
      expect(expr).to be_a(RHDL::Codegen::CIRCT::IR::Concat)
      expect(expr.parts.length).to eq(4)
    end

    it 'parses variadic comb.add as folded binary additions' do
      mlir = <<~MLIR
        hw.module @variadic_add(%a: i8, %b: i8, %c: i8) -> (y: i8) {
          %sum = comb.add %a, %b, %c : i8
          hw.output %sum : i8
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      expect(result.diagnostics.none? { |diag| diag.message.include?('Unsupported variadic comb.add') }).to be(true)
      expr = result.modules.first.assigns.first.expr
      expect(expr).to be_a(RHDL::Codegen::CIRCT::IR::BinaryOp)
      expect(expr.op).to eq(:+)
    end

    it 'supports ceq/cne comb.icmp predicates without fallback diagnostics' do
      mlir = <<~MLIR
        hw.module @ceq_ops(%a: i8, %b: i8) -> (yeq: i1, yne: i1) {
          %eqv = comb.icmp ceq %a, %b : i8
          %nev = comb.icmp cne %a, %b : i8
          hw.output %eqv, %nev : i1, i1
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      expect(result.diagnostics.none? { |diag| diag.op == 'comb.icmp' && diag.message.include?('Unsupported') }).to be(true)
      by_target = result.modules.first.assigns.each_with_object({}) { |assign, h| h[assign.target] = assign.expr }
      expect(by_target['yeq'].op).to eq(:==)
      expect(by_target['yne'].op).to eq(:'!=')
    end

    it 'parses hw.array_create and hw.array_get with dynamic index' do
      mlir = <<~MLIR
        hw.module @array_get(%a: i8, %b: i8, %idx: i1) -> (y: i8) {
          %arr = hw.array_create %a, %b : i8
          %sel = hw.array_get %arr[%idx] : !hw.array<2xi8>, i1
          hw.output %sel : i8
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      expect(result.diagnostics.any? { |diag| diag.op == 'parser' }).to be(false)
      expr = result.modules.first.assigns.first.expr
      expect(expr).to be_a(RHDL::Codegen::CIRCT::IR::Mux)

      select_terminal = lambda do |node, selector_value|
        while node.is_a?(RHDL::Codegen::CIRCT::IR::Mux)
          condition = node.condition
          expect(condition).to be_a(RHDL::Codegen::CIRCT::IR::BinaryOp)
          expect(condition.left).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
          expect(condition.left.name).to eq('idx')
          literal_value = condition.right.value
          take_true = case condition.op
                      when :==
                        selector_value == literal_value
                      when :<
                        selector_value < literal_value
                      else
                        raise "unexpected selector op #{condition.op.inspect}"
                      end
          node = take_true ? node.when_true : node.when_false
        end
        node
      end

      expect(select_terminal.call(expr, 0).name).to eq('b')
      expect(select_terminal.call(expr, 1).name).to eq('a')
    end

    it 'parses hw.aggregate_constant and hw.array_get using CIRCT index order' do
      mlir = <<~MLIR
        hw.module @aggregate_array_get(%idx: i2) -> (y: i8) {
          %arr = hw.aggregate_constant [1 : i8, 2 : i8, 3 : i8, 4 : i8] : !hw.array<4xi8>
          %sel = hw.array_get %arr[%idx] : !hw.array<4xi8>, i2
          hw.output %sel : i8
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      expr = result.modules.first.assigns.first.expr

      select_terminal = lambda do |node, selector_value|
        while node.is_a?(RHDL::Codegen::CIRCT::IR::Mux)
          condition = node.condition
          literal_value = condition.right.value
          take_true = condition.op == :< ? selector_value < literal_value : selector_value == literal_value
          node = take_true ? node.when_true : node.when_false
        end
        node
      end

      expect(select_terminal.call(expr, 0).value).to eq(4)
      expect(select_terminal.call(expr, 1).value).to eq(3)
      expect(select_terminal.call(expr, 2).value).to eq(2)
      expect(select_terminal.call(expr, 3).value).to eq(1)
    end

    it 'preserves seq.firreg array state as CIRCT memory IR' do
      mlir = <<~MLIR
        hw.module @array_mem(%clk: i1, %rd: i2, %wr: i2, %we: i1, %din: i8) -> (y: i8) {
          %read = hw.array_get %mem[%rd] : !hw.array<4xi8>, i2
          %next_arr = hw.array_inject %mem[%wr], %din : !hw.array<4xi8>, i2
          %next = comb.mux %we, %next_arr, %mem : !hw.array<4xi8>
          %clock = seq.to_clock %clk
          %mem = seq.firreg %next clock %clock : !hw.array<4xi8>
          hw.output %read : i8
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")

      mod = result.modules.first
      expect(mod.memories.map(&:name)).to eq(['mem'])
      expect(mod.memories.first.depth).to eq(4)
      expect(mod.memories.first.width).to eq(8)
      expect(mod.regs.map(&:name)).not_to include('mem')

      expect(mod.write_ports.length).to eq(1)
      write_port = mod.write_ports.first
      expect(write_port.memory).to eq('mem')
      expect(write_port.clock).to eq('clk')
      expect(write_port.addr).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(write_port.addr.name).to eq('wr')
      expect(write_port.data).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(write_port.data.name).to eq('din')
      expect(write_port.enable).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(write_port.enable.name).to eq('we')

      expect(mod.assigns.length).to eq(1)
      expect(mod.assigns.first.target).to eq('y')
      expect(mod.assigns.first.expr).to be_a(RHDL::Codegen::CIRCT::IR::MemoryRead)
      expect(mod.assigns.first.expr.memory).to eq('mem')
      expect(mod.assigns.first.expr.addr).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(mod.assigns.first.expr.addr.name).to eq('rd')
    end

    it 'recovers packed vector register files as CIRCT memory IR' do
      mlir = <<~MLIR
        hw.module @packed_mem(%clk: i1, %sel: i2, %wr: i2, %we: i1, %din: i8) -> (y: i8) {
          %clock = seq.to_clock %clk
          %c0 = hw.constant 0 : i2
          %c1 = hw.constant 1 : i2
          %c2 = hw.constant 2 : i2
          %c3 = hw.constant 3 : i2
          %slot3 = comb.extract %mem from 24 : (i32) -> i8
          %slot2 = comb.extract %mem from 16 : (i32) -> i8
          %slot1 = comb.extract %mem from 8 : (i32) -> i8
          %slot0 = comb.extract %mem from 0 : (i32) -> i8
          %w3 = comb.icmp eq %wr, %c3 : i2
          %w2 = comb.icmp eq %wr, %c2 : i2
          %w1 = comb.icmp eq %wr, %c1 : i2
          %w0 = comb.icmp eq %wr, %c0 : i2
          %p3 = comb.mux %w3, %din, %slot3 : i8
          %p2 = comb.mux %w2, %din, %slot2 : i8
          %p1 = comb.mux %w1, %din, %slot1 : i8
          %p0 = comb.mux %w0, %din, %slot0 : i8
          %packed = comb.concat %p3, %p2, %p1, %p0 : i8, i8, i8, i8
          %next = comb.mux %we, %packed, %mem : i32
          %mem = seq.compreg %next, %clock : i32
          %read3 = comb.extract %mem from 24 : (i32) -> i8
          hw.output %read3 : i8
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")

      mod = result.modules.first
      expect(mod.memories.map(&:name)).to eq(['mem'])
      expect(mod.memories.first.depth).to eq(4)
      expect(mod.memories.first.width).to eq(8)
      expect(mod.regs.map(&:name)).not_to include('mem')

      expect(mod.write_ports.length).to eq(1)
      expect(mod.write_ports.first.memory).to eq('mem')
      expect(mod.write_ports.first.clock).to eq('clk')
      expect(mod.write_ports.first.enable).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(mod.write_ports.first.enable.name).to eq('we')

      expect(mod.assigns.first.expr).to be_a(RHDL::Codegen::CIRCT::IR::MemoryRead)
      expect(mod.assigns.first.expr.memory).to eq('mem')
      expect(mod.assigns.first.expr.addr).to be_a(RHDL::Codegen::CIRCT::IR::Literal)
      expect(mod.assigns.first.expr.addr.value).to eq(3)
    end

    it 'rewrites dead packed shadow registers back into firmem reads' do
      mlir = <<~MLIR
        hw.module @shadow_mem(%clk: i1) -> (y0: i45, y1: i45) {
          %clock = seq.to_clock %clk
          %mem = seq.firmem 0, 1, undefined, port_order : <32 x 45>
          %c0_i1 = hw.constant 0 : i1
          %c0_i1439 = hw.constant 0 : i1439
          %c0_i1440 = hw.constant 0 : i1440
          %reset_vec = comb.concat %c0_i1439, %c0_i1 : i1439, i1
          %cleared = comb.mux %c0_i1, %reset_vec, %c0_i1440 : i1440
          %next = comb.mux %c0_i1, %cleared, %shadow : i1440
          %shadow = seq.compreg %next, %clock : i1440
          %slot0 = comb.extract %shadow from 0 : (i1440) -> i45
          %slot1 = comb.extract %shadow from 45 : (i1440) -> i45
          hw.output %slot0, %slot1 : i45, i45
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")

      mod = result.modules.first
      expect(mod.memories.map(&:name)).to eq(['mem'])
      expect(mod.regs.map(&:name)).not_to include('shadow')

      by_target = mod.assigns.each_with_object({}) { |assign, acc| acc[assign.target] = assign.expr }
      expect(by_target['y0']).to be_a(RHDL::Codegen::CIRCT::IR::MemoryRead)
      expect(by_target['y0'].memory).to eq('mem')
      expect(by_target['y0'].addr).to be_a(RHDL::Codegen::CIRCT::IR::Literal)
      expect(by_target['y0'].addr.value).to eq(0)

      expect(by_target['y1']).to be_a(RHDL::Codegen::CIRCT::IR::MemoryRead)
      expect(by_target['y1'].memory).to eq('mem')
      expect(by_target['y1'].addr).to be_a(RHDL::Codegen::CIRCT::IR::Literal)
      expect(by_target['y1'].addr.value).to eq(1)
    end

    it 'parses seq.firmem read and write ports as CIRCT memory IR' do
      mlir = <<~MLIR
        hw.module @firmem_mod(%clk: i1, %addr: i2, %waddr: i2, %din: i8, %we: i1) -> (y: i8) {
          %clock = seq.to_clock %clk
          %ram = seq.firmem 0, 1, undefined, port_order : <4 x 8>
          %rd = seq.firmem.read_port %ram[%addr], clock %clock : <4 x 8>
          seq.firmem.write_port %ram[%waddr] = %din, clock %clock enable %we : <4 x 8>
          hw.output %rd : i8
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")

      mod = result.modules.first
      expect(mod.memories.map(&:name)).to eq(['ram'])
      expect(mod.memories.first.depth).to eq(4)
      expect(mod.memories.first.width).to eq(8)
      expect(mod.write_ports.length).to eq(1)
      expect(mod.write_ports.first.memory).to eq('ram')
      expect(mod.write_ports.first.clock).to eq('clk')
      expect(mod.assigns.first.expr).to be_a(RHDL::Codegen::CIRCT::IR::MemoryRead)
      expect(mod.assigns.first.expr.memory).to eq('ram')
      expect(mod.assigns.first.expr.addr).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(mod.assigns.first.expr.addr.name).to eq('addr')
    end

    it 'parses hw.bitcast int<->array forms and llhd.sig.array_get' do
      mlir = <<~MLIR
        hw.module @array_llhd(%a: i16, %idx: i1) -> (y: i8, z: i16) {
          %arr = hw.bitcast %a : (i16) -> !hw.array<2xi8>
          %back = hw.bitcast %arr : (!hw.array<2xi8>) -> i16
          %sig = llhd.sig %arr : !hw.array<2xi8>
          %elem_sig = llhd.sig.array_get %sig[%idx] : <!hw.array<2xi8>>
          %elem = llhd.prb %elem_sig : i8
          hw.output %elem, %back : i8, i16
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")
      expect(result.diagnostics.any? { |diag| diag.op == 'parser' }).to be(false)
      by_target = result.modules.first.assigns.each_with_object({}) { |assign, h| h[assign.target] = assign.expr }
      expect(by_target['y']).to be_a(RHDL::Codegen::CIRCT::IR::Mux)
      expect(by_target['z']).to be_a(RHDL::Codegen::CIRCT::IR::Concat)
    end

    it 'resolves forward SSA references used before definition' do
      mlir = <<~MLIR
        hw.module @forward_ref(%a: i8, %b: i8) -> (y: i1) {
          %use = comb.and %cmp, %c1_i1 : i1
          %c1_i1 = hw.constant 1 : i1
          %cmp = comb.icmp eq %a, %b : i8
          hw.output %use : i1
        }
      MLIR

      result = described_class.from_mlir(mlir, strict: true)
      expect(result.success?).to be(true), result.diagnostics.map(&:message).join("\n")

      expr = result.modules.first.assigns.first.expr
      expect(expr).to be_a(RHDL::Codegen::CIRCT::IR::BinaryOp)
      expect(expr.left).to be_a(RHDL::Codegen::CIRCT::IR::BinaryOp)
      expect(expr.left.op).to eq(:==)
    end

    it 'guards expr_signature and simplify_expr against cyclic expression graphs' do
      with_import_expr_caches do
        cond = RHDL::Codegen::CIRCT::IR::Signal.new(name: 'cond', width: 1)
        lit = RHDL::Codegen::CIRCT::IR::Literal.new(value: 1, width: 1)
        mux = RHDL::Codegen::CIRCT::IR::Mux.new(condition: cond, when_true: lit, when_false: lit, width: 1)
        mux.instance_variable_set(:@when_false, mux)

        signature = described_class.send(:expr_signature, mux)
        simplified = described_class.send(:simplify_expr, mux)

        expect(signature.inspect).to include('cycle')
        expect(simplified).to be_a(RHDL::Codegen::CIRCT::IR::Mux)
      end
    end

    it 'memoizes repeated simplification of shared expression dags' do
      with_import_expr_caches do
        shared = RHDL::Codegen::CIRCT::IR::BinaryOp.new(
          op: :and,
          left: RHDL::Codegen::CIRCT::IR::Signal.new(name: 'a', width: 1),
          right: RHDL::Codegen::CIRCT::IR::Signal.new(name: 'b', width: 1),
          width: 1
        )
        expr = RHDL::Codegen::CIRCT::IR::Mux.new(
          condition: RHDL::Codegen::CIRCT::IR::Signal.new(name: 'sel', width: 1),
          when_true: shared,
          when_false: shared,
          width: 1
        )

        first = described_class.send(:simplify_expr, expr)
        second = described_class.send(:simplify_expr, expr)

        expect(first).to equal(second)
        expect(first).to be_a(RHDL::Codegen::CIRCT::IR::BinaryOp)
        expect(first.op).to eq(:and)
      end
    end
  end
end
