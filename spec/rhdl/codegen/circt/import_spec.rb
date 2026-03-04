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
  end
end
