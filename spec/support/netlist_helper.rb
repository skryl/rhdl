# Netlist testing helper for gate-level synthesis validation
# Converts RHDL gate-level IR to structural Verilog and provides
# comparison utilities for validating netlists

require "fileutils"
require "open3"

module NetlistHelper
  module_function

  # Convert RHDL gate-level IR to structural Verilog
  def ir_to_structural_verilog(ir)
    lines = []
    lines << "// Structural Verilog generated from RHDL gate-level IR"
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
      lines << "  // DFF instances (behavioral for simulation)"
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

  # Convert a DFF to Verilog behavioral model
  def dff_to_verilog(dff, idx)
    lines = []
    lines << "  // DFF #{idx}: d=n#{dff.d} q=n#{dff.q} rst=#{dff.rst.nil? ? 'none' : "n#{dff.rst}"} en=#{dff.en.nil? ? 'none' : "n#{dff.en}"}"
    lines << "  reg dff#{idx}_q;"
    lines << "  assign n#{dff.q} = dff#{idx}_q;"

    # For simulation, we need a clock - assume there's a global 'clk' signal
    # In structural netlists, DFFs would use explicit clock from the design
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

  # Generate a testbench for structural Verilog simulation
  def generate_structural_testbench(ir, test_vectors)
    lines = []
    lines << "`timescale 1ns/1ps"
    lines << "module tb;"
    lines << ""

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

    # Clock for DFFs if present
    if ir.dffs.any?
      lines << "  reg clk;"
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

  # Run structural Verilog simulation using iverilog/vvp
  def run_structural_simulation(ir, test_vectors, base_dir:)
    FileUtils.mkdir_p(base_dir)

    module_path = File.join(base_dir, "#{ir.name}.v")
    tb_path = File.join(base_dir, "tb.v")

    File.write(module_path, ir_to_structural_verilog(ir))
    File.write(tb_path, generate_structural_testbench(ir, test_vectors))

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

  # Synthesize behavioral Verilog to structural netlist using Yosys
  def yosys_synthesize(verilog_path, output_json:, top_module:)
    return { success: false, error: "Yosys not available" } unless HdlToolchain.yosys_available?

    script = <<~YOSYS
      read_verilog #{verilog_path}
      hierarchy -top #{top_module}
      proc
      flatten
      opt
      techmap
      opt
      write_json #{output_json}
    YOSYS

    script_path = "#{output_json}.ys"
    File.write(script_path, script)

    stdout, stderr, status = Open3.capture3("yosys", "-s", script_path)
    FileUtils.rm_f(script_path)

    if status.success?
      { success: true, json_path: output_json }
    else
      { success: false, error: stderr }
    end
  end

  # Parse Yosys JSON netlist and convert to comparable format
  def parse_yosys_netlist(json_path)
    return nil unless File.exist?(json_path)

    data = JSON.parse(File.read(json_path), symbolize_names: true)
    modules = data[:modules]
    return nil unless modules

    # Extract gate counts from the first module
    first_module = modules.values.first
    return nil unless first_module

    cells = first_module[:cells] || {}

    gate_counts = {}
    cells.each do |_name, cell|
      type = cell[:type].to_s.downcase.gsub(/^\$/, '')
      gate_counts[type] ||= 0
      gate_counts[type] += 1
    end

    ports = first_module[:ports] || {}
    inputs = ports.select { |_, p| p[:direction] == "input" }.keys
    outputs = ports.select { |_, p| p[:direction] == "output" }.keys

    {
      gate_counts: gate_counts,
      total_gates: cells.length,
      inputs: inputs,
      outputs: outputs
    }
  end
end
