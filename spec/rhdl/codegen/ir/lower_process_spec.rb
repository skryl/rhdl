require 'spec_helper'

RSpec.describe RHDL::Codegen::IR::Lower do
  describe 'process assignment modes' do
    it 'marks combinational assignments as blocking through nested if statements' do
      component = Class.new do
        include RHDL::DSL

        input :sel, width: 1
        input :d, width: 8
        output :y, width: 8

        process :comb_logic, sensitivity: %i[sel d] do
          if_stmt(RHDL::DSL::SignalRef.new(:sel, width: 1) == 1) do
            assign(:y, :d)
          end
        end
      end

      ir = described_class.new(component, top_name: 'comb_logic_test').build
      process = ir.processes.first

      expect(process.clocked).to be(false)
      expect(process.sensitivity_list).to eq(%i[sel d])

      if_stmt = process.statements.first
      assign = if_stmt.then_statements.first

      expect(assign).to be_a(RHDL::Codegen::IR::SeqAssign)
      expect(assign.nonblocking).to be(false)
    end

    it 'retains full clocked sensitivity and non-blocking assignment mode' do
      component = Class.new do
        include RHDL::DSL

        input :clk, width: 1
        input :rst, width: 1
        input :d, width: 8
        output :q, width: 8

        process :seq_logic, sensitivity: %i[clk rst], clocked: true do
          assign(:q, :d)
        end
      end

      ir = described_class.new(component, top_name: 'seq_logic_test').build
      process = ir.processes.first

      expect(process.clocked).to be(true)
      expect(process.clock).to eq(:clk)
      expect(process.sensitivity_list).to eq(%i[clk rst])

      assign = process.statements.first
      expect(assign.nonblocking).to be(true)
    end

    it 'marks DSL initial processes as IR initial processes' do
      component = Class.new do
        include RHDL::DSL

        output :q, width: 8

        process :init_logic, initial: true do
          assign(:q, lit(0, width: 8, base: "d"), kind: :blocking)
        end
      end

      ir = described_class.new(component, top_name: 'init_logic_test').build
      process = ir.processes.first

      expect(process.clocked).to be(false)
      expect(process.initial).to be(true)
      expect(process.sensitivity_list).to eq([])
      expect(process.statements.first).to be_a(RHDL::Codegen::IR::SeqAssign)
    end

    it 'treats import-declared wires as regs when they are assigned in processes' do
      component = Class.new do
        include RHDL::DSL

        self._ports = []
        self._signals = []
        self._constants = []
        self._processes = []
        self._assignments = []
        self._instances = []
        self._generics = []

        def self._import_decl_kinds
          { _unused_ok: :wire }
        end

        signal :_unused_ok, width: 1
        process :init_logic, initial: true do
          assign(:_unused_ok, lit(0, width: 1, base: "d"), kind: :blocking)
        end
      end

      ir = described_class.new(component, top_name: 'wire_proc_assign').build
      expect(ir.nets.map(&:name)).not_to include(:_unused_ok)
      reg = ir.regs.find { |entry| entry.name == :_unused_ok }
      expect(reg).not_to be_nil
      expect(reg.width).to eq(1)
    end

    it 'infers combinational sensitivity from statement reads when source list is empty' do
      component = Class.new do
        include RHDL::DSL

        input :a
        input :b
        output :y

        process :comb_logic do
          assign(:y, RHDL::DSL::BinaryOp.new(:|, RHDL::DSL::SignalRef.new(:a, width: 1), RHDL::DSL::SignalRef.new(:b, width: 1)))
        end
      end

      ir = described_class.new(component, top_name: 'inferred_sensitivity').build
      process = ir.processes.first

      expect(process.clocked).to be(false)
      expect(process.sensitivity_list).to contain_exactly(:a, :b)
    end

    it 'excludes process-local assignment targets from inferred combinational sensitivity' do
      component = Class.new do
        include RHDL::DSL

        input :a
        output :y
        signal :tmp

        process :comb_logic do
          assign(:tmp, :a)
          assign(:y, :tmp)
        end
      end

      ir = described_class.new(component, top_name: 'inferred_sensitivity_targets').build
      process = ir.processes.first

      expect(process.clocked).to be(false)
      expect(process.sensitivity_list).to eq([:a])
    end

    it 'lowers descending static bit slices with non-nil width' do
      component = Class.new do
        include RHDL::DSL

        input :bus, width: 32
        output :out, width: 32

        assign :out, RHDL::DSL::SignalRef.new(:bus, width: 32)[31..0]
      end

      ir = described_class.new(component, top_name: 'slice_width_test').build
      assign = ir.assigns.find { |entry| entry.target == :out }

      expect(assign).not_to be_nil
      expect(assign.expr).to be_a(RHDL::Codegen::IR::Slice)
      expect(assign.expr.width).to eq(32)
    end

    it 'folds constant-expression bit-slice bounds into static IR slices' do
      component = Class.new do
        include RHDL::DSL

        input :bus, width: 30
        output :out, width: 11

        lower = lit(0x13, width: 32, base: "h", signed: false)
        assign :out, sig(:bus, width: 30)[lower..(lower + 10)]
      end

      ir = described_class.new(component, top_name: 'slice_const_fold_test').build
      assign = ir.assigns.find { |entry| entry.target == :out }

      expect(assign).not_to be_nil
      expect(assign.expr).to be_a(RHDL::Codegen::IR::Slice)
      expect(assign.expr.range).to eq(29..19)
      expect(assign.expr.width).to eq(11)
    end

    it 're-applies declaration lsb offsets for imported component bit slices' do
      component = Class.new do
        include RHDL::DSL

        self._ports = []
        self._signals = []
        self._constants = []
        self._processes = []
        self._assignments = []
        self._instances = []
        self._generics = []

        def self._import_decl_kinds
          { bus: :wire, out: :wire }
        end

        signal :bus, width: (31..2)
        signal :out, width: (31..2)

        assign :out, sig(:bus, width: 30)[29..19]
      end

      ir = described_class.new(component, top_name: 'slice_import_offset').build
      assign = ir.assigns.find { |entry| entry.target == :out }

      expect(assign).not_to be_nil
      expect(assign.expr).to be_a(RHDL::Codegen::IR::Resize)
      expect(assign.expr.width).to eq(30)
      expect(assign.expr.expr).to be_a(RHDL::Codegen::IR::Slice)
      expect(assign.expr.expr.range).to eq(31..21)
      expect(assign.expr.expr.width).to eq(11)
    end

    it 'lowers static bit-slice assignment targets to merged base-register writes' do
      component = Class.new do
        include RHDL::DSL

        input :clk
        input :din, width: 12
        output :out, width: 32

        process :seq_logic, sensitivity: %i[clk], clocked: true do
          assign(RHDL::DSL::SignalRef.new(:out, width: 32)[15..4], RHDL::DSL::SignalRef.new(:din, width: 12))
        end
      end

      ir = described_class.new(component, top_name: 'slice_target_test').build
      process = ir.processes.first
      assign = process.statements.first

      expect(assign).to be_a(RHDL::Codegen::IR::SeqAssign)
      expect(assign.target).to eq(:out)
      expect(assign.expr).to be_a(RHDL::Codegen::IR::BinaryOp)
      expect(assign.nonblocking).to be(true)
    end

    it 'lowers reduction unary conditions to single-bit IR width' do
      component = Class.new do
        include RHDL::DSL

        input :save_readburst, width: 2
        output :out, width: 8

        assign :out, RHDL::DSL::TernaryOp.new(
          RHDL::DSL::UnaryOp.new(:&, RHDL::DSL::SignalRef.new(:save_readburst, width: 2)),
          RHDL::DSL::Literal.new(1, width: 8, base: 'd'),
          RHDL::DSL::Literal.new(0, width: 8, base: 'd')
        )
      end

      ir = described_class.new(component, top_name: 'reduction_cond_test').build
      assign = ir.assigns.find { |entry| entry.target == :out }

      expect(assign).not_to be_nil
      expect(assign.expr).to be_a(RHDL::Codegen::IR::Mux)
      expect(assign.expr.condition.width).to eq(1)
    end

    it 'lowers expression-level case_select to IR::Case' do
      component = Class.new do
        include RHDL::DSL

        input :op, width: 2
        output :y, width: 8

        assign :y, case_select(
          sig(:op, width: 2),
          cases: {
            0 => lit(1, width: 8, base: "d"),
            1 => lit(2, width: 8, base: "d")
          },
          default: lit(3, width: 8, base: "d")
        )
      end

      ir = described_class.new(component, top_name: 'case_select_lowering').build
      assign = ir.assigns.find { |entry| entry.target == :y }

      expect(assign).not_to be_nil
      expect(assign.expr).to be_a(RHDL::Codegen::IR::Case)
      expect(assign.expr.selector).to be_a(RHDL::Codegen::IR::Signal)
      expect(assign.expr.selector.name).to eq(:op)
      expect(assign.expr.cases.keys).to include([0], [1])
      expect(assign.expr.default).to be_a(RHDL::Codegen::IR::Literal)
      expect(assign.expr.width).to eq(8)
    end

    it 'keeps shift-left operand width without widening to a wide shift literal' do
      component = Class.new do
        include RHDL::DSL

        input :addr, width: 7
        output :y, width: 7

        assign :y, (sig(:addr, width: 7) >> lit(1, width: 32, base: "h", signed: true))
      end

      ir = described_class.new(component, top_name: 'shift_width_shape').build
      assign = ir.assigns.find { |entry| entry.target == :y }

      expect(assign).not_to be_nil
      expect(assign.expr).to be_a(RHDL::Codegen::IR::BinaryOp)
      expect(assign.expr.op).to eq(:>>)
      expect(assign.expr.width).to eq(7)
      expect(assign.expr.left).to be_a(RHDL::Codegen::IR::Signal)
      expect(assign.expr.left.width).to eq(7)
      expect(assign.expr.right).to be_a(RHDL::Codegen::IR::Literal)
      expect(assign.expr.right.width).to eq(32)
      expect(assign.expr.right.base).to eq("h")
      expect(assign.expr.right.signed).to be(true)
    end

    it 'preserves intrinsic unsized literal width for imported components in HIR mode' do
      component = Class.new do
        include RHDL::DSL

        self._ports = []
        self._signals = []
        self._constants = []
        self._processes = []
        self._assignments = []
        self._instances = []
        self._generics = []

        def self._import_decl_kinds
          { y: :wire }
        end

        output :y, width: 8
        assign :y, lit(1, width: nil, base: "d", signed: false)
      end

      ir = described_class.new(component, top_name: 'import_hir_literal_width', mode: :hir).build
      assign = ir.assigns.find { |entry| entry.target == :y }

      expect(assign).not_to be_nil
      expect(assign.expr).to be_a(RHDL::Codegen::IR::Resize)
      expect(assign.expr.width).to eq(8)
      expect(assign.expr.expr).to be_a(RHDL::Codegen::IR::Literal)
      expect(assign.expr.expr.width).to eq(1)
    end

    it 'preserves component instances in lowered IR' do
      component = Class.new do
        include RHDL::DSL

        input :a
        output :y

        instance :u_child, "child_mod", ports: { din: :a, dout: :y }, generics: { WIDTH: 1 }
      end

      ir = described_class.new(component, top_name: 'instance_test').build

      expect(ir.instances.length).to eq(1)
      instance = ir.instances.first
      expect(instance.name).to eq("u_child")
      expect(instance.module_name).to eq("child_mod")
      expect(instance.parameters).to eq({ WIDTH: 1 })
      expect(instance.connections.map { |conn| [conn.port_name, conn.signal] }).to include([:din, "a"], [:dout, "y"])
    end

    it 'propagates component generics into lowered module parameters' do
      component = Class.new do
        include RHDL::DSL

        generic :WIDTH, default: "32'sh8"
        generic :DEPTH, default: 16
        input :a, width: 8
        output :y, width: 8
        assign :y, :a
      end

      ir = described_class.new(component, top_name: 'module_parameters').build

      expect(ir.parameters).to include(WIDTH: "32'sh8", DEPTH: 16)
    end

    it 'auto-connects omitted instance ports by matching parent signal names' do
      child = Class.new do
        include RHDL::DSL

        input :din
        output :dout
        assign :dout, :din
      end

      component = Class.new do
        include RHDL::DSL

        input :din
        output :dout

        instance :u_child, child
      end

      ir = described_class.new(component, top_name: 'instance_implicit_ports').build
      instance = ir.instances.first

      expect(instance).not_to be_nil
      expect(instance.connections.map { |conn| [conn.port_name, conn.signal] }).to include([:din, "din"], [:dout, "dout"])
      expect(instance.connections.map(&:direction)).to include(:in, :out)
    end

    it 'classifies instance-output-driven signals as nets and preserves connection directions' do
      child = Class.new do
        include RHDL::DSL

        input :din
        output :dout
        assign :dout, :din
      end

      component = Class.new do
        include RHDL::DSL

        input :a
        output :y
        signal :mid

        instance :u_child, child, ports: { din: :a, dout: :mid }
        assign :y, :mid
      end

      ir = described_class.new(component, top_name: 'instance_net_classification').build

      expect(ir.nets.map(&:name)).to include(:mid)
      expect(ir.regs.map(&:name)).not_to include(:mid)

      connection_directions = ir.instances.first.connections.each_with_object({}) do |conn, memo|
        memo[conn.port_name] = conn.direction
      end
      expect(connection_directions[:din]).to eq(:in)
      expect(connection_directions[:dout]).to eq(:out)
    end

    it 'resolves string instance module types for output-net classification' do
      stub_const('LowerStringChild', Class.new do
        include RHDL::DSL

        input :din
        output :dout
        assign :dout, :din
      end)

      component = Class.new do
        include RHDL::DSL

        input :a
        output :y
        signal :mid

        instance :u_child, 'lower_string_child', ports: { din: :a, dout: :mid }
        assign :y, :mid
      end

      ir = described_class.new(component, top_name: 'instance_string_resolution').build

      expect(ir.nets.map(&:name)).to include(:mid)
      expect(ir.regs.map(&:name)).not_to include(:mid)

      connection_directions = ir.instances.first.connections.each_with_object({}) do |conn, memo|
        memo[conn.port_name] = conn.direction
      end
      expect(connection_directions[:dout]).to eq(:out)
    end

    it 'classifies implicitly connected string-instance outputs as nets' do
      stub_const('LowerImplicitChild', Class.new do
        include RHDL::DSL

        input :din
        output :mid
        assign :mid, :din
      end)

      component = Class.new do
        include RHDL::DSL

        input :din
        output :y
        signal :mid

        instance :u_child, 'lower_implicit_child'
        assign :y, :mid
      end

      ir = described_class.new(component, top_name: 'instance_implicit_string_resolution').build

      expect(ir.nets.map(&:name)).to include(:mid)
      expect(ir.regs.map(&:name)).not_to include(:mid)
      expect(ir.instances.first.connections.map { |conn| [conn.port_name, conn.signal] }).to include([:din, "din"], [:mid, "mid"])
    end

    it 'propagates signal defaults into IR register reset values' do
      component = Class.new do
        include RHDL::DSL

        signal :tmp_state, width: 8, default: 3
      end

      ir = described_class.new(component, top_name: 'signal_default_reset').build
      reg = ir.regs.find { |entry| entry.name.to_s == "tmp_state" }

      expect(reg).not_to be_nil
      expect(reg.reset_value).to eq(3)
    end

    it 'does not propagate defaults as reset values for assign-driven signals' do
      component = Class.new do
        include RHDL::DSL

        signal :tmp_wire, width: 1, default: 1
        assign :tmp_wire, RHDL::DSL::Literal.new(0, width: 1, base: 'd')
      end

      ir = described_class.new(component, top_name: 'assign_driven_default').build
      reg = ir.regs.find { |entry| entry.name.to_s == "tmp_wire" }
      net = ir.nets.find { |entry| entry.name.to_s == "tmp_wire" }

      expect(reg).to be_nil
      expect(net).not_to be_nil
    end

    it 'propagates port defaults into lowered IR ports' do
      component = Class.new do
        include RHDL::DSL

        output :flag, default: 1
      end

      ir = described_class.new(component, top_name: 'port_default').build
      port = ir.ports.find { |entry| entry.name.to_s == "flag" }

      expect(port).not_to be_nil
      expect(port.default).to eq(1)
    end

    it 'materializes constant empty-sensitivity combinational processes as assigns' do
      component = Class.new do
        include RHDL::DSL

        output :done, default: 0

        process :const_done, sensitivity: [] do
          assign(:done, RHDL::DSL::Literal.new(1, width: 1, base: 'h'), kind: :blocking)
        end
      end

      ir = described_class.new(component, top_name: 'constant_process_assign').build

      expect(ir.processes).to eq([])
      assign = ir.assigns.find { |entry| entry.target.to_s == "done" }
      expect(assign).not_to be_nil
      expect(assign.expr).to be_a(RHDL::Codegen::IR::Literal)
      expect(assign.expr.value).to eq(1)
    end

    it 'lowers statement-level case_stmt into IR::CaseStmt nodes' do
      component = Class.new do
        include RHDL::DSL

        input :op, width: 2
        output :y, width: 8

        process :comb_logic, sensitivity: [:op] do
          case_stmt(sig(:op, width: 2)) do
            when_value(lit(0, width: 2, base: "d", signed: false)) do
              assign(:y, lit(1, width: 8, base: "d", signed: false), kind: :blocking)
            end

            when_value(lit(1, width: 2, base: "d", signed: false)) do
              assign(:y, lit(2, width: 8, base: "d", signed: false), kind: :blocking)
            end

            default do
              assign(:y, lit(3, width: 8, base: "d", signed: false), kind: :blocking)
            end
          end
        end
      end

      ir = described_class.new(component, top_name: 'case_stmt_lowering').build
      process = ir.processes.first

      expect(process).not_to be_nil
      case_stmt = process.statements.first
      expect(case_stmt).to be_a(RHDL::Codegen::IR::CaseStmt)
      expect(case_stmt.branches.length).to eq(2)
      expect(case_stmt.default_statements.first).to be_a(RHDL::Codegen::IR::SeqAssign)
    end

    it 'lowers statement-level case_stmt when selector is a composite expression' do
      component = Class.new do
        include RHDL::DSL

        input :a, width: 2
        input :b, width: 2
        output :y, width: 2

        process :comb_logic, sensitivity: [:a, :b] do
          selector = sig(:a, width: 2).concat(sig(:b, width: 2))

          case_stmt(selector) do
            when_value(lit(0, width: 4, base: "d", signed: false)) do
              assign(:y, lit(1, width: 2, base: "d", signed: false), kind: :blocking)
            end

            default do
              assign(:y, lit(2, width: 2, base: "d", signed: false), kind: :blocking)
            end
          end
        end
      end

      ir = described_class.new(component, top_name: 'case_stmt_composite_selector').build
      process = ir.processes.first

      expect(process).not_to be_nil
      case_stmt = process.statements.first
      expect(case_stmt).to be_a(RHDL::Codegen::IR::CaseStmt)
      expect(case_stmt.selector).to be_a(RHDL::Codegen::IR::Concat)
    end

    it 'unrolls static for_loop statements during lowering' do
      component = Class.new do
        include RHDL::DSL

        input :a, width: 8
        output :y, width: 8
        signal :i, width: 32

        process :comb_loop, sensitivity: [:a] do
          for_loop(:i, 0..2) do
            assign(:y, sig(:a, width: 8), kind: :blocking)
          end
        end
      end

      ir = described_class.new(component, top_name: 'for_stmt_lowering').build
      process = ir.processes.first

      expect(process).not_to be_nil
      expect(process.statements.length).to eq(3)
      expect(process.statements).to all(be_a(RHDL::Codegen::IR::SeqAssign))
    end

    it 'lowers dynamic bit-slice assignment targets into merged base-register writes' do
      component = Class.new do
        include RHDL::DSL

        input :clk
        input :idx, width: 5
        input :din, width: 4
        output :out, width: 32

        process :seq_logic, sensitivity: [:clk], clocked: true do
          dynamic_range = sig(:idx, width: 5)..(sig(:idx, width: 5) + lit(3, width: 5, base: "d", signed: false))
          assign(sig(:out, width: 32)[dynamic_range], sig(:din, width: 4))
        end
      end

      ir = described_class.new(component, top_name: 'dynamic_slice_target_lowering').build
      process = ir.processes.first
      assign = process.statements.first

      expect(assign).to be_a(RHDL::Codegen::IR::SeqAssign)
      expect(assign.target).to eq(:out)
      expect(assign.expr).to be_a(RHDL::Codegen::IR::BinaryOp)
      expect(assign.nonblocking).to be(true)
    end

    it "restores implicit instance connections when child class is namespace-scoped" do
      namespace = Module.new
      namespace.module_eval do
        class ImportedChild < RHDL::Component
          include RHDL::DSL

          input :clk
          output :q
        end

        class ImportedTop < RHDL::Component
          include RHDL::DSL

          input :clk
          output :q
          instance :child_inst, "child"
        end
      end

      top = namespace.const_get(:ImportedTop)
      ir = described_class.new(top, top_name: "imported_top").build
      child_instance = ir.instances.find { |instance| instance.name == "child_inst" }

      expect(child_instance).not_to be_nil
      expect(child_instance.connections.map { |connection| connection.port_name }.sort).to eq(%i[clk q].sort)
      expect(child_instance.connections.map { |connection| connection.signal }).to all(be_a(String).or(be_a(Symbol)))
      mapped = child_instance.connections.each_with_object({}) { |connection, memo| memo[connection.port_name] = connection.signal }
      expect(mapped).to eq({ clk: "clk", q: "q" })
    end
  end
end
