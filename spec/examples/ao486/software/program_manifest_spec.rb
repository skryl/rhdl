# frozen_string_literal: true

require "open3"
require "spec_helper"

RSpec.describe "ao486 software program set", :no_vendor_reimport do
  ROOT = File.expand_path("../../../../examples/ao486/software", __dir__)
  SOFTWARE_SOURCE_ROOT = File.join(ROOT, "source")
  BIN_ROOT = File.join(ROOT, "bin")
  IMAGE_ROOT = File.join(ROOT, "images")
  BUILD_SCRIPT = File.join(ROOT, "build_programs.sh")

  COMPLEX_PROGRAMS = [
    { source: "04_cellular_automaton.S", binary: "04_cellular_automaton.bin" },
    { source: "05_mandelbrot_fixedpoint.S", binary: "05_mandelbrot_fixedpoint.bin" },
    { source: "06_prime_sieve.S", binary: "06_prime_sieve.bin" }
  ].freeze

  it "includes complex ao486 sources and compiled binaries" do
    expect(File.file?(BUILD_SCRIPT)).to be(true), "missing build script #{BUILD_SCRIPT}"

    COMPLEX_PROGRAMS.each do |program|
      source_path = File.join(SOFTWARE_SOURCE_ROOT, program.fetch(:source))
      binary_path = File.join(BIN_ROOT, program.fetch(:binary))

      expect(File.file?(source_path)).to be(true), "missing source #{source_path}"
      expect(File.file?(binary_path)).to be(true), "missing binary #{binary_path}"
      expect(File.size(binary_path)).to be > 0
    end
  end

  it "rebuilds complex binaries deterministically" do
    before = COMPLEX_PROGRAMS.each_with_object({}) do |program, memo|
      binary_path = File.join(BIN_ROOT, program.fetch(:binary))
      memo[binary_path] = File.binread(binary_path)
    end

    stdout, stderr, status = Open3.capture3(BUILD_SCRIPT.to_s, chdir: ROOT)
    unless status.success?
      raise "build failed status=#{status.exitstatus} stdout=#{stdout} stderr=#{stderr}"
    end

    after = COMPLEX_PROGRAMS.each_with_object({}) do |program, memo|
      binary_path = File.join(BIN_ROOT, program.fetch(:binary))
      memo[binary_path] = File.binread(binary_path)
    end

    expect(after).to eq(before)
  end

  it "includes DOS boot image artifacts used by BIOS mode" do
    fdboot_path = File.join(IMAGE_ROOT, "fdboot.img")
    dos4_path = File.join(IMAGE_ROOT, "dos4.img")

    expect(File.file?(fdboot_path)).to be(true), "missing DOS image #{fdboot_path}"
    expect(File.file?(dos4_path)).to be(true), "missing DOS image alias #{dos4_path}"
    expect(File.size(fdboot_path)).to be > 0
    expect(File.size(dos4_path)).to eq(File.size(fdboot_path))
    expect(File.binread(dos4_path)).to eq(File.binread(fdboot_path))
  end
end
