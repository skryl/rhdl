# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"
require "stringio"
require "tempfile"
require "tmpdir"

load File.expand_path("../../../../examples/ao486/bin/ao486", __dir__)

RSpec.describe RHDL::Examples::AO486::CLI do
  def with_temp_binary(bytes = [0x90, 0x90, 0x90, 0x90].pack("C*"))
    file = Tempfile.new(["ao486_cli", ".bin"])
    file.binmode
    file.write(bytes)
    file.flush
    yield file.path
  ensure
    file.close!
  end

  def build_fake_task_class
    Class.new do
      class << self
        attr_accessor :last_instance
      end

      attr_reader :options, :load_program_args, :ran

      define_method(:initialize) do |options, **_kwargs|
        @options = options
        self.class.last_instance = self
      end

      define_method(:load_program) do |path, base_addr:|
        @load_program_args = { path: path, base_addr: base_addr }
      end

      define_method(:run) do
        @ran = true
        {
          "pc_sequence" => [0x000F_FFF0],
          "instruction_sequence" => [0x9090_9090],
          "memory_writes" => [],
          "memory_contents" => {}
        }
      end
    end
  end

  it "parses AO486 CLI options and dispatches task execution" do
    with_temp_binary do |program_path|
      with_temp_binary("SYSB") do |bios_system|
        with_temp_binary("VIDB") do |bios_video|
          with_temp_binary("DSK!") do |disk_path|
            out = StringIO.new
            task_class = build_fake_task_class

            exit_code = described_class.run(
              [
                "--mode", "ir",
                "--sim", "compile",
                "--debug",
                "--headless",
                "--cycles", "256",
                "--speed", "32",
                "--io", "vga",
                "--address", "0x000ffff0",
                "--bios",
                "--bios-system", bios_system,
                "--bios-video", bios_video,
                "--boot-addr", "0x000ffff0",
                "--disk", disk_path,
                program_path
              ],
              out: out,
              task_class: task_class
            )

            instance = task_class.last_instance
            expect(exit_code).to eq(0)
            expect(instance.options).to include(
              mode: :ir,
              sim: :compiler,
              debug: true,
              headless: true,
              cycles: 256,
              speed: 32,
              io: :vga,
              bios: true,
              bios_system: bios_system,
              bios_video: bios_video,
              boot_addr: 0x000F_FFF0,
              disk: disk_path
            )
            expect(instance.load_program_args).to eq(
              path: program_path,
              base_addr: 0x000F_FFF0
            )
            expect(instance.ran).to eq(true)
          end
        end
      end
    end
  end

  it "rejects missing program when BIOS mode is not enabled" do
    out = StringIO.new
    task_class = build_fake_task_class

    exit_code = described_class.run([], out: out, task_class: task_class)

    expect(exit_code).to eq(1)
    expect(out.string).to include("Error: No program specified.")
  end

  it "accepts BIOS-only invocation and delegates to task run" do
    out = StringIO.new
    task_class = build_fake_task_class

    exit_code = described_class.run(["--bios"], out: out, task_class: task_class)

    expect(exit_code).to eq(0)
    expect(task_class.last_instance.ran).to eq(true)
  end

  it "accepts --dos invocation and expands default BIOS and disk paths" do
    out = StringIO.new
    task_class = build_fake_task_class

    exit_code = described_class.run(["--dos"], out: out, task_class: task_class)
    instance = task_class.last_instance

    expect(exit_code).to eq(0)
    expect(instance.ran).to eq(true)
    expect(instance.options.fetch(:dos)).to eq(true)
    expect(instance.options.fetch(:bios)).to eq(true)
    expect(File.file?(instance.options.fetch(:bios_system))).to eq(true)
    expect(File.file?(instance.options.fetch(:bios_video))).to eq(true)
    expect(File.file?(instance.options.fetch(:disk))).to eq(true)
  end

  it "rejects combining --dos with an explicit program binary" do
    with_temp_binary do |program_path|
      out = StringIO.new
      task_class = build_fake_task_class

      exit_code = described_class.run(["--dos", program_path], out: out, task_class: task_class)

      expect(exit_code).to eq(1)
      expect(out.string).to include("--dos cannot be combined")
    end
  end

  it "surfaces NotImplementedError from task run as a user-facing error" do
    out = StringIO.new
    task_class = Class.new do
      define_method(:initialize) { |_options, **_kwargs| }
      define_method(:run) { raise NotImplementedError, "feature not implemented yet" }
    end

    exit_code = described_class.run(["--bios"], out: out, task_class: task_class)

    expect(exit_code).to eq(1)
    expect(out.string).to include("feature not implemented yet")
    expect(out.string).not_to include("traceback")
  end

  it "renders ao486 binary help with expected option surface" do
    out = StringIO.new
    task_class = build_fake_task_class

    exit_code = described_class.run(["--help"], out: out, task_class: task_class)

    expect(exit_code).to eq(0)
    expect(out.string).to include("AO486 Runner")
    expect(out.string).to include("--mode")
    expect(out.string).to include("--sim")
    expect(out.string).to include("--bios")
    expect(out.string).to include("--dos")
    expect(out.string).to include("--bios-system")
    expect(out.string).to include("--bios-video")
    expect(out.string).to include("--boot-addr")
    expect(out.string).to include("--disk")
  end

  it "wires rhdl examples ao486 in top-level help and subcommand dispatch" do
    project_root = File.expand_path("../../../../", __dir__)
    cli_path = File.join(project_root, "exe/rhdl")

    help_stdout, help_stderr, help_status = Open3.capture3(
      RbConfig.ruby,
      "-Ilib",
      cli_path,
      "examples",
      "--help",
      chdir: project_root
    )

    sub_stdout, sub_stderr, sub_status = Open3.capture3(
      RbConfig.ruby,
      "-Ilib",
      cli_path,
      "examples",
      "ao486",
      "--help",
      chdir: project_root
    )

    expect(help_status.success?).to eq(true)
    expect(help_stderr).not_to include("Unknown examples subcommand")
    expect(help_stdout).to include("ao486")
    expect(help_stdout).to include("riscv")

    expect(sub_status.success?).to eq(true)
    expect(sub_stderr).not_to include("Unknown examples subcommand")
    expect(sub_stdout).to include("AO486 Runner")
    expect(sub_stdout).to include("--bios")
  end
end
