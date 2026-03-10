# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../../examples/sparc64/utilities/integration/import_loader'
require_relative '../../../../examples/sparc64/utilities/integration/import_patch_set'

RSpec.describe RHDL::Examples::SPARC64::Integration::ImportLoader do
  before do
    described_class.instance_variable_set(:@loaded_from, nil)
  end

  it 'loads the committed SPARC64 import tree and resolves S1Top' do
    klass = described_class.load_component_class(top: 'S1Top')
    expect(klass.name).to eq('S1Top')
    expect(klass).to respond_to(:verilog_module_name)
    expect(klass.verilog_module_name).to eq('s1_top')
  end

  it 'builds a fast-boot import tree through the importer patch path when requested' do
    fake_result_class = Class.new do
      def initialize(success: true, diagnostics: [])
        @success = success
        @diagnostics = diagnostics
      end

      def success?
        @success
      end

      attr_reader :diagnostics
    end

    fake_importer_class = Class.new do
      class << self
        attr_reader :last_kwargs
      end

      define_method(:initialize) do |**kwargs|
        self.class.instance_variable_set(:@last_kwargs, kwargs)
      end

      define_method(:run) do
        output_dir = self.class.last_kwargs.fetch(:output_dir)
        FileUtils.mkdir_p(output_dir)
        File.write(
          File.join(output_dir, 's1_top.rb'),
          <<~RUBY
            class S1Top
              def self.verilog_module_name
                's1_top'
              end
            end
          RUBY
        )
        fake_result_class.new(success: true)
      end
    end

    build_root = Dir.mktmpdir('sparc64_import_loader_build')

    begin
      built_dir = described_class.build_import_dir(
        build_cache_root: build_root,
        reference_root: RHDL::Examples::SPARC64::Integration::ImportLoader::DEFAULT_REFERENCE_ROOT,
        import_top: 's1_top',
        fast_boot: true,
        importer_class: fake_importer_class
      )

      expect(File).to exist(File.join(built_dir, 's1_top.rb'))
      expect(fake_importer_class.last_kwargs.fetch(:patches_dir)).to eq(
        RHDL::Examples::SPARC64::Integration::ImportPatchSet::FAST_BOOT_PATCH_DIR
      )
      expect(fake_importer_class.last_kwargs.fetch(:emit_runtime_json)).to eq(false)
    ensure
      FileUtils.rm_rf(build_root)
    end
  end
end
