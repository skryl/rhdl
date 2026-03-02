require "spec_helper"

RSpec.describe RHDL::Codegen::Verilog do
  let(:ir) { RHDL::Export::IR }

  describe "import-focused width/range and naming semantics" do
    it "omits explicit empty port connections from generated instance ports" do
      child = Class.new do
        include RHDL::DSL

        input :clk
        input :rst_n
        input :data
        output :full
        output :usedw
      end
      top = Class.new do
        include RHDL::DSL

        input :clk
        input :payload
        input :rst_n
        instance :queue, "child", ports: {
          clk: :clk,
          rst_n: :rst_n,
          data: :payload,
          full: "",
          usedw: ""
        }
      end
      top.instance_variable_set(:@child_class, child)

      verilog = RHDL::Export.verilog(top, top_name: :queue_user)

      expect(verilog).not_to include(".full()")
      expect(verilog).not_to include(".usedw()")
      expect(verilog).to include(".clk(clk)")
      expect(verilog).to include(".rst_n(rst_n)")
      expect(verilog).to include(".data(payload)")
    end

    it "uses empty explicit port lists for instances without ports" do
      module_def = ir::ModuleDef.new(
        name: :empty_ports_top,
        ports: [],
        nets: [],
        regs: [],
        assigns: [],
        processes: [],
        instances: [
          ir::Instance.new(
            name: :u_empty,
            module_name: :blackbox_child,
            connections: []
          )
        ]
      )

      verilog = described_class.generate(module_def)

      expect(verilog).to include("blackbox_child u_empty ();")
    end

    it "uses empty explicit port lists for parameterized instances without ports" do
      module_def = ir::ModuleDef.new(
        name: :empty_ports_param_top,
        ports: [],
        nets: [],
        regs: [],
        assigns: [],
        processes: [],
        instances: [
          ir::Instance.new(
            name: :u_empty_param,
            module_name: :param_child,
            parameters: { WIDTH: 16 },
            connections: []
          )
        ]
      )

      verilog = described_class.generate(module_def)

      expect(verilog).to include("param_child #(.WIDTH(16)) u_empty_param ();")
    end

    it "emits explicit ports for partial connections" do
      module_def = ir::ModuleDef.new(
        name: :partial_ports_top,
        ports: [],
        nets: [
          ir::Net.new(name: :a, width: 8),
          ir::Net.new(name: :b, width: 8)
        ],
        regs: [],
        assigns: [],
        processes: [],
        instances: [
          ir::Instance.new(
            name: :u_partial,
            module_name: :blackbox_child,
            connections: [
              ir::PortConnection.new(port_name: :a_port, signal: ir::Signal.new(name: :a, width: 8)),
              ir::PortConnection.new(port_name: :b_port, signal: ir::Signal.new(name: :b, width: 8))
            ]
          )
        ]
      )

      verilog = described_class.generate(module_def)

      expect(verilog).to include("blackbox_child u_partial (")
      expect(verilog).to include(".a_port(a)")
      expect(verilog).to include(".b_port(b)")
      expect(verilog).not_to include(".*")
    end

    it "emits explicit ports for parameterized instances with partial connections" do
      module_def = ir::ModuleDef.new(
        name: :partial_ports_param_top,
        ports: [],
        nets: [ir::Net.new(name: :clk, width: 1)],
        regs: [],
        assigns: [],
        processes: [],
        instances: [
          ir::Instance.new(
            name: :u_partial_param,
            module_name: :param_child,
            parameters: { WIDTH: 16, LATENCY: 2 },
            connections: [
              ir::PortConnection.new(port_name: :clk_port, signal: ir::Signal.new(name: :clk, width: 1))
            ]
          )
        ]
      )

      verilog = described_class.generate(module_def)

      expect(verilog).to include("param_child #(")
      expect(verilog).to include(".WIDTH(16)")
      expect(verilog).to include(".LATENCY(2)")
      expect(verilog).to include(".clk_port(clk)")
      expect(verilog).not_to include(".*")
    end

    it "renders parameterized widths and symbolic ranges" do
      module_def = ir::ModuleDef.new(
        name: :import_top,
        parameters: { WIDTH: 8 },
        ports: [
          ir::Port.new(name: :data_in, direction: :in, width: :WIDTH),
          ir::Port.new(name: :slice_out, direction: :out, width: ("WIDTH_MSB".."WIDTH_LSB"))
        ],
        nets: [],
        regs: [],
        assigns: [
          ir::Assign.new(
            target: :slice_out,
            expr: ir::Slice.new(
              base: ir::Signal.new(name: :data_in, width: :WIDTH),
              range: ("WIDTH_MSB".."WIDTH_LSB"),
              width: :WIDTH
            )
          )
        ],
        processes: []
      )

      verilog = described_class.generate(module_def)

      expect(verilog).to include("input [WIDTH-1:0] data_in")
      expect(verilog).to include("output [WIDTH_MSB:WIDTH_LSB] slice_out")
      expect(verilog).to include("assign slice_out = data_in[WIDTH_MSB:WIDTH_LSB];")
    end

    it "preserves explicitly escaped identifiers for import-generated names" do
      module_def = ir::ModuleDef.new(
        name: "\\Top.Core ",
        ports: [
          ir::Port.new(name: "\\in.valid ", direction: :in, width: 1),
          ir::Port.new(name: "\\module ", direction: :out, width: 1)
        ],
        nets: [],
        regs: [],
        assigns: [
          ir::Assign.new(
            target: "\\module ",
            expr: ir::Signal.new(name: "\\in.valid ", width: 1)
          )
        ],
        processes: []
      )

      verilog = described_class.generate(module_def)

      expect(verilog).to match(/module \\Top\.Core \(/)
      expect(verilog).to match(/input \\in\.valid /)
      expect(verilog).to match(/output \\module /)
      expect(verilog).to match(/assign \\module \s*=\s*\\in\.valid \s*;/)
    end
  end
end
