# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/checks/ao486_program_parity_harness"

RSpec.describe RHDL::Import::Checks::Ao486ProgramParityHarness, :no_vendor_reimport do
  class FakeProgramIrSim
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

  class FakeRunnerAo486Sim
    attr_reader :run_cycles_calls

    def initialize(events_text:)
      @event_batches = Array(events_text).map(&:to_s)
      @memory = {}
      @inputs = {}
      @run_cycles_calls = []
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

    def runner_kind
      :ao486
    end

    def reset
      nil
    end

    def poke(name, value)
      @inputs[name.to_s] = Integer(value)
    end

    def evaluate
      nil
    end

    def runner_run_cycles(n, _key_data = 0, _key_ready = false)
      @run_cycles_calls << Integer(n)
      { cycles_run: Integer(n) }
    end

    def runner_ao486_take_events
      @event_batches.shift.to_s
    end

    def runner_write_memory(offset, data, mapped: true)
      _mapped = mapped
      base = Integer(offset) & 0xFFFF_FFFF
      bytes = data.is_a?(String) ? data.bytes : Array(data)
      bytes.each_with_index do |byte, index|
        @memory[(base + index) & 0xFFFF_FFFF] = Integer(byte) & 0xFF
      end
      bytes.length
    end

    def runner_read_memory(offset, length, mapped: true)
      _mapped = mapped
      base = Integer(offset) & 0xFFFF_FFFF
      len = Integer(length)
      Array.new(len) { |index| @memory.fetch((base + index) & 0xFFFF_FFFF, 0) }
    end
  end

  let(:base_trace) do
    {
      "pc_sequence" => [0x000F_FFE0, 0x000F_FFE4, 0x000F_FFE8, 0x000F_FFEC, 0xFFFF_FFF0, 0x000F_FFF4, 0x000F_FFF8],
      "instruction_sequence" => [0x9090_9090, 0x9090_9090, 0x9090_9090, 0x9090_9090, 0xBB12_34B8, 0xD801_00F0, 0xB902_00A3],
      "memory_writes" => [
        {
          "cycle" => 12,
          "address" => 0x0000_0200,
          "data" => 0xABCD_1324,
          "byteenable" => 0x3
        }
      ],
      "memory_contents" => {
        "fffffff0" => 0xBB12_34B8,
        "fffffff4" => 0xD801_00F0,
        "000ffff0" => 0xBB12_34B8,
        "000ffff4" => 0xD801_00F0,
        "000ffff8" => 0xB902_00A3,
        "00000200" => 0xABCD_1324
      }
    }
  end

  it "assembles a deterministic reset-vector program from assembly source" do
    expect(described_class::PROGRAM_ASM_SOURCE).to include("mov ax, 0x1234")
    expect(described_class::PROGRAM_ASM_SOURCE).to include("mov [0x0202], cx")
    program_words = described_class::PROGRAM_LAYOUT.fetch(:memory_words)
    expect(program_words.fetch(0x000F_FFF0)).to eq(0xBB12_34B8)
    expect(program_words.fetch(0x000F_FFF4)).to eq(0xD801_00F0)
    expect(program_words.fetch(0x000F_FFF8)).to eq(0xB902_00A3)
    expect(program_words.fetch(described_class::DATA_CHECK_ADDRESS)).to eq(0)
  end

  it "injects a reset-vector far jump for binaries loaded away from 0x000ffff0" do
    Dir.mktmpdir do |dir|
      binary_path = File.join(dir, "sparse_program.bin")
      File.binwrite(binary_path, [0x90, 0x90, 0xEB, 0xFE].pack("C*"))

      layout = described_class.binary_layout_from_file(
        binary_path: binary_path,
        data_addresses: [0x0000_0200],
        base_address: 0x0000_8000,
        cwd: dir
      )

      memory_words = layout.fetch(:memory_words)
      fetch_addresses = layout.fetch(:fetch_addresses)
      tracked_addresses = layout.fetch(:tracked_addresses)

      expect(memory_words.fetch(0x000F_FFF0)).to eq(0x0000_00EA)
      expect(memory_words.fetch(0x000F_FFF4)).to eq(0x9090_9008)
      expect(memory_words.fetch(0x0000_8000)).to eq(0xFEEB_9090)
      expect(fetch_addresses).to include(0x000F_FFF0, 0xFFFF_FFF0, 0x0000_8000)
      expect(tracked_addresses.length).to be < 32
    end
  end

  it "emits an altdpram fallback stub that performs read/write behavior" do
    harness = described_class.new(out: "tmp/out", top: "ao486", cycles: 8, source_root: "", cwd: Dir.pwd)
    stub_source = harness.send(
      :emit_stub_verilog,
      {
        name: "altdpram",
        parameters: %w[width widthad width_byteena],
        ports: %w[
          aclr byteena data inclock inclocken outclock outclocken q
          rdaddress rdaddressstall rden sclr wraddress wraddressstall wren
        ]
      }
    )

    Dir.mktmpdir do |dir|
      source_path = File.join(dir, "tb_altdpram.v")
      File.write(
        source_path,
        <<~VERILOG
          #{stub_source}

          module tb_altdpram;
            reg aclr = 1'b0;
            reg [0:0] byteena = 1'b1;
            reg [7:0] data = 8'h00;
            reg inclock = 1'b0;
            reg inclocken = 1'b1;
            reg outclock = 1'b0;
            reg outclocken = 1'b1;
            wire [7:0] q;
            reg [3:0] rdaddress = 4'h0;
            reg rdaddressstall = 1'b0;
            reg rden = 1'b1;
            reg sclr = 1'b0;
            reg [3:0] wraddress = 4'h0;
            reg wraddressstall = 1'b0;
            reg wren = 1'b0;

            altdpram #(
              .width(8),
              .widthad(4),
              .width_byteena(1)
            ) dut (
              .aclr(aclr),
              .byteena(byteena),
              .data(data),
              .inclock(inclock),
              .inclocken(inclocken),
              .outclock(outclock),
              .outclocken(outclocken),
              .q(q),
              .rdaddress(rdaddress),
              .rdaddressstall(rdaddressstall),
              .rden(rden),
              .sclr(sclr),
              .wraddress(wraddress),
              .wraddressstall(wraddressstall),
              .wren(wren)
            );

            initial begin
              wraddress = 4'h3;
              data = 8'hA5;
              wren = 1'b1;
              inclock = 1'b1;
              #1;
              inclock = 1'b0;
              wren = 1'b0;
              #1;

              rdaddress = 4'h3;
              inclock = 1'b1;
              #1;
              inclock = 1'b0;
              #1;

              if (q !== 8'hA5) begin
                $display("altdpram stub readback mismatch q=%02x", q);
                $finish_and_return(1);
              end

              $finish_and_return(0);
            end
          endmodule
        VERILOG
      )

      compile_stdout, compile_stderr, compile_status = Open3.capture3(
        "iverilog",
        "-g2012",
        "-s",
        "tb_altdpram",
        "-o",
        "sim.out",
        source_path,
        chdir: dir
      )
      unless compile_status.success?
        raise "iverilog compile failed status=#{compile_status.exitstatus} stdout=#{compile_stdout} stderr=#{compile_stderr}"
      end

      run_stdout, run_stderr, run_status = Open3.capture3("vvp", "sim.out", chdir: dir)
      unless run_status.success?
        raise "vvp run failed status=#{run_status.exitstatus} stdout=#{run_stdout} stderr=#{run_stderr}"
      end
    end
  end

  it "passes when reference/generated verilog/generated ir program traces match and execute" do
    harness = described_class.new(out: "tmp/out", top: "ao486", cycles: 32, source_root: "", cwd: Dir.pwd)

    allow(harness).to receive(:source_contract).and_return(
      { source_files: ["reference.v"], include_dirs: [] },
      { source_files: ["generated.v"], include_dirs: [] }
    )
    allow(harness).to receive(:build_ir_simulator).and_return(double("ir_sim"))
    allow(harness).to receive(:run_verilog_program).and_return(base_trace, base_trace)
    allow(harness).to receive(:run_ir_program).and_return(base_trace)

    result = harness.run

    expect(result[:status]).to eq("pass")
    expect(result.dig(:summary, :fail_count)).to eq(0)
    expect(result[:mismatches]).to eq([])
  end

  it "fails when generated ir diverges from reference program memory results" do
    harness = described_class.new(out: "tmp/out", top: "ao486", cycles: 32, source_root: "", cwd: Dir.pwd)
    diverged_ir = Marshal.load(Marshal.dump(base_trace))
    diverged_ir["memory_contents"]["00000200"] = 0x0000_0000

    allow(harness).to receive(:source_contract).and_return(
      { source_files: ["reference.v"], include_dirs: [] },
      { source_files: ["generated.v"], include_dirs: [] }
    )
    allow(harness).to receive(:build_ir_simulator).and_return(double("ir_sim"))
    allow(harness).to receive(:run_verilog_program).and_return(base_trace, base_trace)
    allow(harness).to receive(:run_ir_program).and_return(diverged_ir)

    result = harness.run

    expect(result[:status]).to eq("fail")
    expect(result.dig(:summary, :fail_count)).to be > 0
    mismatch_kinds = result[:mismatches].map { |entry| entry["kind"] }.uniq
    expect(mismatch_kinds).to include("memory_contents")
    expect(mismatch_kinds).to include("program_data_word")
  end

  it "drives memory readdata valid on the next cycle after an avm_read request" do
    request_address = 0x000F_FFF0 >> 2
    sim = FakeProgramIrSim.new(
      schedule: {
        10 => {
          "avm_read" => 1,
          "avm_address" => request_address,
          "avm_burstcount" => 1
        }
      }
    )
    harness = described_class.new(out: "tmp/out", top: "ao486", cycles: 16, source_root: "", cwd: Dir.pwd)

    result = harness.send(:run_ir_program, sim: sim)
    valid_cycles = sim.tick_inputs.each_with_index.filter_map do |inputs, cycle|
      cycle if Integer(inputs.fetch("avm_readdatavalid", 0)) != 0
    end

    expect(valid_cycles.first).to eq(11)
    expect(result.fetch("pc_sequence")).to include(0x000F_FFF0)
  end

  it "updates backing memory on writes and serves readback data in ir mode" do
    data_address = described_class::DATA_CHECK_ADDRESS
    request_address = data_address >> 2
    sim = FakeProgramIrSim.new(
      schedule: {
        10 => {
          "avm_write" => 1,
          "avm_address" => request_address,
          "avm_writedata" => 0xDEAD_BEEF,
          "avm_byteenable" => 0xF
        },
        11 => {
          "avm_read" => 1,
          "avm_address" => request_address,
          "avm_burstcount" => 1
        }
      }
    )
    harness = described_class.new(out: "tmp/out", top: "ao486", cycles: 20, source_root: "", cwd: Dir.pwd)

    result = harness.send(:run_ir_program, sim: sim)
    valid_cycles = sim.tick_inputs.each_with_index.filter_map do |inputs, cycle|
      cycle if Integer(inputs.fetch("avm_readdatavalid", 0)) != 0
    end

    expect(valid_cycles.first).to eq(12)
    expect(Integer(sim.tick_inputs[12].fetch("avm_readdata"))).to eq(0xDEAD_BEEF)
    expect(result.fetch("memory_writes")).to include(
      hash_including(
        "cycle" => 10,
        "address" => data_address,
        "data" => 0xDEAD_BEEF,
        "byteenable" => 0xF
      )
    )
    expect(result.fetch("memory_contents").fetch(format("%08x", data_address))).to eq(0xDEAD_BEEF)
  end

  it "uses ao486 runner batched execution for IR when runner extensions are available" do
    sim = FakeRunnerAo486Sim.new(
      events_text: [
        "",
        <<~LOG
          EV IF 10 000ffff0 bb1234b8
          EV WR 12 00000200 deadbeef f
        LOG
      ]
    )
    harness = described_class.new(out: "tmp/out", top: "ao486", cycles: 16, source_root: "", cwd: Dir.pwd)

    result = harness.send(:run_ir_program, sim: sim)

    expect(sim.run_cycles_calls).to eq([4, 13])
    expect(result.fetch("pc_sequence")).to include(0x000F_FFF0)
    expect(result.fetch("instruction_sequence")).to include(0xBB12_34B8)
    expect(result.fetch("memory_writes")).to include(
      hash_including(
        "cycle" => 12,
        "address" => 0x0000_0200,
        "data" => 0xDEAD_BEEF,
        "byteenable" => 0xF
      )
    )
  end
end
