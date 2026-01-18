require "fileutils"
require "open3"

module HdlExportHelper
  module_function

  def build_vectors(ref_class, cycles:, clocked:, input_builder:)
    sim = RHDL::HDL::Simulator.new
    component = ref_class.new(:uut)
    sim.add_component(component)

    if clocked
      clock = RHDL::HDL::Clock.new(:clk)
      sim.add_clock(clock)
      RHDL::HDL::SimComponent.connect(clock, component.inputs[:clk])
    end

    input_vectors = []
    output_vectors = []
    output_names = component.outputs.keys

    cycles.times do |cycle|
      inputs = input_builder.call(cycle)
      input_vectors << inputs
      inputs.each { |name, value| component.set_input(name, value) }

      if clocked
        sim.run(1)
      else
        sim.step
      end

      output_vectors << output_names.to_h { |name| [name, component.get_output(name)] }
    end

    {
      inputs: input_vectors,
      outputs: output_vectors,
      output_names: output_names
    }
  end

  def write_verilog_testbench(path, top_name:, ports:, output_names:, vectors:, clocked:)
    File.write(path, verilog_testbench(top_name: top_name, ports: ports, output_names: output_names, vectors: vectors, clocked: clocked))
  end

  def run_cmd(cmd, cwd:)
    stdout, stderr, status = Open3.capture3(*cmd, chdir: cwd)
    { stdout: stdout, stderr: stderr, status: status }
  end

  def parse_cycles(output, output_names)
    lines = output.split("\n")
    results = []
    lines.each do |line|
      match = line.match(/CYCLE\s+(\d+)\s+(.*)/)
      next unless match
      cycle = match[1].to_i
      values = {}
      output_names.each_with_index do |name, idx|
        token = match[2].match(/OUT#{idx}=(\d+)/)
        next unless token
        values[name] = token[1].to_i
      end
      results[cycle] = values
    end
    results
  end

  def verilog_testbench(top_name:, ports:, output_names:, vectors:, clocked:)
    lines = []
    lines << "`timescale 1ns/1ps"
    lines << "module tb;"

    ports.each do |port|
      name = port[:name]
      width = port[:width]
      if port[:direction] == :in
        lines << "  reg #{width_decl(width)}#{name};"
      else
        lines << "  wire #{width_decl(width)}#{name};"
      end
    end

    port_map = ports.map { |port| ".#{port[:name]}(#{port[:name]})" }.join(", ")
    lines << "  #{top_name} uut (#{port_map});"

    if clocked
      lines << "  initial begin"
      lines << "    clk = 0;"
      lines << "  end"
      lines << "  always #5 clk = ~clk;"
    end

    lines << "  integer i;"
    lines << "  initial begin"
    vectors.each_with_index do |inputs, idx|
      inputs.each do |name, value|
        lines << "    #{name} = #{value};"
      end
      if clocked
        lines << "    @(posedge clk);"
        lines << "    #1;"
      else
        lines << "    #1;"
      end
      display_parts = output_names.map.with_index do |name, out_idx|
        "OUT#{out_idx}=%0d"
      end
      display_args = output_names.join(", ")
      lines << "    $display(\"CYCLE #{idx} #{display_parts.join(' ')}\", #{display_args});"
    end
    lines << "    $finish;"
    lines << "  end"
    lines << "endmodule"
    lines.join("\n")
  end

  def width_decl(width)
    width > 1 ? "[#{width - 1}:0] " : ""
  end
end
