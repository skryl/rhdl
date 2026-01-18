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

# =============================================================================
# Parallel Test Tasks
# =============================================================================

begin
  require 'parallel_tests'

  # Helper to find the parallel_rspec command
  def parallel_rspec_cmd
    binstub = File.expand_path('bin/parallel_rspec', __dir__)
    if File.executable?(binstub)
      binstub
    else
      'bundle exec parallel_rspec'
    end
  end

  namespace :parallel do
    desc "Run all tests in parallel (auto-detect CPU count)"
    task :spec do
      sh "#{parallel_rspec_cmd} spec/"
    end

    desc "Run all tests in parallel with specific number of processes"
    task :spec_n, [:count] do |_, args|
      count = args[:count] || ENV['PARALLEL_TEST_PROCESSORS'] || Parallel.processor_count
      sh "#{parallel_rspec_cmd} -n #{count} spec/"
    end

    desc "Run 6502 CPU tests in parallel"
    task :spec_6502 do
      sh "#{parallel_rspec_cmd} spec/examples/mos6502/"
    end

    desc "Run HDL tests in parallel"
    task :spec_hdl do
      sh "#{parallel_rspec_cmd} spec/rhdl/hdl/"
    end

    desc "Prepare parallel test database (record test file runtimes)"
    task :prepare do
      FileUtils.mkdir_p('tmp')
      sh "#{parallel_rspec_cmd} --record-runtime spec/"
    end

    desc "Run tests in parallel using runtime-based grouping for better balance"
    task :spec_balanced do
      runtime_log = 'tmp/parallel_runtime_rspec.log'
      if File.exist?(runtime_log)
        sh "#{parallel_rspec_cmd} --group-by runtime --runtime-log #{runtime_log} spec/"
      else
        puts "No runtime log found. Run 'rake parallel:prepare' first for optimal balancing."
        puts "Falling back to file-count based grouping..."
        Rake::Task['parallel:spec'].invoke
      end
    end
  end

  desc "Run all tests in parallel (alias for parallel:spec)"
  task pspec: 'parallel:spec'

rescue LoadError
  desc "Run tests in parallel (requires parallel_tests gem)"
  task :pspec do
    abort "parallel_tests gem not installed. Run: bundle install"
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
    ir = RHDL::Export::Structural::Lower.from_components([component], name: component.name)

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
    require_relative 'lib/rhdl/export'
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
# HDL Export Tasks (Verilog)
# =============================================================================

namespace :hdl do
  VERILOG_DIR = File.expand_path('export/verilog', __dir__)
  EXAMPLES_DIR = File.expand_path('examples', __dir__)

  # Example components with to_verilog methods
  # Format: { 'relative_path' => ['require_path', 'ClassName'] }
  EXAMPLE_COMPONENTS = {
    # MOS6502 synthesizable components
    'mos6502/mos6502_registers' => ['examples/mos6502/hdl/registers/registers', 'MOS6502::Registers'],
    'mos6502/mos6502_stack_pointer' => ['examples/mos6502/hdl/registers/stack_pointer', 'MOS6502::StackPointer'],
    'mos6502/mos6502_program_counter' => ['examples/mos6502/hdl/registers/program_counter', 'MOS6502::ProgramCounter'],
    'mos6502/mos6502_instruction_register' => ['examples/mos6502/hdl/registers/instruction_register', 'MOS6502::InstructionRegister'],
    'mos6502/mos6502_address_latch' => ['examples/mos6502/hdl/registers/address_latch', 'MOS6502::AddressLatch'],
    'mos6502/mos6502_data_latch' => ['examples/mos6502/hdl/registers/data_latch', 'MOS6502::DataLatch'],
    'mos6502/mos6502_status_register' => ['examples/mos6502/hdl/status_register', 'MOS6502::StatusRegister'],
    'mos6502/mos6502_address_generator' => ['examples/mos6502/hdl/address_gen/address_generator', 'MOS6502::AddressGenerator'],
    'mos6502/mos6502_indirect_addr_calc' => ['examples/mos6502/hdl/address_gen/indirect_address_calc', 'MOS6502::IndirectAddressCalc'],
    'mos6502/mos6502_alu' => ['examples/mos6502/hdl/alu', 'MOS6502::ALU'],
    'mos6502/mos6502_instruction_decoder' => ['examples/mos6502/hdl/instruction_decoder', 'MOS6502::InstructionDecoder'],
    'mos6502/mos6502_control_unit' => ['examples/mos6502/hdl/control_unit', 'MOS6502::ControlUnit'],
    'mos6502/mos6502_memory' => ['examples/mos6502/hdl/memory', 'MOS6502::Memory']
  }.freeze

  desc "Export all DSL components to Verilog (lib/ and examples/)"
  task :export => [:export_lib, :export_examples] do
    puts
    puts "=" * 50
    puts "HDL export complete!"
    puts "Verilog files: #{VERILOG_DIR}"
  end

  desc "Export lib/ DSL components to Verilog"
  task :export_lib do
    require_relative 'lib/rhdl'

    puts "RHDL Component Exporter - lib/"
    puts "=" * 50
    puts

    # Ensure output directories exist
    FileUtils.mkdir_p(VERILOG_DIR)

    # Get all exportable components from lib
    components = RHDL::Export.list_components

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
        # Create subdirectories and export to Verilog
        verilog_file = File.join(VERILOG_DIR, "#{relative_path}.v")
        FileUtils.mkdir_p(File.dirname(verilog_file))
        verilog_content = component.to_verilog
        File.write(verilog_file, verilog_content)

        puts "  [OK] #{component.name}"
        puts "       -> #{verilog_file}"
        exported_count += 1
      rescue => e
        puts "  [ERROR] #{component.name}: #{e.message}"
      end
    end

    puts
    puts "Exported #{exported_count}/#{components.size} lib/ components"
  end

  desc "Export examples/ components to Verilog"
  task :export_examples do
    require_relative 'lib/rhdl'

    puts
    puts "RHDL Component Exporter - examples/"
    puts "=" * 50
    puts

    # Ensure output directories exist
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

  desc "Export Verilog files"
  task :verilog do
    require_relative 'lib/rhdl'

    FileUtils.mkdir_p(VERILOG_DIR)

    components = RHDL::Export.list_components
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
  GATES_DIR = File.expand_path('export/gates', __dir__)

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
    'cpu/synth_datapath' => -> { RHDL::HDL::CPU::SynthDatapath.new('synth_cpu') },

    # MOS6502 (Synthesizable 6502)
    'mos6502/registers' => -> { require_relative 'examples/mos6502/hdl/registers'; MOS6502::Registers.new('regs') },
    'mos6502/stack_pointer' => -> { require_relative 'examples/mos6502/hdl/registers'; MOS6502::StackPointer.new('sp') },
    'mos6502/program_counter' => -> { require_relative 'examples/mos6502/hdl/registers'; MOS6502::ProgramCounter.new('pc') },
    'mos6502/instruction_register' => -> { require_relative 'examples/mos6502/hdl/registers'; MOS6502::InstructionRegister.new('ir') },
    'mos6502/address_latch' => -> { require_relative 'examples/mos6502/hdl/registers'; MOS6502::AddressLatch.new('alat') },
    'mos6502/data_latch' => -> { require_relative 'examples/mos6502/hdl/registers'; MOS6502::DataLatch.new('dlat') },
    'mos6502/status_register' => -> { require_relative 'examples/mos6502/hdl/status_register'; MOS6502::StatusRegister.new('sr') },
    'mos6502/address_generator' => -> { require_relative 'examples/mos6502/hdl/address_gen'; MOS6502::AddressGenerator.new('agen') },
    'mos6502/indirect_addr_calc' => -> { require_relative 'examples/mos6502/hdl/address_gen'; MOS6502::IndirectAddressCalc.new('acalc') },
    'mos6502/alu' => -> { require_relative 'examples/mos6502/hdl/alu'; MOS6502::ALU.new('alu') },
    'mos6502/instruction_decoder' => -> { require_relative 'examples/mos6502/hdl/instruction_decoder'; MOS6502::InstructionDecoder.new('dec') },
    'mos6502/control_unit' => -> { require_relative 'examples/mos6502/hdl/control_unit'; MOS6502::ControlUnit.new('ctrl') },
    'mos6502/datapath' => -> { require_relative 'examples/mos6502/hdl/datapath'; MOS6502::Datapath.new('datapath') }
  }.freeze

  desc "Export all components to gate-level IR (JSON netlists)"
  task :export do
    require_relative 'lib/rhdl/hdl'
    require_relative 'lib/rhdl/export'

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
        ir = RHDL::Export::Structural::Lower.from_components([component], name: component.name)

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
    require_relative 'lib/rhdl/export'

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
        ir = RHDL::Export::Structural::Lower.from_components([component], name: component.name)

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
    require_relative 'lib/rhdl/export'

    puts "RHDL Gate-Level Synthesis Statistics"
    puts "=" * 50
    puts

    total_gates = 0
    total_dffs = 0
    component_stats = []

    GATE_SYNTH_COMPONENTS.each do |name, creator|
      begin
        component = creator.call
        ir = RHDL::Export::Structural::Lower.from_components([component], name: component.name)
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

    sim = RHDL::Export.gate_level([not_gate, dff], backend: :cpu, lanes: lanes, name: 'bench_toggle')

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

# =============================================================================
# Apple II ROM Tasks
# =============================================================================

namespace :apple2 do
  ROMS_DIR = File.expand_path('examples/mos6502/software/roms', __dir__)
  ROM_OUTPUT_DIR = File.expand_path('export/roms', __dir__)

  desc "Assemble the mini monitor ROM"
  task :build do
    require_relative 'examples/mos6502/utilities/assembler'

    puts "Apple II ROM Assembler"
    puts "=" * 50
    puts

    FileUtils.mkdir_p(ROM_OUTPUT_DIR)

    # Read assembly source
    asm_file = File.join(ROMS_DIR, 'mini_monitor.asm')
    unless File.exist?(asm_file)
      puts "ERROR: Assembly file not found: #{asm_file}"
      exit 1
    end

    source = File.read(asm_file)
    puts "Source: #{asm_file}"
    puts "Size: #{source.length} bytes"
    puts

    # Assemble
    assembler = MOS6502::Assembler.new
    begin
      bytes = assembler.assemble(source, 0xF800)
      puts "Assembled: #{bytes.length} bytes"

      # The ROM should be 2KB ($F800-$FFFF)
      # Pad to full 2KB if needed
      rom_size = 0x10000 - 0xF800  # 2KB
      if bytes.length < rom_size
        # Pad with $FF (typical for unprogrammed EPROM)
        bytes += [0xFF] * (rom_size - bytes.length)
      end

      # Write binary ROM
      rom_file = File.join(ROM_OUTPUT_DIR, 'mini_monitor.bin')
      File.binwrite(rom_file, bytes.pack('C*'))
      puts "Output: #{rom_file}"
      puts

      # Verify reset vector
      reset_lo = bytes[0xFFFC - 0xF800]
      reset_hi = bytes[0xFFFD - 0xF800]
      reset_vector = (reset_hi << 8) | reset_lo
      puts "Reset vector: $#{reset_vector.to_s(16).upcase.rjust(4, '0')}"

      puts
      puts "ROM built successfully!"
    rescue => e
      puts "ERROR: Assembly failed: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end

  desc "Run the Apple II emulator with the mini monitor"
  task :run => :build do
    rom_file = File.join(ROM_OUTPUT_DIR, 'mini_monitor.bin')
    exec "ruby", "examples/mos6502/bin/apple2", "-r", rom_file, "--rom-address", "F800", "-d"
  end

  desc "Run with AppleIIGo public domain ROM"
  task :run_appleiigo do
    rom_file = File.join(ROMS_DIR, 'appleiigo.rom')
    unless File.exist?(rom_file)
      puts "ERROR: AppleIIGo ROM not found: #{rom_file}"
      puts "Download from: https://a2go.applearchives.com/roms/"
      exit 1
    end
    exec "ruby", "examples/mos6502/bin/apple2", "-r", rom_file, "--rom-address", "D000", "-d"
  end

  desc "Run the Apple II emulator demo (no ROM needed)"
  task :demo do
    exec "ruby", "examples/mos6502/bin/apple2", "--demo", "-d"
  end

  desc "Clean ROM output files"
  task :clean do
    if Dir.exist?(ROM_OUTPUT_DIR)
      FileUtils.rm_rf(ROM_OUTPUT_DIR)
      puts "Cleaned: #{ROM_OUTPUT_DIR}"
    end
  end
end

desc "Build Apple II ROM (alias for apple2:build)"
task apple2: 'apple2:build'

# =============================================================================
# Test Dependencies Tasks
# =============================================================================

namespace :deps do
  desc "Check and install test dependencies (iverilog)"
  task :install do
    puts "RHDL Test Dependencies Installer"
    puts "=" * 50
    puts

    # Detect platform
    platform = case RUBY_PLATFORM
               when /linux/i then :linux
               when /darwin/i then :macos
               when /mswin|mingw|cygwin/i then :windows
               else :unknown
               end

    puts "Platform: #{platform}"
    puts

    # Check for iverilog
    iverilog_available = system('which iverilog > /dev/null 2>&1')

    if iverilog_available
      version = `iverilog -V 2>&1`.lines.first&.strip
      puts "[OK] iverilog is installed: #{version}"
    else
      puts "[MISSING] iverilog is not installed"
      puts

      case platform
      when :linux
        # Detect Linux distribution
        if File.exist?('/etc/debian_version') || system('which apt-get > /dev/null 2>&1')
          puts "Installing iverilog via apt-get..."
          if ENV['USER'] == 'root'
            system('apt-get update && apt-get install -y iverilog')
          else
            system('sudo apt-get update && sudo apt-get install -y iverilog')
          end
        elsif system('which dnf > /dev/null 2>&1')
          puts "Installing iverilog via dnf..."
          system('sudo dnf install -y iverilog')
        elsif system('which yum > /dev/null 2>&1')
          puts "Installing iverilog via yum..."
          system('sudo yum install -y iverilog')
        elsif system('which pacman > /dev/null 2>&1')
          puts "Installing iverilog via pacman..."
          system('sudo pacman -S --noconfirm iverilog')
        else
          puts "Could not detect package manager."
          puts "Please install iverilog manually:"
          puts "  Ubuntu/Debian: sudo apt-get install iverilog"
          puts "  Fedora: sudo dnf install iverilog"
          puts "  Arch: sudo pacman -S iverilog"
        end
      when :macos
        if system('which brew > /dev/null 2>&1')
          puts "Installing iverilog via Homebrew..."
          system('brew install icarus-verilog')
        else
          puts "Homebrew not found. Please install Homebrew first:"
          puts "  /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
          puts "Then run: brew install icarus-verilog"
        end
      when :windows
        puts "On Windows, please install iverilog manually:"
        puts "  1. Download from: http://bleyer.org/icarus/"
        puts "  2. Or use WSL and install via apt-get"
      else
        puts "Unknown platform. Please install iverilog manually."
      end

      # Verify installation
      puts
      if system('which iverilog > /dev/null 2>&1')
        version = `iverilog -V 2>&1`.lines.first&.strip
        puts "[OK] iverilog installed successfully: #{version}"
      else
        puts "[WARN] iverilog installation may have failed. Check above for errors."
      end
    end

    puts
    puts "=" * 50
    puts "Dependency check complete."
  end

  desc "Check test dependencies status"
  task :check do
    puts "RHDL Test Dependencies Status"
    puts "=" * 50
    puts

    deps = {
      'iverilog' => { cmd: 'iverilog -V', optional: true, desc: 'Icarus Verilog (for gate-level simulation tests)' },
      'dot' => { cmd: 'dot -V', optional: true, desc: 'Graphviz (for diagram rendering)' },
      'ruby' => { cmd: 'ruby --version', optional: false, desc: 'Ruby interpreter' },
      'bundler' => { cmd: 'bundle --version', optional: false, desc: 'Ruby Bundler' }
    }

    deps.each do |name, info|
      available = system("which #{name} > /dev/null 2>&1")
      status = available ? "[OK]" : (info[:optional] ? "[OPTIONAL]" : "[MISSING]")
      version = available ? `#{info[:cmd]} 2>&1`.lines.first&.strip : "not installed"

      puts "#{status.ljust(12)} #{name.ljust(12)} - #{info[:desc]}"
      puts "             #{version}" if available
    end

    puts
    puts "Run 'rake deps:install' to install missing dependencies."
  end
end

desc "Install test dependencies (alias for deps:install)"
task deps: 'deps:install'

# =============================================================================
# Test Benchmarking Tasks
# =============================================================================

namespace :benchmark do
  # Helper to find rspec command
  def rspec_cmd
    binstub = File.expand_path('bin/rspec', __dir__)
    File.executable?(binstub) ? binstub : 'rspec'
  end

  desc "Profile RSpec tests and show slowest 20 tests"
  task :tests, [:count] do |_, args|
    count = args[:count] || 20
    puts "Running RSpec with profiling (showing #{count} slowest tests)..."
    puts "=" * 60
    sh "#{rspec_cmd} --profile #{count} --format progress spec/"
  end

  desc "Profile 6502 tests and show slowest tests"
  task :tests_6502, [:count] do |_, args|
    count = args[:count] || 20
    puts "Running 6502 specs with profiling (showing #{count} slowest tests)..."
    puts "=" * 60
    sh "#{rspec_cmd} --profile #{count} --format progress spec/examples/mos6502/"
  end

  desc "Profile HDL tests and show slowest tests"
  task :tests_hdl, [:count] do |_, args|
    count = args[:count] || 20
    puts "Running HDL specs with profiling (showing #{count} slowest tests)..."
    puts "=" * 60
    sh "#{rspec_cmd} --profile #{count} --format progress spec/rhdl/hdl/"
  end

  desc "Run full test timing analysis (detailed per-file timing)"
  task :timing do
    require 'benchmark'

    puts "RHDL Test Suite Timing Analysis"
    puts "=" * 60
    puts

    spec_files = Dir.glob('spec/**/*_spec.rb').sort

    # Group by directory
    groups = spec_files.group_by { |f| File.dirname(f).sub('spec/', '') }

    results = []

    groups.each do |group, files|
      group_time = 0.0
      file_times = []

      files.each do |file|
        print "."
        $stdout.flush

        # Run each file individually and capture timing
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        output = `#{rspec_cmd} #{file} --format progress 2>&1`
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

        # Check for failures
        status = output.include?('0 failures') ? :pass : :fail

        file_times << {
          file: file,
          time: elapsed,
          status: status
        }
        group_time += elapsed
      end

      results << {
        group: group,
        total_time: group_time,
        files: file_times.sort_by { |f| -f[:time] }
      }
    end

    puts
    puts

    # Sort results by total time
    results.sort_by! { |r| -r[:total_time] }

    # Print summary by group
    puts "Test Groups by Total Time"
    puts "-" * 60
    results.each do |r|
      puts "#{r[:group].ljust(40)} #{format('%.2f', r[:total_time])}s (#{r[:files].length} files)"
    end

    puts
    puts "Top 15 Slowest Test Files"
    puts "-" * 60

    all_files = results.flat_map { |r| r[:files] }.sort_by { |f| -f[:time] }
    all_files.first(15).each_with_index do |f, i|
      status_icon = f[:status] == :pass ? '' : ' [FAIL]'
      puts "#{(i + 1).to_s.rjust(2)}. #{format('%.2f', f[:time])}s  #{f[:file]}#{status_icon}"
    end

    total_time = results.sum { |r| r[:total_time] }
    puts
    puts "=" * 60
    puts "Total test time: #{format('%.2f', total_time)}s"
    puts "Total test files: #{all_files.length}"
  end

  desc "Quick benchmark of test categories"
  task :quick do
    require 'benchmark'

    puts "RHDL Test Suite Quick Benchmark"
    puts "=" * 60
    puts

    categories = {
      'HDL Components' => 'spec/rhdl/hdl/',
      '6502 CPU' => 'spec/examples/mos6502/',
      'Core Framework' => 'spec/rhdl/',
      'All Tests' => 'spec/'
    }

    results = []

    categories.each do |name, path|
      next unless Dir.exist?(path)

      files = Dir.glob("#{path}**/*_spec.rb")
      next if files.empty?

      print "Running #{name}..."
      $stdout.flush

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      output = `#{rspec_cmd} #{path} --format progress 2>&1`
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

      # Parse test counts from output
      match = output.match(/(\d+) examples?, (\d+) failures?/)
      examples = match ? match[1].to_i : 0
      failures = match ? match[2].to_i : 0

      results << {
        name: name,
        time: elapsed,
        examples: examples,
        failures: failures,
        files: files.length
      }

      puts " done (#{format('%.2f', elapsed)}s)"
    end

    puts
    puts "Results Summary"
    puts "-" * 60
    puts "#{'Category'.ljust(20)} #{'Time'.rjust(10)} #{'Tests'.rjust(8)} #{'Files'.rjust(8)} #{'Rate'.rjust(12)}"
    puts "-" * 60

    results.each do |r|
      rate = r[:examples] > 0 ? format('%.1f', r[:examples] / r[:time]) : 'N/A'
      puts "#{r[:name].ljust(20)} #{format('%8.2f', r[:time])}s #{r[:examples].to_s.rjust(8)} #{r[:files].to_s.rjust(8)} #{rate.rjust(8)} t/s"
    end
  end
end

desc "Benchmark tests showing 20 slowest (alias for benchmark:tests)"
task benchmark: 'benchmark:tests'
