require "spec_helper"

RSpec.describe "Verilog HDL export" do
  before do
    skip "Icarus Verilog not installed" unless HdlToolchain.iverilog_available?
  end

  def run_case(component:, reference:, cycles:, clocked:, input_builder:)
    top_name = component.name.split("::").last.underscore
    base_dir = File.join("tmp/hdl_export", top_name, "verilog")
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

    module_path = File.join(base_dir, "#{top_name}.v")
    tb_path = File.join(base_dir, "tb.v")

    File.write(module_path, RHDL::Export.verilog(component, top_name: top_name))
    HdlExportHelper.write_verilog_testbench(
      tb_path,
      top_name: top_name,
      ports: ports,
      output_names: vectors[:output_names],
      vectors: vectors[:inputs],
      clocked: clocked
    )

    compile = HdlExportHelper.run_cmd(["iverilog", "-g2001", "-o", "sim.out", "tb.v", "#{top_name}.v"], cwd: base_dir)
    expect(compile[:status].success?).to be(true), compile[:stderr]

    run = HdlExportHelper.run_cmd(["vvp", "sim.out"], cwd: base_dir)
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
