# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'tmpdir'

RSpec.describe RHDL::CLI::Tasks::DiagramTask do
  let(:temp_dir) { Dir.mktmpdir('rhdl_diagram_test') }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe 'initialization' do
    it 'can be instantiated with no options' do
      expect { described_class.new }.not_to raise_error
    end

    it 'can be instantiated with all option' do
      expect { described_class.new(all: true, mode: 'component') }.not_to raise_error
    end

    it 'can be instantiated with clean option' do
      expect { described_class.new(clean: true) }.not_to raise_error
    end

    it 'can be instantiated with single component option' do
      expect { described_class.new(component: 'gates/not_gate') }.not_to raise_error
    end

    it 'can be instantiated with level option' do
      expect { described_class.new(component: 'gates/not_gate', level: 'component') }.not_to raise_error
      expect { described_class.new(component: 'gates/not_gate', level: 'hierarchy') }.not_to raise_error
      expect { described_class.new(component: 'gates/not_gate', level: 'netlist') }.not_to raise_error
      expect { described_class.new(component: 'gates/not_gate', level: 'gate') }.not_to raise_error
    end

    it 'can be instantiated with depth option' do
      expect { described_class.new(component: 'gates/not_gate', depth: 1) }.not_to raise_error
      expect { described_class.new(component: 'gates/not_gate', depth: :all) }.not_to raise_error
    end

    it 'can be instantiated with bit_blasted option' do
      expect { described_class.new(component: 'gates/not_gate', bit_blasted: true) }.not_to raise_error
    end

    it 'can be instantiated with out option' do
      expect { described_class.new(component: 'gates/not_gate', out: '/path/to/output') }.not_to raise_error
    end

    it 'can be instantiated with format option' do
      expect { described_class.new(component: 'gates/not_gate', format: 'svg') }.not_to raise_error
      expect { described_class.new(component: 'gates/not_gate', format: 'png') }.not_to raise_error
      expect { described_class.new(component: 'gates/not_gate', format: 'dot') }.not_to raise_error
    end

    it 'can be instantiated with mode option for batch generation' do
      expect { described_class.new(all: true, mode: 'component') }.not_to raise_error
      expect { described_class.new(all: true, mode: 'hierarchical') }.not_to raise_error
      expect { described_class.new(all: true, mode: 'gate') }.not_to raise_error
    end
  end

  describe 'options handling' do
    it 'stores all provided options' do
      options = {
        component: 'gates/not_gate',
        level: 'hierarchy',
        depth: 2,
        bit_blasted: true,
        out: '/custom/output',
        format: 'svg'
      }
      task = described_class.new(options)

      expect(task.options[:component]).to eq('gates/not_gate')
      expect(task.options[:level]).to eq('hierarchy')
      expect(task.options[:depth]).to eq(2)
      expect(task.options[:bit_blasted]).to be true
      expect(task.options[:out]).to eq('/custom/output')
      expect(task.options[:format]).to eq('svg')
    end
  end

  describe '#run with clean option' do
    it 'cleans generated diagrams without error' do
      # Create some test files
      test_mode_dir = File.join(temp_dir, 'component')
      FileUtils.mkdir_p(test_mode_dir)
      File.write(File.join(test_mode_dir, 'test.txt'), 'test')

      allow(RHDL::CLI::Config).to receive(:diagrams_dir).and_return(temp_dir)

      task = described_class.new(clean: true)
      expect { task.run }.to output(/Cleaned/).to_stdout

      expect(Dir.exist?(test_mode_dir)).to be false
    end
  end

  describe '#generate_component_diagram' do
    let(:task) { described_class.new }
    let(:component) { RHDL::HDL::NotGate.new('test_not') }

    it 'generates diagram files without error' do
      base_dir = File.join(temp_dir, 'component')

      expect { task.generate_component_diagram('gates/test_not', component, base_dir) }.not_to raise_error

      expect(File.exist?(File.join(base_dir, 'gates/test_not.txt'))).to be true
      expect(File.exist?(File.join(base_dir, 'gates/test_not.svg'))).to be true
      expect(File.exist?(File.join(base_dir, 'gates/test_not.dot'))).to be true
    end
  end

  describe '#generate_hierarchical_diagram' do
    let(:task) { described_class.new }
    let(:component) { RHDL::HDL::Counter.new('test_counter', width: 4) }

    it 'generates hierarchical diagram files without error' do
      base_dir = File.join(temp_dir, 'hierarchical')

      expect { task.generate_hierarchical_diagram('sequential/test_counter', component, base_dir) }.not_to raise_error

      expect(File.exist?(File.join(base_dir, 'sequential/test_counter.txt'))).to be true
    end
  end

  describe '#generate_gate_level_diagram' do
    let(:task) { described_class.new }
    let(:component) { RHDL::HDL::NotGate.new('test_not') }

    it 'generates gate-level diagram files without error' do
      base_dir = File.join(temp_dir, 'gate')

      expect { task.generate_gate_level_diagram('gates/test_not', component, base_dir) }.not_to raise_error

      expect(File.exist?(File.join(base_dir, 'gates/test_not.txt'))).to be true
      expect(File.exist?(File.join(base_dir, 'gates/test_not.dot'))).to be true
    end
  end

  describe '#generate_readme' do
    let(:task) { described_class.new }

    it 'generates README.md without error' do
      allow(RHDL::CLI::Config).to receive(:diagrams_dir).and_return(temp_dir)

      expect { task.send(:generate_readme) }.not_to raise_error

      readme_path = File.join(temp_dir, 'README.md')
      expect(File.exist?(readme_path)).to be true
    end
  end

  describe '#clean' do
    let(:task) { described_class.new(clean: true) }

    it 'removes all diagram mode directories' do
      allow(RHDL::CLI::Config).to receive(:diagrams_dir).and_return(temp_dir)

      # Create test directories
      RHDL::CLI::Config::DIAGRAM_MODES.each do |mode|
        FileUtils.mkdir_p(File.join(temp_dir, mode))
      end

      expect { task.clean }.to output(/Cleaned/).to_stdout

      RHDL::CLI::Config::DIAGRAM_MODES.each do |mode|
        expect(Dir.exist?(File.join(temp_dir, mode))).to be false
      end
    end
  end
end
