# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"
require "rhdl/import/checks/ao486_trace_harness"

RSpec.describe RHDL::Import::Checks::Ao486TraceHarness, :no_vendor_reimport do
  describe "private helpers" do
    class FakeTraceIrSim
      attr_reader :tick_inputs

      def initialize(schedule:)
        @schedule = schedule
        @inputs = {}
        @tick_inputs = []
        @current_outputs = {}
      end

      def input_names
        %w[
          clk rst_n
          a20_enable cache_disable interrupt_do interrupt_vector
          avm_waitrequest avm_readdatavalid avm_readdata
          dma_address dma_16bit dma_write dma_writedata dma_read
          io_read_data io_read_done io_write_done
        ]
      end

      def poke(name, value)
        @inputs[name.to_s] = Integer(value)
      end

      def evaluate
        nil
      end

      def tick
        cycle = @tick_inputs.length
        @tick_inputs << @inputs.dup
        @current_outputs = @schedule.fetch(cycle, {})
      end

      def peek(name)
        @current_outputs.fetch(name.to_s, 0)
      end
    end

    let(:harness) do
      described_class.new(
        mode: "reference",
        top: "ao486",
        out: ".",
        cycles: 32,
        source_root: ".",
        converted_export_mode: nil,
        cwd: Dir.pwd
      )
    end

    it "extracts missing modules from verilator MODMISSING diagnostics" do
      stderr = <<~LOG
        %Error-MODMISSING: foo.v:1:1: Cannot find file containing module: 'cpu_export'
        %Error-MODMISSING: bar.v:2:1: Cannot find file containing module: 'l1_icache'
      LOG

      modules = harness.send(:extract_missing_modules, stderr)
      expect(modules).to eq(%w[cpu_export l1_icache])
    end

    it "emits deterministic stub verilog" do
      source = harness.send(
        :emit_stub_verilog,
        {
          name: "ext_mem",
          parameters: %w[WIDTH DEPTH],
          ports: %w[clk addr data_o]
        }
      )

      expect(source).to include("module ext_mem")
      expect(source).to include("parameter DEPTH = 0,")
      expect(source).to include("parameter WIDTH = 0")
      expect(source).to include("addr,")
      expect(source).to include("clk,")
      expect(source).to include("data_o")
    end

    it "parses canonical event output lines into JSON-ready hashes" do
      stdout = <<~LOG
        EV avm_read 10 00123456 F 4
        EV avm_write 11 0012345A F DEADBEEF
        EV io_read 12 03F8 1
        EV io_write 13 03F8 1 00000041
        EV interrupt_done 14 20
        EV sample 15 1 0 00123456 89ABCDEF F 4 0 1 03F8 03F8 1
      LOG

      parsed = harness.send(:parse_events, stdout)

      expect(parsed).to eq(
        [
          { "kind" => "avm_read", "cycle" => 10, "address" => 0x0012_3456, "byteenable" => 0xF, "burstcount" => 0x4 },
          { "kind" => "avm_write", "cycle" => 11, "address" => 0x0012_345A, "byteenable" => 0xF, "data" => 0xDEAD_BEEF },
          { "kind" => "io_read", "cycle" => 12, "address" => 0x03F8, "length" => 0x1 },
          { "kind" => "io_write", "cycle" => 13, "address" => 0x03F8, "length" => 0x1, "data" => 0x41 },
          { "kind" => "interrupt_done", "cycle" => 14, "vector" => 0x20 },
          {
            "kind" => "sample",
            "cycle" => 15,
            "avm_read" => 1,
            "avm_write" => 0,
            "avm_address" => 0x0012_3456,
            "avm_writedata" => 0x89AB_CDEF,
            "avm_byteenable" => 0xF,
            "avm_burstcount" => 0x4,
            "io_read_do" => 0,
            "io_write_do" => 1,
            "io_read_address" => 0x03F8,
            "io_write_address" => 0x03F8,
            "interrupt_done" => 1
          }
        ]
      )
    end

    it "applies byteenable writes into trace memory and serves readback data" do
      memory = {}

      harness.send(
        :write_trace_memory_word,
        memory,
        address_word: 0x0000_0010,
        data: 0xDEAD_BEEF,
        byteenable: 0x3
      )

      seeded = harness.send(:trace_seed_word, 0x0000_0010)
      expected = (seeded & 0xFFFF_0000) | 0x0000_BEEF
      observed = harness.send(:read_trace_memory_word, memory, 0x0000_0010)
      untouched = harness.send(:read_trace_memory_word, memory, 0x0000_0020)

      expect(observed).to eq(expected)
      expect(untouched).to eq(harness.send(:trace_seed_word, 0x0000_0020))
    end

    it "emits a testbench memory bank with read and write helpers" do
      source = harness.send(:testbench_source, top: "ao486", cycles: 32)

      expect(source).to include("localparam integer MEM_WRITE_LOG_DEPTH = 4096;")
      expect(source).to include("function [31:0] mem_read_word;")
      expect(source).to include("task mem_write_word;")
      expect(source).to include("if (pending_read_words == 0 && avm_read && !avm_waitrequest) begin")
      expect(source).to include("mem_write_word(avm_address, avm_writedata, avm_byteenable);")
    end

    it "drives IR avm readdata from the backing trace memory after writes" do
      sim = FakeTraceIrSim.new(
        schedule: {
          4 => {
            "avm_write" => 1,
            "avm_address" => 0x0000_0010,
            "avm_writedata" => 0xDEAD_BEEF,
            "avm_byteenable" => 0xF
          },
          5 => {
            "avm_read" => 1,
            "avm_address" => 0x0000_0010,
            "avm_byteenable" => 0xF,
            "avm_burstcount" => 1
          }
        }
      )

      ir_harness = described_class.new(
        mode: "converted_ir",
        top: "ao486",
        out: ".",
        cycles: 8,
        source_root: ".",
        converted_export_mode: nil,
        cwd: Dir.pwd
      )

      events = ir_harness.send(:run_ir_trace_simulation, sim: sim)
      write_event = events.find { |event| event.fetch("kind") == "avm_write" }
      read_event = events.find { |event| event.fetch("kind") == "avm_read" }
      readback_cycles = sim.tick_inputs.each_with_index.filter_map do |inputs, cycle|
        cycle if Integer(inputs.fetch("avm_readdatavalid", 0)) != 0
      end

      expect(write_event).to include(
        "cycle" => 4,
        "address" => 0x0000_0010,
        "data" => 0xDEAD_BEEF
      )
      expect(read_event).to include(
        "cycle" => 5,
        "address" => 0x0000_0010
      )
      expect(readback_cycles.first).to eq(6)
      expect(Integer(sim.tick_inputs[6].fetch("avm_readdata"))).to eq(0xDEAD_BEEF)
    end

    it "connects reference-mode memory so avm writes can be read back", timeout: 60 do
      Dir.mktmpdir("ao486_trace_harness_memory_spec") do |root|
        source_root = File.join(root, "rtl")
        FileUtils.mkdir_p(source_root)

        File.write(
          File.join(source_root, "ao486.sv"),
          <<~VERILOG
            module ao486 (
              input wire clk,
              input wire rst_n,
              input wire a20_enable,
              input wire cache_disable,
              input wire interrupt_do,
              input wire [7:0] interrupt_vector,
              output wire interrupt_done,
              output wire [29:0] avm_address,
              output wire [31:0] avm_writedata,
              output wire [3:0] avm_byteenable,
              output wire [3:0] avm_burstcount,
              output wire avm_write,
              output wire avm_read,
              input wire avm_waitrequest,
              input wire avm_readdatavalid,
              input wire [31:0] avm_readdata,
              input wire [23:0] dma_address,
              input wire dma_16bit,
              input wire dma_write,
              input wire [15:0] dma_writedata,
              input wire dma_read,
              output wire [15:0] dma_readdata,
              output wire dma_readdatavalid,
              output wire dma_waitrequest,
              output wire io_read_do,
              output wire [15:0] io_read_address,
              output wire [2:0] io_read_length,
              input wire [31:0] io_read_data,
              input wire io_read_done,
              output wire io_write_do,
              output wire [15:0] io_write_address,
              output wire [2:0] io_write_length,
              output wire [31:0] io_write_data,
              input wire io_write_done
            );
              reg [2:0] state = 3'd0;

              always @(posedge clk) begin
                if (!rst_n) begin
                  state <= 3'd0;
                end else begin
                  case (state)
                    3'd0: state <= 3'd1;
                    3'd1: state <= 3'd2;
                    3'd2: if (avm_readdatavalid) state <= 3'd3;
                    default: state <= state;
                  endcase
                end
              end

              assign interrupt_done = 1'b0;

              assign avm_address = ((state == 3'd1) || (state == 3'd2)) ? 30'h00000010 : 30'h0;
              assign avm_writedata = 32'hDEAD_BEEF;
              assign avm_byteenable = 4'hF;
              assign avm_burstcount = 4'h1;
              assign avm_write = (state == 3'd1);
              assign avm_read = (state == 3'd2);

              assign dma_readdata = 16'h0;
              assign dma_readdatavalid = 1'b0;
              assign dma_waitrequest = 1'b0;

              assign io_read_do = 1'b0;
              assign io_read_address = 16'h0;
              assign io_read_length = 3'h0;

              assign io_write_do = (state == 3'd2) && avm_readdatavalid;
              assign io_write_address = 16'h03F8;
              assign io_write_length = 3'h1;
              assign io_write_data = avm_readdata;
            endmodule
          VERILOG
        )

        events = described_class.capture(
          mode: "reference",
          top: "ao486",
          out: root,
          cycles: 20,
          source_root: source_root,
          converted_export_mode: nil,
          cwd: Dir.pwd
        ).fetch("ao486")

        write_event = events.find { |event| event.fetch("kind") == "avm_write" }
        read_event = events.find { |event| event.fetch("kind") == "avm_read" }
        io_write_event = events.find { |event| event.fetch("kind") == "io_write" }

        expect(write_event).not_to be_nil
        expect(read_event).not_to be_nil
        expect(io_write_event).not_to be_nil
        expect(io_write_event.fetch("data")).to eq(0xDEAD_BEEF)
      end
    end

    it "preserves output-to-slice instance bindings when flattening converted ir modules" do
      parent = RHDL::Codegen::IR::ModuleDef.new(
        name: "parent",
        ports: [
          RHDL::Codegen::IR::Port.new(name: "prefetchfifo_used", direction: :out, width: 5)
        ],
        nets: [],
        regs: [
          RHDL::Codegen::IR::Reg.new(name: "prefetchfifo_used", width: 5, reset_value: 0)
        ],
        assigns: [],
        processes: [],
        reg_ports: ["prefetchfifo_used"],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      child = RHDL::Codegen::IR::ModuleDef.new(
        name: "child",
        ports: [
          RHDL::Codegen::IR::Port.new(name: "full", direction: :out, width: 1),
          RHDL::Codegen::IR::Port.new(name: "usedw", direction: :out, width: 4)
        ],
        nets: [],
        regs: [],
        assigns: [],
        processes: [],
        reg_ports: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      instance = RHDL::Codegen::IR::Instance.new(
        name: "u_fifo",
        module_name: "child",
        parameters: {},
        connections: [
          RHDL::Codegen::IR::PortConnection.new(
            port_name: :full,
            signal: RHDL::Codegen::IR::Slice.new(
              base: RHDL::Codegen::IR::Signal.new(name: :prefetchfifo_used, width: 5),
              range: 4..4,
              width: 1
            ),
            direction: :out
          ),
          RHDL::Codegen::IR::PortConnection.new(
            port_name: :usedw,
            signal: RHDL::Codegen::IR::Slice.new(
              base: RHDL::Codegen::IR::Signal.new(name: :prefetchfifo_used, width: 5),
              range: 3..0,
              width: 4
            ),
            direction: :out
          )
        ]
      )

      harness.send(:inline_child_instance, parent: parent, child: child, instance: instance)

      merged_assigns = parent.assigns.select { |assign| assign.target.to_s == "prefetchfifo_used" }
      expect(merged_assigns.length).to eq(1)

      merged_expr = merged_assigns.first.expr
      expect(merged_expr).to be_a(RHDL::Codegen::IR::BinaryOp)
      expect(merged_expr.width).to eq(5)

      rendered = RHDL::Codegen::Verilog.generate(parent)
      expect(rendered).to include("assign prefetchfifo_used =")
      expect(rendered).to include("u_fifo__full")
      expect(rendered).to include("u_fifo__usedw")
    end

    it "treats __rhdl_unconnected instance connections as open connections while flattening" do
      parent = RHDL::Codegen::IR::ModuleDef.new(
        name: "parent",
        ports: [
          RHDL::Codegen::IR::Port.new(name: "sink", direction: :out, width: 1)
        ],
        nets: [],
        regs: [],
        assigns: [],
        processes: [],
        reg_ports: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      child = RHDL::Codegen::IR::ModuleDef.new(
        name: "child",
        ports: [
          RHDL::Codegen::IR::Port.new(name: "in1", direction: :in, width: 1),
          RHDL::Codegen::IR::Port.new(name: "out1", direction: :out, width: 1)
        ],
        nets: [],
        regs: [],
        assigns: [
          RHDL::Codegen::IR::Assign.new(
            target: "out1",
            expr: RHDL::Codegen::IR::Signal.new(name: "in1", width: 1)
          )
        ],
        processes: [],
        reg_ports: [],
        instances: [],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      closed_output = RHDL::Codegen::IR::Instance.new(
        name: "u_closed",
        module_name: "child",
        parameters: {},
        connections: [
          RHDL::Codegen::IR::PortConnection.new(port_name: :in1, signal: :__rhdl_unconnected, direction: :in),
          RHDL::Codegen::IR::PortConnection.new(port_name: :out1, signal: :sink, direction: :out)
        ]
      )

      open_output = RHDL::Codegen::IR::Instance.new(
        name: "u_open",
        module_name: "child",
        parameters: {},
        connections: [
          RHDL::Codegen::IR::PortConnection.new(port_name: :in1, signal: :__rhdl_unconnected, direction: :in),
          RHDL::Codegen::IR::PortConnection.new(port_name: :out1, signal: :__rhdl_unconnected, direction: :out)
        ]
      )

      harness.send(:inline_child_instance, parent: parent, child: child, instance: closed_output)
      harness.send(:inline_child_instance, parent: parent, child: child, instance: open_output)

      assigns_to_unconnected = parent.assigns.select { |entry| entry.target.to_s == "__rhdl_unconnected" }
      expect(assigns_to_unconnected).to be_empty

      closed_assign = parent.assigns.find { |entry| entry.target.to_s == "u_closed__out1" }
      open_assign = parent.assigns.find { |entry| entry.target.to_s == "u_open__out1" }
      sink_assign = parent.assigns.find { |entry| entry.target.to_s == "sink" && entry.expr.is_a?(RHDL::Codegen::IR::Signal) && entry.expr.name.to_s == "u_closed__out1" }

      expect(closed_assign).not_to be_nil
      expect(open_assign).not_to be_nil
      expect(closed_assign.expr).to be_a(RHDL::Codegen::IR::Literal)
      expect(open_assign.expr).to be_a(RHDL::Codegen::IR::Literal)
      expect(closed_assign.expr.value).to eq(0)
      expect(open_assign.expr.value).to eq(0)
      expect(sink_assign).not_to be_nil
    end

    it "captures converted_ir traces using Ruby IR simulation without external simulators" do
      Dir.mktmpdir("ao486_trace_harness_ir_spec") do |root|
        out = File.join(root, "out")
        module_dir = File.join(out, "lib", "demo_project", "modules")
        report_dir = File.join(out, "reports")

        FileUtils.mkdir_p(module_dir)
        FileUtils.mkdir_p(report_dir)

        File.write(
          File.join(out, "rhdl_import.yml"),
          <<~YAML
            ---
            project: demo_project
          YAML
        )

        File.write(
          File.join(report_dir, "import_report.json"),
          JSON.generate({ project: { options: { include_dirs: [] } } })
        )

        File.write(
          File.join(module_dir, "ao486.rb"),
          <<~RUBY
            # frozen_string_literal: true

            class HarnessIrAo486 < RHDL::Component
              self._ports = []
              self._signals = []
              self._constants = []
              self._processes = []
              self._assignments = []
              self._instances = []
              self._generics = []

              include RHDL::DSL::Behavior
              include RHDL::DSL::Structure

              # source_module: ao486
              input :clk
              input :rst_n
              input :a20_enable
              input :cache_disable
              input :interrupt_do
              input :interrupt_vector, width: 8
              output :interrupt_done
              output :avm_address, width: 30
              output :avm_writedata, width: 32
              output :avm_byteenable, width: 4
              output :avm_burstcount, width: 4
              output :avm_write
              output :avm_read
              input :avm_waitrequest
              input :avm_readdatavalid
              input :avm_readdata, width: 32
              input :dma_address, width: 24
              input :dma_16bit
              input :dma_write
              input :dma_writedata, width: 16
              input :dma_read
              output :dma_readdata, width: 16
              output :dma_readdatavalid
              output :dma_waitrequest
              output :io_read_do
              output :io_read_address, width: 16
              output :io_read_length, width: 3
              input :io_read_data, width: 32
              input :io_read_done
              output :io_write_do
              output :io_write_address, width: 16
              output :io_write_length, width: 3
              output :io_write_data, width: 32
              input :io_write_done

              behavior do
                avm_read <= rst_n
                avm_write <= 0
                avm_address <= 0x0000_1234
                avm_writedata <= 0x89AB_CDEF
                avm_byteenable <= 0xF
                avm_burstcount <= 0x1
                io_read_do <= rst_n
                io_read_address <= 0x03F8
                io_read_length <= 0x1
                io_write_do <= rst_n
                io_write_address <= 0x03F8
                io_write_length <= 0x1
                io_write_data <= io_read_data
                interrupt_done <= io_read_done
                dma_readdata <= 0
                dma_readdatavalid <= 0
                dma_waitrequest <= 0
              end
            end
          RUBY
        )

        events = described_class.capture(
          mode: "converted_ir",
          top: "ao486",
          out: out,
          cycles: 6,
          source_root: "",
          converted_export_mode: nil,
          cwd: Dir.pwd
        )

        trace = events.fetch("ao486")
        sample_events = trace.select { |event| event.fetch("kind") == "sample" }

        expect(sample_events.length).to eq(7)
        expect(sample_events.map { |event| event.fetch("cycle") }).to eq((0..6).to_a)
        expect(sample_events.first).to include(
          "avm_read",
          "avm_write",
          "avm_address",
          "io_read_do",
          "io_write_do",
          "interrupt_done"
        )
      end
    end

    it "materializes converted source files from generated module ruby output" do
      Dir.mktmpdir("ao486_trace_harness_spec") do |root|
        out = File.join(root, "out")
        include_dir = File.join(root, "includes")
        module_dir = File.join(out, "lib", "demo_project", "modules")
        report_dir = File.join(out, "reports")
        work_dir = File.join(root, "work")

        FileUtils.mkdir_p(include_dir)
        FileUtils.mkdir_p(module_dir)
        FileUtils.mkdir_p(report_dir)
        FileUtils.mkdir_p(work_dir)

        File.write(
          File.join(out, "rhdl_import.yml"),
          <<~YAML
            ---
            project: demo_project
          YAML
        )

        File.write(
          File.join(report_dir, "import_report.json"),
          JSON.generate(
            {
              project: {
                options: {
                  include_dirs: [include_dir]
                }
              }
            }
          )
        )

        File.write(
          File.join(module_dir, "ao486.rb"),
          <<~RUBY
            # frozen_string_literal: true

            class HarnessSpecAo486 < RHDL::Component
              self._ports = []
              self._signals = []
              self._constants = []
              self._processes = []
              self._assignments = []
              self._instances = []
              self._generics = []

              include RHDL::DSL::Behavior
              include RHDL::DSL::Structure

              # source_module: ao486
              input :clk
            end
          RUBY
        )

        File.write(
          File.join(module_dir, "helper.rb"),
          <<~RUBY
            # frozen_string_literal: true

            class HarnessSpecHelper < RHDL::Component
              self._ports = []
              self._signals = []
              self._constants = []
              self._processes = []
              self._assignments = []
              self._instances = []
              self._generics = []

              include RHDL::DSL::Behavior
              include RHDL::DSL::Structure

              # source_module: helper
              output :done
            end
          RUBY
        )

        converted_harness = described_class.new(
          mode: "converted",
          top: "ao486",
          out: out,
          cycles: 32,
          source_root: "",
          converted_export_mode: nil,
          cwd: Dir.pwd
        )

        contract = converted_harness.send(:source_contract, work_dir: work_dir)

        generated_files = contract.fetch(:source_files)
        expect(generated_files.length).to eq(2)
        generated_files.each do |path|
          expect(path).to start_with(File.join(work_dir, "converted_sources"))
          expect(File.file?(path)).to be(true)
        end
        expect(File.read(generated_files.find { |path| path.end_with?("ao486.v") })).to include("module ao486")
        expect(File.read(generated_files.find { |path| path.end_with?("helper.v") })).to include("module helper")

        generated_include_dir = File.dirname(generated_files.first)
        expect(contract.fetch(:include_dirs)).to include(generated_include_dir, include_dir)
        expect(Object.const_defined?(:HarnessSpecAo486)).to be(false)
        expect(Object.const_defined?(:HarnessSpecHelper)).to be(false)
      end
    end

    it "evaluates converted module classes in project require order for dependent constants" do
      Dir.mktmpdir("ao486_trace_harness_order_spec") do |root|
        out = File.join(root, "out")
        lib_dir = File.join(out, "lib")
        module_dir = File.join(lib_dir, "demo_project", "modules")
        report_dir = File.join(out, "reports")
        work_dir = File.join(root, "work")

        FileUtils.mkdir_p(module_dir)
        FileUtils.mkdir_p(report_dir)
        FileUtils.mkdir_p(work_dir)

        File.write(
          File.join(out, "rhdl_import.yml"),
          <<~YAML
            ---
            project: demo_project
          YAML
        )

        File.write(
          File.join(lib_dir, "demo_project.rb"),
          <<~RUBY
            # frozen_string_literal: true

            require_relative "demo_project/modules/exception"
            require_relative "demo_project/modules/ao486"
          RUBY
        )

        File.write(
          File.join(report_dir, "import_report.json"),
          JSON.generate({ project: { options: { include_dirs: [] } } })
        )

        File.write(
          File.join(module_dir, "exception.rb"),
          <<~RUBY
            # frozen_string_literal: true

            class ImportedException < RHDL::Component
              self._ports = []
              self._signals = []
              self._constants = []
              self._processes = []
              self._assignments = []
              self._instances = []
              self._generics = []

              include RHDL::DSL::Behavior
              include RHDL::DSL::Structure

              # source_module: exception
              output :fault
            end
          RUBY
        )

        File.write(
          File.join(module_dir, "ao486.rb"),
          <<~RUBY
            # frozen_string_literal: true

            class Ao486 < RHDL::Component
              self._ports = []
              self._signals = []
              self._constants = []
              self._processes = []
              self._assignments = []
              self._instances = []
              self._generics = []

              include RHDL::DSL::Behavior
              include RHDL::DSL::Structure

              # source_module: ao486

              instance :u_exception, ImportedException
              input :clk
            end
          RUBY
        )

        converted_harness = described_class.new(
          mode: "converted",
          top: "ao486",
          out: out,
          cycles: 32,
          source_root: "",
          converted_export_mode: "component",
          cwd: Dir.pwd
        )

        contract = converted_harness.send(:source_contract, work_dir: work_dir)
        exported_top = contract.fetch(:source_files).find { |path| path.end_with?("ao486.v") }
        expect(exported_top).not_to be_nil
        expect(File.read(exported_top)).to include("module ao486")
      end
    end

    it "reloads converted module ruby files on repeated source export" do
      Dir.mktmpdir("ao486_trace_harness_reload_spec") do |root|
        out = File.join(root, "out")
        module_dir = File.join(out, "lib", "demo_project", "modules")
        report_dir = File.join(out, "reports")
        work_dir_one = File.join(root, "work_one")
        work_dir_two = File.join(root, "work_two")
        module_path = File.join(module_dir, "ao486.rb")

        FileUtils.mkdir_p(module_dir)
        FileUtils.mkdir_p(report_dir)
        FileUtils.mkdir_p(work_dir_one)
        FileUtils.mkdir_p(work_dir_two)

        File.write(
          File.join(out, "rhdl_import.yml"),
          <<~YAML
            ---
            project: demo_project
          YAML
        )

        File.write(
          File.join(report_dir, "import_report.json"),
          JSON.generate({ project: { options: { include_dirs: [] } } })
        )

        File.write(
          module_path,
          <<~RUBY
            # frozen_string_literal: true

            class HarnessReloadAo486 < RHDL::Component
              self._ports = []
              self._signals = []
              self._constants = []
              self._processes = []
              self._assignments = []
              self._instances = []
              self._generics = []

              include RHDL::DSL::Behavior
              include RHDL::DSL::Structure

              # source_module: ao486
              input :clk
            end
          RUBY
        )

        converted_harness = described_class.new(
          mode: "converted",
          top: "ao486",
          out: out,
          cycles: 32,
          source_root: "",
          converted_export_mode: nil,
          cwd: Dir.pwd
        )

        first_contract = converted_harness.send(:source_contract, work_dir: work_dir_one)
        first_export = File.read(first_contract.fetch(:source_files).first)
        expect(first_export).to include("module ao486")
        expect(first_export).to include("input clk")
        expect(first_export).not_to include("input rst_n")

        File.write(
          module_path,
          <<~RUBY
            # frozen_string_literal: true

            class HarnessReloadAo486 < RHDL::Component
              self._ports = []
              self._signals = []
              self._constants = []
              self._processes = []
              self._assignments = []
              self._instances = []
              self._generics = []

              include RHDL::DSL::Behavior
              include RHDL::DSL::Structure

              # source_module: ao486
              input :clk
              input :rst_n
            end
          RUBY
        )

        second_contract = converted_harness.send(:source_contract, work_dir: work_dir_two)
        second_export = File.read(second_contract.fetch(:source_files).first)
        expect(second_export).to include("module ao486")
        expect(second_export).to include("input rst_n")
      end
    end

    it "supports dsl_super converted export mode for generated modules" do
      Dir.mktmpdir("ao486_trace_harness_export_mode_spec") do |root|
        out = File.join(root, "out")
        module_dir = File.join(out, "lib", "demo_project", "modules")
        report_dir = File.join(out, "reports")
        work_dir = File.join(root, "work")
        module_path = File.join(module_dir, "ao486.rb")

        FileUtils.mkdir_p(module_dir)
        FileUtils.mkdir_p(report_dir)
        FileUtils.mkdir_p(work_dir)

        File.write(
          File.join(out, "rhdl_import.yml"),
          <<~YAML
            ---
            project: demo_project
          YAML
        )

        File.write(
          File.join(report_dir, "import_report.json"),
          JSON.generate({ project: { options: { include_dirs: [] } } })
        )

        File.write(
          module_path,
          <<~'RUBY'
            # frozen_string_literal: true

            class HarnessDslSuperAo486 < RHDL::Component
              self._ports = []
              self._signals = []
              self._constants = []
              self._processes = []
              self._assignments = []
              self._instances = []
              self._generics = []

              include RHDL::DSL::Behavior
              include RHDL::DSL::Structure

              # source_module: ao486

              input :clk

              def self.to_verilog(top_name: nil)
                "BAD_MARKER_#{top_name}\n"
              end
            end
          RUBY
        )

        converted_harness = described_class.new(
          mode: "converted",
          top: "ao486",
          out: out,
          cycles: 32,
          source_root: "",
          converted_export_mode: "dsl_super",
          cwd: Dir.pwd
        )

        contract = converted_harness.send(:source_contract, work_dir: work_dir)
        exported = File.read(contract.fetch(:source_files).first)

        expect(exported).to include("module ao486")
        expect(exported).to include("input clk")
        expect(exported).not_to include("BAD_MARKER")
      end
    end

    it "uses canonical export in component mode even when class defines to_verilog" do
      Dir.mktmpdir("ao486_trace_harness_component_export_mode_spec") do |root|
        out = File.join(root, "out")
        module_dir = File.join(out, "lib", "demo_project", "modules")
        report_dir = File.join(out, "reports")
        work_dir = File.join(root, "work")
        module_path = File.join(module_dir, "ao486.rb")

        FileUtils.mkdir_p(module_dir)
        FileUtils.mkdir_p(report_dir)
        FileUtils.mkdir_p(work_dir)

        File.write(
          File.join(out, "rhdl_import.yml"),
          <<~YAML
            ---
            project: demo_project
          YAML
        )

        File.write(
          File.join(report_dir, "import_report.json"),
          JSON.generate({ project: { options: { include_dirs: [] } } })
        )

        File.write(
          module_path,
          <<~'RUBY'
            # frozen_string_literal: true

            class HarnessComponentAo486 < RHDL::Component
              self._ports = []
              self._signals = []
              self._constants = []
              self._processes = []
              self._assignments = []
              self._instances = []
              self._generics = []

              include RHDL::DSL::Behavior
              include RHDL::DSL::Structure

              # source_module: ao486

              input :clk

              def self.to_verilog(top_name: nil)
                "BAD_MARKER_#{top_name}\n"
              end
            end
          RUBY
        )

        converted_harness = described_class.new(
          mode: "converted",
          top: "ao486",
          out: out,
          cycles: 32,
          source_root: "",
          converted_export_mode: "component",
          cwd: Dir.pwd
        )

        contract = converted_harness.send(:source_contract, work_dir: work_dir)
        exported = File.read(contract.fetch(:source_files).first)

        expect(exported).to include("module ao486")
        expect(exported).to include("input clk")
        expect(exported).not_to include("BAD_MARKER")
      end
    end

    it "falls back to canonical export when dsl_super has no override" do
      Dir.mktmpdir("ao486_trace_harness_dsl_super_fallback_spec") do |root|
        out = File.join(root, "out")
        module_dir = File.join(out, "lib", "demo_project", "modules")
        report_dir = File.join(out, "reports")
        work_dir = File.join(root, "work")
        module_path = File.join(module_dir, "ao486.rb")

        FileUtils.mkdir_p(module_dir)
        FileUtils.mkdir_p(report_dir)
        FileUtils.mkdir_p(work_dir)

        File.write(
          File.join(out, "rhdl_import.yml"),
          <<~YAML
            ---
            project: demo_project
          YAML
        )

        File.write(
          File.join(report_dir, "import_report.json"),
          JSON.generate({ project: { options: { include_dirs: [] } } })
        )

        File.write(
          module_path,
          <<~'RUBY'
            # frozen_string_literal: true

            class HarnessDslSuperFallbackAo486 < RHDL::Component
              self._ports = []
              self._signals = []
              self._constants = []
              self._processes = []
              self._assignments = []
              self._instances = []
              self._generics = []

              include RHDL::DSL::Behavior
              include RHDL::DSL::Structure

              # source_module: ao486
              input :clk
            end
          RUBY
        )

        converted_harness = described_class.new(
          mode: "converted",
          top: "ao486",
          out: out,
          cycles: 32,
          source_root: "",
          converted_export_mode: "dsl_super",
          cwd: Dir.pwd
        )

        contract = converted_harness.send(:source_contract, work_dir: work_dir)
        exported = File.read(contract.fetch(:source_files).first)

        expect(exported).to include("module ao486")
        expect(exported).to include("input clk")
      end
    end
  end
end
