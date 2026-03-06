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
end
