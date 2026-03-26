# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Sparc64ParityHelper do
  WIDE_XOR_MASK = 0x0123_4567_89AB_CDEF

  def require_semantic_tool!
    skip 'circt-verilog not available' unless HdlToolchain.which('circt-verilog')
  end

  def require_parity_backends!
    skip 'verilator not available' unless HdlToolchain.verilator_available?
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE
  end

  def require_native_ir_parity_backends!
    skip 'verilator not available' unless HdlToolchain.verilator_available?
    skip 'IR native backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE || RHDL::Sim::Native::IR::JIT_AVAILABLE
  end

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  let(:original_wide_verilog) do
    <<~VERILOG
      module wide_passthrough(din, so);
        input [63:0] din;
        output [63:0] so;

        assign #1 so = din ^ 64'h0123_4567_89ab_cdef;
        // synopsys translate_off
        initial $display("debug only");
        // synopsys translate_on
      endmodule
    VERILOG
  end

  let(:staged_wide_verilog) do
    <<~VERILOG
      module wide_passthrough(dout, so);
        input [63:0] dout;
        output [63:0] so;

        assign so = dout ^ 64'h0123_4567_89ab_cdef;
      endmodule
    VERILOG
  end

  let(:wide_concat_verilog) do
    <<~VERILOG
      module wide_concat(din, y);
        input [63:0] din;
        output [71:0] y;

        assign y = {din, 8'hf3};
      endmodule
    VERILOG
  end

  let(:too_wide_port_verilog) do
    <<~VERILOG
      module too_wide_port_probe(din, dout);
        input [159:0] din;
        output [159:0] dout;

        assign dout = din;
      endmodule
    VERILOG
  end

  let(:narrow_port_too_wide_internal_verilog) do
    <<~VERILOG
      module narrow_ports_too_wide_internal(din, dout);
        input [31:0] din;
        output [31:0] dout;

        assign dout = din;
      endmodule
    VERILOG
  end

  let(:simple_passthrough_verilog) do
    <<~VERILOG
      module ruby_fallback_probe(a, y);
        input a;
        output y;

        assign y = a;
      endmodule
    VERILOG
  end

  let(:sequential_verilog) do
    <<~VERILOG
      module seq_capture(clk, rst, d, q);
        input clk;
        input rst;
        input [7:0] d;
        output reg [7:0] q;

        always @(posedge clk or posedge rst) begin
          if (rst) begin
            q <= 8'h00;
          end else begin
            q <= d;
          end
        end
      endmodule
    VERILOG
  end

  let(:sequential_wrapper_verilog) do
    <<~VERILOG
      module seq_wrapper(clk, rst, d, q);
        input clk;
        input rst;
        input [7:0] d;
        output [7:0] q;

        seq_capture u_seq(
          .clk(clk),
          .rst(rst),
          .d(d),
          .q(q)
        );
      endmodule
    VERILOG
  end

  let(:weak_verilog) do
    <<~VERILOG
      module weak_gate(z, a, b1, b2);
        input z;
        input a;
        input b1;
        input b2;
      endmodule
    VERILOG
  end

  let(:active_low_async_verilog) do
    <<~VERILOG
      module dffrl_async(din, clk, rst_l, q);
        input din;
        input clk;
        input rst_l;
        output reg q;

        always @(posedge clk or negedge rst_l) begin
          if (!rst_l) begin
            q <= 1'b0;
          end else begin
            q <= din;
          end
        end
      endmodule
    VERILOG
  end

  let(:outputless_sink_verilog) do
    <<~VERILOG
      module sink(in);
        input [3:0] in;
        wire a;

        assign a = |in;
      endmodule
    VERILOG
  end

  let(:dependency_leaf_verilog) do
    <<~VERILOG
      module helper_leaf(a, y);
        input a;
        output y;

        assign y = ~a;
      endmodule
    VERILOG
  end

  let(:dependency_top_verilog) do
    <<~VERILOG
      module helper_top(a, y);
        input a;
        output y;

        helper_leaf u_leaf(
          .a(a),
          .y(y)
        );
      endmodule
    VERILOG
  end

  let(:dependency_mid_with_unknown_verilog) do
    <<~VERILOG
      module helper_mid_with_unknown(a, y);
        input a;
        output y;

        tap_cell u_tap(
          .a(a),
          .y(y)
        );
      endmodule
    VERILOG
  end

  let(:dependency_top_with_unknown_verilog) do
    <<~VERILOG
      module helper_top_with_unknown(a, y);
        input a;
        output y;

        helper_mid_with_unknown u_mid(
          .a(a),
          .y(y)
        );
      endmodule
    VERILOG
  end

  let(:include_header_verilog) do
    <<~VERILOG
      `define XOR_MASK 8'h5a
    VERILOG
  end

  let(:parameterized_passthrough_verilog) do
    <<~VERILOG
      module parameterized_passthrough(a, y);
        parameter WIDTH = 1;
        input [WIDTH-1:0] a;
        output [WIDTH-1:0] y;

        assign y = a;
      endmodule
    VERILOG
  end

  let(:included_verilog) do
    <<~VERILOG
      `include "defs.vh"

      module include_gate(a, y);
        input [7:0] a;
        output [7:0] y;

        assign y = a ^ `XOR_MASK;
      endmodule
    VERILOG
  end

  let(:undefined_debug_macro_verilog) do
    <<~VERILOG
      module debug_macro_gate(a, y);
        input a;
        output y;

        assign y = a;

        // synopsys translate_off
        initial begin
          if ($time > (4 * `CMP_CLK_PERIOD)) begin
            $display("debug only");
          end
        end
        // synopsys translate_on
      endmodule
    VERILOG
  end

  let(:legacy_leaf_verilog) do
    <<~VERILOG
      module legacy_leaf(din, q);
        parameter SIZE = 1;
        input [SIZE-1:0] din;
        output [SIZE-1:0] q;

        assign q = din;
      endmodule
    VERILOG
  end

  let(:legacy_mid_verilog) do
    <<~VERILOG
      module legacy_mid(din, q);
        input [3:0] din;
        output [3:0] q;

        legacy_leaf #4 u_leaf(
          .din(din),
          .q(q)
        );
      endmodule
    VERILOG
  end

  let(:legacy_top_verilog) do
    <<~VERILOG
      module legacy_top(din, q);
        input [3:0] din;
        output [3:0] q;

        legacy_mid u_mid(
          .din(din),
          .q(q)
        );
      endmodule
    VERILOG
  end

  let(:wide_component_class) do
    stub_const('Sparc64ParityWideFixture', Class.new(RHDL::Sim::Component) do
      def self.verilog_module_name
        'wide_passthrough'
      end

      input :dout, width: 64
      output :so, width: 64

      behavior do
        so <= (dout ^ lit(WIDE_XOR_MASK, width: 64))
      end
    end)
  end

  let(:wide_concat_component_class) do
    stub_const('Sparc64ParityWideConcatFixture', Class.new(RHDL::Sim::Component) do
      def self.verilog_module_name
        'wide_concat'
      end

      input :din, width: 64
      output :y, width: 72

      behavior do
        y <= cat(din, lit(0xF3, width: 8))
      end
    end)
  end

  let(:wide_port_component_class) do
    stub_const('Sparc64ParityWidePortFixture', Class.new(RHDL::Sim::Component) do
      def self.verilog_module_name
        'wide_port_probe'
      end

      input :din, width: 128
      output :dout, width: 128

      behavior do
        dout <= din
      end
    end)
  end

  let(:narrow_port_wide_internal_component_class) do
    stub_const('Sparc64ParityNarrowWideInternalFixture', Class.new(RHDL::Sim::Component) do
      def self.verilog_module_name
        'narrow_ports_wide_internal'
      end

      input :din, width: 32
      output :dout, width: 32
      wire :wide_state, width: 128

      behavior do
        wide_state <= cat(lit(0, width: 96), din)
        dout <= wide_state[31..0]
      end
    end)
  end

  let(:too_wide_port_component_class) do
    stub_const('Sparc64ParityTooWidePortFixture', Class.new(RHDL::Sim::Component) do
      def self.verilog_module_name
        'too_wide_port_probe'
      end

      input :din, width: 160
      output :dout, width: 160

      behavior do
        dout <= din
      end
    end)
  end

  let(:narrow_port_too_wide_internal_component_class) do
    stub_const('Sparc64ParityNarrowTooWideInternalFixture', Class.new(RHDL::Sim::Component) do
      def self.verilog_module_name
        'narrow_ports_too_wide_internal'
      end

      input :din, width: 32
      output :dout, width: 32
      wire :wide_state, width: 160

      behavior do
        wide_state <= cat(lit(0, width: 128), din)
        dout <= wide_state[31..0]
      end
    end)
  end

  let(:sequential_component_class) do
    stub_const('Sparc64ParitySequentialFixture', Class.new(RHDL::Sim::SequentialComponent) do
      include RHDL::DSL::Sequential

      def self.verilog_module_name
        'seq_capture'
      end

      input :clk
      input :rst
      input :d, width: 8
      output :q, width: 8

      sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
        q <= d
      end

      behavior do
        q <= q
      end
    end)
  end

  let(:include_component_class) do
    stub_const('Sparc64ParityIncludeFixture', Class.new(RHDL::Sim::Component) do
      def self.verilog_module_name
        'include_gate'
      end

      input :a, width: 8
      output :y, width: 8

      behavior do
        y <= (a ^ lit(0x5A, width: 8))
      end
    end)
  end

  let(:undefined_debug_macro_component_class) do
    stub_const('Sparc64ParityDebugMacroFixture', Class.new(RHDL::Sim::Component) do
      def self.verilog_module_name
        'debug_macro_gate'
      end

      input :a
      output :y

      behavior do
        y <= a
      end
    end)
  end

  let(:sequential_wrapper_component_class) do
    leaf_class = sequential_component_class

    stub_const('Sparc64ParitySequentialWrapperFixture', Class.new(RHDL::Sim::Component) do
      def self.verilog_module_name
        'seq_wrapper'
      end

      input :clk
      input :rst
      input :d, width: 8
      output :q, width: 8
      wire :u_seq_q, width: 8

      instance :u_seq, leaf_class
      port :clk => [:u_seq, :clk]
      port :rst => [:u_seq, :rst]
      port :d => [:u_seq, :d]
      port [:u_seq, :q] => :u_seq_q

      behavior do
        q <= u_seq_q
      end
    end)
  end

  let(:parameterized_component_class) do
    stub_const('Sparc64ParityParameterizedFixture', Class.new(RHDL::Sim::Component) do
      def self.verilog_module_name
        'parameterized_passthrough'
      end

      input :a, width: 8
      output :y, width: 8

      behavior do
        y <= a
      end
    end)
  end

  let(:reserved_port_component_class) do
    stub_const('Sparc64ParityReservedPortFixture', Class.new(RHDL::Sim::Component) do
      def self.verilog_module_name
        'reserved_port_probe'
      end

      input :_in, width: 32
      output :out

      behavior do
        out <= _in[0]
      end
    end)
  end

  let(:multi_reset_component_class) do
    stub_const('Sparc64ParityMultiResetFixture', Class.new(RHDL::Sim::SequentialComponent) do
      include RHDL::DSL::Sequential

      def self.verilog_module_name
        'multi_reset_probe'
      end

      input :rst_tri_en
      input :rclk
      input :arst_l
      input :grst_l
      input :d
      output :q

      sequential clock: :rclk do
        q <= d
      end

      behavior do
        q <= q
      end
    end)
  end

  let(:request_input_component_class) do
    stub_const('Sparc64ParityRequestInputFixture', Class.new(RHDL::Sim::Component) do
      def self.verilog_module_name
        'request_input_probe'
      end

      input :rdreq
      input :wrreq
      input :invreq
      input :stallreq
      input :cam_vld
      input :quad_ld_cam
      input :rst_tri_en
      input :regular
      output :y

      behavior do
        y <= regular
      end
    end)
  end

  it 'treats staged Verilog as semantically equal to the original after staging normalization', timeout: 120 do
    require_semantic_tool!

    Dir.mktmpdir('sparc64_parity_helper_semantic') do |dir|
      original_path = write(File.join(dir, 'original', 'wide_passthrough.v'), original_wide_verilog)
      staged_path = write(File.join(dir, 'staged', 'wide_passthrough.v'), staged_wide_verilog)

      report = described_class.staged_verilog_semantic_report(
        original_path: original_path,
        staged_path: staged_path,
        base_dir: File.join(dir, 'semantic_report')
      )

      expect(report[:match]).to be(true), <<~MSG
        original signature: #{report[:original_signature].inspect}
        staged signature: #{report[:staged_signature].inspect}
      MSG
    end
  end

  it 'compares staged Verilog using the source dependency closure when the source file is not standalone', timeout: 120 do
    require_semantic_tool!

    Dir.mktmpdir('sparc64_parity_helper_dependency_semantic') do |dir|
      original_top_path = write(File.join(dir, 'original', 'helper_top.v'), dependency_top_verilog)
      original_leaf_path = write(File.join(dir, 'original', 'helper_leaf.v'), dependency_leaf_verilog)
      staged_top_path = write(File.join(dir, 'staged', 'helper_top.v'), dependency_top_verilog)
      staged_leaf_path = write(File.join(dir, 'staged', 'helper_leaf.v'), dependency_leaf_verilog)

      report = described_class.staged_verilog_semantic_report(
        original_paths: [original_top_path, original_leaf_path],
        staged_paths: [staged_top_path, staged_leaf_path],
        base_dir: File.join(dir, 'semantic_report'),
        module_names: %w[helper_top],
        top_module: 'helper_top'
      )

      expect(report[:match]).to be(true), <<~MSG
        original signature: #{report[:original_signature].inspect}
        staged signature: #{report[:staged_signature].inspect}
      MSG
    end
  end

  it 'normalizes the full dependency closure before staged semantic comparison', timeout: 120 do
    require_semantic_tool!

    Dir.mktmpdir('sparc64_parity_helper_legacy_dependency_semantic') do |dir|
      original_top_path = write(File.join(dir, 'original', 'legacy_top.v'), legacy_top_verilog)
      original_mid_path = write(File.join(dir, 'original', 'legacy_mid.v'), legacy_mid_verilog)
      original_leaf_path = write(File.join(dir, 'original', 'legacy_leaf.v'), legacy_leaf_verilog)
      staged_top_path = write(File.join(dir, 'staged', 'legacy_top.v'), legacy_top_verilog)
      staged_mid_path = write(File.join(dir, 'staged', 'legacy_mid.v'), legacy_mid_verilog)
      staged_leaf_path = write(File.join(dir, 'staged', 'legacy_leaf.v'), legacy_leaf_verilog)

      report = described_class.staged_verilog_semantic_report(
        original_paths: [original_top_path, original_mid_path, original_leaf_path],
        staged_paths: [staged_top_path, staged_mid_path, staged_leaf_path],
        base_dir: File.join(dir, 'semantic_report'),
        module_names: %w[legacy_top],
        top_module: 'legacy_top'
      )

      expect(report[:match]).to be(true), <<~MSG
        original signature: #{report[:original_signature].inspect}
        staged signature: #{report[:staged_signature].inspect}
      MSG
    end
  end

  it 'writes semantic support stubs for unknown modules referenced from dependency files', timeout: 120 do
    require_semantic_tool!

    Dir.mktmpdir('sparc64_parity_helper_nested_dependency_semantic') do |dir|
      original_top_path = write(File.join(dir, 'original', 'helper_top_with_unknown.v'), dependency_top_with_unknown_verilog)
      original_mid_path = write(File.join(dir, 'original', 'helper_mid_with_unknown.v'), dependency_mid_with_unknown_verilog)
      staged_top_path = write(File.join(dir, 'staged', 'helper_top_with_unknown.v'), dependency_top_with_unknown_verilog)
      staged_mid_path = write(File.join(dir, 'staged', 'helper_mid_with_unknown.v'), dependency_mid_with_unknown_verilog)

      report = described_class.staged_verilog_semantic_report(
        original_paths: [original_top_path, original_mid_path],
        staged_paths: [staged_top_path, staged_mid_path],
        base_dir: File.join(dir, 'semantic_report'),
        module_names: %w[helper_top_with_unknown],
        top_module: 'helper_top_with_unknown'
      )

      expect(report[:match]).to be(true), <<~MSG
        original signature: #{report[:original_signature].inspect}
        staged signature: #{report[:staged_signature].inspect}
      MSG
    end
  end

  it 'writes semantic support stubs that accept parameterized unknown modules' do
    Dir.mktmpdir('sparc64_parity_helper_stub_params') do |dir|
      source = <<~VERILOG
        module top(a, y);
          input [3:0] a;
          output y;

          sink #(4) s0(.in(a));
          custom #(.WIDTH(4), .DEPTH(8)) u0(
            .din(a),
            .y(y)
          );
        endmodule
      VERILOG

      stub_path = described_class.send(
        :write_semantic_support_stubs,
        source: source,
        base_dir: dir,
        stem: 'top',
        known_module_names: Set.new
      )

      stub_source = File.read(stub_path)

      expect(stub_source).to include('module sink #(parameter P0 = 0) (in);')
      expect(stub_source).to include('module custom #(parameter WIDTH = 0, parameter DEPTH = 0) (din, y);')
    end
  end

  it 'lowers simple gate primitives into assign statements for semantic compare' do
    source = <<~VERILOG
      module primitive_bank(a, b, c, y_buf, y_not, y_nand, y_nor, y_xor);
        input a, b, c;
        output y_buf, y_not, y_nand, y_nor, y_xor;

        buf (y_buf, a);
        not (y_not, a);
        nand (y_nand, a, b, c);
        nor (y_nor, a, b, c);
        xor (y_xor, a, b, c);
      endmodule
    VERILOG

    normalized = described_class.send(
      :normalized_verilog_for_semantic_compare,
      source,
      source_path: '/tmp/primitive_bank.v'
    )

    aggregate_failures do
      expect(normalized).to include('assign y_buf = (a);')
      expect(normalized).to include('assign y_not = ~(a);')
      expect(normalized).to include('assign y_nand = ~(a & b & c);')
      expect(normalized).to include('assign y_nor = ~(a | b | c);')
      expect(normalized).to include('assign y_xor = (a ^ b ^ c);')
      expect(normalized).not_to include('buf (y_buf, a);')
      expect(normalized).not_to include('not (y_not, a);')
      expect(normalized).not_to include('nand (y_nand, a, b, c);')
      expect(normalized).not_to include('nor (y_nor, a, b, c);')
      expect(normalized).not_to include('xor (y_xor, a, b, c);')
    end
  end

  it 'rewrites escaped identifiers into importer-safe names for semantic compare' do
    source = <<~VERILOG
      module escaped_fill(\\vdd! );
        input \\vdd! ;
      endmodule
    VERILOG

    normalized = described_class.send(
      :normalized_verilog_for_semantic_compare,
      source,
      source_path: '/tmp/escaped_fill.v'
    )

    aggregate_failures do
      expect(normalized).to include('module escaped_fill(vdd_ );')
      expect(normalized).to include('input vdd_ ;')
      expect(normalized).not_to include('\\vdd!')
    end
  end

  it 'recognizes highest-DSL expectations for behavioral, sequential, and weak combinational outputs' do
    Dir.mktmpdir('sparc64_parity_helper_rhdl') do |dir|
      original_wide_path = write(File.join(dir, 'rtl', 'wide_passthrough.v'), original_wide_verilog)
      sequential_path = write(File.join(dir, 'rtl', 'seq_capture.v'), sequential_verilog)
      weak_path = write(File.join(dir, 'rtl', 'weak_gate.v'), weak_verilog)

      wide_ruby_path = write(
        File.join(dir, 'hdl', 'wide_passthrough.rb'),
        <<~RUBY
          # frozen_string_literal: true

          class WidePassthroughGenerated < RHDL::Sim::Component
            def self.verilog_module_name
              "wide_passthrough"
            end

            input :dout, width: 96
            output :so, width: 96

            behavior do
              so <= (dout ^ lit(#{WIDE_XOR_MASK}, width: 96))
            end
          end
        RUBY
      )
      sequential_ruby_path = write(
        File.join(dir, 'hdl', 'seq_capture.rb'),
        <<~RUBY
          # frozen_string_literal: true

          class SeqCaptureGenerated < RHDL::Sim::SequentialComponent
            include RHDL::DSL::Sequential

            def self.verilog_module_name
              "seq_capture"
            end

            input :clk
            input :rst
            input :d, width: 8
            output :q, width: 8

            sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
              q <= d
            end

            behavior do
              q <= q
            end
          end
        RUBY
      )
      weak_ruby_path = write(
        File.join(dir, 'hdl', 'weak_gate.rb'),
        <<~RUBY
          # frozen_string_literal: true

          class WeakGateGenerated < RHDL::Sim::Component
            def self.verilog_module_name
              "weak_gate"
            end

            input :z
            input :a
            input :b1
            input :b2

            behavior do
            end
          end
        RUBY
      )

      wide_report = described_class.rhdl_level_report(
        generated_ruby_path: wide_ruby_path,
        original_verilog_path: original_wide_path,
        module_name: 'wide_passthrough',
        suite_raise_diagnostics: [],
        component_class: wide_component_class
      )
      sequential_report = described_class.rhdl_level_report(
        generated_ruby_path: sequential_ruby_path,
        original_verilog_path: sequential_path,
        module_name: 'seq_capture',
        suite_raise_diagnostics: [],
        component_class: sequential_component_class
      )
      weak_report = described_class.rhdl_level_report(
        generated_ruby_path: weak_ruby_path,
        original_verilog_path: weak_path,
        module_name: 'weak_gate',
        suite_raise_diagnostics: []
      )

      expect(wide_report[:issues]).to eq([])
      expect(wide_report[:expected_level]).to eq(:behavioral)
      expect(wide_report[:actual_level]).to eq(:behavioral)

      expect(sequential_report[:issues]).to eq([])
      expect(sequential_report[:expected_level]).to eq(:sequential)
      expect(sequential_report[:actual_level]).to eq(:sequential)

      expect(weak_report[:issues]).to eq([])
      expect(weak_report[:expected_level]).to eq(:structural)
      expect(weak_report[:actual_level]).to eq(:behavioral)
    end
  end

  it 'allows behavioral lowering for active-low async resets and structural lowering for outputless sinks' do
    Dir.mktmpdir('sparc64_parity_helper_rhdl_edge_cases') do |dir|
      active_low_path = write(File.join(dir, 'rtl', 'dffrl_async.v'), active_low_async_verilog)
      sink_path = write(File.join(dir, 'rtl', 'sink.v'), outputless_sink_verilog)

      active_low_ruby_path = write(
        File.join(dir, 'hdl', 'dffrl_async.rb'),
        <<~RUBY
          # frozen_string_literal: true

          class DffrlAsyncGenerated < RHDL::Sim::Component
            def self.verilog_module_name
              "dffrl_async"
            end

            input :din
            input :clk
            input :rst_l
            output :q

            behavior do
              q <= (mux(rst_l, clk, lit(0, width: 1)) | lit(0, width: 1))
            end
          end
        RUBY
      )
      sink_ruby_path = write(
        File.join(dir, 'hdl', 'sink.rb'),
        <<~RUBY
          # frozen_string_literal: true

          class SinkGenerated < RHDL::Sim::Component
            def self.verilog_module_name
              "sink"
            end

            input :_in, width: 4
          end
        RUBY
      )

      active_low_report = described_class.rhdl_level_report(
        generated_ruby_path: active_low_ruby_path,
        original_verilog_path: active_low_path,
        module_name: 'dffrl_async',
        suite_raise_diagnostics: []
      )
      sink_report = described_class.rhdl_level_report(
        generated_ruby_path: sink_ruby_path,
        original_verilog_path: sink_path,
        module_name: 'sink',
        suite_raise_diagnostics: []
      )

      expect(active_low_report[:issues]).to eq([])
      expect(active_low_report[:expected_level]).to eq(:behavioral)
      expect(active_low_report[:actual_level]).to eq(:behavioral)

      expect(sink_report[:issues]).to eq([])
      expect(sink_report[:expected_level]).to eq(:structural)
      expect(sink_report[:actual_level]).to eq(:unknown)
    end
  end

  it 'maps Ruby-safe component port names back to the original Verilog ports' do
    Dir.mktmpdir('sparc64_parity_helper_reserved_port_names') do |dir|
      verilog = <<~VERILOG
        module reserved_port_probe(out, in);
          input [31:0] in;
          output out;

          assign out = |in;
        endmodule
      VERILOG

      original_path = write(File.join(dir, 'rtl', 'reserved_port_probe.v'), verilog)
      staged_path = write(File.join(dir, 'staged', 'reserved_port_probe.v'), verilog)

      mapping = described_class.original_port_by_component_name(
        component_class: reserved_port_component_class,
        original_verilog_path: original_path,
        staged_verilog_path: staged_path,
        module_name: 'reserved_port_probe'
      )

      expect(mapping).to include(
        '_in' => 'in',
        'out' => 'out'
      )
    end
  end

  it 'detects active-low reset-like inputs without mistaking rst_tri_en for the reset and keeps secondary resets inactive' do
    plan = described_class.deterministic_vector_plan(
      component_class: multi_reset_component_class,
      functional_steps: 2
    )

    aggregate_failures do
      expect(plan[:clock_name]).to eq('rclk')
      expect(plan[:reset_info]).to eq(name: 'arst_l', active_low: true)
      expect(plan[:steps].first[:inputs]['arst_l']).to eq(0)
      expect(plan[:steps].first[:inputs]['grst_l']).to eq(1)
      expect(plan[:steps].last[:inputs]['arst_l']).to eq(1)
      expect(plan[:steps].last[:inputs]['grst_l']).to eq(1)
    end
  end

  it 'keeps request-style control inputs quiescent in deterministic parity vectors' do
    plan = described_class.deterministic_vector_plan(
      component_class: request_input_component_class,
      combinational_steps: 3
    )

    plan[:steps].each do |step|
      expect(step[:inputs]).to include(
        'cam_vld' => 0,
        'rdreq' => 0,
        'rst_tri_en' => 0,
        'quad_ld_cam' => 0,
        'wrreq' => 0,
        'invreq' => 0,
        'stallreq' => 0
      )
    end
  end

  it 'ignores reset setup vectors when checking parity mismatches' do
    ports = [{ name: 'q', direction: :out, width: 2 }]
    lhs = [{ q: 0 }, { q: 1 }, { q: 2 }]
    rhs = [{ q: 3 }, { q: 1 }, { q: 2 }]
    steps = [{ tag: :reset }, { tag: :functional }, { tag: :functional }]

    mismatch = described_class.first_result_mismatch(lhs, rhs, ports, steps: steps)

    expect(mismatch).to be_nil
  end

  it 'matches IR compiler and Verilator for a wide combinational module with staged-to-original port renames',
     timeout: 180 do
    require_parity_backends!
    if (reason = described_class.compiler_parity_skip_reason(component_class: wide_component_class))
      skip reason
    end

    Dir.mktmpdir('sparc64_parity_helper_wide') do |dir|
      original_path = write(File.join(dir, 'rtl', 'wide_passthrough.v'), original_wide_verilog)
      staged_path = write(File.join(dir, 'staged', 'wide_passthrough.v'), staged_wide_verilog)

      report = described_class.parity_report(
        component_class: wide_component_class,
        module_name: 'wide_passthrough',
        verilog_files: [original_path],
        original_verilog_path: original_path,
        staged_verilog_path: staged_path,
        base_dir: File.join(dir, 'build')
      )

      expect(report[:match]).to be(true), report[:mismatch] || report[:error] || report.inspect
      expect(report[:vector_plan][:steps].length).to eq(10)
      expect(report[:vector_plan][:clock_name]).to be_nil
    end
  end

  it 'preserves leading zeros in wide Verilator output chunks during parity capture', timeout: 180 do
    require_native_ir_parity_backends!
    if (reason = described_class.compiler_parity_skip_reason(component_class: wide_concat_component_class))
      skip reason
    end

    Dir.mktmpdir('sparc64_parity_helper_wide_concat') do |dir|
      module_path = write(File.join(dir, 'rtl', 'wide_concat.v'), wide_concat_verilog)
      vector_plan = {
        clock_name: nil,
        reset_info: nil,
        sequential: false,
        steps: [
          {
            tag: :functional,
            inputs: { 'din' => 0x3F9E_8746_4A01_7FDD }
          }
        ]
      }

      report = described_class.parity_report(
        component_class: wide_concat_component_class,
        module_name: 'wide_concat',
        verilog_files: [module_path],
        original_verilog_path: module_path,
        base_dir: File.join(dir, 'build'),
        vector_plan: vector_plan
      )

      expect(report[:match]).to be(true), report[:mismatch] || report[:error] || report.inspect
      expect(report[:verilator_results].first[:y]).to eq(0x3F9E_8746_4A01_7FDD_F3)
      expect(report[:ir_results].first[:y]).to eq(0x3F9E_8746_4A01_7FDD_F3)
    end
  end

  it 'matches IR compiler and Verilator for a sequential module using reset heuristics', timeout: 180 do
    require_parity_backends!

    Dir.mktmpdir('sparc64_parity_helper_seq') do |dir|
      sequential_path = write(File.join(dir, 'rtl', 'seq_capture.v'), sequential_verilog)

      report = described_class.parity_report(
        component_class: sequential_component_class,
        module_name: 'seq_capture',
        verilog_files: [sequential_path],
        original_verilog_path: sequential_path,
        base_dir: File.join(dir, 'build')
      )

      expect(report[:match]).to be(true), report[:mismatch] || report[:error] || report.inspect
      expect(report[:vector_plan][:clock_name]).to eq('clk')
      expect(report[:vector_plan][:reset_info]).to eq(name: 'rst', active_low: false)
      expect(report[:vector_plan][:steps].length).to eq(10)
      expect(report[:vector_plan][:steps].first[:inputs]['rst']).to eq(1)
      expect(report[:vector_plan][:steps].last[:inputs]['rst']).to eq(0)
    end
  end

  it 'treats wrappers around sequential subcomponents as sequential for parity warmup', timeout: 180 do
    require_parity_backends!

    Dir.mktmpdir('sparc64_parity_helper_seq_wrapper') do |dir|
      sequential_path = write(File.join(dir, 'rtl', 'seq_capture.v'), sequential_verilog)
      wrapper_path = write(File.join(dir, 'rtl', 'seq_wrapper.v'), sequential_wrapper_verilog)

      report = described_class.parity_report(
        component_class: sequential_wrapper_component_class,
        module_name: 'seq_wrapper',
        verilog_files: [wrapper_path, sequential_path],
        original_verilog_path: wrapper_path,
        base_dir: File.join(dir, 'build')
      )

      expect(report[:match]).to be(true), report[:mismatch] || report[:error] || report.inspect
      expect(report[:vector_plan][:sequential]).to be(true)
      expect(report[:vector_plan][:clock_name]).to eq('clk')
      expect(report[:vector_plan][:steps].first[:tag]).to eq(:reset)
      expect(report[:vector_plan][:steps].first[:inputs]['rst']).to eq(1)
    end
  end

  it 'passes include directories through to Verilator parity builds', timeout: 180 do
    require_parity_backends!

    Dir.mktmpdir('sparc64_parity_helper_include_dir') do |dir|
      include_dir = File.join(dir, 'rtl', 'include')
      write(File.join(include_dir, 'defs.vh'), include_header_verilog)
      module_path = write(File.join(dir, 'rtl', 'include_gate.v'), included_verilog)

      report = described_class.parity_report(
        component_class: include_component_class,
        module_name: 'include_gate',
        verilog_files: [module_path],
        original_verilog_path: module_path,
        include_dirs: [include_dir],
        base_dir: File.join(dir, 'build')
      )

      expect(report[:match]).to be(true), report[:mismatch] || report[:error] || report.inspect
    end
  end

  it 'defines CMP_CLK_PERIOD for original-source parity builds that retain debug timing checks', timeout: 180 do
    require_parity_backends!

    Dir.mktmpdir('sparc64_parity_helper_debug_macro') do |dir|
      module_path = write(File.join(dir, 'rtl', 'debug_macro_gate.v'), undefined_debug_macro_verilog)

      report = described_class.parity_report(
        component_class: undefined_debug_macro_component_class,
        module_name: 'debug_macro_gate',
        verilog_files: [module_path],
        original_verilog_path: module_path,
        base_dir: File.join(dir, 'build')
      )

      expect(report[:match]).to be(true), report[:mismatch] || report[:error] || report.inspect
    end
  end

  it 'matches Verilator against inferred specializations for parameterized source modules', timeout: 180 do
    require_parity_backends!

    Dir.mktmpdir('sparc64_parity_helper_parameterized') do |dir|
      module_path = write(File.join(dir, 'rtl', 'parameterized_passthrough.v'), parameterized_passthrough_verilog)

      report = described_class.parity_report(
        component_class: parameterized_component_class,
        module_name: 'parameterized_passthrough',
        verilog_files: [module_path],
        original_verilog_path: module_path,
        base_dir: File.join(dir, 'build')
      )

      expect(report[:match]).to be(true), report[:mismatch] || report[:error] || report.inspect
    end
  end

  it 'uses native IR parity up to 128 bits and skips only truly over-wide modules' do
    wide_reason = described_class.compiler_parity_skip_reason(component_class: wide_port_component_class)
    narrow_reason = described_class.compiler_parity_skip_reason(
      component_class: narrow_port_wide_internal_component_class
    )
    too_wide_reason = described_class.compiler_parity_skip_reason(component_class: too_wide_port_component_class)

    allow(described_class).to receive(:compiler_runtime_probe)
      .with(narrow_port_too_wide_internal_component_class)
      .and_return(
        success: true,
        runtime_json: {
          'modules' => [
            {
              'nets' => [{ 'name' => 'wide_state', 'width' => 160 }],
              'regs' => [],
              'memories' => []
            }
          ]
        }
      )

    too_wide_internal_reason = described_class.compiler_parity_skip_reason(
      component_class: narrow_port_too_wide_internal_component_class
    )

    aggregate_failures do
      if RHDL::Sim::Native::IR::COMPILER_AVAILABLE || RHDL::Sim::Native::IR::JIT_AVAILABLE
        expect(wide_reason).to be_nil
        expect(narrow_reason).to be_nil
      else
        expect(wide_reason).to eq('IR native parity backend unavailable')
        expect(narrow_reason).to eq('IR native parity backend unavailable')
      end

      expect(too_wide_reason).to include('din(160)', 'dout(160)', '128 bits')
      expect(too_wide_internal_reason).to include('wide_state(160)', '128 bits')
    end
  end

  it 'routes 128-bit parity through the compiler backend and reserves JIT for truly over-wide modules' do
    runtime_probe = described_class.send(:compiler_runtime_probe, wide_port_component_class)

    skip runtime_probe[:error] unless runtime_probe[:success]
    expect(runtime_probe[:runtime_json]).to be_a(String)
    expect(JSON.parse(runtime_probe[:runtime_json], max_nesting: false)).to include('circt_json_version' => 1)

    backend = described_class.ir_runtime_backend(
      component_class: wide_port_component_class,
      runtime_json: runtime_probe[:runtime_json]
    )
    narrow_backend = described_class.ir_runtime_backend(
      component_class: wide_component_class,
      runtime_json: described_class.send(:compiler_runtime_probe, wide_component_class).fetch(:runtime_json)
    )
    too_wide_backend = described_class.ir_runtime_backend(
      component_class: too_wide_port_component_class,
      runtime_json: described_class.send(:compiler_runtime_probe, too_wide_port_component_class).fetch(:runtime_json)
    )

    aggregate_failures do
      expected_narrow_backend = if RHDL::Sim::Native::IR::COMPILER_AVAILABLE
                                  :compiler
                                elsif RHDL::Sim::Native::IR::JIT_AVAILABLE
                                  :jit
                                else
                                  :backend_unavailable
                                end
      expect(backend).to eq(expected_narrow_backend)
      expect(narrow_backend).to eq(expected_narrow_backend)
      expect(too_wide_backend).to eq(:jit_required_for_ports)
    end
  end

  it 'returns a principled compiler parity skip when runtime export itself fails' do
    broken_component_class = stub_const('Sparc64ParityBrokenRuntimeFixture', Class.new(RHDL::Sim::Component) do
      def self.verilog_module_name
        'broken_runtime_probe'
      end

      input :a
      output :y

      behavior do
        y <= a
      end
    end)

    allow(broken_component_class).to receive(:to_flat_circt_nodes).and_raise(
      NoMethodError,
      "undefined method `<=' for #<RHDL::Synth::Context>"
    )

    reason = described_class.compiler_parity_skip_reason(component_class: broken_component_class)

    expect(reason).to include(
      'IR native parity runtime export is not available',
      'NoMethodError',
      'undefined method `<='
    )
  end

  it 'returns a principled compiler parity skip when runtime export times out' do
    slow_component_class = stub_const('Sparc64ParitySlowRuntimeFixture', Class.new(RHDL::Sim::Component) do
      def self.verilog_module_name
        'slow_runtime_probe'
      end

      input :a
      output :y

      behavior do
        y <= a
      end
    end)

    stub_const('Sparc64ParityHelper::COMPILER_RUNTIME_EXPORT_TIMEOUT', 0.01)
    allow(slow_component_class).to receive(:to_flat_circt_nodes) do
      sleep 0.05
      :never_reached
    end

    reason = described_class.compiler_parity_skip_reason(component_class: slow_component_class)

    expect(reason).to include(
      'IR native parity runtime export is not available',
      'Timeout::Error',
      'compiler runtime export exceeded 0.01 second timeout'
    )
  end

  it 'does not pre-skip parity when Verilator is available and Ruby fallback can run' do
    if HdlToolchain.verilator_available?
      expect(described_class.parity_skip_reason(component_class: too_wide_port_component_class)).to be_nil
    else
      expect(described_class.parity_skip_reason(component_class: too_wide_port_component_class)).to eq(
        'verilator not available'
      )
    end
  end

  it 'falls back to Ruby parity when native IR rejects over-wide ports', timeout: 180 do
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    Dir.mktmpdir('sparc64_parity_helper_ruby_port_fallback') do |dir|
      module_path = write(File.join(dir, 'rtl', 'too_wide_port_probe.v'), too_wide_port_verilog)

      report = described_class.parity_report(
        component_class: too_wide_port_component_class,
        module_name: 'too_wide_port_probe',
        verilog_files: [module_path],
        original_verilog_path: module_path,
        base_dir: File.join(dir, 'build')
      )

      aggregate_failures do
        expect(report[:match]).to be(true), report[:mismatch] || report[:error] || report.inspect
        expect(report[:runtime_backend]).to eq(:ruby)
        expect(report[:native_ir_error]).to include('din(160)', 'dout(160)', '128 bits')
        expect(report[:ir_results]).to eq(report[:runtime_results])
      end
    end
  end

  it 'falls back to Ruby parity when native IR rejects over-wide internal signals', timeout: 180 do
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    allow(described_class).to receive(:compiler_runtime_probe)
      .with(narrow_port_too_wide_internal_component_class)
      .and_return(
        success: true,
        runtime_json: {
          'modules' => [
            {
              'nets' => [{ 'name' => 'wide_state', 'width' => 160 }],
              'regs' => [],
              'memories' => []
            }
          ]
        }
      )

    Dir.mktmpdir('sparc64_parity_helper_ruby_internal_fallback') do |dir|
      module_path = write(
        File.join(dir, 'rtl', 'narrow_ports_too_wide_internal.v'),
        narrow_port_too_wide_internal_verilog
      )

      report = described_class.parity_report(
        component_class: narrow_port_too_wide_internal_component_class,
        module_name: 'narrow_ports_too_wide_internal',
        verilog_files: [module_path],
        original_verilog_path: module_path,
        base_dir: File.join(dir, 'build')
      )

      aggregate_failures do
        expect(report[:match]).to be(true), report[:mismatch] || report[:error] || report.inspect
        expect(report[:runtime_backend]).to eq(:ruby)
        expect(report[:native_ir_error]).to include('wide_state(160)', '128 bits')
      end
    end
  end

  it 'falls back to Ruby parity when native IR runtime export is unavailable', timeout: 180 do
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    ruby_fallback_component_class = stub_const('Sparc64ParityRubyFallbackFixture', Class.new(RHDL::Sim::Component) do
      def self.verilog_module_name
        'ruby_fallback_probe'
      end

      input :a
      output :y

      behavior do
        y <= a
      end
    end)

    allow(described_class).to receive(:compiler_runtime_probe)
      .with(ruby_fallback_component_class)
      .and_return(
        success: false,
        error: 'Timeout::Error: compiler runtime export exceeded 60.0 second timeout'
      )

    Dir.mktmpdir('sparc64_parity_helper_ruby_runtime_export_fallback') do |dir|
      module_path = write(File.join(dir, 'rtl', 'ruby_fallback_probe.v'), simple_passthrough_verilog)

      report = described_class.parity_report(
        component_class: ruby_fallback_component_class,
        module_name: 'ruby_fallback_probe',
        verilog_files: [module_path],
        original_verilog_path: module_path,
        base_dir: File.join(dir, 'build')
      )

      aggregate_failures do
        expect(report[:match]).to be(true), report[:mismatch] || report[:error] || report.inspect
        expect(report[:runtime_backend]).to eq(:ruby)
        expect(report[:native_ir_error]).to include(
          'IR native parity runtime export is not available',
          'Timeout::Error'
        )
      end
    end
  end

  it 'parses deep runtime JSON payloads without tripping Ruby JSON nesting limits' do
    deep_expr = { 'kind' => 'literal', 'value' => 0, 'width' => 1 }
    101.times do
      deep_expr = {
        'kind' => 'slice',
        'base' => deep_expr,
        'range_begin' => 0,
        'range_end' => 0,
        'width' => 1
      }
    end

    runtime_json = JSON.generate(
      {
        'modules' => [
          {
            'nets' => [],
            'regs' => [],
            'memories' => [],
            'assigns' => [{ 'target' => 'y', 'expr' => deep_expr }]
          }
        ]
      },
      max_nesting: false
    )

    module_payload = described_class.send(:first_runtime_module, runtime_json)

    expect(module_payload.fetch('assigns').first.fetch('expr')).to be_a(Hash)
  end
end
