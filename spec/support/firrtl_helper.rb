# FIRRTL export validation helper
# Converts RHDL FIRRTL to Verilog using firtool and validates against RHDL Verilog output

require "fileutils"
require "open3"

module FirrtlHelper
  module_function

  # Convert FIRRTL to Verilog using firtool
  # Returns the generated Verilog string or nil on failure
  def firtool_to_verilog(firrtl_source, base_dir:)
    base_dir = File.expand_path(base_dir)
    FileUtils.mkdir_p(base_dir)

    firrtl_path = File.join(base_dir, "design.fir")
    verilog_path = File.join(base_dir, "design.v")

    File.write(firrtl_path, firrtl_source)

    # Run firtool to convert FIRRTL to Verilog
    # Use lowering options for iverilog compatibility:
    # - disallowLocalVariables: iverilog doesn't support 'automatic' lifetime
    # - disallowPackedArrays: iverilog doesn't support packed arrays
    result = run_cmd(
      ["firtool", firrtl_path, "-o", verilog_path, "--format=fir",
       "--lowering-options=disallowLocalVariables,disallowPackedArrays"],
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

  # Validate FIRRTL export by comparing simulation results
  # Takes a component class and test vectors
  # Returns comparison result with success status
  def validate_firrtl_export(component_class, test_vectors:, base_dir:, has_clock: false)
    # Get RHDL outputs
    rhdl_verilog = component_class.to_verilog
    rhdl_firrtl = component_class.to_firrtl

    # Convert FIRRTL to Verilog using firtool
    firrtl_result = firtool_to_verilog(rhdl_firrtl, base_dir: File.join(base_dir, "firrtl"))

    unless firrtl_result[:success]
      return {
        success: false,
        error: firrtl_result[:error],
        rhdl_verilog: rhdl_verilog,
        rhdl_firrtl: rhdl_firrtl
      }
    end

    firrtl_verilog = firrtl_result[:verilog]

    # Extract port info from RHDL component
    rhdl_inputs = {}
    rhdl_outputs = {}
    component_class._ports.each do |port|
      if port.direction == :in
        rhdl_inputs[port.name] = port.width
      else
        rhdl_outputs[port.name] = port.width
      end
    end

    module_name = component_class.verilog_module_name

    # Run simulation on RHDL-generated Verilog
    rhdl_sim = NetlistHelper.run_behavior_simulation(
      rhdl_verilog,
      module_name: module_name,
      inputs: rhdl_inputs,
      outputs: rhdl_outputs,
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
        firrtl_verilog: firrtl_verilog
      }
    end

    # Extract actual port names from FIRRTL-generated Verilog
    # (firtool may rename ports to avoid reserved words, e.g., 'eq' -> 'eq_fir')
    firrtl_ports = extract_verilog_ports(firrtl_verilog)

    # Build mappings from RHDL port names to FIRRTL port names
    input_mapping = build_port_mapping(rhdl_inputs, firrtl_ports[:inputs])
    output_mapping = build_port_mapping(rhdl_outputs, firrtl_ports[:outputs])

    # Create FIRRTL port definitions using mapped names
    firrtl_inputs = {}
    rhdl_inputs.each do |name, width|
      firrtl_name = input_mapping[name] || name
      firrtl_inputs[firrtl_name.to_sym] = width
    end

    firrtl_outputs = {}
    rhdl_outputs.each do |name, width|
      firrtl_name = output_mapping[name] || name
      firrtl_outputs[firrtl_name.to_sym] = width
    end

    # Transform test vectors to use FIRRTL port names
    firrtl_test_vectors = test_vectors.map do |vec|
      firrtl_inputs_vec = {}
      vec[:inputs].each do |name, value|
        firrtl_name = input_mapping[name] || name
        firrtl_inputs_vec[firrtl_name.to_sym] = value
      end

      firrtl_expected = {}
      vec[:expected].each do |name, value|
        firrtl_name = output_mapping[name] || name
        firrtl_expected[firrtl_name.to_sym] = value
      end

      { inputs: firrtl_inputs_vec, expected: firrtl_expected }
    end

    # Run simulation on FIRRTL-generated Verilog with mapped port names
    firrtl_sim = NetlistHelper.run_behavior_simulation(
      firrtl_verilog,
      module_name: module_name,
      inputs: firrtl_inputs,
      outputs: firrtl_outputs,
      test_vectors: firrtl_test_vectors,
      base_dir: File.join(base_dir, "firrtl_sim"),
      has_clock: has_clock
    )

    unless firrtl_sim[:success]
      return {
        success: false,
        error: "FIRRTL Verilog simulation failed: #{firrtl_sim[:error]}",
        rhdl_verilog: rhdl_verilog,
        rhdl_firrtl: rhdl_firrtl,
        firrtl_verilog: firrtl_verilog,
        rhdl_results: rhdl_sim[:results]
      }
    end

    # Build reverse mapping (FIRRTL -> RHDL) for result comparison
    reverse_output_mapping = output_mapping.invert

    # Compare results (map FIRRTL port names back to RHDL names for comparison)
    # Only compare outputs that are specified in the test vector's expected hash
    mismatches = []
    test_vectors.each_with_index do |vec, idx|
      rhdl_out = rhdl_sim[:results][idx]
      firrtl_raw = firrtl_sim[:results][idx]

      # Map FIRRTL result keys back to RHDL names
      firrtl_out = {}
      firrtl_raw.each do |firrtl_name, value|
        rhdl_name = reverse_output_mapping[firrtl_name.to_s] || firrtl_name
        firrtl_out[rhdl_name.to_sym] = value
      end

      # Only compare outputs specified in expected hash
      expected_keys = vec[:expected].keys
      rhdl_filtered = rhdl_out.select { |k, _| expected_keys.include?(k) }
      firrtl_filtered = firrtl_out.select { |k, _| expected_keys.include?(k) }

      next if rhdl_filtered == firrtl_filtered

      mismatches << {
        cycle: idx,
        rhdl: rhdl_filtered,
        firrtl: firrtl_filtered
      }
    end

    if mismatches.any?
      {
        success: false,
        error: "Output mismatch between RHDL and FIRRTL Verilog",
        mismatches: mismatches,
        rhdl_verilog: rhdl_verilog,
        rhdl_firrtl: rhdl_firrtl,
        firrtl_verilog: firrtl_verilog,
        rhdl_results: rhdl_sim[:results],
        firrtl_results: firrtl_sim[:results]
      }
    else
      {
        success: true,
        rhdl_verilog: rhdl_verilog,
        rhdl_firrtl: rhdl_firrtl,
        firrtl_verilog: firrtl_verilog,
        rhdl_results: rhdl_sim[:results],
        firrtl_results: firrtl_sim[:results]
      }
    end
  end

  # Simple validation that just checks firtool can parse and compile the FIRRTL
  # without running full simulation comparison
  def validate_firrtl_syntax(component_class, base_dir:)
    rhdl_firrtl = component_class.to_firrtl
    result = firtool_to_verilog(rhdl_firrtl, base_dir: base_dir)

    {
      success: result[:success],
      error: result[:error],
      firrtl: rhdl_firrtl,
      verilog: result[:verilog]
    }
  end

  # Validate hierarchical FIRRTL export using to_firrtl_hierarchy
  # This includes all submodule definitions in a single circuit
  def validate_hierarchical_firrtl(component_class, base_dir:)
    rhdl_firrtl = component_class.to_firrtl_hierarchy
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

  # Extract port names and widths from Verilog module definition
  # Returns { inputs: { name => width }, outputs: { name => width } }
  def extract_verilog_ports(verilog_source)
    inputs = {}
    outputs = {}
    current_direction = nil
    current_width = 1

    # Match module definition to end of port list
    if verilog_source =~ /module\s+\w+\s*\(([\s\S]*?)\);/m
      port_block = $1

      # Parse line by line to handle firtool's multi-line format
      port_block.split("\n").each do |line|
        line = line.strip

        # Detect direction changes (input/output)
        if line =~ /\b(input|output)\b/
          current_direction = $1.to_sym

          # Check for width declaration
          if line =~ /\[(\d+):0\]/
            current_width = $1.to_i + 1
          else
            current_width = 1
          end
        end

        # Extract port names from this line (handles comma-separated and single ports)
        # Skip reserved words and empty lines
        port_names = line.scan(/\b([a-zA-Z_][a-zA-Z0-9_]*)\b/).flatten
        port_names.reject! { |n| %w[input output wire reg].include?(n) }

        # For each valid port name, add to appropriate hash
        port_names.each do |name|
          next if name.empty?

          case current_direction
          when :input
            inputs[name] = current_width
          when :output
            outputs[name] = current_width
          end
        end
      end
    end

    { inputs: inputs, outputs: outputs }
  end

  # Build port name mapping from RHDL ports to FIRRTL-generated ports
  # FIRRTL may rename ports (e.g., 'eq' -> 'eq_fir' to avoid reserved words)
  def build_port_mapping(rhdl_ports, firrtl_ports)
    mapping = {}

    rhdl_ports.each do |rhdl_name, width|
      rhdl_name_str = rhdl_name.to_s

      # Try exact match first (handles both symbol and string keys)
      if firrtl_ports[rhdl_name_str] || firrtl_ports[rhdl_name]
        mapping[rhdl_name] = rhdl_name_str
        next
      end

      # Try common FIRRTL renaming patterns (appending _fir suffix)
      firrtl_name = "#{rhdl_name_str}_fir"
      if firrtl_ports[firrtl_name]
        mapping[rhdl_name] = firrtl_name
        next
      end

      # If no match found, log warning but don't use loose matching
      # (loose prefix matching like 'd' -> 'd_in' causes bugs)
    end

    mapping
  end
end
