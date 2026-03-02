require "spec_helper"

module RHDL
  module Spec
    class HIRLIRSplitComponent
      include RHDL::DSL

      input :clk, width: 1
      input :idx, width: 4
      input :din, width: 1
      output :out, width: 8

      process :seq_logic, sensitivity: [:clk], clocked: true do
        assign(RHDL::DSL::SignalRef.new(:out, width: 8)[RHDL::DSL::SignalRef.new(:idx, width: 4)], :din)
      end
    end

    class HIRScalarIndexedFallbackComponent
      include RHDL::DSL

      input :clk, width: 1
      input :idx, width: 1
      input :din, width: 1
      output :flag, width: 1

      process :seq_logic, sensitivity: [:clk], clocked: true do
        assign(RHDL::DSL::SignalRef.new(:flag, width: 1)[RHDL::DSL::SignalRef.new(:idx, width: 1)], :din)
      end
    end

    class HIRDynamicSliceFallbackComponent
      include RHDL::DSL

      input :clk, width: 1
      input :cnt, width: 3
      input :din, width: 8
      output :out, width: 16

      process :seq_logic, sensitivity: [:clk], clocked: true do
        cnt_ref = RHDL::DSL::SignalRef.new(:cnt, width: 3)
        low = cnt_ref << 1
        high = low + 7
        assign(RHDL::DSL::SignalRef.new(:out, width: 16)[high..low], :din)
      end
    end

    class HIRMemoryLikeIndexedComponent
      include RHDL::DSL

      input :clk, width: 1
      input :wr_en, width: 1
      input :addr, width: 6
      input :din, width: 10
      output :dout, width: 10

      signal :mem, width: 1

      process :write_logic, sensitivity: [:clk], clocked: true do
        if_stmt(RHDL::DSL::SignalRef.new(:wr_en, width: 1)) do
          assign(
            RHDL::DSL::SignalRef.new(:mem, width: 1)[RHDL::DSL::SignalRef.new(:addr, width: 6)],
            :din
          )
        end
      end

      process :read_logic, sensitivity: [:addr], clocked: false do
        assign(
          :dout,
          RHDL::DSL::SignalRef.new(:mem, width: 1)[RHDL::DSL::SignalRef.new(:addr, width: 6)]
        )
      end
    end

    class HIRDynamicSliceExprComponent
      include RHDL::DSL

      input :idx, width: 5
      input :bus, width: 32
      output :out, width: 8

      assign :out, RHDL::DSL::SignalRef.new(:bus, width: 32)[(RHDL::DSL::SignalRef.new(:idx, width: 5) + 7)..RHDL::DSL::SignalRef.new(:idx, width: 5)]
    end
  end
end

RSpec.describe "HIR/LIR split" do
  let(:component) { RHDL::Spec::HIRLIRSplitComponent }

  it "preserves indexed lvalue targets in HIR lowering" do
    hir = RHDL::Codegen::HIR::Lower.new(component, top_name: "hir_target_preserve").build
    process = hir.processes.fetch(0)
    stmt = process.statements.fetch(0)

    expect(stmt).to be_a(RHDL::Codegen::IR::SeqAssign)
    expect(stmt.target).to be_a(RHDL::DSL::BitSelect)
  end

  it "normalizes indexed lvalue targets in LIR lowering" do
    lir = RHDL::Codegen::LIR::Lower.new(component, top_name: "lir_target_lower").build
    process = lir.processes.fetch(0)
    stmt = process.statements.fetch(0)

    expect(stmt).to be_a(RHDL::Codegen::IR::SeqAssign)
    expect(stmt.target).to eq(:out)
    expect(stmt.expr).to be_a(RHDL::Codegen::IR::BinaryOp)
  end

  it "routes Verilog export through the HIR path" do
    verilog = RHDL::Codegen.verilog(component, top_name: "hir_export_top")
    expect(verilog).to include("out[idx] <= din;")
  end

  it "falls back to normalized assignment for scalar indexed lvalues in HIR" do
    hir = RHDL::Codegen::HIR::Lower.new(
      RHDL::Spec::HIRScalarIndexedFallbackComponent,
      top_name: "hir_scalar_indexed_fallback"
    ).build
    stmt = hir.processes.fetch(0).statements.fetch(0)
    expect(stmt.target).to eq(:flag)
  end

  it "falls back to normalized assignment for dynamic slice lvalues in HIR" do
    hir = RHDL::Codegen::HIR::Lower.new(
      RHDL::Spec::HIRDynamicSliceFallbackComponent,
      top_name: "hir_dynamic_slice_fallback"
    ).build
    stmt = hir.processes.fetch(0).statements.fetch(0)
    expect(stmt.target).to eq(:out)
  end

  it "preserves dynamic slice expressions in HIR and Verilog export" do
    hir = RHDL::Codegen::HIR::Lower.new(
      RHDL::Spec::HIRDynamicSliceExprComponent,
      top_name: "hir_dynamic_slice_expr"
    ).build
    assign = hir.assigns.find { |entry| entry.target == :out }
    expect(assign).not_to be_nil
    expect(assign.expr).to be_a(RHDL::Codegen::IR::DynamicSlice)

    verilog = RHDL::Codegen.verilog(
      RHDL::Spec::HIRDynamicSliceExprComponent,
      top_name: "hir_dynamic_slice_expr"
    )
    expect(verilog).to include("out = bus[")
    expect(verilog).to include(":")
    expect(verilog).not_to include("out = ((bus >>")
  end

  it "lowers memory-like indexed reads to IR::MemoryRead in HIR" do
    hir = RHDL::Codegen::HIR::Lower.new(
      RHDL::Spec::HIRMemoryLikeIndexedComponent,
      top_name: "hir_memory_like_indexed"
    ).build

    read_process = hir.processes.find { |process| process.name.to_s == "read_logic" }
    expect(read_process).not_to be_nil

    stmt = read_process.statements.fetch(0)
    expect(stmt.target).to eq(:dout)
    expect(stmt.expr).to be_a(RHDL::Codegen::IR::MemoryRead)
    expect(stmt.expr.memory.to_s).to eq("mem")
  end

  it "exports memory-like indexed writes/reads as array access in Verilog" do
    verilog = RHDL::Codegen.verilog(
      RHDL::Spec::HIRMemoryLikeIndexedComponent,
      top_name: "hir_memory_like_export"
    )

    expect(verilog).to include("reg [9:0] mem [0:63];")
    expect(verilog).to include("mem[addr] <= din;")
    expect(verilog).to include("dout = mem[addr];")
  end
end
