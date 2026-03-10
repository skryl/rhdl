# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../../examples/sparc64/utilities/integration/image_builder'
require_relative '../../../../examples/sparc64/utilities/integration/programs'
require_relative '../../../../examples/sparc64/utilities/integration/toolchain'

RSpec.describe RHDL::Examples::SPARC64::Integration::ProgramImageBuilder do
  let(:cache_root) { Dir.mktmpdir('sparc64_program_image_builder_spec') }
  let(:builder) { described_class.new(cache_root: cache_root) }

  after do
    FileUtils.rm_rf(cache_root)
  end

  it 'defines all named benchmark programs' do
    programs = RHDL::Examples::SPARC64::Integration::Programs.all
    expect(programs.map(&:name)).to eq(%i[prime_sieve mandelbrot game_of_life])
    expect(programs.map(&:expected_value)).to eq([0xA0, 0xFFF0, 0x2])
  end

  it 'raises on unknown benchmark names' do
    expect do
      RHDL::Examples::SPARC64::Integration::Programs.fetch(:missing)
    end.to raise_error(KeyError, /Unknown SPARC64 integration program/)
  end

  it 'builds separate boot and DRAM images for each benchmark' do
    skip 'llvm-mc not available' unless RHDL::Examples::SPARC64::Integration::Toolchain.which('llvm-mc')
    skip 'ld.lld not available' unless RHDL::Examples::SPARC64::Integration::Toolchain.which('ld.lld')
    skip 'llvm-objcopy not available' unless RHDL::Examples::SPARC64::Integration::Toolchain.which('llvm-objcopy')

    RHDL::Examples::SPARC64::Integration::Programs.all.each do |program|
      result = builder.build(program)

      expect(result.boot_bytes.bytesize).to be > 0
      expect(result.program_bytes.bytesize).to be > 0
      expect(File).to exist(result.boot_bin_path)
      expect(File).to exist(result.program_bin_path)
      expect(File.read(result.boot_source_path)).to include('PROGRAM_BASE')
      expect(File.read(result.boot_source_path)).to include('jmpl %g1, %g0')
      expect(File.read(result.boot_source_path)).not_to include('ba PROGRAM_BASE')
      expect(result.boot_bytes.bytesize).to be >= 16
      expect(File.read(result.program_source_path)).to include('MAILBOX_STATUS')
    end
  end

  it 'reuses cached build artifacts when source digests match' do
    skip 'llvm-mc not available' unless RHDL::Examples::SPARC64::Integration::Toolchain.which('llvm-mc')
    skip 'ld.lld not available' unless RHDL::Examples::SPARC64::Integration::Toolchain.which('ld.lld')
    skip 'llvm-objcopy not available' unless RHDL::Examples::SPARC64::Integration::Toolchain.which('llvm-objcopy')

    program = RHDL::Examples::SPARC64::Integration::Programs.fetch(:prime_sieve)
    first = builder.build(program)
    second = builder.build(program)

    expect(second.build_dir).to eq(first.build_dir)
    expect(second.boot_bytes).to eq(first.boot_bytes)
    expect(second.program_bytes).to eq(first.program_bytes)
  end
end
