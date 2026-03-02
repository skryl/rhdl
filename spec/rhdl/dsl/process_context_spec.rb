# frozen_string_literal: true

require "spec_helper"

RSpec.describe RHDL::DSL::ProcessContext do
  describe "expression helper methods" do
    let(:process_stub) { double("process", add_statement: nil) }
    subject(:context) { described_class.new(process_stub) }

    it "builds signal/literal/mux/unary helper expressions used by importer output" do
      signal = context.sig(:bus, width: 8)
      literal = context.lit(1, width: 1, base: "b", signed: false)
      mux_expr = context.mux(signal[0], literal, context.lit(0, width: 1))
      case_expr = context.case_select(signal[1..0], cases: { 0 => context.lit(3, width: 8) }, default: context.lit(0, width: 8))
      unary_expr = context.u(:&, signal)
      negated = -signal

      expect(signal).to be_a(RHDL::DSL::SignalRef)
      expect(literal).to be_a(RHDL::DSL::Literal)
      expect(mux_expr).to be_a(RHDL::DSL::TernaryOp)
      expect(case_expr).to be_a(RHDL::DSL::CaseSelect)
      expect(unary_expr).to be_a(RHDL::DSL::UnaryOp)
      expect(unary_expr.op).to eq(:&)
      expect(negated).to be_a(RHDL::DSL::UnaryOp)
      expect(negated.op).to eq(:-)
    end
  end
end
