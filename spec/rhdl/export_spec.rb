require 'spec_helper'
require 'tmpdir'

RSpec.describe RHDL::Export do
  # Define test components for export testing
  before(:all) do
    Object.send(:remove_const, :ExportTestAdder) if defined?(ExportTestAdder)
    Object.send(:remove_const, :ExportTestCounter) if defined?(ExportTestCounter)

    class ExportTestAdder
      include RHDL::DSL

      generic :width, type: :integer, default: 8

      input :a, width: 8
      input :b, width: 8
      output :sum, width: 8
      output :carry, width: 1

      signal :internal_sum, width: 9
    end

    class ExportTestCounter
      include RHDL::DSL

      input :clk, width: 1
      input :rst, width: 1
      input :enable, width: 1
      output :count, width: 8

      signal :counter_reg, width: 8, default: 0
    end
  end

  describe '.discover_components' do
    it 'finds classes that include RHDL::DSL' do
      components = RHDL::Export.discover_components
      expect(components).to include(ExportTestAdder)
      expect(components).to include(ExportTestCounter)
    end

    it 'excludes RHDL::Component base class' do
      components = RHDL::Export.discover_components
      expect(components).not_to include(RHDL::Component)
    end
  end

  describe '.to_verilog' do
    it 'exports a single component to Verilog' do
      verilog = RHDL::Export.to_verilog(ExportTestAdder)
      expect(verilog).to include('module export_test_adder')
      expect(verilog).to include('endmodule')
    end
  end

  describe '.all_to_verilog' do
    it 'exports all discovered components to Verilog' do
      results = RHDL::Export.all_to_verilog
      expect(results).to be_a(Hash)
      expect(results[ExportTestAdder]).to include('module export_test_adder')
      expect(results[ExportTestCounter]).to include('module export_test_counter')
    end
  end

  describe '.export_verilog' do
    it 'exports specific components to Verilog' do
      results = RHDL::Export.export_verilog([ExportTestCounter])
      expect(results.keys).to eq([ExportTestCounter])
      expect(results[ExportTestCounter]).to include('module export_test_counter')
    end
  end

  describe '.export_to_files' do
    it 'exports specific components to Verilog files' do
      Dir.mktmpdir do |dir|
        results = RHDL::Export.export_to_files([ExportTestCounter], dir)

        expect(results[:verilog][ExportTestCounter]).to end_with('export_test_counter.v')
        expect(File.exist?(File.join(dir, 'export_test_counter.v'))).to be true

        content = File.read(File.join(dir, 'export_test_counter.v'))
        expect(content).to include('module export_test_counter')
      end
    end
  end

  describe '.export_all_to_files' do
    it 'exports all discovered components to files' do
      Dir.mktmpdir do |dir|
        results = RHDL::Export.export_all_to_files(dir)

        # Check that files were created for discovered components
        expect(results[:verilog]).not_to be_empty

        # Check that export_test_adder files exist
        expect(File.exist?(File.join(dir, 'export_test_adder.v'))).to be true
      end
    end

    it 'creates the output directory if it does not exist' do
      Dir.mktmpdir do |base_dir|
        new_dir = File.join(base_dir, 'nested', 'output')
        expect(File.exist?(new_dir)).to be false

        RHDL::Export.export_all_to_files(new_dir)

        expect(File.exist?(new_dir)).to be true
      end
    end
  end

  describe '.list_components' do
    it 'lists all exportable components with their info' do
      list = RHDL::Export.list_components

      adder_info = list.find { |c| c[:class] == ExportTestAdder }
      expect(adder_info).not_to be_nil
      expect(adder_info[:name]).to eq('export_test_adder')
      expect(adder_info[:ports]).to eq(4)
      expect(adder_info[:signals]).to eq(1)
      expect(adder_info[:generics]).to eq(1)

      counter_info = list.find { |c| c[:class] == ExportTestCounter }
      expect(counter_info).not_to be_nil
      expect(counter_info[:name]).to eq('export_test_counter')
      expect(counter_info[:ports]).to eq(4)
      expect(counter_info[:generics]).to eq(0)
    end
  end

  describe 'Verilog output' do
    it 'generates correct port names' do
      verilog = RHDL::Export.to_verilog(ExportTestAdder)

      expect(verilog).to include('a')
      expect(verilog).to include('b')
      expect(verilog).to include('sum')
    end

    it 'generates correct signal names' do
      verilog = RHDL::Export.to_verilog(ExportTestAdder)

      expect(verilog).to include('internal_sum')
    end
  end
end
