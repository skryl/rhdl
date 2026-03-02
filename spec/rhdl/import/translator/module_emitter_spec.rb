# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/translator"

RSpec.describe RHDL::Import::Translator::ModuleEmitter do
  let(:mapped_module) do
    load_import_fixture_json("translator", "mapped_modules.json").fetch("modules").first
  end

  describe ".emit" do
    it "emits operator-style DSL expressions instead of nested AST constructor trees" do
      source = described_class.emit(
        "name" => "operator_style",
        "ports" => [
          { "direction" => "input", "name" => "a", "width" => 8 },
          { "direction" => "input", "name" => "b", "width" => 8 },
          { "direction" => "input", "name" => "sel", "width" => 1 },
          { "direction" => "output", "name" => "y", "width" => 8 }
        ],
        "statements" => [
          {
            "kind" => "continuous_assign",
            "target" => { "kind" => "identifier", "name" => "y" },
            "value" => {
              "kind" => "ternary",
              "condition" => { "kind" => "identifier", "name" => "sel" },
              "true_expr" => {
                "kind" => "binary",
                "operator" => "+",
                "left" => { "kind" => "identifier", "name" => "a" },
                "right" => { "kind" => "identifier", "name" => "b" }
              },
              "false_expr" => {
                "kind" => "concat",
                "parts" => [
                  { "kind" => "identifier", "name" => "a" },
                  {
                    "kind" => "replication",
                    "count" => { "kind" => "number", "value" => 1, "base" => 10, "width" => nil, "signed" => false },
                    "value" => { "kind" => "identifier", "name" => "sel" }
                  }
                ]
              }
            }
          }
        ]
      )

      expect(source).to include("assign :y, mux(")
      expect(source).to include("(sig(:a, width: 8) + sig(:b, width: 8))")
      expect(source).to include(".concat(")
      expect(source).to include(".replicate(")
      expect(source).not_to include("RHDL::DSL::BinaryOp.new(")
      expect(source).not_to include("RHDL::DSL::Concatenation.new(")
      expect(source).not_to include("RHDL::DSL::Replication.new(")
      assign_line = source.each_line.find { |line| line.include?("assign :y,") }
      expect(assign_line).to include("assign :y, mux(")
      expect(assign_line).not_to include("RHDL::DSL::")
    end

    it "lifts ternary selector chains into case_select expressions" do
      source = described_class.emit(
        "name" => "case_select_style",
        "ports" => [
          { "direction" => "input", "name" => "op", "width" => 2 },
          { "direction" => "output", "name" => "y", "width" => 8 }
        ],
        "statements" => [
          {
            "kind" => "continuous_assign",
            "target" => { "kind" => "identifier", "name" => "y" },
            "value" => {
              "kind" => "ternary",
              "condition" => {
                "kind" => "binary",
                "operator" => "==",
                "left" => { "kind" => "identifier", "name" => "op" },
                "right" => { "kind" => "number", "value" => 0, "base" => 10, "width" => nil, "signed" => false }
              },
              "true_expr" => { "kind" => "number", "value" => 1, "base" => 10, "width" => 8, "signed" => false },
              "false_expr" => {
                "kind" => "ternary",
                "condition" => {
                  "kind" => "binary",
                  "operator" => "==",
                  "left" => { "kind" => "identifier", "name" => "op" },
                  "right" => { "kind" => "number", "value" => 1, "base" => 10, "width" => nil, "signed" => false }
                },
                "true_expr" => { "kind" => "number", "value" => 2, "base" => 10, "width" => 8, "signed" => false },
                "false_expr" => { "kind" => "number", "value" => 3, "base" => 10, "width" => 8, "signed" => false }
              }
            }
          }
        ]
      )

      expect(source).to include("assign :y, case_select(")
      expect(source).to include("cases: { 0 =>")
      expect(source).to include("1 =>")
      expect(source).to include("default:")
      expect(source).not_to include("assign :y, mux(")
    end

    it "does not emit per-module helper DSL methods" do
      source = described_class.emit(
        "name" => "helper_methods"
      )

      expect(source).not_to include("def self.sig(name, width: 1)")
      expect(source).not_to include("def self.lit(value, width: nil, base: nil, signed: false)")
      expect(source).not_to include("def self.mux(condition, when_true, when_false)")
      expect(source).not_to include("def self.u(op, operand)")
    end

    it "emits source preserving module name and shape for ports/signals/body constructs" do
      source = described_class.emit(mapped_module)

      expect(source).to include("self._ports = []")
      expect(source).to include("self._instances = []")
      expect(source).to include("# source_module: top_core")
      expect(source).to include("  # Parameters")
      expect(source).to include("generic :WIDTH, default: 8")
      expect(source).to include("generic :RESET_VALUE, default: 0")

      expect(source).to include("  # Ports")
      expect(source).to include("input :clk")
      expect(source).to include("input :a, width: :WIDTH")
      expect(source).to include("output :y, width: :WIDTH")

      expect(source).to include("  # Signals")
      expect(source).to include("signal :sum, width: :WIDTH")
      expect(source).to include("signal :acc, width: :WIDTH")

      expect(source).to include("  # Assignments")
      expect(source).to include('assign :sum, "a + b"')
      expect(source).to include("  # Processes")
      expect(source).to include("process :comb_logic")
      expect(source).to include("process :seq_logic")
      expect(source).to include("  # Instances")

      expect(source).to include('instance :u_child, "child_unit",')
      expect(source).to include("generics: {")
      expect(source).to include("WIDTH: :WIDTH")
      expect(source).to include("ports: {")
      expect(source).not_to include("clk: :clk")
      expect(source).not_to include("rst_n: :rst_n")
      expect(source).to include("data_in: :sum")
      expect(source).to include("data_out: :y")
    end

    it "emits declarations, statement assigns, and array-style instance connections" do
      source = described_class.emit(
        "name" => "statement_and_instance",
        "declarations" => [
          {
            "kind" => "wire",
            "name" => "bus_data",
            "width" => {
              "msb" => { "kind" => "number", "value" => 31 },
              "lsb" => { "kind" => "number", "value" => 0 }
            }
          }
        ],
        "statements" => [
          {
            "kind" => "continuous_assign",
            "target" => { "kind" => "identifier", "name" => "bus_data" },
            "value" => {
              "kind" => "concat",
              "parts" => [
                { "kind" => "identifier", "name" => "a" },
                { "kind" => "identifier", "name" => "b" }
              ]
            }
          }
        ],
        "instances" => [
          {
            "name" => "u_logic",
            "module_name" => "logic_block",
            "connections" => [
              { "port" => "clk", "signal" => { "kind" => "identifier", "name" => "clk" } },
              { "port" => "data", "signal" => { "kind" => "identifier", "name" => "bus_data" } },
              { "port" => "unused", "signal" => nil }
            ]
          }
        ]
      )

      expect(source).to include("signal :bus_data, width: 32")
      expect(source).to include("assign :bus_data, sig(:a, width: 1).concat(sig(:b, width: 1))")
      expect(source).to include('instance :u_logic, "logic_block",')
      expect(source).to include("ports: {")
      expect(source).not_to include("clk: :clk")
      expect(source).to include("data: :bus_data")
      expect(source).to include('unused: ""')
    end

    it "preserves explicit scalar ranges from mapped width hashes" do
      source = described_class.emit(
        "name" => "scalar_range_preserve",
        "ports" => [
          {
            "direction" => "input",
            "name" => "flag_in",
            "width" => {
              "msb" => { "kind" => "number", "value" => 0 },
              "lsb" => { "kind" => "number", "value" => 0 }
            }
          }
        ],
        "declarations" => [
          {
            "kind" => "wire",
            "name" => "flag_wire",
            "width" => {
              "msb" => { "kind" => "number", "value" => 0 },
              "lsb" => { "kind" => "number", "value" => 0 }
            }
          }
        ]
      )

      expect(source).to include("input :flag_in, width: (0..0)")
      expect(source).to include("signal :flag_wire, width: (0..0)")
    end

    it "renders instance port expressions with DSL operators instead of quoted Verilog text" do
      source = described_class.emit(
        "name" => "instance_port_expressions",
        "declarations" => [
          {
            "kind" => "wire",
            "name" => "bus_data",
            "width" => {
              "msb" => { "kind" => "number", "value" => 15 },
              "lsb" => { "kind" => "number", "value" => 0 }
            }
          }
        ],
        "signals" => [
          { "name" => "lhs", "width" => 8 },
          { "name" => "rhs", "width" => 8 }
        ],
        "instances" => [
          {
            "name" => "u_logic",
            "module_name" => "logic_block",
            "connections" => [
              {
                "port" => "mix",
                "signal" => {
                  "kind" => "binary",
                  "operator" => "|",
                  "left" => { "kind" => "identifier", "name" => "lhs" },
                  "right" => { "kind" => "identifier", "name" => "rhs" }
                }
              },
              {
                "port" => "slice",
                "signal" => {
                  "kind" => "slice",
                  "base" => { "kind" => "identifier", "name" => "bus_data" },
                  "msb" => { "kind" => "number", "value" => 7, "base" => 10, "width" => nil, "signed" => false },
                  "lsb" => { "kind" => "number", "value" => 4, "base" => 10, "width" => nil, "signed" => false }
                }
              },
              {
                "port" => "bit",
                "signal" => {
                  "kind" => "index",
                  "base" => { "kind" => "identifier", "name" => "bus_data" },
                  "index" => { "kind" => "number", "value" => "4", "base" => "h", "width" => 3, "signed" => false }
                }
              },
              { "port" => "raw", "signal" => { "kind" => "identifier", "name" => "clk" } }
            ]
          }
        ]
      )

      expect(source).to include("mix: (sig(:lhs, width: 8) | sig(:rhs, width: 8))")
      expect(source).to include("slice: sig(:bus_data, width: 16)[7..4]")
      expect(source).to include("bit: sig(:bus_data, width: 16)[4]")
      expect(source).to include("raw: :clk")
      expect(source).not_to include('mix: "(lhs | rhs)"')
      expect(source).not_to include('slice: "bus_data[7:4]"')
      expect(source).not_to include("bit: sig(:bus_data, width: 16)[lit(")
    end

    it "emits process-level case_stmt and for_loop blocks for mapped statements" do
      source = described_class.emit(
        "name" => "process_case_for",
        "ports" => [
          { "direction" => "input", "name" => "op", "width" => 2 },
          { "direction" => "output", "name" => "y", "width" => 8 }
        ],
        "processes" => [
          {
            "kind" => "always",
            "domain" => "combinational",
            "sensitivity" => [{ "edge" => "any", "signal" => { "kind" => "identifier", "name" => "op" } }],
            "statements" => [
              {
                "kind" => "case",
                "selector" => { "kind" => "identifier", "name" => "op" },
                "items" => [
                  {
                    "values" => [{ "kind" => "number", "value" => 0, "base" => 10, "width" => 2, "signed" => false }],
                    "body" => [
                      {
                        "kind" => "blocking_assign",
                        "target" => { "kind" => "identifier", "name" => "y" },
                        "value" => { "kind" => "number", "value" => 1, "base" => 10, "width" => 8, "signed" => false }
                      }
                    ]
                  }
                ],
                "default_body" => [
                  {
                    "kind" => "blocking_assign",
                    "target" => { "kind" => "identifier", "name" => "y" },
                    "value" => { "kind" => "number", "value" => 0, "base" => 10, "width" => 8, "signed" => false }
                  }
                ]
              },
              {
                "kind" => "for",
                "variable" => "i",
                "range" => { "from" => 0, "to" => 3 },
                "body" => [
                  {
                    "kind" => "blocking_assign",
                    "target" => { "kind" => "identifier", "name" => "y" },
                    "value" => { "kind" => "number", "value" => 1, "base" => 10, "width" => 8, "signed" => false }
                  }
                ]
              }
            ]
          }
        ]
      )

      expect(source).to include("case_stmt(")
      expect(source).to include("when_value(")
      expect(source).to include("default do")
      expect(source).to include("for_loop(:i, 0..3) do")
    end

    it "preserves simple initial-static assignments as an explicit initial process" do
      source = described_class.emit(
        "name" => "initial_defaults",
        "ports" => [
          { "direction" => "output", "name" => "flag" }
        ],
        "declarations" => [
          { "kind" => "reg", "name" => "counter" }
        ],
        "processes" => [
          {
            "kind" => "initial",
            "domain" => "initial",
            "statements" => [
              {
                "kind" => "blocking_assign",
                "target" => { "kind" => "identifier", "name" => "flag" },
                "value" => { "kind" => "number", "value" => 1, "base" => 10, "width" => nil, "signed" => false }
              },
              {
                "kind" => "blocking_assign",
                "target" => { "kind" => "identifier", "name" => "counter" },
                "value" => { "kind" => "number", "value" => 3, "base" => 10, "width" => nil, "signed" => false }
              }
            ]
          }
        ]
      )

      expect(source).to include("output :flag")
      expect(source).to include("signal :counter")
      expect(source).to include("process :initial_block_0")
      expect(source).to include("assign(:flag, lit(1, width: nil, base: \"d\", signed: false), kind: :blocking)")
      expect(source).to include("assign(:counter, lit(3, width: nil, base: \"d\", signed: false), kind: :blocking)")
    end

    it "does not synthesize extra assigns for undriven output defaults" do
      source = described_class.emit(
        "name" => "output_default_assigns",
        "ports" => [
          { "direction" => "output", "name" => "done", "width" => 1, "default" => 1 },
          { "direction" => "output", "name" => "ready", "width" => 4, "default" => 9 }
        ]
      )

      expect(source).to include("output :done, default: 1")
      expect(source).to include("output :ready, width: 4, default: 9")
      expect(source).not_to include("assign :done")
      expect(source).not_to include("assign :ready")
    end

    it "emits readable layout with section spacing and descriptive auto process names" do
      source = described_class.emit(
        "name" => "layout_readable",
        "ports" => [
          { "direction" => "input", "name" => "clk" },
          { "direction" => "input", "name" => "rst_n" },
          { "direction" => "input", "name" => "a" },
          { "direction" => "output", "name" => "y" }
        ],
        "statements" => [
          {
            "kind" => "continuous_assign",
            "target" => { "kind" => "identifier", "name" => "y" },
            "value" => { "kind" => "identifier", "name" => "a" }
          }
        ],
        "processes" => [
          {
            "sensitivity" => [{ "edge" => "posedge", "signal" => { "kind" => "identifier", "name" => "clk" } }],
            "statements" => [
              {
                "kind" => "nonblocking_assign",
                "target" => { "kind" => "identifier", "name" => "y" },
                "value" => { "kind" => "identifier", "name" => "a" }
              }
            ]
          },
          {
            "domain" => "combinational",
            "sensitivity" => [],
            "statements" => [
              {
                "kind" => "blocking_assign",
                "target" => { "kind" => "identifier", "name" => "y" },
                "value" => { "kind" => "identifier", "name" => "a" }
              }
            ]
          }
        ]
      )

      expect(source).to include("  # Ports")
      expect(source).to include("  # Assignments")
      expect(source).to include("  # Processes")
      expect(source).to include("process :sequential_posedge_clk")
      expect(source).to include("process :combinational_logic_1")
      expect(source).not_to include("process :process_0")
      expect(source).not_to include("# assign ")
      expect(source).not_to include("# process ")
      expect(source).to include("assign :y, sig(:a, width: 1)\n\n  # Processes")
    end

    it "lays out process and instance argument hashes across multiple lines" do
      source = described_class.emit(
        "name" => "hash_layout",
        "ports" => [
          { "direction" => "input", "name" => "clk" },
          { "direction" => "input", "name" => "din" },
          { "direction" => "output", "name" => "dout" }
        ],
        "processes" => [
          {
            "domain" => "clocked",
            "sensitivity" => [{ "edge" => "posedge", "signal" => { "kind" => "identifier", "name" => "clk" } }],
            "statements" => []
          }
        ],
        "instances" => [
          {
            "name" => "u0",
            "module_name" => "child_mod",
            "parameters" => { "WIDTH" => "8", "DEPTH" => "4" },
            "connections" => [
              { "port" => "clk", "signal" => { "kind" => "identifier", "name" => "clk" } },
              { "port" => "din", "signal" => { "kind" => "identifier", "name" => "din" } },
              { "port" => "dout", "signal" => { "kind" => "identifier", "name" => "dout" } }
            ]
          }
        ]
      )

      expect(source).to include("process :sequential_posedge_clk,")
      expect(source).to include("sensitivity: [\n      { edge: \"posedge\", signal: sig(:clk, width: 1) }\n    ],")
      expect(source).to include("instance :u0, \"child_mod\",")
      expect(source).to include("generics: {\n      WIDTH: \"8\",\n      DEPTH: \"4\"\n    }")
      expect(source).not_to include("ports: {")
    end

    it "maps integer declarations into DSL signal declarations for procedural temps" do
      source = described_class.emit(
        "name" => "integer_decl",
        "declarations" => [
          { "kind" => "integer", "name" => "i" }
        ],
        "processes" => [
          {
            "name" => "p0",
            "domain" => "clocked",
            "sensitivity" => [],
            "statements" => [
              {
                "kind" => "blocking_assign",
                "target" => { "kind" => "identifier", "name" => "i" },
                "value" => { "kind" => "number", "value" => 0, "base" => 10, "width" => 3, "signed" => false }
              }
            ]
          }
        ]
      )

      expect(source).to include("signal :i")
      expect(source).to include("assign(:i")
    end

    it "adds undeclared procedural assignment targets as signals" do
      source = described_class.emit(
        "name" => "implicit_proc_target",
        "processes" => [
          {
            "name" => "p0",
            "domain" => "clocked",
            "sensitivity" => [],
            "statements" => [
              {
                "kind" => "blocking_assign",
                "target" => { "kind" => "identifier", "name" => "tmp_i" },
                "value" => { "kind" => "number", "value" => 0, "base" => 10, "width" => 3, "signed" => false }
              }
            ]
          }
        ]
      )

      expect(source).to include("signal :tmp_i")
      expect(source).to include("assign(:tmp_i")
    end

    it "declares nested case/for procedural targets and infers their widths" do
      source = described_class.emit(
        "name" => "nested_proc_targets",
        "processes" => [
          {
            "name" => "p0",
            "domain" => "clocked",
            "sensitivity" => [],
            "statements" => [
              {
                "kind" => "case",
                "selector" => { "kind" => "identifier", "name" => "state" },
                "items" => [
                  {
                    "values" => [{ "kind" => "number", "value" => 0, "base" => 10, "width" => 1, "signed" => false }],
                    "body" => [
                      {
                        "kind" => "nonblocking_assign",
                        "target" => { "kind" => "identifier", "name" => "cnt" },
                        "value" => { "kind" => "number", "value" => 0, "base" => 10, "width" => 2, "signed" => false }
                      }
                    ]
                  }
                ]
              },
              {
                "kind" => "for",
                "variable" => "i",
                "range" => { "from" => 0, "to" => 1 },
                "body" => [
                  {
                    "kind" => "blocking_assign",
                    "target" => { "kind" => "identifier", "name" => "match" },
                    "value" => { "kind" => "number", "value" => 3, "base" => 10, "width" => 3, "signed" => false }
                  }
                ]
              }
            ]
          }
        ]
      )

      expect(source).to include("signal :cnt, width: 2")
      expect(source).to include("signal :match, width: 3")
      expect(source).to include("assign(:cnt")
      expect(source).to include("assign(:match")
    end

    it "normalizes decimal numeric bases in emitted expressions" do
      source = described_class.emit(
        "name" => "number_base_norm",
        "declarations" => [
          {
            "kind" => "wire",
            "name" => "in_sig",
            "width" => {
              "msb" => { "kind" => "number", "value" => 31 },
              "lsb" => { "kind" => "number", "value" => 0 }
            }
          }
        ],
        "statements" => [
          {
            "kind" => "continuous_assign",
            "target" => { "kind" => "identifier", "name" => "out_sig" },
            "value" => {
              "kind" => "slice",
              "base" => { "kind" => "identifier", "name" => "in_sig" },
              "msb" => {
                "kind" => "binary",
                "operator" => "+",
                "left" => { "kind" => "number", "value" => 0, "base" => 10, "width" => 32 },
                "right" => { "kind" => "number", "value" => 1, "base" => 10, "width" => nil }
              },
              "lsb" => { "kind" => "number", "value" => 0, "base" => 10, "width" => 32 }
            }
          }
        ]
      )

      expect(source).to include("assign :out_sig, sig(:in_sig, width: 32)[")
      expect(source).to include("[1..0]")
      expect(source).not_to include("'101")
    end

    it "honors explicit numeric bases when folding static slice bounds" do
      source = described_class.emit(
        "name" => "hex_slice_bounds",
        "declarations" => [
          {
            "kind" => "wire",
            "name" => "cache",
            "width" => {
              "msb" => { "kind" => "number", "value" => 63 },
              "lsb" => { "kind" => "number", "value" => 0 }
            }
          }
        ],
        "statements" => [
          {
            "kind" => "continuous_assign",
            "target" => { "kind" => "identifier", "name" => "slice_out" },
            "value" => {
              "kind" => "slice",
              "base" => { "kind" => "identifier", "name" => "cache" },
              "msb" => {
                "kind" => "binary",
                "operator" => "+",
                "left" => { "kind" => "number", "value" => "38", "base" => "h", "width" => 32, "signed" => false },
                "right" => { "kind" => "number", "value" => 7, "base" => 10, "width" => nil, "signed" => false }
              },
              "lsb" => { "kind" => "number", "value" => "38", "base" => "h", "width" => 32, "signed" => false }
            }
          }
        ]
      )

      expect(source).to include("[63..56]")
      expect(source).not_to include("[45..38]")
    end

    it "folds constant target slice bounds to avoid dynamic Ruby ranges" do
      source = described_class.emit(
        "name" => "target_slice_bounds",
        "ports" => [
          {
            "name" => "vga_rd_seg",
            "direction" => "input",
            "width" => {
              "msb" => { "kind" => "number", "value" => 5 },
              "lsb" => { "kind" => "number", "value" => 0 }
            }
          }
        ],
        "processes" => [
          {
            "name" => "p0",
            "domain" => "clocked",
            "sensitivity" => [],
            "statements" => [
              {
                "kind" => "nonblocking_assign",
                "target" => {
                  "kind" => "slice",
                  "base" => { "kind" => "identifier", "name" => "ram_addr" },
                  "msb" => {
                    "kind" => "binary",
                    "operator" => "+",
                    "left" => { "kind" => "number", "value" => 13, "base" => 10, "width" => nil, "signed" => false },
                    "right" => { "kind" => "number", "value" => 11, "base" => 10, "width" => nil, "signed" => false }
                  },
                  "lsb" => { "kind" => "number", "value" => 13, "base" => 10, "width" => nil, "signed" => false }
                },
                "value" => {
                  "kind" => "concat",
                  "parts" => [
                    { "kind" => "number", "value" => 62, "base" => 10, "width" => 6, "signed" => false },
                    { "kind" => "identifier", "name" => "vga_rd_seg" }
                  ]
                }
              }
            ]
          }
        ]
      )

      assign_line = source.each_line.find { |line| line.include?("assign(") }
      expect(assign_line).to include("sig(:ram_addr, width: 25)[24..13]")
      expect(assign_line).not_to include("((sig(:")
    end

    it "renders AST parameter defaults as Verilog literal strings" do
      source = described_class.emit(
        "name" => "parameter_defaults",
        "parameters" => [
          {
            "name" => "STATE_IDLE",
            "default" => {
              "kind" => "number",
              "value" => "0",
              "base" => "h",
              "width" => 3,
              "signed" => false
            }
          }
        ]
      )

      expect(source).to include('generic :STATE_IDLE, default: "3\'h0"')
    end

    it "uses inferred widths for undeclared indexed table signals" do
      source = described_class.emit(
        "name" => "inferred_table_width",
        "signals" => [
          { "name" => "tab_sig", "width" => nil },
          { "name" => "idx_sig", "width" => 8 }
        ],
        "statements" => [
          {
            "kind" => "continuous_assign",
            "target" => { "kind" => "identifier", "name" => "out_sig" },
            "value" => {
              "kind" => "index",
              "base" => { "kind" => "identifier", "name" => "tab_sig" },
              "index" => { "kind" => "identifier", "name" => "idx_sig" }
            }
          }
        ]
      )

      expect(source).to include("signal :tab_sig, width: 256")
      expect(source).to include("assign :out_sig, sig(:tab_sig, width: 256)[sig(:idx_sig, width: 8)]")
    end

    it "infers declaration widths from indexed instance connection expressions" do
      source = described_class.emit(
        "name" => "inferred_instance_connection_widths",
        "declarations" => [
          { "kind" => "reg", "name" => "bank_num_p", "width" => nil },
          { "kind" => "reg", "name" => "op_num_p", "width" => nil }
        ],
        "instances" => [
          {
            "name" => "u_mem",
            "module_name" => "dual_port_mem",
            "connections" => [
              {
                "port" => "banka",
                "signal" => {
                  "kind" => "index",
                  "base" => { "kind" => "identifier", "name" => "bank_num_p" },
                  "index" => { "kind" => "number", "value" => 2, "base" => 10, "width" => nil, "signed" => false }
                }
              },
              {
                "port" => "addra",
                "signal" => {
                  "kind" => "slice",
                  "base" => { "kind" => "identifier", "name" => "op_num_p" },
                  "msb" => { "kind" => "number", "value" => 14, "base" => 10, "width" => nil, "signed" => false },
                  "lsb" => { "kind" => "number", "value" => 10, "base" => 10, "width" => nil, "signed" => false }
                }
              }
            ]
          }
        ]
      )

      expect(source).to include("signal :bank_num_p, width: 3")
      expect(source).to include("signal :op_num_p, width: 15")
      expect(source).to include("banka: sig(:bank_num_p, width: 3)[2]")
      expect(source).to include("addra: sig(:op_num_p, width: 15)[14..10]")
    end

    it "infers missing port widths from indexed expressions" do
      source = described_class.emit(
        "name" => "inferred_port_widths",
        "ports" => [
          { "direction" => "input", "name" => "opl3_reg_wr", "width" => nil },
          { "direction" => "output", "name" => "nts", "width" => 1 }
        ],
        "processes" => [
          {
            "name" => "decode",
            "sensitivity" => [{ "kind" => "all" }],
            "statements" => [
              {
                "kind" => "blocking_assign",
                "target" => { "kind" => "identifier", "name" => "nts" },
                "value" => {
                  "kind" => "index",
                  "base" => { "kind" => "identifier", "name" => "opl3_reg_wr" },
                  "index" => { "kind" => "number", "value" => 6, "base" => 10, "width" => nil, "signed" => false }
                }
              }
            ]
          }
        ]
      )

      expect(source).to include("input :opl3_reg_wr, width: 7")
      expect(source).to include("assign(:nts, sig(:opl3_reg_wr, width: 7)[6], kind: :blocking)")
    end

    it "preserves unknown-width identifier indexes as direct select expressions" do
      source = described_class.emit(
        "name" => "unknown_width_index",
        "statements" => [
          {
            "kind" => "continuous_assign",
            "target" => { "kind" => "identifier", "name" => "out_sig" },
            "value" => {
              "kind" => "index",
              "base" => { "kind" => "identifier", "name" => "tab_sig" },
              "index" => { "kind" => "identifier", "name" => "idx_unknown" }
            }
          }
        ]
      )

      expect(source).to include("assign :out_sig, sig(:tab_sig, width: 1)[sig(:idx_unknown, width: 1)]")
    end

    it "preserves dynamic slices as direct range select expressions" do
      source = described_class.emit(
        "name" => "dynamic_slice",
        "declarations" => [
          {
            "kind" => "wire",
            "name" => "bus",
            "width" => {
              "msb" => { "kind" => "number", "value" => 31 },
              "lsb" => { "kind" => "number", "value" => 0 }
            }
          }
        ],
        "statements" => [
          {
            "kind" => "continuous_assign",
            "target" => { "kind" => "identifier", "name" => "out_sig" },
            "value" => {
              "kind" => "slice",
              "base" => { "kind" => "identifier", "name" => "bus" },
              "msb" => {
                "kind" => "binary",
                "operator" => "+",
                "left" => { "kind" => "identifier", "name" => "idx" },
                "right" => { "kind" => "number", "value" => 7, "base" => 10, "width" => nil, "signed" => false }
              },
              "lsb" => { "kind" => "identifier", "name" => "idx" }
            }
          }
        ]
      )

      expect(source).to include("assign :out_sig, sig(:bus, width: 32)[(sig(:idx, width: 1) + lit(7, width: nil, base: \"d\", signed: false))..sig(:idx, width: 1)]")
    end

    it "renders replication expressions in assign trees without dropping statements" do
      source = described_class.emit(
        "name" => "replication_expression",
        "statements" => [
          {
            "kind" => "continuous_assign",
            "target" => { "kind" => "identifier", "name" => "helper" },
            "value" => {
              "kind" => "ternary",
              "condition" => { "kind" => "identifier", "name" => "sel" },
              "true_expr" => { "kind" => "number", "value" => "0", "base" => "h", "width" => 4, "signed" => false },
              "false_expr" => {
                "kind" => "replication",
                "count" => { "kind" => "number", "value" => "2", "base" => "d", "width" => nil, "signed" => false },
                "value" => { "kind" => "identifier", "name" => "bit" }
              }
            }
          }
        ]
      )

      expect(source).to include("assign :helper, mux(")
      expect(source).to include(".replicate(")
    end

    it "does not emit custom to_verilog methods even when module span has source path" do
      source = described_class.emit(
        "name" => "ao486",
        "span" => {
          "source_path" => "/tmp/reference/rtl/ao486/ao486.v"
        }
      )

      expect(source).not_to include("def self.to_verilog(")
      expect(source).not_to include("def self.to_verilog_generated(")
    end

    it "avoids Ruby core constant collisions for generated class names" do
      source = described_class.emit("name" => "exception")

      expect(source).to include("class ImportedException < RHDL::Component")
    end

    it "formats range-style widths into DSL-friendly widths" do
      source = described_class.emit(
        "name" => "range_widths",
        "ports" => [
          {
            "direction" => "input",
            "name" => "byte_in",
            "width" => {
              "msb" => { "kind" => "number", "value" => 7 },
              "lsb" => { "kind" => "number", "value" => 0 }
            }
          },
          {
            "direction" => "output",
            "name" => "word_out",
            "width" => {
              "msb" => {
                "kind" => "binary",
                "operator" => "-",
                "left" => { "kind" => "identifier", "name" => "WIDTH" },
                "right" => { "kind" => "number", "value" => 1 }
              },
              "lsb" => { "kind" => "number", "value" => 0 }
            }
          },
          {
            "direction" => "input",
            "name" => "ascending",
            "width" => {
              "msb" => { "kind" => "number", "value" => 0 },
              "lsb" => { "kind" => "number", "value" => 6 }
            }
          }
        ]
      )

      expect(source).to include("input :byte_in, width: 8")
      expect(source).to include("output :word_out, width: :WIDTH")
      expect(source).to include("input :ascending, width: (0..6)")
    end

    it "does not synthesize importer temporary helper signal defaults" do
      source = described_class.emit(
        "name" => "temp_defaults",
        "signals" => [
          { "name" => "__VdfgTmp_habc123_0_0" },
          { "name" => "__VdfgTmp_habc123_0_1" },
          { "name" => "_unused_ok" },
          { "name" => "regular_signal" }
        ],
        "statements" => [
          {
            "kind" => "continuous_assign",
            "target" => { "kind" => "identifier", "name" => "__VdfgTmp_habc123_0_1" },
            "value" => { "kind" => "number", "value" => 1 }
          }
        ],
        "processes" => [
          {
            "domain" => "combinational",
            "sensitivity" => [],
            "statements" => [
              {
                "kind" => "blocking_assign",
                "target" => { "kind" => "identifier", "name" => "__VdfgTmp_habc123_0_0" },
                "value" => { "kind" => "number", "value" => 0 }
              },
              {
                "kind" => "blocking_assign",
                "target" => { "kind" => "identifier", "name" => "_unused_ok" },
                "value" => { "kind" => "number", "value" => 0 }
              }
            ]
          }
        ]
      )

      expect(source).to include("signal :__VdfgTmp_habc123_0_0")
      expect(source).to include("signal :__VdfgTmp_habc123_0_1")
      expect(source).to include("signal :_unused_ok")
      expect(source).to include("signal :regular_signal")
      expect(source).not_to include("default: 0")
      expect(source).not_to include("signal :regular_signal, default: 0")
    end
  end
end
