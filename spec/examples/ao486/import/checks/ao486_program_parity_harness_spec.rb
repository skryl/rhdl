# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/checks/ao486_program_parity_harness"

RSpec.describe RHDL::Import::Checks::Ao486ProgramParityHarness do
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
end
