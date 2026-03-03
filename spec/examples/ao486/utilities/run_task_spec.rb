# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "tempfile"

require_relative "../../../../examples/ao486/utilities/tasks/run_task"

RSpec.describe RHDL::Examples::AO486::Tasks::RunTask do
  class FakeHeadlessRunner
    class << self
      attr_accessor :instances
    end

    attr_reader :init_kwargs, :run_calls, :run_dos_boot_calls

    def initialize(**kwargs)
      @init_kwargs = kwargs
      @run_calls = []
      @run_dos_boot_calls = []
      self.class.instances ||= []
      self.class.instances << self
    end

    def run_program(**kwargs)
      @run_calls << kwargs
      {
        "pc_sequence" => [0x000F_FFF0, 0x000F_FFF4],
        "instruction_sequence" => [0xBB12_34B8, 0xD801_00F0],
        "memory_writes" => [
          {
            "cycle" => 12,
            "address" => 0x0000_0200,
            "data" => 0xABCD_1324,
            "byteenable" => 0x3
          }
        ],
        "memory_contents" => {
          "00000200" => 0xABCD_1324
        }
      }
    end

    def run_dos_boot(**kwargs)
      @run_dos_boot_calls << kwargs
      {
        "pc_sequence" => [0x000F_FFF0],
        "instruction_sequence" => [0xEA00_F000],
        "memory_writes" => [],
        "memory_contents" => {},
        "serial_output" => "Starting MS-DOS\r\nC:\\>",
        "milestones" => ["serial:Starting MS-DOS", "prompt:C:\\>"]
      }
    end

    def supports_live_cycles?
      false
    end
  end

  class LiveFakeHeadlessRunner < FakeHeadlessRunner
    attr_reader :load_program_calls, :load_dos_boot_calls, :run_cycles_calls, :keyboard_bytes

    def initialize(**kwargs)
      super
      @cycles = 0
      @load_program_calls = []
      @load_dos_boot_calls = []
      @run_cycles_calls = []
      @keyboard_bytes = []
      @state = {
        "pc" => 0x000F_FFF0,
        "instruction" => 0x9090_9090,
        "cycles" => 0,
        "memory_write_count" => 0,
        "serial_output" => "",
        "memory_contents" => {},
        "vga_text_lines" => ["", ""]
      }
    end

    def supports_live_cycles?
      true
    end

    def load_program(**kwargs)
      @load_program_calls << kwargs
    end

    def load_dos_boot(**kwargs)
      @load_dos_boot_calls << kwargs
      @state["serial_output"] = "Starting MS-DOS\r\nC:\\>"
    end

    def run_cycles(cycles)
      @run_cycles_calls << cycles
      @cycles += Integer(cycles)
      @state["cycles"] = @cycles
      @state["pc"] = (0x000F_FFF0 + (@cycles & 0xFF)) & 0xFFFF_FFFF
      @state["instruction"] = 0x9090_9090
      @state["vga_text_lines"] = ["Starting MS-DOS C:\\>", ""] if @cycles >= 64
      @state
    end

    def state
      @state
    end

    def send_keyboard_bytes(bytes)
      @keyboard_bytes.concat(Array(bytes).map { |entry| Integer(entry) & 0xFF })
      true
    end
  end

  let(:output) { StringIO.new }
  let(:program_file) do
    Tempfile.new(["ao486_prog", ".bin"]).tap do |file|
      file.binmode
      file.write([0xB8, 0x34, 0x12, 0xBB].pack("C*"))
      file.flush
    end
  end

  after do
    program_file.close!
    FakeHeadlessRunner.instances = []
    LiveFakeHeadlessRunner.instances = []
  end

  def build_task(options = {})
    described_class.new(
      {
        headless: true,
        cycles: 64,
        mode: :ir,
        sim: :compile,
        cwd: File.expand_path("../../../../", __dir__)
      }.merge(options),
      runner_class: FakeHeadlessRunner,
      out: output
    )
  end

  it "builds AO486 headless runner with IR compiler defaults" do
    build_task
    runner = FakeHeadlessRunner.instances.fetch(0)

    expect(runner.init_kwargs.fetch(:mode)).to eq(:ir)
    expect(runner.init_kwargs.fetch(:backend)).to eq(:compiler)
    expect(runner.init_kwargs.fetch(:allow_fallback)).to eq(false)
  end

  it "loads a program and executes a headless run via runner API" do
    task = build_task
    task.load_program(program_file.path, base_addr: 0x000F_FFF0)

    trace = task.run
    runner = FakeHeadlessRunner.instances.fetch(0)
    run_call = runner.run_calls.fetch(0)

    expect(run_call).to include(
      program_binary: program_file.path,
      cycles: 64,
      program_base_address: 0x000F_FFF0
    )
    expect(trace.fetch("pc_sequence")).to eq([0x000F_FFF0, 0x000F_FFF4])
    expect(output.string).to include("AO486 Headless")
  end

  it "maps --sim jit onto the ir backend used by the runner" do
    task = build_task(sim: :jit)
    task.load_program(program_file.path)
    task.run

    runner = FakeHeadlessRunner.instances.fetch(0)
    expect(runner.init_kwargs.fetch(:backend)).to eq(:jit)
  end

  it "routes non-headless run through interactive path" do
    task = build_task(headless: false)
    task.load_program(program_file.path)
    allow(task).to receive(:run_interactive).and_return(:ok)

    expect(task.run).to eq(:ok)
    expect(task).to have_received(:run_interactive)
  end

  it "runs BIOS mode through run_dos_boot when no program binary is provided" do
    task = build_task(bios: true)
    trace = task.run
    runner = FakeHeadlessRunner.instances.fetch(0)

    expect(runner.run_calls).to be_empty
    expect(runner.run_dos_boot_calls.length).to eq(1)
    expect(trace.fetch("serial_output")).to include("C:\\>")
  end

  it "uses live cycle loop in interactive mode when runner supports live cycles" do
    task = described_class.new(
      {
        headless: false,
        mode: :ir,
        sim: :compile,
        debug: true,
        speed: 32,
        cwd: File.expand_path("../../../../", __dir__)
      },
      runner_class: LiveFakeHeadlessRunner,
      out: output
    )
    task.load_program(program_file.path, base_addr: 0x000F_FFF0)

    runner = LiveFakeHeadlessRunner.instances.last
    allow(task).to receive(:setup_terminal_input_mode)
    allow(task).to receive(:tty_out?).and_return(false)
    allow(task).to receive(:handle_keyboard_input) do
      task.instance_variable_set(:@running, false) if runner.run_cycles_calls.length >= 2
    end

    result = task.run

    expect(runner.load_program_calls).not_to be_empty
    expect(runner.run_cycles_calls.length).to be >= 2
    expect(result.fetch("cycles")).to be >= 64
    expect(output.string).to include("AO486 MMAP View")
    expect(output.string).to include("|PC:")
    expect(output.string).to include("Starting MS-DOS C:\\>")
  end

  it "forwards normalized keyboard bytes to the live runner" do
    task = described_class.new(
      {
        headless: false,
        mode: :ir,
        sim: :compile,
        debug: false,
        speed: 32,
        cwd: File.expand_path("../../../../", __dir__)
      },
      runner_class: LiveFakeHeadlessRunner,
      out: output
    )
    task.load_program(program_file.path, base_addr: 0x000F_FFF0)

    runner = LiveFakeHeadlessRunner.instances.last
    runner.load_program(program_binary: program_file.path, program_base_address: 0x000F_FFF0, data_check_addresses: [0x0000_0200])
    task.instance_variable_set(:@live_state, runner.state)
    task.instance_variable_set(:@running, true)

    task.send(:process_keyboard_bytes, [65, 13, 127]) # A, Enter, Backspace

    expect(runner.keyboard_bytes).to eq([65, 10, 8])
  end
end
