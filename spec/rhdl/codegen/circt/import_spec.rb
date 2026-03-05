# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::Codegen::CIRCT::Import do
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
      expect(result.modules.first.assigns.first.expr).to be_a(RHDL::Codegen::CIRCT::IR::Mux)
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
  end
end
