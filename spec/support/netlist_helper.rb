# Netlist testing helper for gate-level synthesis validation
# Converts RHDL gate-level IR to structure Verilog and provides
# comparison utilities for validating netlists

require "fileutils"
require "open3"

module NetlistHelper
  module_function

  # Convert RHDL gate-level IR to structure Verilog
  def ir_to_structure_verilog(ir)
    lines = []
    lines << "// Structure Verilog generated from RHDL gate-level IR"
    lines << "// Design: #{ir.name}"
    lines << "// Gates: #{ir.gates.length}, DFFs: #{ir.dffs.length}, Nets: #{ir.net_count}"
    lines << ""

    # Module declaration
    port_names = []
    ir.inputs.each do |name, _nets|
      port_names << sanitize_port_name(name)
    end
    ir.outputs.each do |name, _nets|
      port_names << sanitize_port_name(name)
    end

    lines << "module #{ir.name} ("
    lines << "  " + port_names.join(",\n  ")
    lines << ");"
    lines << ""

    # Input port declarations
    ir.inputs.each do |name, nets|
      port_name = sanitize_port_name(name)
      if nets.length > 1
        lines << "  input [#{nets.length - 1}:0] #{port_name};"
      else
        lines << "  input #{port_name};"
      end
    end

    # Output port declarations
    ir.outputs.each do |name, nets|
      port_name = sanitize_port_name(name)
      if nets.length > 1
        lines << "  output [#{nets.length - 1}:0] #{port_name};"
      else
        lines << "  output #{port_name};"
      end
    end
    lines << ""

    # Internal wire declarations
    lines << "  // Internal nets"
    (0...ir.net_count).each do |i|
      lines << "  wire n#{i};"
    end
    lines << ""

    # Connect input ports to nets
    lines << "  // Input connections"
    ir.inputs.each do |name, nets|
      port_name = sanitize_port_name(name)
      nets.each_with_index do |net, idx|
        if nets.length > 1
          lines << "  assign n#{net} = #{port_name}[#{idx}];"
        else
          lines << "  assign n#{net} = #{port_name};"
        end
      end
    end
    lines << ""

    # Gate instantiations
    lines << "  // Gate instances"
    ir.gates.each_with_index do |gate, idx|
      lines << gate_to_verilog(gate, idx)
    end
    lines << ""

    # DFF instantiations
    if ir.dffs.any?
      lines << "  // DFF instances (behavior for simulation)"
      ir.dffs.each_with_index do |dff, idx|
        lines << dff_to_verilog(dff, idx)
      end
      lines << ""
    end

    # Connect nets to output ports
    lines << "  // Output connections"
    ir.outputs.each do |name, nets|
      port_name = sanitize_port_name(name)
      nets.each_with_index do |net, idx|
        if nets.length > 1
          lines << "  assign #{port_name}[#{idx}] = n#{net};"
        else
          lines << "  assign #{port_name} = n#{net};"
        end
      end
    end

    lines << ""
    lines << "endmodule"
    lines.join("\n")
  end

  # Convert a gate to Verilog primitive instantiation
  def gate_to_verilog(gate, idx)
    case gate.type
    when :not
      "  not g#{idx} (n#{gate.output}, n#{gate.inputs[0]});"
    when :and
      "  and g#{idx} (n#{gate.output}, n#{gate.inputs[0]}, n#{gate.inputs[1]});"
    when :or
      "  or g#{idx} (n#{gate.output}, n#{gate.inputs[0]}, n#{gate.inputs[1]});"
    when :xor
      "  xor g#{idx} (n#{gate.output}, n#{gate.inputs[0]}, n#{gate.inputs[1]});"
    when :nand
      "  nand g#{idx} (n#{gate.output}, n#{gate.inputs[0]}, n#{gate.inputs[1]});"
    when :nor
      "  nor g#{idx} (n#{gate.output}, n#{gate.inputs[0]}, n#{gate.inputs[1]});"
    when :xnor
      "  xnor g#{idx} (n#{gate.output}, n#{gate.inputs[0]}, n#{gate.inputs[1]});"
    when :buf
      "  buf g#{idx} (n#{gate.output}, n#{gate.inputs[0]});"
    when :mux
      # MUX: output = sel ? b : a (inputs = [a, b, sel])
      "  assign n#{gate.output} = n#{gate.inputs[2]} ? n#{gate.inputs[1]} : n#{gate.inputs[0]}; // mux g#{idx}"
    when :const
      "  assign n#{gate.output} = 1'b#{gate.value}; // const g#{idx}"
    else
      "  // Unknown gate type: #{gate.type}"
    end
  end

  # Convert a DFF to Verilog behavior model
  def dff_to_verilog(dff, idx)
    lines = []
    lines << "  // DFF #{idx}: d=n#{dff.d} q=n#{dff.q} rst=#{dff.rst.nil? ? 'none' : "n#{dff.rst}"} en=#{dff.en.nil? ? 'none' : "n#{dff.en}"}"
    lines << "  reg dff#{idx}_q = 1'b0;"  # Initialize to 0 for simulation
    lines << "  assign n#{dff.q} = dff#{idx}_q;"

    # For simulation, we need a clock - assume there's a global 'clk' signal
    # In structure netlists, DFFs would use explicit clock from the design
    if dff.async_reset && dff.rst
      lines << "  always @(posedge clk or posedge n#{dff.rst}) begin"
      lines << "    if (n#{dff.rst})"
      lines << "      dff#{idx}_q <= 1'b0;"
      elsif_or_else = "    else"
    else
      lines << "  always @(posedge clk) begin"
      if dff.rst
        lines << "    if (n#{dff.rst})"
        lines << "      dff#{idx}_q <= 1'b0;"
        elsif_or_else = "    else"
      else
        elsif_or_else = nil
      end
    end

    if dff.en
      if elsif_or_else
        lines << "#{elsif_or_else} if (n#{dff.en})"
      else
        lines << "    if (n#{dff.en})"
      end
      lines << "      dff#{idx}_q <= n#{dff.d};"
    else
      if elsif_or_else
        lines << elsif_or_else
        lines << "      dff#{idx}_q <= n#{dff.d};"
      else
        lines << "    dff#{idx}_q <= n#{dff.d};"
      end
    end

    lines << "  end"
    lines.join("\n")
  end

  # Sanitize port name (remove prefix like "component_name.")
  def sanitize_port_name(name)
    name.to_s.split('.').last
  end

  # Compare two netlists for functional equivalence
  # Returns a hash with comparison results
  def compare_netlists(ir1, ir2)
    result = {
      inputs_match: ir1.inputs.keys.sort == ir2.inputs.keys.sort,
      outputs_match: ir1.outputs.keys.sort == ir2.outputs.keys.sort,
      gate_count_match: ir1.gates.length == ir2.gates.length,
      dff_count_match: ir1.dffs.length == ir2.dffs.length,
      net_count_match: ir1.net_count == ir2.net_count,
      ir1_stats: {
        gates: ir1.gates.length,
        dffs: ir1.dffs.length,
        nets: ir1.net_count
      },
      ir2_stats: {
        gates: ir2.gates.length,
        dffs: ir2.dffs.length,
        nets: ir2.net_count
      }
    }

    # Count gates by type
    result[:ir1_gate_types] = ir1.gates.group_by(&:type).transform_values(&:length)
    result[:ir2_gate_types] = ir2.gates.group_by(&:type).transform_values(&:length)
    result[:gate_types_match] = result[:ir1_gate_types] == result[:ir2_gate_types]

    result
  end

  # Generate a testbench for structure Verilog simulation
  def generate_structure_testbench(ir, test_vectors)
    lines = []
    lines << "`timescale 1ns/1ps"
    lines << "module tb;"
    lines << ""

    # Check if clk is already an input
    has_clk_input = ir.inputs.keys.any? { |k| sanitize_port_name(k) == 'clk' }

    # Declare signals
    ir.inputs.each do |name, nets|
      port_name = sanitize_port_name(name)
      if nets.length > 1
        lines << "  reg [#{nets.length - 1}:0] #{port_name};"
      else
        lines << "  reg #{port_name};"
      end
    end

    ir.outputs.each do |name, nets|
      port_name = sanitize_port_name(name)
      if nets.length > 1
        lines << "  wire [#{nets.length - 1}:0] #{port_name};"
      else
        lines << "  wire #{port_name};"
      end
    end

    # Clock for DFFs if present (only add if not already an input)
    if ir.dffs.any? && !has_clk_input
      lines << "  reg clk;"
    end

    if ir.dffs.any?
      lines << ""
      lines << "  initial begin"
      lines << "    clk = 0;"
      lines << "  end"
      lines << "  always #5 clk = ~clk;"
    end

    lines << ""

    # Instantiate the module
    port_map = []
    ir.inputs.each do |name, _|
      port_name = sanitize_port_name(name)
      port_map << ".#{port_name}(#{port_name})"
    end
    ir.outputs.each do |name, _|
      port_name = sanitize_port_name(name)
      port_map << ".#{port_name}(#{port_name})"
    end

    lines << "  #{ir.name} uut ("
    lines << "    " + port_map.join(",\n    ")
    lines << "  );"
    lines << ""

    # Test vectors
    lines << "  initial begin"

    test_vectors.each_with_index do |vec, idx|
      vec[:inputs].each do |port, value|
        lines << "    #{port} = #{value};"
      end

      if ir.dffs.any?
        lines << "    @(posedge clk);"
        lines << "    #1;"
      else
        lines << "    #1;"
      end

      # Display outputs
      output_names = ir.outputs.keys.map { |k| sanitize_port_name(k) }
      display_parts = output_names.map.with_index { |name, i| "OUT#{i}=%0d" }
      display_args = output_names.join(", ")
      lines << "    $display(\"CYCLE #{idx} #{display_parts.join(' ')}\", #{display_args});"
    end

    lines << "    $finish;"
    lines << "  end"
    lines << "endmodule"

    lines.join("\n")
  end

  # Run structure Verilog simulation using iverilog/vvp
  def run_structure_simulation(ir, test_vectors, base_dir:)
    FileUtils.mkdir_p(base_dir)

    module_path = File.join(base_dir, "#{ir.name}.v")
    tb_path = File.join(base_dir, "tb.v")

    File.write(module_path, ir_to_structure_verilog(ir))
    File.write(tb_path, generate_structure_testbench(ir, test_vectors))

    compile = run_cmd(["iverilog", "-g2001", "-o", "sim.out", "tb.v", "#{ir.name}.v"], cwd: base_dir)
    return { success: false, error: "Compilation failed: #{compile[:stderr]}" } unless compile[:status].success?

    run = run_cmd(["vvp", "sim.out"], cwd: base_dir)
    return { success: false, error: "Simulation failed: #{run[:stderr]}" } unless run[:status].success?

    output_names = ir.outputs.keys.map { |k| sanitize_port_name(k) }
    parsed = parse_cycles(run[:stdout], output_names)

    { success: true, results: parsed, stdout: run[:stdout] }
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

        values[name.to_sym] = token[1].to_i
      end
      results[cycle] = values
    end
    results
  end

  # Generate a testbench for behavior Verilog simulation
  # Takes component class and test vectors with input/output port info
  def generate_behavior_testbench(module_name, inputs, outputs, test_vectors, has_clock: false)
    lines = []
    lines << "`timescale 1ns/1ps"
    lines << "module tb;"
    lines << ""

    # Check if clk is in inputs (for clock generation)
    has_clk_input = inputs.key?(:clk)

    # Declare signals
    inputs.each do |name, width|
      if width > 1
        lines << "  reg [#{width - 1}:0] #{name};"
      else
        lines << "  reg #{name};"
      end
    end

    outputs.each do |name, width|
      if width > 1
        lines << "  wire [#{width - 1}:0] #{name};"
      else
        lines << "  wire #{name};"
      end
    end

    # Clock generation if needed (only if clk is already declared as input)
    if has_clock && has_clk_input
      lines << ""
      lines << "  initial begin"
      lines << "    clk = 0;"
      lines << "  end"
      lines << "  always #5 clk = ~clk;"
    end

    lines << ""

    # Instantiate the module
    port_map = []
    inputs.each_key { |name| port_map << ".#{name}(#{name})" }
    outputs.each_key { |name| port_map << ".#{name}(#{name})" }

    lines << "  #{module_name} uut ("
    lines << "    " + port_map.join(",\n    ")
    lines << "  );"
    lines << ""

    # Test vectors
    lines << "  initial begin"

    test_vectors.each_with_index do |vec, idx|
      vec[:inputs].each do |port, value|
        lines << "    #{port} = #{value};"
      end

      if has_clock
        lines << "    @(posedge clk);"
        lines << "    #1;"
      else
        lines << "    #10;"
      end

      # Display outputs
      output_names = outputs.keys
      display_parts = output_names.map.with_index { |_name, i| "OUT#{i}=%0d" }
      display_args = output_names.join(", ")
      lines << "    $display(\"CYCLE #{idx} #{display_parts.join(' ')}\", #{display_args});"
    end

    lines << "    $finish;"
    lines << "  end"
    lines << "endmodule"

    lines.join("\n")
  end

  # Run behavior Verilog simulation using iverilog/vvp
  # Takes the verilog source directly (from to_verilog) along with port info and test vectors
  def run_behavior_simulation(verilog_source, module_name:, inputs:, outputs:, test_vectors:, base_dir:, has_clock: false)
    FileUtils.mkdir_p(base_dir)

    module_path = File.join(base_dir, "#{module_name}.v")
    tb_path = File.join(base_dir, "tb.v")

    File.write(module_path, verilog_source)
    File.write(tb_path, generate_behavior_testbench(module_name, inputs, outputs, test_vectors, has_clock: has_clock))

    compile = run_cmd(["iverilog", "-g2012", "-o", "sim.out", "tb.v", "#{module_name}.v"], cwd: base_dir)
    return { success: false, error: "Compilation failed: #{compile[:stderr]}\n#{compile[:stdout]}" } unless compile[:status].success?

    run = run_cmd(["vvp", "sim.out"], cwd: base_dir)
    return { success: false, error: "Simulation failed: #{run[:stderr]}" } unless run[:status].success?

    output_names = outputs.keys.map(&:to_s)
    parsed = parse_cycles(run[:stdout], output_names)

    { success: true, results: parsed, stdout: run[:stdout] }
  end

  # Run simulation using Ruby SimCPU netlist simulator
  # Takes IR and test vectors, returns results in the same format as other simulators
  def run_ruby_netlist_simulation(ir, test_vectors, has_clock: false)
    require 'rhdl/codegen'

    sim = RHDL::Codegen::Structure::SimCPU.new(ir, lanes: 64)
    run_netlist_sim(sim, ir, test_vectors, has_clock: has_clock, name: 'Ruby SimCPU')
  end

  # Run simulation using Native SimCPUNative netlist simulator
  # Takes IR and test vectors, returns results in the same format as other simulators
  def run_native_netlist_simulation(ir, test_vectors, has_clock: false)
    require 'rhdl/codegen'

    unless RHDL::Codegen::Structure::NATIVE_SIM_AVAILABLE
      return { success: false, error: 'Native SimCPU extension not available', skipped: true }
    end

    sim = RHDL::Codegen::Structure::SimCPUNative.new(ir.to_json, 64)
    run_netlist_sim(sim, ir, test_vectors, has_clock: has_clock, name: 'Native SimCPU')
  end

  # Common implementation for Ruby and Native netlist simulators
  def run_netlist_sim(sim, ir, test_vectors, has_clock:, name:)
    results = []
    output_names = ir.outputs.keys.map { |k| sanitize_port_name(k) }

    # Build input port name mapping (sanitized name -> full IR name)
    input_map = {}
    ir.inputs.each do |full_name, _nets|
      short_name = sanitize_port_name(full_name)
      input_map[short_name] = full_name
    end

    # Build output port name mapping (sanitized name -> full IR name)
    output_map = {}
    ir.outputs.each do |full_name, nets|
      short_name = sanitize_port_name(full_name)
      output_map[short_name] = { full_name: full_name, width: nets.length }
    end

    test_vectors.each_with_index do |vec, _idx|
      # Apply inputs - convert values to lane masks per bit
      vec[:inputs].each do |port, value|
        port_str = port.to_s
        full_name = input_map[port_str] || port_str
        nets = ir.inputs[full_name]

        if nets && nets.length > 1
          # Multi-bit input: set each bit's lane mask based on value
          # All lanes get the same value, so use the value bits as the mask pattern
          sim.poke(full_name, lanes_from_value(value, nets.length))
        else
          # Single-bit input: value 1 means all lanes high
          lane_value = value != 0 ? 0xFFFFFFFFFFFFFFFF : 0
          sim.poke(full_name, lane_value)
        end
      end

      # Execute simulation
      if has_clock
        sim.tick
      else
        sim.evaluate
      end

      # Collect outputs - convert lane masks back to single values
      cycle_results = {}
      output_names.each do |out_name|
        info = output_map[out_name]
        next unless info

        full_name = info[:full_name]
        width = info[:width]
        lane_data = sim.peek(full_name)

        # Extract value from lane 0
        cycle_results[out_name.to_sym] = value_from_lanes(lane_data, width)
      end
      results << cycle_results
    end

    { success: true, results: results, simulator: name }
  rescue StandardError => e
    { success: false, error: "#{name} simulation failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}" }
  end

  # Convert a numeric value to the format expected by SimCPU.poke
  # For multi-bit signals, poke expects an array of lane values [lane0_val, lane1_val, ...]
  # We simulate with lane 0 only, so we pass [value] as the array
  def lanes_from_value(value, width)
    if width == 1
      value != 0 ? 0xFFFFFFFFFFFFFFFF : 0
    else
      # For multi-bit values, pass the value as lane 0's value
      # SimCPU.poke will convert this to per-bit lane masks internally via lane_values_to_masks
      [value]
    end
  end

  # Convert lane masks back to a numeric value (extract from lane 0)
  def value_from_lanes(lane_data, width)
    if width == 1
      # Single bit - check lane 0
      if lane_data.is_a?(Array)
        (lane_data[0] & 1) != 0 ? 1 : 0
      else
        (lane_data & 1) != 0 ? 1 : 0
      end
    elsif lane_data.is_a?(Array)
      # Multi-bit bus - reconstruct value from bit lane masks
      value = 0
      lane_data.each_with_index do |bit_mask, bit_idx|
        if (bit_mask & 1) != 0
          value |= (1 << bit_idx)
        end
      end
      value
    else
      # Single value returned for multi-bit (shouldn't happen, but handle it)
      (lane_data & 1) != 0 ? 1 : 0
    end
  end

  # Run all available simulators and compare results
  # Returns comparison results showing any mismatches between:
  # - Verilog structure simulation (iverilog)
  # - Ruby SimCPU netlist simulation
  # - Native Rust SimCPUNative netlist simulation
  def run_netlist_comparison(ir, test_vectors, base_dir:, has_clock: false)
    results = {
      verilog: nil,
      ruby: nil,
      native: nil,
      all_match: false,
      mismatches: []
    }

    # Run Verilog simulation if iverilog is available
    if HdlToolchain.iverilog_available?
      results[:verilog] = run_structure_simulation(ir, test_vectors, base_dir: base_dir)
    else
      results[:verilog] = { success: false, error: 'iverilog not available', skipped: true }
    end

    # Run Ruby netlist simulation
    results[:ruby] = run_ruby_netlist_simulation(ir, test_vectors, has_clock: has_clock)

    # Run Native netlist simulation
    results[:native] = run_native_netlist_simulation(ir, test_vectors, has_clock: has_clock)

    # Compare results across all successful simulators
    compare_simulator_results(results, ir, test_vectors)

    results
  end

  # Compare results between all successful simulators
  def compare_simulator_results(results, ir, test_vectors)
    output_names = ir.outputs.keys.map { |k| sanitize_port_name(k).to_sym }

    test_vectors.each_with_index do |vec, idx|
      expected = vec[:expected]

      # Get results from each simulator
      verilog_result = results[:verilog][:success] ? results[:verilog][:results][idx] : nil
      ruby_result = results[:ruby][:success] ? results[:ruby][:results][idx] : nil
      native_result = results[:native][:success] ? results[:native][:results][idx] : nil

      # Compare each output
      output_names.each do |out_name|
        values = {
          expected: expected ? expected[out_name] : nil,
          verilog: verilog_result ? verilog_result[out_name] : nil,
          ruby: ruby_result ? ruby_result[out_name] : nil,
          native: native_result ? native_result[out_name] : nil
        }

        # Check for mismatches between available simulators
        available_values = values.values.compact.uniq
        if available_values.length > 1
          results[:mismatches] << {
            cycle: idx,
            output: out_name,
            inputs: vec[:inputs],
            values: values
          }
        end
      end
    end

    results[:all_match] = results[:mismatches].empty?
  end

  # Helper to run behavior simulation (RTL Ruby) and compare with all netlist simulators
  # This is the main entry point for comprehensive testing
  def compare_behavior_to_netlist(component_class, component_name, test_cases, base_dir:, has_clock: false)
    require 'rhdl/codegen'

    # Create behavior component and generate test vectors with expected outputs
    behavior = component_class.new
    test_vectors = []

    test_cases.each do |tc|
      tc.each do |port, value|
        behavior.set_input(port, value)
      end

      if has_clock
        behavior.set_input(:clk, 0)
        behavior.propagate
        behavior.set_input(:clk, 1)
        behavior.propagate
      else
        behavior.propagate
      end

      # Get expected outputs from behavior simulation
      expected = {}
      behavior.outputs.each_key do |out_name|
        expected[out_name] = behavior.get_output(out_name)
      end

      test_vectors << {
        inputs: tc.dup,
        expected: expected
      }
    end

    # Create gate-level IR
    component = component_class.new(component_name)
    ir = RHDL::Codegen::Structure::Lower.from_components([component], name: component_name)

    # Run comparison across all simulators
    comparison = run_netlist_comparison(ir, test_vectors, base_dir: base_dir, has_clock: has_clock)

    # Add behavior reference to results
    comparison[:behavior] = { success: true, results: test_vectors.map { |v| v[:expected] } }
    comparison[:test_vectors] = test_vectors

    comparison
  end
end
