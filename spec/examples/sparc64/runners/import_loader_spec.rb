# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../../examples/sparc64/utilities/integration/import_loader'
require_relative '../../../../examples/sparc64/utilities/integration/import_patch_set'

RSpec.describe RHDL::Examples::SPARC64::Integration::ImportLoader do
  before do
    described_class.instance_variable_set(:@loaded_from, nil)
  end

  it 'loads the committed SPARC64 import tree and resolves S1Top' do
    skip 'SPARC64 committed import tree not available' unless Dir.exist?(described_class::DEFAULT_IMPORT_DIR)

    klass = described_class.load_component_class(top: 'S1Top')
    expect(klass.name).to eq('S1Top')
    expect(klass).to respond_to(:verilog_module_name)
    expect(klass.verilog_module_name).to eq('s1_top')
  end

  it 'builds a patched import tree through the importer patch path when requested' do
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
        RHDL::Examples::SPARC64::Integration::ImportPatchSet::MINIMAL_PATCH_DIR
      )
      expect(fake_importer_class.last_kwargs.fetch(:emit_runtime_json)).to eq(true)
    ensure
      FileUtils.rm_rf(build_root)
    end
  end

  it 'invalidates the patched build digest when the shared import pipeline changes' do
    shared_import_path = File.expand_path('../../../../lib/rhdl/codegen/circt/import.rb', __dir__)
    digests = Hash.new('same-digest')
    allow(Digest::SHA256).to receive(:file) do |path|
      instance_double('DigestFile', hexdigest: digests[path])
    end

    digest_before = described_class.send(
      :build_digest,
      reference_root: described_class::DEFAULT_REFERENCE_ROOT,
      import_top: 's1_top',
      import_top_file: described_class::DEFAULT_IMPORT_TOP_FILE,
      patches_dir: RHDL::Examples::SPARC64::Integration::ImportPatchSet::MINIMAL_PATCH_DIR,
      patch_files: []
    )

    digests[shared_import_path] = 'changed-shared-import'

    digest_after = described_class.send(
      :build_digest,
      reference_root: described_class::DEFAULT_REFERENCE_ROOT,
      import_top: 's1_top',
      import_top_file: described_class::DEFAULT_IMPORT_TOP_FILE,
      patches_dir: RHDL::Examples::SPARC64::Integration::ImportPatchSet::MINIMAL_PATCH_DIR,
      patch_files: []
    )

    expect(digest_after).not_to eq(digest_before)
  end

  it 'removes partially loaded generated classes before retrying dependent files' do
    import_root = Dir.mktmpdir('sparc64_import_loader_retry')

    begin
      File.write(
        File.join(import_root, 'a_retry_early_child.rb'),
        <<~RUBY
          class RetryEarlyChild < RHDL::Sim::Component
            input :a
            output :y

            behavior do
              y <= a
            end
          end
        RUBY
      )
      File.write(
        File.join(import_root, 'b_retry_top.rb'),
        <<~RUBY
          class RetryTop < RHDL::Sim::Component
            input :a
            output :y
            wire :early_y
            wire :late_y

            instance :early, RetryEarlyChild
            instance :late, RetryLateChild

            port :a => [:early, :a]
            port :a => [:late, :a]
            port [:early, :y] => :early_y
            port [:late, :y] => :late_y

            behavior do
              y <= early_y | late_y
            end
          end
        RUBY
      )
      File.write(
        File.join(import_root, 'c_retry_late_child.rb'),
        <<~RUBY
          class RetryLateChild < RHDL::Sim::Component
            input :a
            output :y

            behavior do
              y <= a
            end
          end
        RUBY
      )

      described_class.load_tree!(import_dir: import_root)

      aggregate_failures do
        expect(RetryTop._instance_defs.count { |entry| entry[:name] == :early }).to eq(1)
        expect(RetryTop._instance_defs.count { |entry| entry[:name] == :late }).to eq(1)
        expect(RetryTop._connection_defs.count { |entry| entry[:dest] == [:early, :a] }).to eq(1)
        expect(RetryTop._connection_defs.count { |entry| entry[:dest] == [:late, :a] }).to eq(1)
      end
    ensure
      described_class.instance_variable_set(:@loaded_from, nil)
      %i[RetryTop RetryEarlyChild RetryLateChild].each do |const_name|
        Object.send(:remove_const, const_name) if Object.const_defined?(const_name, false)
      end
      FileUtils.rm_rf(import_root)
    end
  end
end
