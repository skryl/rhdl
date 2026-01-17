# Try to load bundler, but don't fail if it's not available
begin
  require "bundler/gem_tasks"
rescue LoadError
  # Bundler not available, skip gem tasks
end

# RSpec tasks
begin
  require "rspec/core/rake_task"

  RSpec::Core::RakeTask.new(:spec)

  RSpec::Core::RakeTask.new(:spec_6502) do |t|
    t.pattern = "spec/examples/mos6502/**/*_spec.rb"
    t.rspec_opts = "--format progress"
  end

  RSpec::Core::RakeTask.new(:spec_doc) do |t|
    t.rspec_opts = "--format documentation"
  end
rescue LoadError
  desc "Run RSpec tests"
  task :spec do
    sh "ruby -Ilib -S rspec"
  end

  desc "Run 6502 CPU tests"
  task :spec_6502 do
    sh "ruby -Ilib -S rspec spec/examples/mos6502/ --format progress"
  end

  desc "Run all tests with documentation format"
  task :spec_doc do
    sh "ruby -Ilib -S rspec --format documentation"
  end
end

# RuboCop tasks (optional)
begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
  task default: %i[spec rubocop]
rescue LoadError
  # RuboCop not available
  task default: :spec
end

# =============================================================================
# Diagram Generation Tasks
# =============================================================================

namespace :diagrams do
  DIAGRAMS_DIR = File.expand_path('diagrams', __dir__)

  # Diagram modes
  DIAGRAM_MODES = %w[component hierarchical gate].freeze

  # Component categories
  CATEGORIES = %w[gates sequential arithmetic combinational memory cpu].freeze

  # Component definitions with their instantiation parameters
  HDL_COMPONENTS = {
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

  # Components that support gate-level lowering
  GATE_LEVEL_COMPONENTS = %w[
    gates/not_gate gates/buffer gates/and_gate gates/and_gate_3input
    gates/or_gate gates/xor_gate
    gates/bitwise_and gates/bitwise_or gates/bitwise_xor
    sequential/d_flipflop sequential/d_flipflop_async
    arithmetic/half_adder arithmetic/full_adder arithmetic/ripple_carry_adder
    combinational/mux2
  ].freeze

  def create_mode_directories
    DIAGRAM_MODES.each do |mode|
      mode_dir = File.join(DIAGRAMS_DIR, mode)
      CATEGORIES.each do |category|
        FileUtils.mkdir_p(File.join(mode_dir, category))
      end
    end
  end

  def generate_component_diagram(name, component, base_dir)
    subdir = File.dirname(name)
    full_subdir = File.join(base_dir, subdir)
    FileUtils.mkdir_p(full_subdir)
    base_path = File.join(base_dir, name)

    # Generate ASCII block diagram
    txt_content = []
    txt_content << "=" * 60
    txt_content << "Component: #{component.name}"
    txt_content << "Type: #{component.class.name.split('::').last}"
    txt_content << "=" * 60
    txt_content << ""
    txt_content << component.to_diagram
    File.write("#{base_path}.txt", txt_content.join("\n"))

    # Generate SVG (simple block view)
    component.save_svg("#{base_path}.svg", show_subcomponents: false)

    # Generate DOT
    component.save_dot("#{base_path}.dot")
  end

  def generate_hierarchical_diagram(name, component, base_dir)
    subdir = File.dirname(name)
    full_subdir = File.join(base_dir, subdir)
    FileUtils.mkdir_p(full_subdir)
    base_path = File.join(base_dir, name)

    # Generate ASCII schematic with subcomponents
    txt_content = []
    txt_content << "=" * 60
    txt_content << "Component: #{component.name}"
    txt_content << "Type: #{component.class.name.split('::').last}"
    txt_content << "=" * 60
    txt_content << ""
    txt_content << component.to_schematic(show_subcomponents: true)
    txt_content << ""
    txt_content << "Hierarchy:"
    txt_content << "-" * 40
    txt_content << component.to_hierarchy(max_depth: 3)
    File.write("#{base_path}.txt", txt_content.join("\n"))

    # Generate SVG with subcomponents
    component.save_svg("#{base_path}.svg", show_subcomponents: true)

    # Generate DOT
    component.save_dot("#{base_path}.dot")
  end

  def generate_gate_level_diagram(name, component, base_dir)
    subdir = File.dirname(name)
    full_subdir = File.join(base_dir, subdir)
    FileUtils.mkdir_p(full_subdir)
    base_path = File.join(base_dir, name)

    # Lower to gate-level IR
    ir = RHDL::Gates::Lower.from_components([component], name: component.name)

    # Build gate-level diagram
    diagram = RHDL::Diagram.gate_level(ir)

    # Generate DOT format
    dot_content = diagram.to_dot
    File.write("#{base_path}.dot", dot_content)

    # Generate text summary
    txt_content = []
    txt_content << "=" * 60
    txt_content << "Gate-Level: #{component.name}"
    txt_content << "Type: #{component.class.name.split('::').last}"
    txt_content << "=" * 60
    txt_content << ""
    txt_content << "Gates: #{ir.gates.length}"
    txt_content << "DFFs: #{ir.dffs.length}"
    txt_content << "Nets: #{ir.net_count}"
    txt_content << ""
    txt_content << "Inputs:"
    ir.inputs.each { |n, nets| txt_content << "  #{n}[#{nets.length}]" }
    txt_content << ""
    txt_content << "Outputs:"
    ir.outputs.each { |n, nets| txt_content << "  #{n}[#{nets.length}]" }
    txt_content << ""
    txt_content << "Gate Types:"
    gate_counts = ir.gates.group_by(&:type).transform_values(&:length)
    gate_counts.each { |type, count| txt_content << "  #{type}: #{count}" }
    File.write("#{base_path}.txt", txt_content.join("\n"))
  end

  def generate_readme(diagrams_dir)
    readme = []
    readme << "# RHDL Component Diagrams"
    readme << ""
    readme << "This directory contains circuit diagrams for all HDL components in RHDL,"
    readme << "organized into three visualization modes."
    readme << ""
    readme << "## Diagram Modes"
    readme << ""
    readme << "### Component (`component/`)"
    readme << "Simple block diagrams showing component interface (inputs/outputs)."
    readme << "Best for understanding what a component does at a high level."
    readme << ""
    readme << "### Hierarchical (`hierarchical/`)"
    readme << "Detailed schematics showing internal subcomponents and hierarchy."
    readme << "Best for understanding how complex components are built from simpler ones."
    readme << ""
    readme << "### Gate (`gate/`)"
    readme << "Gate-level netlist diagrams showing primitive logic gates and flip-flops."
    readme << "Only available for components that support gate-level lowering."
    readme << "Best for understanding the actual hardware implementation."
    readme << ""
    readme << "## File Formats"
    readme << ""
    readme << "Each component has up to three diagram files:"
    readme << "- `.txt` - ASCII/Unicode text diagram for terminal viewing"
    readme << "- `.svg` - Scalable vector graphics for web/document viewing"
    readme << "- `.dot` - Graphviz DOT format for custom rendering"
    readme << ""
    readme << "## Rendering DOT Files"
    readme << ""
    readme << "To render DOT files as PNG images using Graphviz:"
    readme << "```bash"
    readme << "dot -Tpng diagrams/gate/arithmetic/full_adder.dot -o full_adder.png"
    readme << "```"
    readme << ""
    readme << "## Components by Category"
    readme << ""

    category_names = {
      'gates' => 'Logic Gates',
      'sequential' => 'Sequential Components',
      'arithmetic' => 'Arithmetic Components',
      'combinational' => 'Combinational Components',
      'memory' => 'Memory Components',
      'cpu' => 'CPU Components'
    }

    CATEGORIES.each do |category|
      readme << "### #{category_names[category]}"
      readme << ""

      # List components in this category from component mode
      path = File.join(diagrams_dir, 'component', category)
      if Dir.exist?(path)
        files = Dir.glob(File.join(path, '*.txt')).sort
        files.each do |f|
          basename = File.basename(f, '.txt')
          gate_level = GATE_LEVEL_COMPONENTS.include?("#{category}/#{basename}")
          gate_link = gate_level ? ", [Gate](gate/#{category}/#{basename}.dot)" : ""
          readme << "- **#{basename}**: [Component](component/#{category}/#{basename}.txt), [Hierarchical](hierarchical/#{category}/#{basename}.txt)#{gate_link}"
        end
      end
      readme << ""
    end

    readme << "## Regenerating Diagrams"
    readme << ""
    readme << "```bash"
    readme << "# Generate all diagrams in all modes"
    readme << "rake diagrams:generate"
    readme << ""
    readme << "# Generate only component-level diagrams"
    readme << "rake diagrams:component"
    readme << ""
    readme << "# Generate only hierarchical diagrams"
    readme << "rake diagrams:hierarchical"
    readme << ""
    readme << "# Generate only gate-level diagrams"
    readme << "rake diagrams:gate"
    readme << "```"
    readme << ""
    readme << "---"
    readme << "*Generated by RHDL Circuit Diagram Generator*"

    File.write(File.join(diagrams_dir, 'README.md'), readme.join("\n"))
  end

  desc "Generate component-level diagrams (simple block view)"
  task :component do
    require_relative 'lib/rhdl/hdl'

    puts "Generating component-level diagrams..."
    base_dir = File.join(DIAGRAMS_DIR, 'component')
    CATEGORIES.each { |c| FileUtils.mkdir_p(File.join(base_dir, c)) }

    HDL_COMPONENTS.each do |name, creator|
      begin
        component = creator.call
        generate_component_diagram(name, component, base_dir)
        puts "  [OK] #{name}"
      rescue => e
        puts "  [ERROR] #{name}: #{e.message}"
      end
    end
  end

  desc "Generate hierarchical diagrams (with subcomponents)"
  task :hierarchical do
    require_relative 'lib/rhdl/hdl'

    puts "Generating hierarchical diagrams..."
    base_dir = File.join(DIAGRAMS_DIR, 'hierarchical')
    CATEGORIES.each { |c| FileUtils.mkdir_p(File.join(base_dir, c)) }

    HDL_COMPONENTS.each do |name, creator|
      begin
        component = creator.call
        generate_hierarchical_diagram(name, component, base_dir)
        puts "  [OK] #{name}"
      rescue => e
        puts "  [ERROR] #{name}: #{e.message}"
      end
    end
  end

  desc "Generate gate-level diagrams (primitive gates and flip-flops)"
  task :gate do
    require_relative 'lib/rhdl/hdl'
    require_relative 'lib/rhdl/gates'
    require_relative 'lib/rhdl/diagram'

    puts "Generating gate-level diagrams..."
    base_dir = File.join(DIAGRAMS_DIR, 'gate')
    CATEGORIES.each { |c| FileUtils.mkdir_p(File.join(base_dir, c)) }

    GATE_LEVEL_COMPONENTS.each do |name|
      creator = HDL_COMPONENTS[name]
      next unless creator

      begin
        component = creator.call
        generate_gate_level_diagram(name, component, base_dir)
        puts "  [OK] #{name}"
      rescue => e
        puts "  [ERROR] #{name}: #{e.message}"
      end
    end

    puts ""
    puts "Note: Gate-level diagrams are only available for components that support lowering."
    puts "Components with gate-level support: #{GATE_LEVEL_COMPONENTS.length}"
  end

  desc "Generate all circuit diagrams (component, hierarchical, gate)"
  task :generate => [:component, :hierarchical, :gate] do
    require_relative 'lib/rhdl/hdl'

    puts ""
    puts "=" * 60
    puts "Generating README..."
    generate_readme(DIAGRAMS_DIR)
    puts "Done! Diagrams generated in: #{DIAGRAMS_DIR}"
    puts "=" * 60
  end

  desc "Clean all generated diagrams"
  task :clean do
    DIAGRAM_MODES.each do |mode|
      mode_dir = File.join(DIAGRAMS_DIR, mode)
      if Dir.exist?(mode_dir)
        FileUtils.rm_rf(mode_dir)
        puts "Cleaned: #{mode_dir}"
      end
    end
    readme = File.join(DIAGRAMS_DIR, 'README.md')
    FileUtils.rm_f(readme) if File.exist?(readme)
    puts "Diagrams cleaned."
  end
end

desc "Generate all diagrams (alias for diagrams:generate)"
task diagrams: 'diagrams:generate'

# =============================================================================
# HDL Export Tasks (VHDL/Verilog)
# =============================================================================

namespace :hdl do
  VHDL_DIR = File.expand_path('vhdl', __dir__)
  VERILOG_DIR = File.expand_path('verilog', __dir__)
  EXAMPLES_DIR = File.expand_path('examples', __dir__)

  # Example components with to_verilog methods
  # Format: { 'relative_path' => ['require_path', 'ClassName'] }
  EXAMPLE_COMPONENTS = {
    # MOS6502S synthesizable components
    'mos6502s/mos6502s_registers' => ['examples/mos6502s/registers/registers', 'MOS6502S::Registers'],
    'mos6502s/mos6502s_stack_pointer' => ['examples/mos6502s/registers/stack_pointer', 'MOS6502S::StackPointer'],
    'mos6502s/mos6502s_program_counter' => ['examples/mos6502s/registers/program_counter', 'MOS6502S::ProgramCounter'],
    'mos6502s/mos6502s_instruction_register' => ['examples/mos6502s/registers/instruction_register', 'MOS6502S::InstructionRegister'],
    'mos6502s/mos6502s_address_latch' => ['examples/mos6502s/registers/address_latch', 'MOS6502S::AddressLatch'],
    'mos6502s/mos6502s_data_latch' => ['examples/mos6502s/registers/data_latch', 'MOS6502S::DataLatch'],
    'mos6502s/mos6502s_status_register' => ['examples/mos6502s/status_register', 'MOS6502S::StatusRegister'],
    'mos6502s/mos6502s_address_generator' => ['examples/mos6502s/address_gen/address_generator', 'MOS6502S::AddressGenerator'],
    'mos6502s/mos6502s_indirect_addr_calc' => ['examples/mos6502s/address_gen/indirect_address_calc', 'MOS6502S::IndirectAddressCalc'],
    'mos6502s/mos6502s_alu' => ['examples/mos6502s/alu', 'MOS6502S::ALU'],
    'mos6502s/mos6502s_instruction_decoder' => ['examples/mos6502s/instruction_decoder', 'MOS6502S::InstructionDecoder'],
    'mos6502s/mos6502s_control_unit' => ['examples/mos6502s/control_unit', 'MOS6502S::ControlUnit'],
    'mos6502s/mos6502s_memory' => ['examples/mos6502s/memory', 'MOS6502S::Memory']
  }.freeze

  desc "Export all DSL components to VHDL and Verilog (lib/ and examples/)"
  task :export => [:export_lib, :export_examples] do
    puts
    puts "=" * 50
    puts "HDL export complete!"
    puts "VHDL files:    #{VHDL_DIR}"
    puts "Verilog files: #{VERILOG_DIR}"
  end

  desc "Export lib/ DSL components to VHDL and Verilog"
  task :export_lib do
    require_relative 'lib/rhdl'

    puts "RHDL Component Exporter - lib/"
    puts "=" * 50
    puts

    # Ensure output directories exist
    FileUtils.mkdir_p(VHDL_DIR)
    FileUtils.mkdir_p(VERILOG_DIR)

    # Get all exportable components from lib
    components = RHDL::Exporter.list_components

    if components.empty?
      puts "No exportable components found in lib/."
      return
    end

    puts "Found #{components.size} exportable component(s) in lib/:"
    puts

    # Export each component
    exported_count = 0
    components.each do |info|
      component = info[:class]
      relative_path = info[:relative_path]

      begin
        # Create subdirectories and export to VHDL
        vhdl_file = File.join(VHDL_DIR, "#{relative_path}.vhd")
        FileUtils.mkdir_p(File.dirname(vhdl_file))
        vhdl_content = component.to_vhdl
        File.write(vhdl_file, vhdl_content)

        # Create subdirectories and export to Verilog
        verilog_file = File.join(VERILOG_DIR, "#{relative_path}.v")
        FileUtils.mkdir_p(File.dirname(verilog_file))
        verilog_content = component.to_verilog
        File.write(verilog_file, verilog_content)

        puts "  [OK] #{component.name}"
        puts "       -> #{vhdl_file}"
        puts "       -> #{verilog_file}"
        exported_count += 1
      rescue => e
        puts "  [ERROR] #{component.name}: #{e.message}"
      end
    end

    puts
    puts "Exported #{exported_count}/#{components.size} lib/ components"
  end

  desc "Export examples/ components to VHDL and Verilog"
  task :export_examples do
    require_relative 'lib/rhdl'

    puts
    puts "RHDL Component Exporter - examples/"
    puts "=" * 50
    puts

    # Ensure output directories exist
    FileUtils.mkdir_p(VHDL_DIR)
    FileUtils.mkdir_p(VERILOG_DIR)

    exported_count = 0
    EXAMPLE_COMPONENTS.each do |relative_path, (require_path, class_name)|
      begin
        # Load the component
        require_relative require_path

        # Get the class
        component = class_name.split('::').inject(Object) { |o, c| o.const_get(c) }

        # Export to Verilog (only Verilog for examples as VHDL may not be implemented)
        verilog_file = File.join(VERILOG_DIR, "#{relative_path}.v")
        FileUtils.mkdir_p(File.dirname(verilog_file))
        verilog_content = component.to_verilog
        File.write(verilog_file, verilog_content)

        puts "  [OK] #{class_name}"
        puts "       -> #{verilog_file}"
        exported_count += 1
      rescue => e
        puts "  [ERROR] #{class_name}: #{e.message}"
      end
    end

    puts
    puts "Exported #{exported_count}/#{EXAMPLE_COMPONENTS.size} examples/ components"
  end

  desc "Export only VHDL files"
  task :vhdl do
    require_relative 'lib/rhdl'

    FileUtils.mkdir_p(VHDL_DIR)

    components = RHDL::Exporter.list_components
    puts "Exporting #{components.size} components to VHDL..."

    components.each do |info|
      component = info[:class]
      relative_path = info[:relative_path]
      begin
        vhdl_file = File.join(VHDL_DIR, "#{relative_path}.vhd")
        FileUtils.mkdir_p(File.dirname(vhdl_file))
        File.write(vhdl_file, component.to_vhdl)
        puts "  [OK] #{relative_path}.vhd"
      rescue => e
        puts "  [ERROR] #{relative_path}: #{e.message}"
      end
    end
  end

  desc "Export only Verilog files"
  task :verilog do
    require_relative 'lib/rhdl'

    FileUtils.mkdir_p(VERILOG_DIR)

    components = RHDL::Exporter.list_components
    puts "Exporting #{components.size} components to Verilog..."

    components.each do |info|
      component = info[:class]
      relative_path = info[:relative_path]
      begin
        verilog_file = File.join(VERILOG_DIR, "#{relative_path}.v")
        FileUtils.mkdir_p(File.dirname(verilog_file))
        File.write(verilog_file, component.to_verilog)
        puts "  [OK] #{relative_path}.v"
      rescue => e
        puts "  [ERROR] #{relative_path}: #{e.message}"
      end
    end
  end

  desc "Clean all generated HDL files"
  task :clean do
    # Clean VHDL files recursively (keep .gitkeep)
    Dir.glob(File.join(VHDL_DIR, '**', '*.vhd')).each do |f|
      FileUtils.rm_f(f)
    end
    # Remove empty subdirectories
    Dir.glob(File.join(VHDL_DIR, '**', '*')).sort.reverse.each do |d|
      FileUtils.rmdir(d) if File.directory?(d) && Dir.empty?(d)
    end
    puts "Cleaned: #{VHDL_DIR}"

    # Clean Verilog files recursively (keep .gitkeep)
    Dir.glob(File.join(VERILOG_DIR, '**', '*.v')).each do |f|
      FileUtils.rm_f(f)
    end
    # Remove empty subdirectories
    Dir.glob(File.join(VERILOG_DIR, '**', '*')).sort.reverse.each do |d|
      FileUtils.rmdir(d) if File.directory?(d) && Dir.empty?(d)
    end
    puts "Cleaned: #{VERILOG_DIR}"

    puts "HDL files cleaned."
  end
end

desc "Export all HDL (alias for hdl:export)"
task hdl: 'hdl:export'

# =============================================================================
# Gate-Level Synthesis Tasks
# =============================================================================

namespace :gates do
  GATES_DIR = File.expand_path('gates', __dir__)

  # All components that support gate-level synthesis
  GATE_SYNTH_COMPONENTS = {
    # Gates
    'gates/not_gate' => -> { RHDL::HDL::NotGate.new('not_gate') },
    'gates/buffer' => -> { RHDL::HDL::Buffer.new('buffer') },
    'gates/and_gate' => -> { RHDL::HDL::AndGate.new('and_gate') },
    'gates/or_gate' => -> { RHDL::HDL::OrGate.new('or_gate') },
    'gates/xor_gate' => -> { RHDL::HDL::XorGate.new('xor_gate') },
    'gates/nand_gate' => -> { RHDL::HDL::NandGate.new('nand_gate') },
    'gates/nor_gate' => -> { RHDL::HDL::NorGate.new('nor_gate') },
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
    'sequential/register' => -> { RHDL::HDL::Register.new('reg', width: 8) },
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
    'arithmetic/incdec' => -> { RHDL::HDL::IncDec.new('incdec', width: 8) },
    'arithmetic/multiplier' => -> { RHDL::HDL::Multiplier.new('mul', width: 4) },
    'arithmetic/divider' => -> { RHDL::HDL::Divider.new('div', width: 4) },
    'arithmetic/alu' => -> { RHDL::HDL::ALU.new('alu', width: 8) },

    # Combinational
    'combinational/mux2' => -> { RHDL::HDL::Mux2.new('mux2', width: 8) },
    'combinational/mux4' => -> { RHDL::HDL::Mux4.new('mux4', width: 4) },
    'combinational/mux8' => -> { RHDL::HDL::Mux8.new('mux8', width: 4) },
    'combinational/demux2' => -> { RHDL::HDL::Demux2.new('demux2', width: 4) },
    'combinational/demux4' => -> { RHDL::HDL::Demux4.new('demux4', width: 4) },
    'combinational/decoder_2to4' => -> { RHDL::HDL::Decoder2to4.new('dec2to4') },
    'combinational/decoder_3to8' => -> { RHDL::HDL::Decoder3to8.new('dec3to8') },
    'combinational/encoder_4to2' => -> { RHDL::HDL::Encoder4to2.new('enc4to2') },
    'combinational/encoder_8to3' => -> { RHDL::HDL::Encoder8to3.new('enc8to3') },
    'combinational/zero_detect' => -> { RHDL::HDL::ZeroDetect.new('zero_det', width: 8) },
    'combinational/sign_extend' => -> { RHDL::HDL::SignExtend.new('sext', in_width: 8, out_width: 16) },
    'combinational/zero_extend' => -> { RHDL::HDL::ZeroExtend.new('zext', in_width: 8, out_width: 16) },
    'combinational/bit_reverse' => -> { RHDL::HDL::BitReverse.new('bitrev', width: 8) },
    'combinational/popcount' => -> { RHDL::HDL::PopCount.new('popcount', width: 8) },
    'combinational/lzcount' => -> { RHDL::HDL::LZCount.new('lzcount', width: 8) },
    'combinational/barrel_shifter' => -> { RHDL::HDL::BarrelShifter.new('barrel', width: 8) },

    # CPU
    'cpu/instruction_decoder' => -> { RHDL::HDL::CPU::InstructionDecoder.new('decoder') },
    'cpu/synth_datapath' => -> { RHDL::HDL::CPU::SynthDatapath.new('synth_cpu') }
  }.freeze

  desc "Export all components to gate-level IR (JSON netlists)"
  task :export do
    require_relative 'lib/rhdl/hdl'
    require_relative 'lib/rhdl/gates'

    puts "RHDL Gate-Level Synthesis Export"
    puts "=" * 50
    puts

    FileUtils.mkdir_p(GATES_DIR)
    exported_count = 0
    error_count = 0

    GATE_SYNTH_COMPONENTS.each do |name, creator|
      begin
        component = creator.call

        # Create subdirectory
        subdir = File.dirname(name)
        FileUtils.mkdir_p(File.join(GATES_DIR, subdir))

        # Lower to gate-level IR
        ir = RHDL::Gates::Lower.from_components([component], name: component.name)

        # Export to JSON
        json_file = File.join(GATES_DIR, "#{name}.json")
        File.write(json_file, ir.to_json)

        # Also create a summary text file
        txt_file = File.join(GATES_DIR, "#{name}.txt")
        summary = []
        summary << "Component: #{component.name}"
        summary << "Type: #{component.class.name}"
        summary << "Gates: #{ir.gates.length}"
        summary << "DFFs: #{ir.dffs.length}"
        summary << "Nets: #{ir.net_count}"
        summary << ""
        summary << "Inputs:"
        ir.inputs.each { |n, nets| summary << "  #{n}: #{nets.length} bits" }
        summary << ""
        summary << "Outputs:"
        ir.outputs.each { |n, nets| summary << "  #{n}: #{nets.length} bits" }
        summary << ""
        summary << "Gate Types:"
        gate_counts = ir.gates.group_by(&:type).transform_values(&:length)
        gate_counts.each { |type, count| summary << "  #{type}: #{count}" }
        File.write(txt_file, summary.join("\n"))

        puts "  [OK] #{name} (#{ir.gates.length} gates, #{ir.dffs.length} DFFs)"
        exported_count += 1
      rescue => e
        puts "  [ERROR] #{name}: #{e.message}"
        error_count += 1
      end
    end

    puts
    puts "=" * 50
    puts "Exported: #{exported_count}/#{GATE_SYNTH_COMPONENTS.size} components"
    puts "Errors: #{error_count}"
    puts "Output: #{GATES_DIR}"
  end

  desc "Export simcpu datapath to gate-level"
  task :simcpu do
    require_relative 'lib/rhdl/hdl'
    require_relative 'lib/rhdl/gates'

    puts "RHDL SimCPU Gate-Level Export"
    puts "=" * 50
    puts

    FileUtils.mkdir_p(File.join(GATES_DIR, 'cpu'))

    begin
      # Create CPU datapath components
      pc = RHDL::HDL::ProgramCounter.new('pc', width: 16)
      acc = RHDL::HDL::Register.new('acc', width: 8)
      alu = RHDL::HDL::ALU.new('alu', width: 8)
      decoder = RHDL::HDL::CPU::InstructionDecoder.new('decoder')

      # Lower each component individually
      components = [
        ['cpu/pc', pc],
        ['cpu/acc', acc],
        ['cpu/alu', alu],
        ['cpu/decoder', decoder]
      ]

      total_gates = 0
      total_dffs = 0

      components.each do |name, component|
        ir = RHDL::Gates::Lower.from_components([component], name: component.name)

        json_file = File.join(GATES_DIR, "#{name}.json")
        File.write(json_file, ir.to_json)

        puts "  [OK] #{name}: #{ir.gates.length} gates, #{ir.dffs.length} DFFs"
        total_gates += ir.gates.length
        total_dffs += ir.dffs.length
      end

      puts
      puts "SimCPU Totals:"
      puts "  Total Gates: #{total_gates}"
      puts "  Total DFFs: #{total_dffs}"
      puts "  Output: #{File.join(GATES_DIR, 'cpu')}"
    rescue => e
      puts "  [ERROR] #{e.message}"
      puts e.backtrace.first(5).join("\n")
    end
  end

  desc "Clean gate-level synthesis output"
  task :clean do
    if Dir.exist?(GATES_DIR)
      FileUtils.rm_rf(GATES_DIR)
      puts "Cleaned: #{GATES_DIR}"
    end
    puts "Gate-level files cleaned."
  end

  desc "Show gate-level synthesis statistics"
  task :stats do
    require_relative 'lib/rhdl/hdl'
    require_relative 'lib/rhdl/gates'

    puts "RHDL Gate-Level Synthesis Statistics"
    puts "=" * 50
    puts

    total_gates = 0
    total_dffs = 0
    component_stats = []

    GATE_SYNTH_COMPONENTS.each do |name, creator|
      begin
        component = creator.call
        ir = RHDL::Gates::Lower.from_components([component], name: component.name)
        component_stats << {
          name: name,
          gates: ir.gates.length,
          dffs: ir.dffs.length,
          nets: ir.net_count
        }
        total_gates += ir.gates.length
        total_dffs += ir.dffs.length
      rescue => e
        component_stats << { name: name, error: e.message }
      end
    end

    # Sort by gate count
    component_stats.sort_by! { |s| -(s[:gates] || 0) }

    puts "Components by Gate Count:"
    puts "-" * 50
    component_stats.each do |s|
      if s[:error]
        puts "  #{s[:name]}: ERROR - #{s[:error]}"
      else
        puts "  #{s[:name]}: #{s[:gates]} gates, #{s[:dffs]} DFFs, #{s[:nets]} nets"
      end
    end

    puts
    puts "=" * 50
    puts "Total Components: #{GATE_SYNTH_COMPONENTS.size}"
    puts "Total Gates: #{total_gates}"
    puts "Total DFFs: #{total_dffs}"
  end
end

desc "Export gate-level synthesis (alias for gates:export)"
task gates: 'gates:export'

# =============================================================================
# Benchmarking Tasks
# =============================================================================

namespace :bench do
  desc "Benchmark gate-level simulation"
  task :gates do
    require_relative 'lib/rhdl'

    lanes = (ENV['RHDL_BENCH_LANES'] || '64').to_i
    cycles = (ENV['RHDL_BENCH_CYCLES'] || '100000').to_i

    puts "Gate-level Simulation Benchmark"
    puts "=" * 50
    puts "Lanes: #{lanes}"
    puts "Cycles: #{cycles}"
    puts

    not_gate = RHDL::HDL::NotGate.new('inv')
    dff = RHDL::HDL::DFlipFlop.new('reg')

    RHDL::HDL::SimComponent.connect(dff.outputs[:q], not_gate.inputs[:a])
    RHDL::HDL::SimComponent.connect(not_gate.outputs[:y], dff.inputs[:d])

    sim = RHDL::Gates.gate_level([not_gate, dff], backend: :cpu, lanes: lanes, name: 'bench_toggle')

    sim.poke('reg.rst', 0)
    sim.poke('reg.en', (1 << lanes) - 1)

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    cycles.times { sim.tick }
    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    elapsed = finish - start
    rate = cycles / elapsed
    puts "Result: #{cycles} cycles in #{format('%.3f', elapsed)}s (#{format('%.2f', rate)} cycles/s)"
  end
end

desc "Run gate benchmark (alias for bench:gates)"
task bench: 'bench:gates'

# =============================================================================
# Combined Tasks
# =============================================================================

desc "Generate all output files (diagrams + HDL exports)"
task :generate_all => ['diagrams:generate', 'hdl:export']

desc "Clean all generated files"
task :clean_all => ['diagrams:clean', 'hdl:clean']

desc "Regenerate all output files (clean + generate)"
task :regenerate => ['clean_all', 'generate_all']
