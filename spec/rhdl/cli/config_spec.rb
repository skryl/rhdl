# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'

RSpec.describe RHDL::CLI::Config do
  describe '.project_root' do
    it 'returns the project root directory' do
      expect(described_class.project_root).to eq(File.expand_path('../../..', __dir__))
    end

    it 'returns an existing directory' do
      expect(Dir.exist?(described_class.project_root)).to be true
    end
  end

  describe '.diagrams_dir' do
    it 'returns the diagrams directory path' do
      expect(described_class.diagrams_dir).to eq(File.join(described_class.project_root, 'diagrams'))
    end
  end

  describe '.verilog_dir' do
    it 'returns the verilog export directory path' do
      expect(described_class.verilog_dir).to eq(File.join(described_class.project_root, 'export/verilog'))
    end
  end

  describe '.gates_dir' do
    it 'returns the gates export directory path' do
      expect(described_class.gates_dir).to eq(File.join(described_class.project_root, 'export/gates'))
    end
  end

  describe '.rom_output_dir' do
    it 'returns the ROM output directory path' do
      expect(described_class.rom_output_dir).to eq(File.join(described_class.project_root, 'export/roms'))
    end
  end

  describe '.roms_dir' do
    it 'returns the ROMs source directory path' do
      expect(described_class.roms_dir).to eq(File.join(described_class.project_root, 'examples/mos6502/software/roms'))
    end
  end

  describe '.examples_dir' do
    it 'returns the examples directory path' do
      expect(described_class.examples_dir).to eq(File.join(described_class.project_root, 'examples'))
    end
  end

  describe '.apple2_dir' do
    it 'returns the Apple II directory path' do
      expect(described_class.apple2_dir).to eq(File.join(described_class.project_root, 'examples/mos6502'))
    end
  end

  describe '.tui_ink_dir' do
    it 'returns the TUI Ink directory path' do
      expect(described_class.tui_ink_dir).to eq(File.join(described_class.project_root, 'tui-ink'))
    end
  end

  describe 'DIAGRAM_MODES' do
    it 'contains expected diagram modes' do
      expect(described_class::DIAGRAM_MODES).to eq(%w[component hierarchical gate])
    end

    it 'is frozen' do
      expect(described_class::DIAGRAM_MODES).to be_frozen
    end
  end

  describe 'CATEGORIES' do
    it 'contains expected categories' do
      expect(described_class::CATEGORIES).to eq(%w[gates sequential arithmetic combinational memory cpu])
    end

    it 'is frozen' do
      expect(described_class::CATEGORIES).to be_frozen
    end
  end

  describe '.hdl_components' do
    it 'returns a hash of component creators' do
      expect(described_class.hdl_components).to be_a(Hash)
    end

    it 'contains gate components' do
      expect(described_class.hdl_components.keys).to include('gates/not_gate')
      expect(described_class.hdl_components.keys).to include('gates/and_gate')
    end

    it 'contains sequential components' do
      expect(described_class.hdl_components.keys).to include('sequential/d_flipflop')
      expect(described_class.hdl_components.keys).to include('sequential/counter')
    end

    it 'contains arithmetic components' do
      expect(described_class.hdl_components.keys).to include('arithmetic/alu_8bit')
      expect(described_class.hdl_components.keys).to include('arithmetic/full_adder')
    end

    it 'contains combinational components' do
      expect(described_class.hdl_components.keys).to include('combinational/mux2')
      expect(described_class.hdl_components.keys).to include('combinational/decoder_2to4')
    end

    it 'contains memory components' do
      expect(described_class.hdl_components.keys).to include('memory/ram')
      expect(described_class.hdl_components.keys).to include('memory/rom')
    end

    it 'contains CPU components' do
      expect(described_class.hdl_components.keys).to include('cpu/instruction_decoder')
      expect(described_class.hdl_components.keys).to include('cpu/cpu')
    end

    it 'creates valid components from lambdas' do
      creator = described_class.hdl_components['gates/not_gate']
      component = creator.call
      expect(component).to be_a(RHDL::HDL::NotGate)
      expect(component.name).to eq('not_gate')
    end
  end

  describe 'GATE_LEVEL_COMPONENTS' do
    it 'contains components that support gate-level lowering' do
      expect(described_class::GATE_LEVEL_COMPONENTS).to include('gates/not_gate')
      expect(described_class::GATE_LEVEL_COMPONENTS).to include('arithmetic/full_adder')
    end

    it 'is frozen' do
      expect(described_class::GATE_LEVEL_COMPONENTS).to be_frozen
    end
  end

  describe '.gate_synth_components' do
    it 'returns a hash of components for gate-level synthesis' do
      expect(described_class.gate_synth_components).to be_a(Hash)
    end

    it 'contains synthesizable components' do
      expect(described_class.gate_synth_components.keys).to include('gates/not_gate')
      expect(described_class.gate_synth_components.keys).to include('arithmetic/alu')
      expect(described_class.gate_synth_components.keys).to include('cpu/instruction_decoder')
    end

    it 'creates valid components from lambdas' do
      creator = described_class.gate_synth_components['sequential/register']
      component = creator.call
      expect(component).to be_a(RHDL::HDL::Register)
    end
  end

  describe 'EXAMPLE_COMPONENTS' do
    it 'contains MOS 6502 example components' do
      expect(described_class::EXAMPLE_COMPONENTS.keys).to include('mos6502/mos6502_alu')
      expect(described_class::EXAMPLE_COMPONENTS.keys).to include('mos6502/mos6502_control_unit')
    end

    it 'has require path and class name for each component' do
      described_class::EXAMPLE_COMPONENTS.each do |_key, (require_path, class_name)|
        expect(require_path).to be_a(String)
        expect(class_name).to be_a(String)
        expect(class_name).to include('MOS6502::')
      end
    end

    it 'is frozen' do
      expect(described_class::EXAMPLE_COMPONENTS).to be_frozen
    end
  end

  describe '.create_component' do
    it 'creates a component by name from hdl_components' do
      component = described_class.create_component('gates/not_gate')
      expect(component).to be_a(RHDL::HDL::NotGate)
    end

    it 'creates a component by name from gate_synth_components' do
      component = described_class.create_component('arithmetic/alu')
      expect(component).to be_a(RHDL::HDL::ALU)
    end

    it 'raises ArgumentError for unknown component' do
      expect { described_class.create_component('unknown/component') }.to raise_error(ArgumentError, /Unknown component/)
    end
  end
end
