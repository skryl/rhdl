# frozen_string_literal: true

require "spec_helper"
require "json"
require "rhdl/import/frontend/normalizer"

RSpec.describe RHDL::Import::Frontend::Normalizer do
  let(:fixture_root) { File.expand_path("../../../fixtures/import/frontend/normalized", __dir__) }

  describe ".normalize" do
    it "normalizes adapter output into a stable payload schema" do
      raw = load_fixture("raw_adapter_payload.json")
      expected = load_fixture("expected_normalized_payload.json")

      normalized = described_class.normalize(raw)

      expect(normalized).to eq(deep_symbolize(expected))
    end

    it "produces deterministic output regardless of input ordering" do
      raw = load_fixture("raw_adapter_payload.json")

      shuffled = deep_clone(raw)
      shuffled.fetch("sources").reverse!
      shuffled.fetch("modules").reverse!
      shuffled.fetch("diagnostics").rotate!

      expect(described_class.normalize(shuffled)).to eq(described_class.normalize(raw))
    end

    it "normalizes real verilator wrapper payloads with modulesp + meta file maps" do
      raw = {
        "payload" => {
          "version" => "5.044",
          "type" => "NETLIST",
          "modulesp" => [
            { "type" => "MODULE", "name" => "top", "loc" => "e,1:8,1:11" },
            { "type" => "MODULE", "name" => "leaf", "loc" => "f,1:8,1:12" },
            { "type" => "MODULE", "name" => "@CONST-POOL@", "loc" => "a,0:0,0:0" },
            { "type" => "TYPETABLE", "name" => "ignored", "loc" => "a,0:0,0:0" }
          ]
        },
        "metadata" => {
          "frontend_meta" => {
            "files" => {
              "e" => { "filename" => "rtl/top.sv" },
              "f" => { "filename" => "rtl/leaf.v" }
            }
          },
          "command" => {
            "argv" => ["verilator", "--json-only"],
            "chdir" => "/tmp/frontend"
          }
        }
      }

      normalized = described_class.normalize(raw)

      expect(normalized.dig(:adapter, :name)).to eq("verilator_json")
      expect(normalized.dig(:adapter, :version)).to eq("5.044")
      expect(normalized.dig(:invocation, :cwd)).to eq("/tmp/frontend")
      expect(normalized.dig(:invocation, :command)).to eq(["verilator", "--json-only"])

      expect(normalized.dig(:source_map, :sources)).to eq(
        [
          { id: 1, original_id: "f", path: "rtl/leaf.v" },
          { id: 2, original_id: "e", path: "rtl/top.sv" }
        ]
      )

      expect(normalized.dig(:design, :modules)).to eq(
        [
          {
            name: "leaf",
            source_id: 1,
            span: {
              source_id: 1,
              source_path: "rtl/leaf.v",
              line: 1,
              column: 8,
              end_line: 1,
              end_column: 12
            }
          },
          {
            name: "top",
            source_id: 2,
            span: {
              source_id: 2,
              source_path: "rtl/top.sv",
              line: 1,
              column: 8,
              end_line: 1,
              end_column: 11
            }
          }
        ]
      )
    end

    it "extracts ports/declarations/statements/processes/instances from modulesp AST nodes" do
      raw = {
        "payload" => {
          "version" => "5.044",
          "type" => "NETLIST",
          "modulesp" => [
            {
              "type" => "MODULE",
              "name" => "top",
              "addr" => "(M1)",
              "loc" => "e,1:1,1:3",
              "stmtsp" => [
                { "type" => "VAR", "name" => "clk", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT1)" },
                { "type" => "VAR", "name" => "rst_n", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT1)" },
                { "type" => "VAR", "name" => "y", "direction" => "OUTPUT", "varType" => "PORT", "dtypep" => "(DT1)" },
                { "type" => "VAR", "name" => "tmp", "direction" => "NONE", "varType" => "WIRE", "dtypep" => "(DT8)" },
                {
                  "type" => "ALWAYS",
                  "keyword" => "cont_assign",
                  "stmtsp" => [
                    {
                      "type" => "ASSIGNW",
                      "lhsp" => [{ "type" => "VARREF", "name" => "y" }],
                      "rhsp" => [
                        {
                          "type" => "AND",
                          "lhsp" => [{ "type" => "VARREF", "name" => "clk" }],
                          "rhsp" => [{ "type" => "VARREF", "name" => "rst_n" }]
                        }
                      ]
                    }
                  ]
                },
                {
                  "type" => "ALWAYS",
                  "keyword" => "always",
                  "sentreep" => [
                    {
                      "type" => "SENTREE",
                      "sensesp" => [
                        {
                          "type" => "SENITEM",
                          "edgeType" => "POS",
                          "sensp" => [{ "type" => "VARREF", "name" => "clk" }]
                        }
                      ]
                    }
                  ],
                  "stmtsp" => [
                    {
                      "type" => "BEGIN",
                      "stmtsp" => [
                        {
                          "type" => "IF",
                          "condp" => [{ "type" => "VARREF", "name" => "rst_n" }],
                          "thensp" => [
                            {
                              "type" => "ASSIGNDLY",
                              "lhsp" => [{ "type" => "VARREF", "name" => "tmp" }],
                              "rhsp" => [{ "type" => "CONST", "name" => "8'hff" }]
                            }
                          ],
                          "elsesp" => [
                            {
                              "type" => "ASSIGNDLY",
                              "lhsp" => [{ "type" => "VARREF", "name" => "tmp" }],
                              "rhsp" => [{ "type" => "CONST", "name" => "8'h00" }]
                            }
                          ]
                        }
                      ]
                    }
                  ]
                },
                {
                  "type" => "CELL",
                  "name" => "u_child",
                  "modp" => "(M2)",
                  "paramsp" => [
                    { "type" => "PIN", "name" => "WIDTH", "exprp" => [{ "type" => "CONST", "name" => "32" }] }
                  ],
                  "pinsp" => [
                    { "type" => "PIN", "name" => "clk", "exprp" => [{ "type" => "VARREF", "name" => "clk" }] },
                    { "type" => "PIN", "name" => "o", "exprp" => [{ "type" => "VARREF", "name" => "tmp" }] },
                    { "type" => "PIN", "name" => "unused", "exprp" => [] }
                  ]
                }
              ]
            },
            {
              "type" => "MODULE",
              "name" => "child",
              "addr" => "(M2)",
              "loc" => "f,1:1,1:5",
              "stmtsp" => [
                { "type" => "VAR", "name" => "clk", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT1)" },
                { "type" => "VAR", "name" => "o", "direction" => "OUTPUT", "varType" => "PORT", "dtypep" => "(DT8)" }
              ]
            }
          ],
          "typeTablep" => [
            { "type" => "BASICDTYPE", "addr" => "(DT1)", "name" => "logic" },
            { "type" => "BASICDTYPE", "addr" => "(DT8)", "name" => "logic", "range" => "7:0" }
          ]
        },
        "metadata" => {
          "frontend_meta" => {
            "files" => {
              "e" => { "filename" => "rtl/top.sv" },
              "f" => { "filename" => "rtl/child.sv" }
            }
          }
        }
      }

      normalized = described_class.normalize(raw)
      top = normalized.dig(:design, :modules).find { |entry| entry[:name] == "top" }

      expect(top[:ports]).to eq(
        [
          { direction: "input", name: "clk", width: nil },
          { direction: "input", name: "rst_n", width: nil },
          { direction: "output", name: "y", width: nil }
        ]
      )
      expect(top[:declarations]).to eq(
        [
          {
            kind: "wire",
            name: "tmp",
            width: {
              msb: { kind: "number", value: 7, base: 10, width: nil, signed: false },
              lsb: { kind: "number", value: 0, base: 10, width: nil, signed: false }
            }
          }
        ]
      )
      expect(top[:statements]).to eq(
        [
          {
            kind: "continuous_assign",
            target: { kind: "identifier", name: "y" },
            value: {
              kind: "binary",
              operator: "&",
              left: { kind: "identifier", name: "clk" },
              right: { kind: "identifier", name: "rst_n" }
            }
          }
        ]
      )
      expect(top[:processes]).to eq(
        [
          {
            kind: "always",
            domain: "sequential",
            sensitivity: [
              {
                edge: "posedge",
                signal: { kind: "identifier", name: "clk" }
              }
            ],
            statements: [
              {
                kind: "if",
                condition: { kind: "identifier", name: "rst_n" },
                then: [
                  {
                    kind: "nonblocking_assign",
                    target: { kind: "identifier", name: "tmp" },
                    value: { kind: "number", value: "ff", base: "h", width: 8, signed: false }
                  }
                ],
                else: [
                  {
                    kind: "nonblocking_assign",
                    target: { kind: "identifier", name: "tmp" },
                    value: { kind: "number", value: "00", base: "h", width: 8, signed: false }
                  }
                ]
              }
            ]
          }
        ]
      )
      expect(top[:instances]).to eq(
        [
          {
            name: "u_child",
            module_name: "child",
            parameter_overrides: [
              { name: "WIDTH", value: { kind: "number", value: 32, base: 10, width: nil, signed: false } }
            ],
            connections: [
              { port: "clk", signal: { kind: "identifier", name: "clk" } },
              { port: "o", signal: { kind: "identifier", name: "tmp" } },
              { port: "unused", signal: nil }
            ]
          }
        ]
      )
    end

    it "treats empty CONST instance pin expressions as open connections" do
      raw = {
        "payload" => {
          "version" => "5.044",
          "type" => "NETLIST",
          "modulesp" => [
            {
              "type" => "MODULE",
              "name" => "top_open_const",
              "addr" => "(M1)",
              "loc" => "e,1:1,1:3",
              "stmtsp" => [
                { "type" => "VAR", "name" => "clk", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT1)" },
                {
                  "type" => "CELL",
                  "name" => "u0",
                  "modp" => "(M2)",
                  "paramsp" => [],
                  "pinsp" => [
                    { "type" => "PIN", "name" => "clk", "exprp" => [{ "type" => "VARREF", "name" => "clk" }] },
                    { "type" => "PIN", "name" => "unused", "exprp" => [{ "type" => "CONST", "name" => "" }] }
                  ]
                }
              ]
            },
            {
              "type" => "MODULE",
              "name" => "child",
              "addr" => "(M2)",
              "loc" => "f,1:1,1:5",
              "stmtsp" => [
                { "type" => "VAR", "name" => "clk", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT1)" },
                { "type" => "VAR", "name" => "unused", "direction" => "OUTPUT", "varType" => "PORT", "dtypep" => "(DT1)" }
              ]
            }
          ],
          "typeTablep" => [
            { "type" => "BASICDTYPE", "addr" => "(DT1)", "name" => "logic" }
          ]
        },
        "metadata" => {
          "frontend_meta" => {
            "files" => {
              "e" => { "filename" => "rtl/top_open_const.sv" },
              "f" => { "filename" => "rtl/child.sv" }
            }
          }
        }
      }

      normalized = described_class.normalize(raw)
      top = normalized.dig(:design, :modules).find { |entry| entry[:name] == "top_open_const" }

      expect(top.fetch(:instances).fetch(0).fetch(:connections)).to eq(
        [
          { port: "clk", signal: { kind: "identifier", name: "clk" } },
          { port: "unused", signal: nil }
        ]
      )
    end

    it "maps EQCASE/NEQCASE expressions in cont_assign nodes without dropping statements" do
      raw = {
        "payload" => {
          "version" => "5.044",
          "type" => "NETLIST",
          "modulesp" => [
            {
              "type" => "MODULE",
              "name" => "eqcase_top",
              "loc" => "e,1:1,1:10",
              "stmtsp" => [
                { "type" => "VAR", "name" => "wren", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT1)" },
                { "type" => "VAR", "name" => "wraddressstall", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT1)" },
                { "type" => "VAR", "name" => "inclocken", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT1)" },
                { "type" => "VAR", "name" => "wr_fire", "direction" => "NONE", "varType" => "WIRE", "dtypep" => "(DT1)" },
                {
                  "type" => "ALWAYS",
                  "keyword" => "cont_assign",
                  "stmtsp" => [
                    {
                      "type" => "ASSIGNW",
                      "lhsp" => [{ "type" => "VARREF", "name" => "wr_fire" }],
                      "rhsp" => [
                        {
                          "type" => "AND",
                          "lhsp" => [
                            {
                              "type" => "EQCASE",
                              "lhsp" => [{ "type" => "CONST", "name" => "1'h1" }],
                              "rhsp" => [{ "type" => "VARREF", "name" => "wren" }]
                            }
                          ],
                          "rhsp" => [
                            {
                              "type" => "AND",
                              "lhsp" => [
                                {
                                  "type" => "NEQCASE",
                                  "lhsp" => [{ "type" => "CONST", "name" => "1'h1" }],
                                  "rhsp" => [{ "type" => "VARREF", "name" => "wraddressstall" }]
                                }
                              ],
                              "rhsp" => [
                                {
                                  "type" => "NEQCASE",
                                  "lhsp" => [{ "type" => "CONST", "name" => "1'h0" }],
                                  "rhsp" => [{ "type" => "VARREF", "name" => "inclocken" }]
                                }
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ],
          "typeTablep" => [
            { "type" => "BASICDTYPE", "addr" => "(DT1)", "name" => "logic" }
          ]
        },
        "metadata" => {
          "frontend_meta" => {
            "files" => {
              "e" => { "filename" => "rtl/eqcase_top.sv" }
            }
          }
        }
      }

      normalized = described_class.normalize(raw)
      top = normalized.dig(:design, :modules).find { |entry| entry[:name] == "eqcase_top" }
      stmt = Array(top[:statements]).first

      expect(Array(top[:statements]).length).to eq(1)
      expect(stmt).to include(
        kind: "continuous_assign",
        target: { kind: "identifier", name: "wr_fire" }
      )
      expect(stmt.dig(:value, :operator)).to eq("&")
      expect(stmt.dig(:value, :left, :operator)).to eq("==")
      expect(stmt.dig(:value, :right, :operator)).to eq("&")
      expect(stmt.dig(:value, :right, :left, :operator)).to eq("!=")
      expect(stmt.dig(:value, :right, :right, :operator)).to eq("!=")
    end

    it "flattens unpacked-array declarations and maps ARRAYSEL into element slices" do
      raw = {
        "payload" => {
          "version" => "5.044",
          "type" => "NETLIST",
          "modulesp" => [
            {
              "type" => "MODULE",
              "name" => "array_top",
              "addr" => "(M1)",
              "loc" => "e,1:1,1:9",
              "stmtsp" => [
                { "type" => "VAR", "name" => "sel", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT2)" },
                { "type" => "VAR", "name" => "out_data", "direction" => "OUTPUT", "varType" => "PORT", "dtypep" => "(DT32)" },
                { "type" => "VAR", "name" => "cache_data", "direction" => "NONE", "varType" => "WIRE", "dtypep" => "(ARR)" },
                {
                  "type" => "ASSIGNW",
                  "lhsp" => [{ "type" => "VARREF", "name" => "out_data" }],
                  "rhsp" => [
                    {
                      "type" => "ARRAYSEL",
                      "fromp" => [{ "type" => "VARREF", "name" => "cache_data" }],
                      "bitp" => [{ "type" => "VARREF", "name" => "sel" }]
                    }
                  ]
                }
              ]
            }
          ],
          "typeTablep" => [
            { "type" => "BASICDTYPE", "addr" => "(DT2)", "name" => "logic", "range" => "1:0" },
            { "type" => "BASICDTYPE", "addr" => "(DT32)", "name" => "logic", "range" => "31:0" },
            {
              "type" => "UNPACKARRAYDTYPE",
              "addr" => "(ARR)",
              "refDTypep" => "(DT32)",
              "rangep" => [
                {
                  "type" => "RANGE",
                  "leftp" => [{ "type" => "CONST", "name" => "32'h0" }],
                  "rightp" => [{ "type" => "CONST", "name" => "32'h3" }]
                }
              ]
            }
          ]
        },
        "metadata" => {
          "frontend_meta" => {
            "files" => {
              "e" => { "filename" => "rtl/array_top.sv" }
            }
          }
        }
      }

      normalized = described_class.normalize(raw)
      top = normalized.dig(:design, :modules).find { |entry| entry[:name] == "array_top" }

      declaration = top.fetch(:declarations).find { |entry| entry[:name] == "cache_data" }
      expect(declaration).to eq(
        {
          kind: "wire",
          name: "cache_data",
          width: {
            msb: { kind: "number", value: 127, base: 10, width: nil, signed: false },
            lsb: { kind: "number", value: 0, base: 10, width: nil, signed: false }
          }
        }
      )

      expect(top.fetch(:statements)).to eq(
        [
          {
            kind: "continuous_assign",
            target: { kind: "identifier", name: "out_data" },
            value: {
              kind: "slice",
              base: { kind: "identifier", name: "cache_data" },
              msb: {
                kind: "binary",
                operator: "+",
                left: {
                  kind: "binary",
                  operator: "*",
                  left: { kind: "identifier", name: "sel" },
                  right: { kind: "number", value: 32, base: 10, width: nil, signed: false }
                },
                right: { kind: "number", value: 31, base: 10, width: nil, signed: false }
              },
              lsb: {
                kind: "binary",
                operator: "*",
                left: { kind: "identifier", name: "sel" },
                right: { kind: "number", value: 32, base: 10, width: nil, signed: false }
              }
            }
          }
        ]
      )
    end

    it "collects CELL instances declared under GENBLOCK itemsp" do
      raw = {
        "payload" => {
          "version" => "5.044",
          "type" => "NETLIST",
          "modulesp" => [
            {
              "type" => "MODULE",
              "name" => "gen_top",
              "addr" => "(M1)",
              "loc" => "e,1:1,1:7",
              "stmtsp" => [
                { "type" => "VAR", "name" => "in_sig", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT1)" },
                {
                  "type" => "GENBLOCK",
                  "name" => "g0",
                  "itemsp" => [
                    {
                      "type" => "CELL",
                      "name" => "u_child",
                      "modp" => "(M2)",
                      "paramsp" => [],
                      "pinsp" => [
                        { "type" => "PIN", "name" => "a", "exprp" => [{ "type" => "VARREF", "name" => "in_sig" }] }
                      ]
                    }
                  ]
                }
              ]
            },
            {
              "type" => "MODULE",
              "name" => "child",
              "addr" => "(M2)",
              "loc" => "f,1:1,1:5",
              "stmtsp" => [
                { "type" => "VAR", "name" => "a", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT1)" }
              ]
            }
          ],
          "typeTablep" => [
            { "type" => "BASICDTYPE", "addr" => "(DT1)", "name" => "logic" }
          ]
        },
        "metadata" => {
          "frontend_meta" => {
            "files" => {
              "e" => { "filename" => "rtl/gen_top.sv" },
              "f" => { "filename" => "rtl/child.sv" }
            }
          }
        }
      }

      normalized = described_class.normalize(raw)
      top = normalized.dig(:design, :modules).find { |entry| entry[:name] == "gen_top" }

      expect(top.fetch(:instances)).to eq(
        [
          {
            name: "u_child",
            module_name: "child",
            parameter_overrides: [],
            connections: [
              { port: "a", signal: { kind: "identifier", name: "in_sig" } }
            ]
          }
        ]
      )
    end

    it "deduplicates repeated instance names produced by generate expansion" do
      raw = {
        "payload" => {
          "version" => "5.044",
          "type" => "NETLIST",
          "modulesp" => [
            {
              "type" => "MODULE",
              "name" => "dup_top",
              "addr" => "(M1)",
              "loc" => "e,1:1,1:7",
              "stmtsp" => [
                {
                  "type" => "GENBLOCK",
                  "name" => "g0",
                  "itemsp" => [
                    { "type" => "CELL", "name" => "u_dup", "modp" => "(M2)", "pinsp" => [], "paramsp" => [] }
                  ]
                },
                {
                  "type" => "GENBLOCK",
                  "name" => "g1",
                  "itemsp" => [
                    { "type" => "CELL", "name" => "u_dup", "modp" => "(M2)", "pinsp" => [], "paramsp" => [] }
                  ]
                }
              ]
            },
            {
              "type" => "MODULE",
              "name" => "child",
              "addr" => "(M2)",
              "loc" => "f,1:1,1:5",
              "stmtsp" => []
            }
          ]
        },
        "metadata" => {
          "frontend_meta" => {
            "files" => {
              "e" => { "filename" => "rtl/dup_top.sv" },
              "f" => { "filename" => "rtl/child.sv" }
            }
          }
        }
      }

      normalized = described_class.normalize(raw)
      top = normalized.dig(:design, :modules).find { |entry| entry[:name] == "dup_top" }
      instance_names = top.fetch(:instances).map { |entry| entry[:name] }

      expect(instance_names).to eq(%w[u_dup u_dup__1])
    end

    it "normalizes additional expression node families used by verilator modulesp" do
      raw = {
        "payload" => {
          "version" => "5.044",
          "type" => "NETLIST",
          "modulesp" => [
            {
              "type" => "MODULE",
              "name" => "expr_top",
              "addr" => "(M1)",
              "loc" => "e,1:1,1:8",
              "stmtsp" => [
                { "type" => "VAR", "name" => "a", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT8)" },
                { "type" => "VAR", "name" => "b", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT8)" },
                { "type" => "VAR", "name" => "y_ext", "direction" => "OUTPUT", "varType" => "PORT", "dtypep" => "(DT8)" },
                { "type" => "VAR", "name" => "y_neg", "direction" => "OUTPUT", "varType" => "PORT", "dtypep" => "(DT8)" },
                { "type" => "VAR", "name" => "y_or", "direction" => "OUTPUT", "varType" => "PORT", "dtypep" => "(DT1)" },
                { "type" => "VAR", "name" => "y_and", "direction" => "OUTPUT", "varType" => "PORT", "dtypep" => "(DT1)" },
                { "type" => "VAR", "name" => "y_lts", "direction" => "OUTPUT", "varType" => "PORT", "dtypep" => "(DT1)" },
                { "type" => "VAR", "name" => "y_gts", "direction" => "OUTPUT", "varType" => "PORT", "dtypep" => "(DT1)" },
                {
                  "type" => "ASSIGNW",
                  "lhsp" => [{ "type" => "VARREF", "name" => "y_ext" }],
                  "rhsp" => [
                    {
                      "type" => "EXTEND",
                      "lhsp" => [{ "type" => "VARREF", "name" => "a" }]
                    }
                  ]
                },
                {
                  "type" => "ASSIGNW",
                  "lhsp" => [{ "type" => "VARREF", "name" => "y_neg" }],
                  "rhsp" => [
                    {
                      "type" => "NEGATE",
                      "lhsp" => [{ "type" => "VARREF", "name" => "a" }]
                    }
                  ]
                },
                {
                  "type" => "ASSIGNW",
                  "lhsp" => [{ "type" => "VARREF", "name" => "y_or" }],
                  "rhsp" => [
                    {
                      "type" => "REDOR",
                      "lhsp" => [{ "type" => "VARREF", "name" => "a" }]
                    }
                  ]
                },
                {
                  "type" => "ASSIGNW",
                  "lhsp" => [{ "type" => "VARREF", "name" => "y_and" }],
                  "rhsp" => [
                    {
                      "type" => "REDAND",
                      "lhsp" => [{ "type" => "VARREF", "name" => "a" }]
                    }
                  ]
                },
                {
                  "type" => "ASSIGNW",
                  "lhsp" => [{ "type" => "VARREF", "name" => "y_lts" }],
                  "rhsp" => [
                    {
                      "type" => "LTS",
                      "lhsp" => [{ "type" => "VARREF", "name" => "a" }],
                      "rhsp" => [{ "type" => "VARREF", "name" => "b" }]
                    }
                  ]
                },
                {
                  "type" => "ASSIGNW",
                  "lhsp" => [{ "type" => "VARREF", "name" => "y_gts" }],
                  "rhsp" => [
                    {
                      "type" => "GTS",
                      "lhsp" => [{ "type" => "VARREF", "name" => "a" }],
                      "rhsp" => [{ "type" => "VARREF", "name" => "b" }]
                    }
                  ]
                }
              ]
            }
          ],
          "typeTablep" => [
            { "type" => "BASICDTYPE", "addr" => "(DT1)", "name" => "logic" },
            { "type" => "BASICDTYPE", "addr" => "(DT8)", "name" => "logic", "range" => "7:0" }
          ]
        },
        "metadata" => {
          "frontend_meta" => {
            "files" => {
              "e" => { "filename" => "rtl/expr_top.sv" }
            }
          }
        }
      }

      normalized = described_class.normalize(raw)
      top = normalized.dig(:design, :modules, 0)

      expect(top[:statements]).to eq(
        [
          {
            kind: "continuous_assign",
            target: { kind: "identifier", name: "y_ext" },
            value: { kind: "identifier", name: "a" }
          },
          {
            kind: "continuous_assign",
            target: { kind: "identifier", name: "y_neg" },
            value: {
              kind: "unary",
              operator: "-",
              operand: { kind: "identifier", name: "a" }
            }
          },
          {
            kind: "continuous_assign",
            target: { kind: "identifier", name: "y_or" },
            value: {
              kind: "unary",
              operator: "|",
              operand: { kind: "identifier", name: "a" }
            }
          },
          {
            kind: "continuous_assign",
            target: { kind: "identifier", name: "y_and" },
            value: {
              kind: "unary",
              operator: "&",
              operand: { kind: "identifier", name: "a" }
            }
          },
          {
            kind: "continuous_assign",
            target: { kind: "identifier", name: "y_lts" },
            value: {
              kind: "binary",
              operator: "<",
              left: { kind: "identifier", name: "a" },
              right: { kind: "identifier", name: "b" }
            }
          },
          {
            kind: "continuous_assign",
            target: { kind: "identifier", name: "y_gts" },
            value: {
              kind: "binary",
              operator: ">",
              left: { kind: "identifier", name: "a" },
              right: { kind: "identifier", name: "b" }
            }
          }
        ]
      )
    end

    it "normalizes __VdfgRegularize VAR declarations as logic to stabilize frontend temp kinds" do
      raw = {
        "payload" => {
          "version" => "5.044",
          "type" => "NETLIST",
          "modulesp" => [
            {
              "type" => "MODULE",
              "name" => "temp_kind_top",
              "addr" => "(M1)",
              "loc" => "e,1:1,1:8",
              "stmtsp" => [
                {
                  "type" => "VAR",
                  "name" => "__VdfgRegularize_hdeadbeef_0_0",
                  "direction" => "NONE",
                  "varType" => "VAR",
                  "dtypep" => "(DT1)"
                }
              ]
            }
          ],
          "typeTablep" => [
            { "type" => "BASICDTYPE", "addr" => "(DT1)", "name" => "logic" }
          ]
        },
        "metadata" => {
          "frontend_meta" => {
            "files" => {
              "e" => { "filename" => "rtl/temp_kind_top.sv" }
            }
          }
        }
      }

      normalized = described_class.normalize(raw)
      mod = normalized.dig(:design, :modules).find { |entry| entry[:name] == "temp_kind_top" }

      expect(mod).not_to be_nil
      expect(mod[:declarations]).to eq(
        [
          {
            kind: "logic",
            name: "__VdfgRegularize_hdeadbeef_0_0",
            width: nil
          }
        ]
      )
    end

    it "normalizes _unused_ok VAR declarations as wire to match frontend synthesized placeholders" do
      raw = {
        "payload" => {
          "version" => "5.044",
          "type" => "NETLIST",
          "modulesp" => [
            {
              "type" => "MODULE",
              "name" => "unused_ok_top",
              "addr" => "(M1)",
              "loc" => "e,1:1,1:8",
              "stmtsp" => [
                {
                  "type" => "VAR",
                  "name" => "_unused_ok",
                  "direction" => "NONE",
                  "varType" => "VAR",
                  "dtypep" => "(DT1)"
                }
              ]
            }
          ],
          "typeTablep" => [
            { "type" => "BASICDTYPE", "addr" => "(DT1)", "name" => "logic" }
          ]
        },
        "metadata" => {
          "frontend_meta" => {
            "files" => {
              "e" => { "filename" => "rtl/unused_ok_top.sv" }
            }
          }
        }
      }

      normalized = described_class.normalize(raw)
      mod = normalized.dig(:design, :modules).find { |entry| entry[:name] == "unused_ok_top" }

      expect(mod).not_to be_nil
      expect(mod[:declarations]).to eq(
        [
          {
            kind: "wire",
            name: "_unused_ok",
            width: nil
          }
        ]
      )
    end

    it "preserves widening EXTEND nodes used inside concatenations" do
      raw = {
        "payload" => {
          "version" => "5.044",
          "type" => "NETLIST",
          "modulesp" => [
            {
              "type" => "MODULE",
              "name" => "extend_top",
              "addr" => "(M1)",
              "loc" => "e,1:1,1:10",
              "stmtsp" => [
                { "type" => "VAR", "name" => "hi", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT4)" },
                { "type" => "VAR", "name" => "a", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT4)" },
                { "type" => "VAR", "name" => "y_ext", "direction" => "OUTPUT", "varType" => "PORT", "dtypep" => "(DT12)" },
                {
                  "type" => "ASSIGNW",
                  "lhsp" => [{ "type" => "VARREF", "name" => "y_ext", "dtypep" => "(DT12)" }],
                  "rhsp" => [
                    {
                      "type" => "CONCAT",
                      "dtypep" => "(DT12)",
                      "lhsp" => [{ "type" => "VARREF", "name" => "hi", "dtypep" => "(DT4)" }],
                      "rhsp" => [
                        {
                          "type" => "EXTEND",
                          "dtypep" => "(DT8)",
                          "lhsp" => [{ "type" => "VARREF", "name" => "a", "dtypep" => "(DT4)" }]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ],
          "typeTablep" => [
            { "type" => "BASICDTYPE", "addr" => "(DT4)", "name" => "logic", "range" => "3:0" },
            { "type" => "BASICDTYPE", "addr" => "(DT8)", "name" => "logic", "range" => "7:0" },
            { "type" => "BASICDTYPE", "addr" => "(DT12)", "name" => "logic", "range" => "11:0" }
          ]
        },
        "metadata" => {
          "frontend_meta" => {
            "files" => {
              "e" => { "filename" => "rtl/extend_top.sv" }
            }
          }
        }
      }

      normalized = described_class.normalize(raw)
      top = normalized.dig(:design, :modules, 0)

      expect(top[:statements]).to eq(
        [
          {
            kind: "continuous_assign",
            target: { kind: "identifier", name: "y_ext" },
            value: {
              kind: "concat",
              parts: [
                { kind: "identifier", name: "hi" },
                {
                  kind: "concat",
                  parts: [
                    { kind: "number", value: 0, base: 10, width: 4, signed: false },
                    { kind: "identifier", name: "a" }
                  ]
                }
              ]
            }
          }
        ]
      )
    end

    it "truncates arithmetic EXTEND sources to source dtype width before widening" do
      raw = {
        "payload" => {
          "version" => "5.044",
          "type" => "NETLIST",
          "modulesp" => [
            {
              "type" => "MODULE",
              "name" => "extend_add_top",
              "addr" => "(M1)",
              "loc" => "e,1:1,1:14",
              "stmtsp" => [
                { "type" => "VAR", "name" => "a", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT4)" },
                { "type" => "VAR", "name" => "b", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT4)" },
                { "type" => "VAR", "name" => "y", "direction" => "OUTPUT", "varType" => "PORT", "dtypep" => "(DT8)" },
                {
                  "type" => "ASSIGNW",
                  "lhsp" => [{ "type" => "VARREF", "name" => "y", "dtypep" => "(DT8)" }],
                  "rhsp" => [
                    {
                      "type" => "EXTEND",
                      "dtypep" => "(DT8)",
                      "lhsp" => [
                        {
                          "type" => "ADD",
                          "dtypep" => "(DT4)",
                          "lhsp" => [{ "type" => "VARREF", "name" => "a", "dtypep" => "(DT4)" }],
                          "rhsp" => [{ "type" => "VARREF", "name" => "b", "dtypep" => "(DT4)" }]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ],
          "typeTablep" => [
            { "type" => "BASICDTYPE", "addr" => "(DT4)", "name" => "logic", "range" => "3:0" },
            { "type" => "BASICDTYPE", "addr" => "(DT8)", "name" => "logic", "range" => "7:0" }
          ]
        },
        "metadata" => {
          "frontend_meta" => {
            "files" => {
              "e" => { "filename" => "rtl/extend_add_top.sv" }
            }
          }
        }
      }

      normalized = described_class.normalize(raw)
      top = normalized.dig(:design, :modules, 0)

      expect(top[:statements]).to eq(
        [
          {
            kind: "continuous_assign",
            target: { kind: "identifier", name: "y" },
            value: {
              kind: "concat",
              parts: [
                { kind: "number", value: 0, base: 10, width: 4, signed: false },
                {
                  kind: "slice",
                  base: {
                    kind: "binary",
                    operator: "+",
                    left: { kind: "identifier", name: "a" },
                    right: { kind: "identifier", name: "b" }
                  },
                  msb: { kind: "number", value: 3, base: 10, width: nil, signed: false },
                  lsb: { kind: "number", value: 0, base: 10, width: nil, signed: false }
                }
              ]
            }
          }
        ]
      )
    end

    it "extracts INITIAL and INITIALSTATIC blocks as initial processes" do
      raw = {
        "payload" => {
          "version" => "5.044",
          "type" => "NETLIST",
          "modulesp" => [
            {
              "type" => "MODULE",
              "name" => "init_top",
              "addr" => "(M1)",
              "loc" => "e,1:1,1:8",
              "stmtsp" => [
                { "type" => "VAR", "name" => "flag_a", "direction" => "NONE", "varType" => "VAR", "dtypep" => "(DT1)" },
                { "type" => "VAR", "name" => "flag_b", "direction" => "NONE", "varType" => "VAR", "dtypep" => "(DT1)" },
                {
                  "type" => "INITIAL",
                  "stmtsp" => [
                    {
                      "type" => "ASSIGN",
                      "lhsp" => [{ "type" => "VARREF", "name" => "flag_a" }],
                      "rhsp" => [{ "type" => "CONST", "name" => "1'h1" }]
                    }
                  ]
                },
                {
                  "type" => "INITIALSTATIC",
                  "stmtsp" => [
                    {
                      "type" => "ASSIGN",
                      "lhsp" => [{ "type" => "VARREF", "name" => "flag_b" }],
                      "rhsp" => [{ "type" => "CONST", "name" => "1'h0" }]
                    }
                  ]
                }
              ]
            }
          ],
          "typeTablep" => [
            { "type" => "BASICDTYPE", "addr" => "(DT1)", "name" => "logic" }
          ]
        },
        "metadata" => {
          "frontend_meta" => {
            "files" => {
              "e" => { "filename" => "rtl/init_top.sv" }
            }
          }
        }
      }

      normalized = described_class.normalize(raw)
      top = normalized.dig(:design, :modules, 0)

      expect(top[:processes]).to eq(
        [
          {
            kind: "initial",
            domain: "initial",
            sensitivity: [],
            statements: [
              {
                kind: "blocking_assign",
                target: { kind: "identifier", name: "flag_a" },
                value: { kind: "number", value: "1", base: "h", width: 1, signed: false }
              }
            ]
          },
          {
            kind: "initial",
            domain: "initial",
            sensitivity: [],
            statements: [
              {
                kind: "blocking_assign",
                target: { kind: "identifier", name: "flag_b" },
                value: { kind: "number", value: "0", base: "h", width: 1, signed: false }
              }
            ]
          }
        ]
      )
    end

    it "preserves CASE statements from modulesp as structured case nodes" do
      raw = {
        "payload" => {
          "version" => "5.044",
          "type" => "NETLIST",
          "modulesp" => [
            {
              "type" => "MODULE",
              "name" => "case_top",
              "addr" => "(M1)",
              "loc" => "e,1:1,1:3",
              "stmtsp" => [
                { "type" => "VAR", "name" => "sel", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT2)" },
                { "type" => "VAR", "name" => "out_v", "direction" => "OUTPUT", "varType" => "PORT", "dtypep" => "(DT8)" },
                {
                  "type" => "ALWAYS",
                  "keyword" => "always",
                  "stmtsp" => [
                    {
                      "type" => "CASE",
                      "exprp" => [{ "type" => "VARREF", "name" => "sel" }],
                      "itemsp" => [
                        {
                          "type" => "CASEITEM",
                          "condsp" => [{ "type" => "CONST", "name" => "2'h0" }],
                          "stmtsp" => [
                            {
                              "type" => "ASSIGN",
                              "lhsp" => [{ "type" => "VARREF", "name" => "out_v" }],
                              "rhsp" => [{ "type" => "CONST", "name" => "8'h11" }]
                            }
                          ]
                        },
                        {
                          "type" => "CASEITEM",
                          "condsp" => [{ "type" => "CONST", "name" => "2'h1" }],
                          "stmtsp" => [
                            {
                              "type" => "ASSIGN",
                              "lhsp" => [{ "type" => "VARREF", "name" => "out_v" }],
                              "rhsp" => [{ "type" => "CONST", "name" => "8'h22" }]
                            }
                          ]
                        },
                        {
                          "type" => "CASEITEM",
                          "condsp" => [],
                          "stmtsp" => [
                            {
                              "type" => "ASSIGN",
                              "lhsp" => [{ "type" => "VARREF", "name" => "out_v" }],
                              "rhsp" => [{ "type" => "CONST", "name" => "8'hff" }]
                            }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ],
          "typeTablep" => [
            { "type" => "BASICDTYPE", "addr" => "(DT2)", "name" => "logic", "range" => "1:0" },
            { "type" => "BASICDTYPE", "addr" => "(DT8)", "name" => "logic", "range" => "7:0" }
          ]
        },
        "metadata" => {
          "frontend_meta" => {
            "files" => {
              "e" => { "filename" => "rtl/case_top.sv" }
            }
          }
        }
      }

      normalized = described_class.normalize(raw)
      process = normalized.dig(:design, :modules, 0, :processes, 0)
      case_stmt = process.fetch(:statements).first

      expect(case_stmt.fetch(:kind)).to eq("case")
      expect(case_stmt.fetch(:selector)).to eq(
        { kind: "identifier", name: "sel" }
      )
      expect(case_stmt.fetch(:items)).to eq(
        [
          {
            values: [
              { kind: "number", value: "0", base: "h", width: 2, signed: false }
            ],
            body: [
              {
                kind: "blocking_assign",
                target: { kind: "identifier", name: "out_v" },
                value: { kind: "number", value: "11", base: "h", width: 8, signed: false }
              }
            ]
          },
          {
            values: [
              { kind: "number", value: "1", base: "h", width: 2, signed: false }
            ],
            body: [
              {
                kind: "blocking_assign",
                target: { kind: "identifier", name: "out_v" },
                value: { kind: "number", value: "22", base: "h", width: 8, signed: false }
              }
            ]
          }
        ]
      )
      expect(case_stmt.fetch(:default)).to eq(
        [
          {
            kind: "blocking_assign",
            target: { kind: "identifier", name: "out_v" },
            value: { kind: "number", value: "ff", base: "h", width: 8, signed: false }
          }
        ]
      )
    end

    it "normalizes recoverable static LOOP statements into structured for nodes" do
      raw = {
        "payload" => {
          "version" => "5.044",
          "type" => "NETLIST",
          "modulesp" => [
            {
              "type" => "MODULE",
              "name" => "loop_top",
              "addr" => "(M1)",
              "loc" => "e,1:1,1:3",
              "stmtsp" => [
                { "type" => "VAR", "name" => "a", "direction" => "INPUT", "varType" => "PORT", "dtypep" => "(DT4)" },
                { "type" => "VAR", "name" => "y", "direction" => "OUTPUT", "varType" => "PORT", "dtypep" => "(DT4)" },
                { "type" => "VAR", "name" => "i", "direction" => "NONE", "varType" => "VAR", "dtypep" => "(DTI)" },
                {
                  "type" => "ALWAYS",
                  "keyword" => "always",
                  "stmtsp" => [
                    {
                      "type" => "BEGIN",
                      "stmtsp" => [
                        {
                          "type" => "BEGIN",
                          "stmtsp" => [
                            {
                              "type" => "ASSIGN",
                              "lhsp" => [{ "type" => "VARREF", "name" => "i" }],
                              "rhsp" => [{ "type" => "CONST", "name" => "32'sh0" }]
                            },
                            {
                              "type" => "LOOP",
                              "stmtsp" => [
                                {
                                  "type" => "LOOPTEST",
                                  "condp" => [
                                    {
                                      "type" => "GTES",
                                      "lhsp" => [{ "type" => "CONST", "name" => "32'sh3" }],
                                      "rhsp" => [{ "type" => "VARREF", "name" => "i" }]
                                    }
                                  ]
                                },
                                {
                                  "type" => "BEGIN",
                                  "stmtsp" => [
                                    {
                                      "type" => "ASSIGN",
                                      "lhsp" => [
                                        {
                                          "type" => "SEL",
                                          "fromp" => [{ "type" => "VARREF", "name" => "y" }],
                                          "lsbp" => [{ "type" => "VARREF", "name" => "i" }],
                                          "widthConst" => 1
                                        }
                                      ],
                                      "rhsp" => [
                                        {
                                          "type" => "SEL",
                                          "fromp" => [{ "type" => "VARREF", "name" => "a" }],
                                          "lsbp" => [{ "type" => "VARREF", "name" => "i" }],
                                          "widthConst" => 1
                                        }
                                      ]
                                    }
                                  ]
                                },
                                {
                                  "type" => "ASSIGN",
                                  "lhsp" => [{ "type" => "VARREF", "name" => "i" }],
                                  "rhsp" => [
                                    {
                                      "type" => "ADD",
                                      "lhsp" => [{ "type" => "VARREF", "name" => "i" }],
                                      "rhsp" => [{ "type" => "CONST", "name" => "32'sh1" }]
                                    }
                                  ]
                                }
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ],
          "typeTablep" => [
            { "type" => "BASICDTYPE", "addr" => "(DT4)", "name" => "logic", "range" => "3:0" },
            { "type" => "BASICDTYPE", "addr" => "(DTI)", "name" => "integer" }
          ]
        },
        "metadata" => {
          "frontend_meta" => {
            "files" => {
              "e" => { "filename" => "rtl/loop_top.sv" }
            }
          }
        }
      }

      normalized = described_class.normalize(raw)
      process = normalized.dig(:design, :modules, 0, :processes, 0)
      for_stmt = process.fetch(:statements).first

      expect(for_stmt.fetch(:kind)).to eq("for")
      expect(for_stmt.fetch(:var)).to eq("i")
      expect(for_stmt.fetch(:range)).to eq(from: 0, to: 3)
      expect(for_stmt.fetch(:body).first.fetch(:kind)).to eq("blocking_assign")
    end
  end

  def load_fixture(name)
    JSON.parse(File.read(File.join(fixture_root, name)))
  end

  def deep_symbolize(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, inner), memo|
        memo[key.to_sym] = deep_symbolize(inner)
      end
    when Array
      value.map { |inner| deep_symbolize(inner) }
    else
      value
    end
  end

  def deep_clone(value)
    JSON.parse(JSON.dump(value))
  end
end
