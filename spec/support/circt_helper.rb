# CIRCT testing helper for FIRRTL export validation
# Converts RHDL FIRRTL to Verilog using firtool and validates against RHDL Verilog output

require "fileutils"
require "open3"

module CirctHelper
  module_function

  # Convert FIRRTL to Verilog using firtool
  # Returns the generated Verilog string or nil on failure
  def firtool_to_verilog(firrtl_source, base_dir:)
    FileUtils.mkdir_p(base_dir)

    firrtl_path = File.join(base_dir, "design.fir")
    verilog_path = File.join(base_dir, "design.v")

    File.write(firrtl_path, firrtl_source)

    # Run firtool to convert FIRRTL to Verilog
    result = run_cmd(
      ["firtool", firrtl_path, "-o", verilog_path, "--format=fir"],
      cwd: base_dir
    )

    unless result[:status].success?
      return { success: false, error: "firtool failed: #{result[:stderr]}\n#{result[:stdout]}" }
    end

    unless File.exist?(verilog_path)
      return { success: false, error: "firtool did not generate output file" }
    end

    { success: true, verilog: File.read(verilog_path) }
  end

  # Validate CIRCT export by comparing simulation results
  # Takes a component class and test vectors
  # Returns comparison result with success status
  def validate_circt_export(component_class, test_vectors:, base_dir:, has_clock: false)
    # Get RHDL outputs
    rhdl_verilog = component_class.to_verilog
    rhdl_firrtl = component_class.to_circt

    # Convert FIRRTL to Verilog using firtool
    circt_result = firtool_to_verilog(rhdl_firrtl, base_dir: File.join(base_dir, "circt"))

    unless circt_result[:success]
      return {
        success: false,
        error: circt_result[:error],
        rhdl_verilog: rhdl_verilog,
        rhdl_firrtl: rhdl_firrtl
      }
    end

    circt_verilog = circt_result[:verilog]

    # Extract port info from component
    inputs = {}
    outputs = {}
    component_class._ports.each do |port|
      if port.direction == :in
        inputs[port.name] = port.width
      else
        outputs[port.name] = port.width
      end
    end

    module_name = component_class.verilog_module_name

    # Run simulation on RHDL-generated Verilog
    rhdl_sim = NetlistHelper.run_behavior_simulation(
      rhdl_verilog,
      module_name: module_name,
      inputs: inputs,
      outputs: outputs,
      test_vectors: test_vectors,
      base_dir: File.join(base_dir, "rhdl_sim"),
      has_clock: has_clock
    )

    unless rhdl_sim[:success]
      return {
        success: false,
        error: "RHDL Verilog simulation failed: #{rhdl_sim[:error]}",
        rhdl_verilog: rhdl_verilog,
        rhdl_firrtl: rhdl_firrtl,
        circt_verilog: circt_verilog
      }
    end

    # Run simulation on CIRCT-generated Verilog
    circt_sim = NetlistHelper.run_behavior_simulation(
      circt_verilog,
      module_name: module_name,
      inputs: inputs,
      outputs: outputs,
      test_vectors: test_vectors,
      base_dir: File.join(base_dir, "circt_sim"),
      has_clock: has_clock
    )

    unless circt_sim[:success]
      return {
        success: false,
        error: "CIRCT Verilog simulation failed: #{circt_sim[:error]}",
        rhdl_verilog: rhdl_verilog,
        rhdl_firrtl: rhdl_firrtl,
        circt_verilog: circt_verilog,
        rhdl_results: rhdl_sim[:results]
      }
    end

    # Compare results
    mismatches = []
    test_vectors.each_with_index do |_vec, idx|
      rhdl_out = rhdl_sim[:results][idx]
      circt_out = circt_sim[:results][idx]

      next if rhdl_out == circt_out

      mismatches << {
        cycle: idx,
        rhdl: rhdl_out,
        circt: circt_out
      }
    end

    if mismatches.any?
      {
        success: false,
        error: "Output mismatch between RHDL and CIRCT Verilog",
        mismatches: mismatches,
        rhdl_verilog: rhdl_verilog,
        rhdl_firrtl: rhdl_firrtl,
        circt_verilog: circt_verilog,
        rhdl_results: rhdl_sim[:results],
        circt_results: circt_sim[:results]
      }
    else
      {
        success: true,
        rhdl_verilog: rhdl_verilog,
        rhdl_firrtl: rhdl_firrtl,
        circt_verilog: circt_verilog,
        rhdl_results: rhdl_sim[:results],
        circt_results: circt_sim[:results]
      }
    end
  end

  # Simple validation that just checks firtool can parse and compile the FIRRTL
  # without running full simulation comparison
  def validate_firrtl_syntax(component_class, base_dir:)
    rhdl_firrtl = component_class.to_circt
    result = firtool_to_verilog(rhdl_firrtl, base_dir: base_dir)

    {
      success: result[:success],
      error: result[:error],
      firrtl: rhdl_firrtl,
      verilog: result[:verilog]
    }
  end

  def run_cmd(cmd, cwd:)
    stdout, stderr, status = Open3.capture3(*cmd, chdir: cwd)
    { stdout: stdout, stderr: stderr, status: status }
  end
end
