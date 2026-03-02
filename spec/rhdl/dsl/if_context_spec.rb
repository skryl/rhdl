# frozen_string_literal: true

require "spec_helper"

RSpec.describe RHDL::DSL::IfContext do
  describe "expression helper methods" do
    subject(:context) { described_class.new(RHDL::DSL::IfStatement.new(true)) }

    it "builds signal/literal/mux/unary helper expressions for branch bodies" do
      signal = context.sig(:flag, width: 1)
      literal = context.lit(0, width: 1, base: "b")
      mux_expr = context.mux(signal, literal, context.lit(1, width: 1, base: "b"))
      case_expr = context.case_select(signal, cases: { 0 => literal }, default: context.lit(1, width: 1, base: "b"))
      unary_expr = context.u(:|, signal)

      expect(signal).to be_a(RHDL::DSL::SignalRef)
      expect(literal).to be_a(RHDL::DSL::Literal)
      expect(mux_expr).to be_a(RHDL::DSL::TernaryOp)
      expect(case_expr).to be_a(RHDL::DSL::CaseSelect)
      expect(unary_expr).to be_a(RHDL::DSL::UnaryOp)
      expect(unary_expr.op).to eq(:|)
    end
  end
end

RSpec.describe RHDL::DSL::BlockCollector do
  describe "expression helper methods" do
    subject(:collector) { described_class.new([]) }

    it "builds signal/literal/mux/unary helper expressions for collected blocks" do
      signal = collector.sig(:bus, width: 8)
      literal = collector.lit(15, width: 8, base: "h")
      mux_expr = collector.mux(signal[0], literal, collector.lit(0, width: 8))
      case_expr = collector.case_select(signal[1..0], cases: { 0 => literal }, default: collector.lit(1, width: 8))
      unary_expr = collector.u(:&, signal)

      expect(signal).to be_a(RHDL::DSL::SignalRef)
      expect(literal).to be_a(RHDL::DSL::Literal)
      expect(mux_expr).to be_a(RHDL::DSL::TernaryOp)
      expect(case_expr).to be_a(RHDL::DSL::CaseSelect)
      expect(unary_expr).to be_a(RHDL::DSL::UnaryOp)
      expect(unary_expr.op).to eq(:&)
    end
  end
end
