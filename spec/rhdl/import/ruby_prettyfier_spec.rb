# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/ruby_prettyfier"

RSpec.describe RHDL::Import::RubyPrettyfier do
  describe ".format" do
    it "reflows inline keyword hash arguments into multiline sections" do
      source = <<~RUBY
        class PrettyPorts < RHDL::Component
          instance :u_core, "child_core", generics: { WIDTH: "8", DEPTH: "4" }, ports: { clk: :clk, rst_n: :rst_n, nibble: sig(:bus, width: 8)[7..4] }
        end
      RUBY

      formatted = described_class.format(source)

      expect(formatted).to include('instance :u_core, "child_core",')
      expect(formatted).to include("  generics: {")
      expect(formatted).to include('    WIDTH: "8",')
      expect(formatted).to include('    DEPTH: "4"')
      expect(formatted).to include("  ports: {")
      expect(formatted).to include("    clk: :clk,")
      expect(formatted).to include("    rst_n: :rst_n,")
      expect(formatted).to include("    nibble: sig(:bus, width: 8)[7..4]")
      expect(formatted).not_to include('generics: { WIDTH: "8", DEPTH: "4" }')
      expect(formatted).not_to include("ports: { clk: :clk, rst_n: :rst_n, nibble: sig(:bus, width: 8)[7..4] }")
    end

    it "preserves inline calls without keyword hash literals" do
      source = <<~RUBY
        class KeepInline
          assign :flag, lit(1, width: 1, base: "d", signed: false)
        end
      RUBY

      formatted = described_class.format(source)
      expect(formatted).to include("assign :flag,")
      expect(formatted).to include('  lit(1, width: 1, base: "d", signed: false)')
    end

    it "formats process assign calls and nested mux trees across multiple lines" do
      source = <<~RUBY
        class ProcessAssign
          process :p0, sensitivity: [ { edge: "posedge", signal: sig(:clk, width: 1) } ], clocked: true do
            assign(:dout, mux((sig(:sel, width: 1) == lit(1, width: 1, base: "d", signed: false)), sig(:a, width: 8), sig(:b, width: 8)), kind: :nonblocking)
          end
        end
      RUBY

      formatted = described_class.format(source)

      expect(formatted).to include("assign(")
      expect(formatted).to include("  :dout,")
      expect(formatted).to include("  mux(")
      expect(formatted).to include("    (")
      expect(formatted).to include("    kind: :nonblocking")
      expect(formatted).to include("  )")
    end

    it "formats nested case_select keyword hash arguments in assignment expressions" do
      source = <<~RUBY
        class CaseAssign
          assign :out, case_select(sig(:op, width: 2), cases: { 0 => lit(1, width: 8, base: "d"), 1 => lit(2, width: 8, base: "d") }, default: lit(3, width: 8, base: "d"))
        end
      RUBY

      formatted = described_class.format(source)

      expect(formatted).to include("assign :out,")
      expect(formatted).to include("case_select(")
      expect(formatted).to include("cases: {")
      expect(formatted).to include("0 => lit(1, width: 8, base: \"d\"),")
      expect(formatted).to include("1 => lit(2, width: 8, base: \"d\")")
      expect(formatted).to include("default: lit(3, width: 8, base: \"d\")")
      expect(formatted).not_to include("default:(")
    end

    it "formats nested infix boolean trees inside assign expressions across multiple lines" do
      source = <<~RUBY
        class BooleanAssign
          assign :active, ((sig(:a, width: 1) | (sig(:b, width: 1) | sig(:c, width: 1))) & (sig(:d, width: 1) & sig(:e, width: 1)))
        end
      RUBY

      formatted = described_class.format(source)

      expect(formatted).to include("assign :active,")
      expect(formatted).to include("  (")
      expect(formatted).not_to include("assign :active, ((sig(:a, width: 1)")
      expect(formatted.lines.any? { |line| line.length > 160 }).to be(false)
    end

    it "keeps deeply nested mux chains multiline inside assign bodies" do
      nested_mux = (0..40).to_a.reverse.reduce("sig(:fallback, width: 8)") do |tail, index|
        "mux(sig(:s#{index}, width: 1), lit(#{index}, width: 8, base: \"d\"), #{tail})"
      end

      source = <<~RUBY
        class DeepMuxAssign
          assign :out, #{nested_mux}
        end
      RUBY

      formatted = described_class.format(source)

      expect(formatted).to include("assign :out,")
      expect(formatted).to include("  mux(")
      expect(formatted).to match(/\n\s+sig\(:s0, width: 1\),\n/)
      expect(formatted).to include("sig(:fallback, width: 8)")
      expect(formatted.lines.any? { |line| line.length > 220 && line.include?("assign :out,") }).to be(false)
      expect(formatted.lines.any? { |line| line.length > 320 }).to be(false)
    end

    it "formats complex receiver calls and unary wrapped trees in assign expressions" do
      source = <<~RUBY
        class ReceiverAssign
          assign :packed, (~((sig(:a, width: 1) | sig(:b, width: 1)) | (sig(:c, width: 1) | sig(:d, width: 1)))).concat(lit(0, width: 3, base: "d"))
        end
      RUBY

      formatted = described_class.format(source)

      expect(formatted).to include("assign :packed,")
      expect(formatted).to include("~(")
      expect(formatted).to include(").concat(")
      expect(formatted.lines.any? { |line| line.length > 220 }).to be(false)
    end

    it "reformats multi-line assign bodies as a single expression tree" do
      source = <<~RUBY
        class WrappedAssign
          assign :slice,
            (
              mux((sig(:sel, width: 1) | sig(:alt, width: 1)), lit(7, width: 3, base: "h"), lit(2, width: 3, base: "h")) > >
              lit(0, width: nil, base: "d")
            )
        end
      RUBY

      formatted = described_class.format(source)

      expect(formatted).to include("assign :slice,")
      expect(formatted).to include("  (")
      expect(formatted).to include("lit(0, width: nil, base: \"d\")")
      expect(formatted.lines.any? { |line| line.length > 220 }).to be(false)
    end

    it "formats parenthesized call expressions nested under infix operators" do
      source = <<~RUBY
        class ParenthesizedCallAssign
          assign :slice, ((mux((sig(:sel, width: 1) | sig(:alt, width: 1)), lit(7, width: 3, base: "h"), lit(2, width: 3, base: "h"))) > > lit(0, width: nil, base: "d"))
        end
      RUBY

      formatted = described_class.format(source)

      expect(formatted).to include("assign :slice,")
      expect(formatted).to include("lit(0, width: nil, base: \"d\")")
      expect(formatted.lines.any? { |line| line.length > 220 }).to be(false)
    end

    it "formats unwrapped infix expressions with call operands" do
      source = <<~RUBY
        class ShiftAssign
          assign :slice, mux(sig(:sel, width: 1), sig(:a, width: 8), sig(:b, width: 8)) >> lit(0, width: nil, base: "d")
        end
      RUBY

      formatted = described_class.format(source)

      expect(formatted).to include("assign :slice,")
      expect(formatted).to include("mux(")
      expect(formatted).to include("lit(0, width: nil, base: \"d\")")
      expect(formatted.lines.any? { |line| line.length > 220 }).to be(false)
    end
  end
end
