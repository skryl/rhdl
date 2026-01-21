# VHDL/Verilog Reference Comparison Helper
# Provides utilities for comparing RHDL implementations against reference HDL

require 'fileutils'
require 'open3'
require_relative 'hdl_toolchain'

module VhdlReferenceHelper
  REFERENCE_DIR = File.expand_path('../../examples/apple2/reference/neoapple2/hdl', __dir__)

  # Check if GHDL is available
  def self.ghdl_available?
    HdlToolchain.ghdl_available?
  end

  # Check if iverilog is available
  def self.iverilog_available?
    HdlToolchain.iverilog_available?
  end

  module_function

  # Generate a VHDL testbench for the given component
  def generate_vhdl_testbench(component_name, ports, test_vectors, clock_name: 'clk_14m')
    lines = []
    lines << "library ieee;"
    lines << "use ieee.std_logic_1164.all;"
    lines << "use ieee.numeric_std.all;"
    lines << ""
    lines << "entity tb is"
    lines << "end tb;"
    lines << ""
    lines << "architecture sim of tb is"
    lines << ""

    # Component declaration
    lines << "  component #{component_name}"
    lines << "    port ("
    port_lines = ports.map do |name, info|
      direction = info[:direction] || 'in'
      width = info[:width] || 1
      if width > 1
        "      #{name} : #{direction} std_logic_vector(#{width - 1} downto 0)"
      else
        "      #{name} : #{direction} std_logic"
      end
    end
    lines << port_lines.join(";\n") + ");"
    lines << "  end component;"
    lines << ""

    # Signal declarations
    ports.each do |name, info|
      width = info[:width] || 1
      if width > 1
        lines << "  signal #{name} : std_logic_vector(#{width - 1} downto 0) := (others => '0');"
      else
        lines << "  signal #{name} : std_logic := '0';"
      end
    end
    lines << ""

    lines << "begin"
    lines << ""

    # Component instantiation
    lines << "  uut: #{component_name}"
    lines << "    port map ("
    port_map = ports.keys.map { |name| "      #{name} => #{name}" }
    lines << port_map.join(",\n") + ");"
    lines << ""

    # Clock generation
    lines << "  clk_gen: process"
    lines << "  begin"
    lines << "    #{clock_name} <= '0';"
    lines << "    wait for 35 ns;  -- ~14.31818 MHz"
    lines << "    #{clock_name} <= '1';"
    lines << "    wait for 35 ns;"
    lines << "  end process;"
    lines << ""

    # Stimulus process
    lines << "  stim: process"
    lines << "  begin"
    lines << "    wait for 100 ns;  -- Initial settle"
    lines << ""

    test_vectors.each_with_index do |vec, idx|
      lines << "    -- Test vector #{idx}"
      vec[:inputs].each do |port, value|
        port_info = ports[port]
        width = port_info[:width] || 1
        if width > 1
          lines << "    #{port} <= std_logic_vector(to_unsigned(#{value}, #{width}));"
        else
          lines << "    #{port} <= '#{value}';"
        end
      end
      lines << "    wait for 70 ns;  -- One clock cycle"

      # Report outputs
      output_ports = ports.select { |_, info| info[:direction] == 'out' || info[:direction] == 'buffer' }
      output_ports.each do |name, info|
        width = info[:width] || 1
        if width > 1
          lines << "    report \"CYCLE #{idx} #{name}=\" & integer'image(to_integer(unsigned(#{name})));"
        else
          lines << "    report \"CYCLE #{idx} #{name}=\" & std_logic'image(#{name});"
        end
      end
      lines << ""
    end

    lines << "    report \"SIMULATION_DONE\";"
    lines << "    wait;"
    lines << "  end process;"
    lines << ""
    lines << "end sim;"

    lines.join("\n")
  end

  # Run GHDL simulation and return results
  def run_ghdl_simulation(vhdl_files, testbench, base_dir:, work_lib: 'work')
    FileUtils.mkdir_p(base_dir)

    # Write testbench
    tb_path = File.join(base_dir, 'tb.vhd')
    File.write(tb_path, testbench)

    # Copy VHDL files to work directory
    vhdl_files.each do |file|
      FileUtils.cp(file, base_dir)
    end

    # Analyze all VHDL files
    vhdl_basenames = vhdl_files.map { |f| File.basename(f) }
    all_files = vhdl_basenames + ['tb.vhd']

    all_files.each do |file|
      result = run_cmd(['ghdl', '-a', '--std=08', file], cwd: base_dir)
      unless result[:status].success?
        return { success: false, error: "GHDL analysis failed for #{file}: #{result[:stderr]}" }
      end
    end

    # Elaborate
    result = run_cmd(['ghdl', '-e', '--std=08', 'tb'], cwd: base_dir)
    unless result[:status].success?
      return { success: false, error: "GHDL elaboration failed: #{result[:stderr]}" }
    end

    # Run simulation
    result = run_cmd(['ghdl', '-r', '--std=08', 'tb', '--stop-time=100us'], cwd: base_dir)
    unless result[:status].success?
      return { success: false, error: "GHDL simulation failed: #{result[:stderr]}" }
    end

    # Parse results from report statements
    parsed = parse_ghdl_output(result[:stderr])

    { success: true, results: parsed, stdout: result[:stdout], stderr: result[:stderr] }
  end

  def run_cmd(cmd, cwd:)
    stdout, stderr, status = Open3.capture3(*cmd, chdir: cwd)
    { stdout: stdout, stderr: stderr, status: status }
  end

  def parse_ghdl_output(output)
    results = []
    current_cycle = nil

    output.each_line do |line|
      if match = line.match(/CYCLE\s+(\d+)\s+(\w+)=(\d+|'[01]')/)
        cycle = match[1].to_i
        port = match[2].to_sym
        value = match[3]
        value = value == "'1'" ? 1 : (value == "'0'" ? 0 : value.to_i)

        results[cycle] ||= {}
        results[cycle][port] = value
      end
    end

    results.compact
  end

  # Compare RHDL simulation results with VHDL reference
  def compare_results(rhdl_results, vhdl_results, output_ports)
    mismatches = []

    [rhdl_results.length, vhdl_results.length].max.times do |cycle|
      rhdl_cycle = rhdl_results[cycle] || {}
      vhdl_cycle = vhdl_results[cycle] || {}

      output_ports.each do |port|
        rhdl_val = rhdl_cycle[port]
        vhdl_val = vhdl_cycle[port]

        if rhdl_val != vhdl_val
          mismatches << {
            cycle: cycle,
            port: port,
            rhdl: rhdl_val,
            vhdl: vhdl_val
          }
        end
      end
    end

    {
      match: mismatches.empty?,
      mismatches: mismatches,
      cycles_compared: [rhdl_results.length, vhdl_results.length].min
    }
  end

  # Get path to reference VHDL file
  def reference_file(name)
    File.join(REFERENCE_DIR, name)
  end

  # Check if reference file exists
  def reference_exists?(name)
    File.exist?(reference_file(name))
  end

  # Generate a Verilog testbench for the given component
  def generate_verilog_testbench(module_name, ports, test_vectors, clock_name: 'clk')
    lines = []
    lines << "`timescale 1ns/1ps"
    lines << ""
    lines << "module tb;"
    lines << ""

    # Register/wire declarations for ports
    ports.each do |name, info|
      direction = info[:direction] || 'in'
      width = info[:width] || 1
      if direction == 'in'
        if width > 1
          lines << "  reg [#{width - 1}:0] #{name};"
        else
          lines << "  reg #{name};"
        end
      else
        if width > 1
          lines << "  wire [#{width - 1}:0] #{name};"
        else
          lines << "  wire #{name};"
        end
      end
    end
    lines << ""

    # Module instantiation
    port_connections = ports.keys.map { |name| ".#{name}(#{name})" }
    lines << "  #{module_name} uut("
    lines << "    " + port_connections.join(",\n    ")
    lines << "  );"
    lines << ""

    # Clock generation
    lines << "  always begin"
    lines << "    #35 #{clock_name} = ~#{clock_name};"
    lines << "  end"
    lines << ""

    # Initial block with test vectors
    lines << "  initial begin"
    lines << "    // Initialize"
    ports.each do |name, info|
      direction = info[:direction] || 'in'
      if direction == 'in'
        lines << "    #{name} = 0;"
      end
    end
    lines << ""
    lines << "    #100; // Initial settle"
    lines << ""

    test_vectors.each_with_index do |vec, idx|
      lines << "    // Test vector #{idx}"
      vec[:inputs].each do |port, value|
        lines << "    #{port} = #{value};"
      end
      lines << "    #70; // One clock cycle"

      # Report outputs
      output_ports = ports.select { |_, info| info[:direction] == 'out' || info[:direction] == 'buffer' }
      output_ports.each do |name, _|
        lines << "    $display(\"CYCLE #{idx} #{name}=%d\", #{name});"
      end
      lines << ""
    end

    lines << "    $display(\"SIMULATION_DONE\");"
    lines << "    $finish;"
    lines << "  end"
    lines << ""
    lines << "endmodule"

    lines.join("\n")
  end

  # Run iverilog simulation and return results
  def run_iverilog_simulation(verilog_files, testbench, base_dir:)
    FileUtils.mkdir_p(base_dir)

    # Write testbench
    tb_path = File.join(base_dir, 'tb.v')
    File.write(tb_path, testbench)

    # Copy Verilog files to work directory
    verilog_files.each do |file|
      FileUtils.cp(file, base_dir)
    end

    # Compile all Verilog files
    verilog_basenames = verilog_files.map { |f| File.basename(f) }
    all_files = verilog_basenames + ['tb.v']

    result = run_cmd(['iverilog', '-o', 'sim.vvp'] + all_files, cwd: base_dir)
    unless result[:status].success?
      return { success: false, error: "iverilog compilation failed: #{result[:stderr]}" }
    end

    # Run simulation
    result = run_cmd(['vvp', 'sim.vvp'], cwd: base_dir)
    unless result[:status].success?
      return { success: false, error: "vvp simulation failed: #{result[:stderr]}" }
    end

    # Parse results from $display statements
    parsed = parse_verilog_output(result[:stdout])

    { success: true, results: parsed, stdout: result[:stdout], stderr: result[:stderr] }
  end

  def parse_verilog_output(output)
    results = []

    output.each_line do |line|
      if match = line.match(/CYCLE\s+(\d+)\s+(\w+)=(\d+)/)
        cycle = match[1].to_i
        port = match[2].to_sym
        value = match[3].to_i

        results[cycle] ||= {}
        results[cycle][port] = value
      end
    end

    results.compact
  end

  # Run Verilog comparison test (using iverilog)
  def run_verilog_comparison_test(rhdl_component, verilog_files:, ports:, test_vectors:, base_dir:, clock_name: 'clk')
    # Run RHDL simulation
    rhdl_results = []
    test_vectors.each_with_index do |vec, idx|
      # Apply inputs
      vec[:inputs].each do |port, value|
        rhdl_component.set_input(port, value)
      end

      # Clock cycle
      rhdl_component.set_input(clock_name.to_sym, 0)
      rhdl_component.propagate
      rhdl_component.set_input(clock_name.to_sym, 1)
      rhdl_component.propagate

      # Capture outputs
      output_ports = ports.select { |_, info| info[:direction] == 'out' || info[:direction] == 'buffer' }
      cycle_result = {}
      output_ports.each do |name, _|
        cycle_result[name] = rhdl_component.get_output(name)
      end
      rhdl_results[idx] = cycle_result
    end

    # Generate Verilog testbench
    module_name = File.basename(verilog_files.first, '.v')
    testbench = generate_verilog_testbench(
      module_name,
      ports,
      test_vectors,
      clock_name: clock_name
    )

    # Run Verilog simulation
    verilog_result = run_iverilog_simulation(verilog_files, testbench, base_dir: base_dir)
    return verilog_result unless verilog_result[:success]

    # Compare results
    output_port_names = ports.select { |_, info| info[:direction] == 'out' || info[:direction] == 'buffer' }.keys
    comparison = compare_results(rhdl_results, verilog_result[:results], output_port_names)

    {
      success: comparison[:match],
      rhdl_results: rhdl_results,
      verilog_results: verilog_result[:results],
      comparison: comparison
    }
  end

  # Run comparison test between RHDL component and VHDL reference
  # This is the main entry point for behavioral comparison tests
  def run_comparison_test(rhdl_component, vhdl_files:, ports:, test_vectors:, base_dir:, clock_name: 'clk_14m')
    # Run RHDL simulation
    rhdl_results = []
    test_vectors.each_with_index do |vec, idx|
      # Apply inputs
      vec[:inputs].each do |port, value|
        rhdl_component.set_input(port, value)
      end

      # Clock cycle
      rhdl_component.set_input(clock_name.to_sym, 0)
      rhdl_component.propagate
      rhdl_component.set_input(clock_name.to_sym, 1)
      rhdl_component.propagate

      # Capture outputs
      output_ports = ports.select { |_, info| info[:direction] == 'out' || info[:direction] == 'buffer' }
      cycle_result = {}
      output_ports.each do |name, _|
        cycle_result[name] = rhdl_component.get_output(name)
      end
      rhdl_results[idx] = cycle_result
    end

    # Generate VHDL testbench
    testbench = generate_vhdl_testbench(
      File.basename(vhdl_files.first, '.vhd'),
      ports,
      test_vectors,
      clock_name: clock_name
    )

    # Run VHDL simulation
    vhdl_result = run_ghdl_simulation(vhdl_files, testbench, base_dir: base_dir)
    return vhdl_result unless vhdl_result[:success]

    # Compare results
    output_port_names = ports.select { |_, info| info[:direction] == 'out' || info[:direction] == 'buffer' }.keys
    comparison = compare_results(rhdl_results, vhdl_result[:results], output_port_names)

    {
      success: comparison[:match],
      rhdl_results: rhdl_results,
      vhdl_results: vhdl_result[:results],
      comparison: comparison
    }
  end
end
