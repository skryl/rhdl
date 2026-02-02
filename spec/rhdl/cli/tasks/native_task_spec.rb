# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'

RSpec.describe RHDL::CLI::Tasks::NativeTask do
  describe 'constants' do
    it 'defines EXTENSIONS' do
      expect(described_class::EXTENSIONS).to be_a(Hash)
      expect(described_class::EXTENSIONS.keys).to include(
        :isa_simulator,
        :netlist_interpreter,
        :netlist_jit,
        :netlist_compiler,
        :ir_interpreter,
        :ir_jit,
        :ir_compiler
      )
    end
  end

  describe 'initialization' do
    it 'can be instantiated with no options' do
      expect { described_class.new }.not_to raise_error
    end

    it 'can be instantiated with build option' do
      expect { described_class.new(build: true) }.not_to raise_error
    end

    it 'can be instantiated with clean option' do
      expect { described_class.new(clean: true) }.not_to raise_error
    end

    it 'can be instantiated with check option' do
      expect { described_class.new(check: true) }.not_to raise_error
    end
  end

  describe '#run' do
    context 'with check option' do
      it 'displays native simulator status' do
        task = described_class.new(check: true)

        expect { task.run }.to output(/ISA Simulator/).to_stdout
      end
    end

    context 'with clean option' do
      it 'can be called' do
        task = described_class.new(clean: true)

        # Mock FileUtils to avoid actually cleaning built extensions
        allow(FileUtils).to receive(:rm_rf)

        # Clean should not raise even if directories don't exist
        expect { task.run }.to output(/cleaned/).to_stdout
      end
    end
  end

  describe '#check' do
    let(:task) { described_class.new(check: true) }

    it 'displays native simulator status' do
      expect { task.check }.to output(/ISA Simulator/).to_stdout
    end

    it 'returns true or false' do
      result = nil
      capture_stdout { result = task.check }
      expect([true, false]).to include(result)
    end
  end

  describe '#clean' do
    let(:task) { described_class.new(clean: true) }

    it 'displays cleaned message' do
      # Mock FileUtils to avoid actually cleaning built extensions
      allow(FileUtils).to receive(:rm_rf)

      expect { task.clean }.to output(/cleaned/).to_stdout
    end
  end

  describe '#available?' do
    let(:task) { described_class.new }

    it 'returns a boolean' do
      result = task.available?
      expect([true, false]).to include(result)
    end
  end

  describe 'private methods' do
    let(:task) { described_class.new }
    let(:ext) { described_class::EXTENSIONS[:isa_simulator] }

    describe '#host_os' do
      it 'returns a string' do
        result = task.send(:host_os)
        expect(result).to be_a(String)
      end
    end

    describe '#src_lib_name' do
      it 'returns library name based on platform' do
        result = task.send(:src_lib_name, ext)
        expect(result).to match(/libisa_simulator_native\.(so|dylib)|isa_simulator_native\.dll/)
      end
    end

    describe '#dst_lib_name' do
      it 'returns target library name based on platform' do
        result = task.send(:dst_lib_name, ext)
        expect(result).to match(/isa_simulator_native\.(so|bundle|dll)/)
      end
    end

    describe '#src_lib_path' do
      it 'returns path under target/release' do
        result = task.send(:src_lib_path, ext)
        expect(result).to include('target')
        expect(result).to include('release')
      end
    end

    describe '#dst_lib_path' do
      it 'returns path under lib directory' do
        result = task.send(:dst_lib_path, ext)
        expect(result).to include('lib')
      end
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
