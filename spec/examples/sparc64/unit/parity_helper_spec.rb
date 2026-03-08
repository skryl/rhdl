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

  it 'only skips compiler parity when external component ports exceed 64 bits' do
    wide_reason = described_class.compiler_parity_skip_reason(component_class: wide_port_component_class)
    narrow_reason = described_class.compiler_parity_skip_reason(
      component_class: narrow_port_wide_internal_component_class
    )

    aggregate_failures do
      expect(wide_reason).to include('din(128)', 'dout(128)', '64 bits')
      expect(narrow_reason).to be_nil
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

    allow(broken_component_class).to receive(:to_circt_runtime_json).and_raise(
      NoMethodError,
      "undefined method `<=' for #<RHDL::Synth::Context>"
    )

    reason = described_class.compiler_parity_skip_reason(component_class: broken_component_class)

    expect(reason).to include(
      'IR compiler parity runtime export is not available',
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
    allow(slow_component_class).to receive(:to_circt_runtime_json) do
      sleep 0.05
      '{}'
    end

    reason = described_class.compiler_parity_skip_reason(component_class: slow_component_class)

    expect(reason).to include(
      'IR compiler parity runtime export is not available',
      'Timeout::Error',
      'compiler runtime export exceeded 0.01 second timeout'
    )
  end
end
