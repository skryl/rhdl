#!/usr/bin/env ruby
# Example: Circuit Diagram Generation
# This demonstrates how to create pretty circuit diagrams of any HDL component

require_relative '../lib/rhdl/hdl'

puts "=" * 60
puts "RHDL Circuit Diagram Examples"
puts "=" * 60

# ====================
# 1. Simple Gate Diagram
# ====================
puts "\n1. Simple AND Gate"
puts "-" * 40

gate = RHDL::HDL::AndGate.new("and_gate")
puts gate.to_diagram
puts

# ====================
# 2. Gate with Values
# ====================
puts "\n2. AND Gate with Signal Values"
puts "-" * 40

gate.set_input(:a0, 1)
gate.set_input(:a1, 0)
gate.propagate

puts gate.to_diagram(show_values: true)
puts

# ====================
# 3. ASCII Style (for terminals without Unicode support)
# ====================
puts "\n3. ASCII Style Diagram"
puts "-" * 40

puts gate.to_diagram(style: :ascii, show_values: true)
puts

# ====================
# 4. Full Adder
# ====================
puts "\n4. Full Adder"
puts "-" * 40

adder = RHDL::HDL::FullAdder.new("fa")
puts adder.to_diagram
puts

# ====================
# 5. ALU (Arithmetic Logic Unit)
# ====================
puts "\n5. ALU (8-bit)"
puts "-" * 40

alu = RHDL::HDL::ALU.new("alu", width: 8)
puts alu.to_diagram
puts

# ====================
# 6. ALU Schematic (detailed view)
# ====================
puts "\n6. ALU Schematic View"
puts "-" * 40

puts alu.to_schematic
puts

# ====================
# 7. CPU Datapath
# ====================
puts "\n7. CPU Datapath"
puts "-" * 40

cpu = RHDL::HDL::CPU::Datapath.new("my_cpu")
puts cpu.to_diagram
puts

# ====================
# 8. CPU Hierarchy Tree
# ====================
puts "\n8. CPU Component Hierarchy"
puts "-" * 40

puts cpu.to_hierarchy(max_depth: 2)
puts

# ====================
# 9. CPU Schematic with Subcomponents
# ====================
puts "\n9. CPU Schematic (with internal components)"
puts "-" * 40

puts cpu.to_schematic(show_subcomponents: true)
puts

# ====================
# 10. Export to DOT (Graphviz) format
# ====================
puts "\n10. DOT Format Export (for Graphviz)"
puts "-" * 40

puts alu.to_dot
puts

# ====================
# 11. File Export Examples
# ====================
puts "\n11. File Export"
puts "-" * 40

# Save SVG diagram
cpu.save_svg("/tmp/cpu_diagram.svg")
puts "Saved CPU diagram to /tmp/cpu_diagram.svg"

# Save DOT file (can be rendered with Graphviz: dot -Tpng cpu.dot -o cpu.png)
cpu.save_dot("/tmp/cpu_diagram.dot")
puts "Saved CPU DOT to /tmp/cpu_diagram.dot"
puts

# ====================
# 12. Memory Components
# ====================
puts "\n12. RAM Component"
puts "-" * 40

ram = RHDL::HDL::RAM.new("memory", data_width: 8, addr_width: 16)
puts ram.to_diagram
puts

# ====================
# 13. Sequential Components
# ====================
puts "\n13. D Flip-Flop"
puts "-" * 40

dff = RHDL::HDL::DFlipFlop.new("dff")
puts dff.to_diagram
puts

# ====================
# 14. Counter
# ====================
puts "\n14. Program Counter (16-bit)"
puts "-" * 40

pc = RHDL::HDL::ProgramCounter.new("pc", width: 16)
puts pc.to_diagram
puts

# ====================
# 15. Register File
# ====================
puts "\n15. Register File"
puts "-" * 40

regfile = RHDL::HDL::RegisterFile.new("regs", num_regs: 8, width: 8)
puts regfile.to_diagram
puts

puts "=" * 60
puts "To render SVG diagrams:"
puts "  Open /tmp/cpu_diagram.svg in a web browser"
puts ""
puts "To render DOT diagrams with Graphviz:"
puts "  dot -Tpng /tmp/cpu_diagram.dot -o cpu.png"
puts "=" * 60
