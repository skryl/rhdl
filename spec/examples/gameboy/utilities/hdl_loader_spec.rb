# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/gameboy/utilities/hdl_loader'

RSpec.describe RHDL::Examples::GameBoy::HdlLoader do
  around do |example|
    previous_env = ENV[described_class::HDL_DIR_ENV]
    previous_loaded_from = described_class.loaded_from
    described_class.instance_variable_set(:@loaded_from, nil)
    ENV.delete(described_class::HDL_DIR_ENV)
    example.run
  ensure
    described_class.instance_variable_set(:@loaded_from, previous_loaded_from)
    if previous_env.nil?
      ENV.delete(described_class::HDL_DIR_ENV)
    else
      ENV[described_class::HDL_DIR_ENV] = previous_env
    end
  end

  it 'resolves to the default HDL directory when not overridden' do
    expect(described_class.resolve_hdl_dir).to eq(described_class::DEFAULT_HDL_DIR)
  end

  it 'loads custom HDL directories with dependency retries' do
    Dir.mktmpdir('rhdl_gameboy_hdl_loader') do |dir|
      file_a = File.join(dir, 'a.rb')
      file_b = File.join(dir, 'b.rb')

      File.write(file_a, "class RhdlLoaderSpecA\n  DEP = RhdlLoaderSpecB\nend\n")
      File.write(file_b, "class RhdlLoaderSpecB\nend\n")

      expect { described_class.load_component_tree!(hdl_dir: dir) }.not_to raise_error
      expect(described_class.loaded_from).to eq(File.expand_path(dir))
      expect(defined?(RhdlLoaderSpecA)).to eq('constant')
      expect(defined?(RhdlLoaderSpecB)).to eq('constant')
    end
  ensure
    Object.send(:remove_const, :RhdlLoaderSpecA) if Object.const_defined?(:RhdlLoaderSpecA)
    Object.send(:remove_const, :RhdlLoaderSpecB) if Object.const_defined?(:RhdlLoaderSpecB)
  end

  it 'loads imported-style component trees without pulling handwritten support code' do
    Dir.mktmpdir('rhdl_gameboy_import_loader') do |dir|
      gb_file = File.join(dir, 'gb.rb')
      wrapper_file = File.join(dir, 'gameboy.rb')

      File.write(gb_file, <<~RUBY)
        class Gb < RHDL::Sim::SequentialComponent
          include RHDL::DSL::Behavior
          include RHDL::DSL::Sequential

          def self.verilog_module_name
            'gb'
          end
        end
      RUBY

      File.write(wrapper_file, <<~RUBY)
        class Gameboy < RHDL::Sim::SequentialComponent
          DEP = Gb

          def self.verilog_module_name
            'gameboy'
          end
        end
      RUBY

      expect { described_class.load_component_tree!(hdl_dir: dir) }.not_to raise_error
      expect(defined?(Gb)).to eq('constant')
      expect(defined?(Gameboy)).to eq('constant')
      expect(Gameboy::DEP).to eq(Gb)
    end
  ensure
    Object.send(:remove_const, :Gb) if Object.const_defined?(:Gb)
    Object.send(:remove_const, :GB) if Object.const_defined?(:GB)
    Object.send(:remove_const, :Gameboy) if Object.const_defined?(:Gameboy)
  end
end
