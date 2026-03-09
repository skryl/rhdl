# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Sparc64UnitSupport::RuntimeImportSession do
  include Sparc64UnitSupport::RuntimeImportRequirements

  describe '.current' do
    it 'imports W1 once per process and reuses the prepared session', timeout: 480 do
      require_reference_tree!
      require_import_tool!

      first = described_class.current
      second = described_class.current

      aggregate_failures do
        expect(first).to equal(second)
        expect(first.import_run_count).to eq(1)
        expect(first).to be_prepared
        expect(File.directory?(first.output_dir)).to be(true)
        expect(File.directory?(first.workspace_dir)).to be(true)
        expect(File.file?(first.report_path)).to be(true)
      end
    end
  end

  describe '#cleanup!' do
    it 'removes the temp workspace and output tree for ad hoc sessions', timeout: 480 do
      require_reference_tree!
      require_import_tool!

      temp_root = Dir.mktmpdir('sparc64_unit_runtime_cleanup')
      session = described_class.new(temp_root: temp_root)
      session.prepare!
      temp_root = session.temp_root
      expect(Dir.exist?(temp_root)).to be(true)

      session.cleanup!

      aggregate_failures do
        expect(Dir.exist?(temp_root)).to be(false)
        expect(session.cleanup_complete?).to be(true)
      end
    end
  end
end
