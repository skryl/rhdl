# frozen_string_literal: true

require "spec_helper"

require_relative "../../../../examples/ao486/utilities/runners/headless_runner"

RSpec.describe "ao486 vendor Verilator functional programs", :slow, :no_vendor_reimport do
  RESET_WINDOW_START = 0x000F_FFE0
  RESET_WINDOW_END = 0x000F_FFFC

  FUNCTIONAL_PROGRAMS = [
    {
      name: "04_cellular_automaton",
      binary: "04_cellular_automaton.bin",
      data_check_addresses: [0x0000_0240, 0x0000_0242],
      expected_words: {
        0x0000_0240 => 0x0000_F5E2,
        0x0000_0242 => 0x0000_0010
      },
      cycles: 65_536
    },
    {
      name: "05_mandelbrot_fixedpoint",
      binary: "05_mandelbrot_fixedpoint.bin",
      data_check_addresses: [0x0000_0250, 0x0000_0252],
      expected_words: {
        0x0000_0250 => 0x0000_8EEE,
        0x0000_0252 => 0x0000_0003
      },
      cycles: 65_536
    },
    {
      name: "06_prime_sieve",
      binary: "06_prime_sieve.bin",
      data_check_addresses: [0x0000_0260, 0x0000_0262],
      expected_words: {
        0x0000_0260 => 0x0000_06B8,
        0x0000_0262 => 0x0000_001F
      },
      cycles: 65_536
    }
  ].freeze

  let(:cwd) { File.expand_path("../../../../", __dir__) }
  let(:out_dir) { File.expand_path("../../../../examples/ao486/hdl", __dir__) }
  let(:vendor_root) { File.expand_path("../../../../examples/ao486/hdl/vendor/source_hdl", __dir__) }
  let(:program_root) { File.expand_path("../../../../examples/ao486/software/bin", __dir__) }

  def read_word(memory_contents, address)
    normalized = Integer(address) & 0xFFFF_FFFF
    key_hex = format("%08x", normalized)
    key_prefixed = format("0x%08x", normalized)

    raw =
      if memory_contents.key?(normalized)
        memory_contents[normalized]
      elsif memory_contents.key?(key_hex)
        memory_contents[key_hex]
      elsif memory_contents.key?(key_prefixed)
        memory_contents[key_prefixed]
      else
        nil
      end

    return nil if raw.nil?

    Integer(raw) & 0xFFFF_FFFF
  rescue ArgumentError, TypeError
    nil
  end

  it "executes complex programs with expected output words before DOS work", timeout: 420 do
    skip "Verilator not available" unless HdlToolchain.verilator_available?
    skip "ao486 vendor hdl tree is unavailable" unless Dir.exist?(vendor_root)

    runner = RHDL::Examples::AO486::HeadlessRunner.new(
      mode: :verilator,
      source_mode: :vendor,
      out_dir: out_dir,
      vendor_root: vendor_root,
      cwd: cwd
    )

    FUNCTIONAL_PROGRAMS.each do |program|
      binary = File.join(program_root, program.fetch(:binary))
      expect(File.file?(binary)).to be(true), "missing program binary #{binary}"

      run = runner.run_program(
        program_binary: binary,
        cycles: program.fetch(:cycles),
        data_check_addresses: program.fetch(:data_check_addresses)
      )

      pcs = Array(run.fetch("pc_sequence", []))
      writes = Array(run.fetch("memory_writes", []))
      memory_contents = run.fetch("memory_contents", {}).to_h

      expect(pcs).not_to be_empty, "#{program.fetch(:name)} produced no PC trace"
      escaped_reset_window = pcs.any? do |pc|
        value = Integer(pc) & 0xFFFF_FFFF
        value < RESET_WINDOW_START || value > RESET_WINDOW_END
      rescue ArgumentError, TypeError
        false
      end
      expect(escaped_reset_window).to be(true), <<~MSG
        #{program.fetch(:name)} never escaped reset-vector window #{format("0x%08x", RESET_WINDOW_START)}..#{format("0x%08x", RESET_WINDOW_END)}
        last_pc=#{format("0x%08x", Integer(pcs.last || 0) & 0xFFFF_FFFF)}
      MSG

      expect(writes.length).to be > 0, "#{program.fetch(:name)} observed no memory writes"

      program.fetch(:expected_words).each do |address, expected_value|
        actual = read_word(memory_contents, address)
        expect(actual).to eq(expected_value), <<~MSG
          #{program.fetch(:name)} wrong output word at #{format("0x%08x", address)}
          expected=#{format("0x%08x", expected_value)}
          actual=#{actual.nil? ? "nil" : format("0x%08x", actual)}
        MSG
      end
    end
  end
end
