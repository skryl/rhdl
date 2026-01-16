require "spec_helper"

RSpec.describe "VHDL HDL export" do
  before do
    skip "GHDL not installed" unless HdlToolchain.ghdl_available?
  end

  def run_case(component:, reference:, cycles:, clocked:, input_builder:)
    top_name = component.name.split("::").last.underscore
    base_dir = File.join("tmp/hdl_export", top_name, "vhdl")
    FileUtils.mkdir_p(base_dir)

    vectors = HdlExportHelper.build_vectors(
      reference,
      cycles: cycles,
      clocked: clocked,
      input_builder: input_builder
    )

    ports = component._ports.map do |port|
      { name: port.name, width: port.width, direction: port.direction }
    end

    module_path = File.join(base_dir, "#{top_name}.vhd")
    tb_path = File.join(base_dir, "tb.vhd")

    File.write(module_path, RHDL::Export.vhdl(component, top_name: top_name))
    HdlExportHelper.write_vhdl_testbench(
      tb_path,
      top_name: top_name,
      ports: ports,
      output_names: vectors[:output_names],
      vectors: vectors[:inputs],
      clocked: clocked
    )

    compile_module = HdlExportHelper.run_cmd(["ghdl", "-a", "--std=08", "#{top_name}.vhd"], cwd: base_dir)
    expect(compile_module[:status].success?).to be(true), compile_module[:stderr]

    compile_tb = HdlExportHelper.run_cmd(["ghdl", "-a", "--std=08", "tb.vhd"], cwd: base_dir)
    expect(compile_tb[:status].success?).to be(true), compile_tb[:stderr]

    elaborate = HdlExportHelper.run_cmd(["ghdl", "-e", "--std=08", "tb_#{top_name}"], cwd: base_dir)
    expect(elaborate[:status].success?).to be(true), elaborate[:stderr]

    run = HdlExportHelper.run_cmd(["ghdl", "-r", "--std=08", "tb_#{top_name}"], cwd: base_dir)
    expect(run[:status].success?).to be(true), run[:stderr]

    parsed = HdlExportHelper.parse_cycles(run[:stdout], vectors[:output_names])
    vectors[:outputs].each_with_index do |expected, idx|
      expect(parsed[idx]).to eq(expected)
    end
  end

  it "exports and simulates a mux" do
    rng = Random.new(1234)
    run_case(
      component: RHDL::ExportFixtures::Mux2,
      reference: RHDL::ExportFixtures::Mux2Ref,
      cycles: 8,
      clocked: false,
      input_builder: lambda { |_cycle|
        { a: rng.rand(16), b: rng.rand(16), sel: rng.rand(2) }
      }
    )
  end

  it "exports and simulates an adder" do
    rng = Random.new(5678)
    run_case(
      component: RHDL::ExportFixtures::Adder8,
      reference: RHDL::ExportFixtures::Adder8Ref,
      cycles: 8,
      clocked: false,
      input_builder: lambda { |_cycle|
        { a: rng.rand(256), b: rng.rand(256) }
      }
    )
  end

  it "exports and simulates a register" do
    rng = Random.new(9012)
    run_case(
      component: RHDL::ExportFixtures::Reg8,
      reference: RHDL::ExportFixtures::Reg8Ref,
      cycles: 8,
      clocked: true,
      input_builder: lambda { |cycle|
        { reset: cycle.zero? ? 1 : 0, d: rng.rand(256) }
      }
    )
  end
end
