# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../../examples/sparc64/utilities/integration/image_builder'
require_relative '../../../../examples/sparc64/utilities/integration/programs'
require_relative '../../../../examples/sparc64/utilities/integration/toolchain'
require_relative '../../../../examples/sparc64/utilities/runners/verilator_runner'

RSpec.describe RHDL::Examples::SPARC64::VerilogRunner, :slow, timeout: 1800 do
  let(:image_cache_root) { Dir.mktmpdir('sparc64_verilator_smoke_images') }
  let(:bundle_cache_root) { Dir.mktmpdir('sparc64_verilator_smoke_bundle') }

  after do
    FileUtils.rm_rf(image_cache_root)
    FileUtils.rm_rf(bundle_cache_root)
  end

  it 'builds the concrete Verilator harness, hands off to DRAM, and reaches mailbox completion' do
    %w[verilator llvm-mc ld.lld llvm-objcopy].each do |tool|
      skip "#{tool} not available" unless RHDL::Examples::SPARC64::Integration::Toolchain.which(tool)
    end

    program = RHDL::Examples::SPARC64::Integration::Programs::Program.new(
      name: :verilator_smoke,
      description: 'Minimal mailbox smoke program for the Verilator runner.',
      expected_value: 0x55AA,
      max_cycles: 1_000,
      min_transactions: 1,
      program_source: <<~ASM
        .section .text
        .global _start
      _start:
        sethi %hi(MAILBOX_STATUS), %g1
        or %g1, %lo(MAILBOX_STATUS), %g1
        mov 1, %g2
        stx %g2, [%g1]
        sethi %hi(MAILBOX_VALUE), %g1
        or %g1, %lo(MAILBOX_VALUE), %g1
        sethi %hi(0x55AA), %g2
        or %g2, %lo(0x55AA), %g2
        stx %g2, [%g1]
      spin:
        ba,a spin
        nop
      ASM
    )

    images = RHDL::Examples::SPARC64::Integration::ProgramImageBuilder.new(
      cache_root: image_cache_root
    ).build(program)

    runner = described_class.new(
      adapter_factory: lambda {
        described_class::DefaultAdapter.new(
          source_bundle_options: { cache_root: bundle_cache_root },
          fast_boot: true
        )
      }
    )

    runner.load_images(
      boot_image: images.boot_bytes,
      program_image: images.program_bytes
    )

    expect(runner.read_memory(0, images.boot_bytes.bytesize)).to eq(images.boot_bytes.bytes)
    expect(
      runner.read_memory(
        RHDL::Examples::SPARC64::Integration::FLASH_BOOT_BASE,
        images.boot_bytes.bytesize
      )
    ).to eq(images.boot_bytes.bytes)

    result = runner.run_until_complete(max_cycles: 1_000, batch_cycles: 250)
    boot_words = images.boot_bytes.bytes.each_slice(8).first(2).map do |slice|
      slice.reduce(0) { |acc, byte| (acc << 8) | (byte & 0xFF) }
    end

    expect(result[:completed]).to be(true)
    expect(result[:timeout]).to be(false)
    expect(result[:mailbox_status]).to eq(1)
    expect(result[:mailbox_value]).to eq(0x55AA)
    expect(result[:unmapped_accesses]).to be_empty
    expect(result[:wishbone_trace]).not_to be_empty
    expect(result[:wishbone_trace].map(&:addr)).to include(0)
    expect(result[:wishbone_trace].map(&:addr)).to include(8)
    expect(
      result[:wishbone_trace].any? { |event| event.addr >= RHDL::Examples::SPARC64::Integration::PROGRAM_BASE }
    ).to be(true)
    expect(
      result[:wishbone_trace].any? { |event| event.addr == 0 && event.read_data == boot_words[0] }
    ).to be(true)
    expect(
      result[:wishbone_trace].any? { |event| event.addr == 8 && event.read_data == boot_words[1] }
    ).to be(true)
    expect(
      result[:wishbone_trace].any? do |event|
        event.op == :write &&
          event.addr == RHDL::Examples::SPARC64::Integration::MAILBOX_STATUS &&
          event.write_data == 1
      end
    ).to be(true)
    expect(
      result[:wishbone_trace].any? do |event|
        event.op == :write &&
          event.addr == RHDL::Examples::SPARC64::Integration::MAILBOX_VALUE &&
          event.write_data == 0x55AA
      end
    ).to be(true)
  end
end
