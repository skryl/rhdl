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
rescue LoadError
  desc "Run RSpec tests (rspec not available via bundler, use bin/test)"
  task :spec do
    sh "bin/test"
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

desc "Run 6502 CPU tests"
task :spec_6502 do
  sh "bin/test spec/examples/mos6502/ --format progress"
end

desc "Run all tests with documentation format"
task :spec_doc do
  sh "bin/test --format documentation"
end

# =============================================================================
# Diagram Generation Tasks
# =============================================================================

namespace :diagrams do
  DIAGRAMS_DIR = File.expand_path('diagrams', __dir__)

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

  def generate_diagram(name, component, diagrams_dir)
    # Create subdirectory if needed
    subdir = File.dirname(name)
    full_subdir = File.join(diagrams_dir, subdir)
    FileUtils.mkdir_p(full_subdir)

    base_path = File.join(diagrams_dir, name)

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

  def generate_diagrams_index(diagrams_dir)
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

      path = File.join(diagrams_dir, dir)
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
    readme << "rake diagrams:generate"
    readme << "```"
    readme << ""
    readme << "---"
    readme << "*Generated by RHDL Circuit Diagram Generator*"

    File.write(File.join(diagrams_dir, 'README.md'), readme.join("\n"))
  end

  desc "Generate circuit diagrams for all HDL components"
  task :generate do
    require_relative 'lib/rhdl/hdl'

    puts "=" * 60
    puts "RHDL Circuit Diagram Generator"
    puts "=" * 60
    puts ""
    puts "Output directory: #{DIAGRAMS_DIR}"
    puts ""

    # Create category subdirectories
    %w[gates sequential arithmetic combinational memory cpu].each do |category|
      FileUtils.mkdir_p(File.join(DIAGRAMS_DIR, category))
    end

    success_count = 0
    error_count = 0

    HDL_COMPONENTS.each do |name, creator|
      begin
        component = creator.call
        generate_diagram(name, component, DIAGRAMS_DIR)
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
    generate_diagrams_index(DIAGRAMS_DIR)

    puts ""
    puts "Index file generated: #{File.join(DIAGRAMS_DIR, 'README.md')}"
  end

  desc "Clean all generated diagrams"
  task :clean do
    %w[gates sequential arithmetic combinational memory cpu].each do |category|
      dir = File.join(DIAGRAMS_DIR, category)
      if Dir.exist?(dir)
        FileUtils.rm_rf(Dir.glob(File.join(dir, '*')))
        puts "Cleaned: #{dir}"
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

  desc "Export all DSL components to VHDL and Verilog"
  task :export do
    require_relative 'lib/rhdl'

    puts "RHDL Component Exporter"
    puts "=" * 50
    puts

    # Ensure output directories exist
    FileUtils.mkdir_p(VHDL_DIR)
    FileUtils.mkdir_p(VERILOG_DIR)

    # Get all exportable components
    components = RHDL::Exporter.list_components

    if components.empty?
      puts "No exportable components found."
      exit 0
    end

    puts "Found #{components.size} exportable component(s):"
    puts

    # Export each component
    exported_count = 0
    components.each do |info|
      component = info[:class]
      name = info[:name]

      begin
        # Export to VHDL
        vhdl_file = File.join(VHDL_DIR, "#{name}.vhd")
        vhdl_content = component.to_vhdl
        File.write(vhdl_file, vhdl_content)

        # Export to Verilog
        verilog_file = File.join(VERILOG_DIR, "#{name}.v")
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
    puts "=" * 50
    puts "Exported #{exported_count}/#{components.size} components"
    puts "VHDL files:    #{VHDL_DIR}"
    puts "Verilog files: #{VERILOG_DIR}"
  end

  desc "Export only VHDL files"
  task :vhdl do
    require_relative 'lib/rhdl'

    FileUtils.mkdir_p(VHDL_DIR)

    components = RHDL::Exporter.list_components
    puts "Exporting #{components.size} components to VHDL..."

    components.each do |info|
      component = info[:class]
      name = info[:name]
      begin
        vhdl_file = File.join(VHDL_DIR, "#{name}.vhd")
        File.write(vhdl_file, component.to_vhdl)
        puts "  [OK] #{name}.vhd"
      rescue => e
        puts "  [ERROR] #{name}: #{e.message}"
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
      name = info[:name]
      begin
        verilog_file = File.join(VERILOG_DIR, "#{name}.v")
        File.write(verilog_file, component.to_verilog)
        puts "  [OK] #{name}.v"
      rescue => e
        puts "  [ERROR] #{name}: #{e.message}"
      end
    end
  end

  desc "Clean all generated HDL files"
  task :clean do
    # Clean VHDL files (keep .gitkeep)
    Dir.glob(File.join(VHDL_DIR, '*.vhd')).each do |f|
      FileUtils.rm_f(f)
    end
    puts "Cleaned: #{VHDL_DIR}"

    # Clean Verilog files (keep .gitkeep)
    Dir.glob(File.join(VERILOG_DIR, '*.v')).each do |f|
      FileUtils.rm_f(f)
    end
    puts "Cleaned: #{VERILOG_DIR}"

    puts "HDL files cleaned."
  end
end

desc "Export all HDL (alias for hdl:export)"
task hdl: 'hdl:export'

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
