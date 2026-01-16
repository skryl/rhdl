#!/usr/bin/env ruby
# Script to generate circuit diagrams for all HDL components
# Usage: ruby scripts/generate_diagrams.rb
#
# This script creates ASCII/Unicode diagrams and SVG files for all
# HDL components in the RHDL library.

require_relative '../lib/rhdl/hdl'

DIAGRAMS_DIR = File.expand_path('../diagrams', __dir__)

# Ensure diagrams directory exists
Dir.mkdir(DIAGRAMS_DIR) unless Dir.exist?(DIAGRAMS_DIR)

# Component definitions with their instantiation parameters
COMPONENTS = {
  # Gates
  'gates/not_gate' => -> { RHDL::HDL::NotGate.new('not_gate') },
  'gates/buffer' => -> { RHDL::HDL::Buffer.new('buffer') },
  'gates/and_gate' => -> { RHDL::HDL::AndGate.new('and_gate') },
  'gates/and_gate_3input' => -> { RHDL::HDL::AndGate.new('and_gate_3in', inputs: 3) },
  'gates/or_gate' => -> { RHDL::HDL::OrGate.new('or_gate') },
  'gates/nand_gate' => -> { RHDL::HDL::NandGate.new('nand_gate') },
  'gates/nor_gate' => -> { RHDL::HDL::NorGate.new('nor_gate') },
  'gates/xor_gate' => -> { RHDL::HDL::XorGate.new('xor_gate') },
  'gates/xnor_gate' => -> { RHDL::HDL::XnorGate.new('xnor_gate') },
  'gates/tristate_buffer' => -> { RHDL::HDL::TristateBuffer.new('tristate') },
  'gates/bitwise_and' => -> { RHDL::HDL::BitwiseAnd.new('bitwise_and', width: 8) },
  'gates/bitwise_or' => -> { RHDL::HDL::BitwiseOr.new('bitwise_or', width: 8) },
  'gates/bitwise_xor' => -> { RHDL::HDL::BitwiseXor.new('bitwise_xor', width: 8) },
  'gates/bitwise_not' => -> { RHDL::HDL::BitwiseNot.new('bitwise_not', width: 8) },

  # Sequential
  'sequential/d_flipflop' => -> { RHDL::HDL::DFlipFlop.new('dff') },
  'sequential/d_flipflop_async' => -> { RHDL::HDL::DFlipFlopAsync.new('dff_async') },
  'sequential/t_flipflop' => -> { RHDL::HDL::TFlipFlop.new('tff') },
  'sequential/jk_flipflop' => -> { RHDL::HDL::JKFlipFlop.new('jkff') },
  'sequential/sr_flipflop' => -> { RHDL::HDL::SRFlipFlop.new('srff') },
  'sequential/sr_latch' => -> { RHDL::HDL::SRLatch.new('sr_latch') },
  'sequential/register_8bit' => -> { RHDL::HDL::Register.new('reg8', width: 8) },
  'sequential/register_16bit' => -> { RHDL::HDL::Register.new('reg16', width: 16) },
  'sequential/register_load' => -> { RHDL::HDL::RegisterLoad.new('reg_load', width: 8) },
  'sequential/shift_register' => -> { RHDL::HDL::ShiftRegister.new('shift_reg', width: 8) },
  'sequential/counter' => -> { RHDL::HDL::Counter.new('counter', width: 8) },
  'sequential/program_counter' => -> { RHDL::HDL::ProgramCounter.new('pc', width: 16) },
  'sequential/stack_pointer' => -> { RHDL::HDL::StackPointer.new('sp', width: 8) },

  # Arithmetic
  'arithmetic/half_adder' => -> { RHDL::HDL::HalfAdder.new('half_adder') },
  'arithmetic/full_adder' => -> { RHDL::HDL::FullAdder.new('full_adder') },
  'arithmetic/ripple_carry_adder' => -> { RHDL::HDL::RippleCarryAdder.new('rca', width: 8) },
  'arithmetic/subtractor' => -> { RHDL::HDL::Subtractor.new('sub', width: 8) },
  'arithmetic/addsub' => -> { RHDL::HDL::AddSub.new('addsub', width: 8) },
  'arithmetic/comparator' => -> { RHDL::HDL::Comparator.new('cmp', width: 8) },
  'arithmetic/multiplier' => -> { RHDL::HDL::Multiplier.new('mul', width: 8) },
  'arithmetic/divider' => -> { RHDL::HDL::Divider.new('div', width: 8) },
  'arithmetic/incdec' => -> { RHDL::HDL::IncDec.new('incdec', width: 8) },
  'arithmetic/alu_8bit' => -> { RHDL::HDL::ALU.new('alu8', width: 8) },
  'arithmetic/alu_16bit' => -> { RHDL::HDL::ALU.new('alu16', width: 16) },

  # Combinational
  'combinational/mux2' => -> { RHDL::HDL::Mux2.new('mux2', width: 8) },
  'combinational/mux4' => -> { RHDL::HDL::Mux4.new('mux4', width: 8) },
  'combinational/mux8' => -> { RHDL::HDL::Mux8.new('mux8', width: 8) },
  'combinational/muxn' => -> { RHDL::HDL::MuxN.new('muxn', width: 8, inputs: 4) },
  'combinational/demux2' => -> { RHDL::HDL::Demux2.new('demux2', width: 8) },
  'combinational/demux4' => -> { RHDL::HDL::Demux4.new('demux4', width: 8) },
  'combinational/decoder_2to4' => -> { RHDL::HDL::Decoder2to4.new('dec2to4') },
  'combinational/decoder_3to8' => -> { RHDL::HDL::Decoder3to8.new('dec3to8') },
  'combinational/decoder_n' => -> { RHDL::HDL::DecoderN.new('decn', width: 4) },
  'combinational/encoder_4to2' => -> { RHDL::HDL::Encoder4to2.new('enc4to2') },
  'combinational/encoder_8to3' => -> { RHDL::HDL::Encoder8to3.new('enc8to3') },
  'combinational/zero_detect' => -> { RHDL::HDL::ZeroDetect.new('zero_det', width: 8) },
  'combinational/sign_extend' => -> { RHDL::HDL::SignExtend.new('sext', in_width: 8, out_width: 16) },
  'combinational/zero_extend' => -> { RHDL::HDL::ZeroExtend.new('zext', in_width: 8, out_width: 16) },
  'combinational/barrel_shifter' => -> { RHDL::HDL::BarrelShifter.new('barrel', width: 8) },
  'combinational/bit_reverse' => -> { RHDL::HDL::BitReverse.new('bitrev', width: 8) },
  'combinational/popcount' => -> { RHDL::HDL::PopCount.new('popcount', width: 8) },
  'combinational/lzcount' => -> { RHDL::HDL::LZCount.new('lzcount', width: 8) },

  # Memory
  'memory/ram' => -> { RHDL::HDL::RAM.new('ram', data_width: 8, addr_width: 8) },
  'memory/ram_64k' => -> { RHDL::HDL::RAM.new('ram64k', data_width: 8, addr_width: 16) },
  'memory/dual_port_ram' => -> { RHDL::HDL::DualPortRAM.new('dpram', data_width: 8, addr_width: 8) },
  'memory/rom' => -> { RHDL::HDL::ROM.new('rom', data_width: 8, addr_width: 8) },
  'memory/register_file' => -> { RHDL::HDL::RegisterFile.new('regfile', num_regs: 8, data_width: 8) },
  'memory/stack' => -> { RHDL::HDL::Stack.new('stack', data_width: 8, depth: 16) },
  'memory/fifo' => -> { RHDL::HDL::FIFO.new('fifo', data_width: 8, depth: 16) },

  # CPU
  'cpu/instruction_decoder' => -> { RHDL::HDL::CPU::InstructionDecoder.new('decoder') },
  'cpu/accumulator' => -> { RHDL::HDL::CPU::Accumulator.new('acc') },
  'cpu/datapath' => -> { RHDL::HDL::CPU::Datapath.new('cpu') }
}

def generate_diagram(name, component)
  # Create subdirectory if needed
  subdir = File.dirname(name)
  full_subdir = File.join(DIAGRAMS_DIR, subdir)
  Dir.mkdir(full_subdir) unless Dir.exist?(full_subdir)

  base_path = File.join(DIAGRAMS_DIR, name)
  basename = File.basename(name)

  # Generate ASCII diagram (text file)
  txt_content = []
  txt_content << "=" * 60
  txt_content << "Component: #{component.name}"
  txt_content << "Type: #{component.class.name.split('::').last}"
  txt_content << "=" * 60
  txt_content << ""
  txt_content << "Block Diagram:"
  txt_content << "-" * 40
  txt_content << component.to_diagram
  txt_content << ""
  txt_content << "Schematic:"
  txt_content << "-" * 40
  txt_content << component.to_schematic(show_subcomponents: true)

  File.write("#{base_path}.txt", txt_content.join("\n"))

  # Generate SVG diagram
  component.save_svg("#{base_path}.svg", show_subcomponents: true)

  # Generate DOT diagram
  component.save_dot("#{base_path}.dot")

  puts "  Generated: #{name}.txt, #{name}.svg, #{name}.dot"
end

def main
  puts "=" * 60
  puts "RHDL Circuit Diagram Generator"
  puts "=" * 60
  puts ""
  puts "Output directory: #{DIAGRAMS_DIR}"
  puts ""

  # Create category subdirectories
  %w[gates sequential arithmetic combinational memory cpu].each do |category|
    dir = File.join(DIAGRAMS_DIR, category)
    Dir.mkdir(dir) unless Dir.exist?(dir)
  end

  success_count = 0
  error_count = 0

  COMPONENTS.each do |name, creator|
    begin
      component = creator.call
      generate_diagram(name, component)
      success_count += 1
    rescue => e
      puts "  ERROR generating #{name}: #{e.message}"
      error_count += 1
    end
  end

  puts ""
  puts "=" * 60
  puts "Generation complete!"
  puts "  Success: #{success_count}"
  puts "  Errors: #{error_count}"
  puts "=" * 60

  # Generate index file
  generate_index

  puts ""
  puts "Index file generated: #{File.join(DIAGRAMS_DIR, 'README.md')}"
end

def generate_index
  readme = []
  readme << "# RHDL Component Diagrams"
  readme << ""
  readme << "This directory contains circuit diagrams for all HDL components in RHDL."
  readme << ""
  readme << "## File Formats"
  readme << ""
  readme << "Each component has three diagram files:"
  readme << "- `.txt` - ASCII/Unicode text diagram for terminal viewing"
  readme << "- `.svg` - Scalable vector graphics for web/document viewing"
  readme << "- `.dot` - Graphviz DOT format for custom rendering"
  readme << ""
  readme << "## Rendering DOT Files"
  readme << ""
  readme << "To render DOT files as PNG images using Graphviz:"
  readme << "```bash"
  readme << "dot -Tpng diagrams/cpu/datapath.dot -o cpu.png"
  readme << "```"
  readme << ""
  readme << "## Components by Category"
  readme << ""

  categories = {
    'gates' => 'Logic Gates',
    'sequential' => 'Sequential Components',
    'arithmetic' => 'Arithmetic Components',
    'combinational' => 'Combinational Components',
    'memory' => 'Memory Components',
    'cpu' => 'CPU Components'
  }

  categories.each do |dir, title|
    readme << "### #{title}"
    readme << ""

    path = File.join(DIAGRAMS_DIR, dir)
    if Dir.exist?(path)
      files = Dir.glob(File.join(path, '*.txt')).sort
      files.each do |f|
        basename = File.basename(f, '.txt')
        readme << "- [#{basename}](#{dir}/#{basename}.txt) ([SVG](#{dir}/#{basename}.svg), [DOT](#{dir}/#{basename}.dot))"
      end
    end
    readme << ""
  end

  readme << "## Regenerating Diagrams"
  readme << ""
  readme << "To regenerate all diagrams, run:"
  readme << "```bash"
  readme << "ruby scripts/generate_diagrams.rb"
  readme << "```"
  readme << ""
  readme << "---"
  readme << "*Generated by RHDL Circuit Diagram Generator*"

  File.write(File.join(DIAGRAMS_DIR, 'README.md'), readme.join("\n"))
end

# Run the script
main
