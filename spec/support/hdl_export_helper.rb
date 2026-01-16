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

  def write_vhdl_testbench(path, top_name:, ports:, output_names:, vectors:, clocked:)
    File.write(path, vhdl_testbench(top_name: top_name, ports: ports, output_names: output_names, vectors: vectors, clocked: clocked))
  end

  def run_cmd(cmd, cwd:)
    stdout, stderr, status = Open3.capture3(*cmd, chdir: cwd)
    { stdout: stdout, stderr: stderr, status: status }
  end

  def parse_cycles(output, output_names)
    lines = output.split("\n")
    results = []
    lines.each do |line|
      match = line.match(/CYCLE\s+(\\d+)\\s+(.*)/)
      next unless match
      cycle = match[1].to_i
      values = {}
      output_names.each_with_index do |name, idx|
        token = match[2].match(/OUT#{idx}=(\\d+)/)
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

  def vhdl_testbench(top_name:, ports:, output_names:, vectors:, clocked:)
    tb_name = "tb_#{top_name}"
    lines = []
    lines << "library ieee;"
    lines << "use ieee.std_logic_1164.all;"
    lines << "use ieee.numeric_std.all;"
    lines << ""
    lines << "entity #{tb_name} is"
    lines << "end #{tb_name};"
    lines << ""
    lines << "architecture sim of #{tb_name} is"

    ports.each do |port|
      lines << "  signal #{port[:name]} : #{vhdl_type(port[:width])} := #{vhdl_init(port[:width])};"
    end

    lines << "  function to_int(sig : std_logic) return integer is"
    lines << "  begin"
    lines << "    if sig = '1' then"
    lines << "      return 1;"
    lines << "    else"
    lines << "      return 0;"
    lines << "    end if;"
    lines << "  end function;"
    lines << ""
    lines << "  function to_int(sig : std_logic_vector) return integer is"
    lines << "  begin"
    lines << "    return to_integer(unsigned(sig));"
    lines << "  end function;"

    lines << "begin"
    port_map = ports.map { |port| "#{port[:name]} => #{port[:name]}" }.join(", ")
    lines << "  uut : entity work.#{top_name} port map(#{port_map});"

    if clocked
      lines << "  clk_process : process"
      lines << "  begin"
      lines << "    clk <= '0';"
      lines << "    wait for 5 ns;"
      lines << "    clk <= '1';"
      lines << "    wait for 5 ns;"
      lines << "  end process;"
    end

    lines << "  stim : process"
    lines << "  begin"
    vectors.each_with_index do |inputs, idx|
      inputs.each do |name, value|
        lines << "    #{name} <= #{vhdl_literal(value, ports.find { |p| p[:name] == name }[:width])};"
      end
      if clocked
        lines << "    wait until rising_edge(clk);"
        lines << "    wait for 1 ns;"
      else
        lines << "    wait for 1 ns;"
      end
      report_parts = ["\"CYCLE #{idx} \""]
      output_names.each_with_index do |name, out_idx|
        report_parts << " & \"OUT#{out_idx}=\" & integer'image(to_int(#{name}))"
        report_parts << " & \" \"" if out_idx < output_names.size - 1
      end
      lines << "    report #{report_parts.join};"
    end
    lines << "    wait;"
    lines << "  end process;"
    lines << "end sim;"
    lines.join("\n")
  end

  def width_decl(width)
    width > 1 ? "[#{width - 1}:0] " : ""
  end

  def vhdl_type(width)
    width > 1 ? "std_logic_vector(#{width - 1} downto 0)" : "std_logic"
  end

  def vhdl_init(width)
    width > 1 ? "(others => '0')" : "'0'"
  end

  def vhdl_literal(value, width)
    if width == 1
      value.to_i == 0 ? "'0'" : "'1'"
    else
      "std_logic_vector(to_unsigned(#{value}, #{width}))"
    end
  end
end
