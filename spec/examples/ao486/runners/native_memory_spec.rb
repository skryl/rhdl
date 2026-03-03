# frozen_string_literal: true

require "spec_helper"

require_relative "../../../../examples/ao486/utilities/runners/native_memory"

RSpec.describe RHDL::Examples::AO486::NativeMemory, :no_vendor_reimport do
  it "reads loaded words and defaults missing locations to zero" do
    memory = described_class.from_words(
      0x0000_1000 => 0x1122_3344
    )

    expect(memory.read_word(0x0000_1000)).to eq(0x1122_3344)
    expect(memory.read_word(0x0000_1004)).to eq(0x0000_0000)
  end

  it "applies byteenable writes with little-endian byte lanes" do
    memory = described_class.from_words(
      0x0000_1000 => 0x1122_3344
    )

    memory.write_word(address: 0x0000_1000, data: 0xAABB_CCDD, byteenable: 0b0101)
    expect(memory.read_word(0x0000_1000)).to eq(0x11BB_33DD)

    memory.write_word(address: 0x0000_1000, data: 0x1234_5678, byteenable: 0b1010)
    expect(memory.read_word(0x0000_1000)).to eq(0x12BB_56DD)
  end

  it "reads bytes from little-endian words at arbitrary byte addresses" do
    memory = described_class.from_words(
      0x0000_1000 => 0x1122_3344,
      0x0000_1004 => 0xAABB_CCDD
    )

    expect(memory.read_byte(0x0000_1000)).to eq(0x44)
    expect(memory.read_byte(0x0000_1001)).to eq(0x33)
    expect(memory.read_byte(0x0000_1002)).to eq(0x22)
    expect(memory.read_byte(0x0000_1003)).to eq(0x11)
    expect(memory.read_byte(0x0000_1004)).to eq(0xDD)
    expect(memory.read_byte(0x0000_1005)).to eq(0xCC)
  end

  it "produces tracked snapshots keyed by canonical lowercase hex" do
    memory = described_class.from_words(
      0x0000_0200 => 0x0000_ABCD,
      0xFFFF_FFF0 => 0x1234_5678
    )

    snapshot = memory.snapshot([0x0000_0200, 0xFFFF_FFF0, 0x0000_0204])
    expect(snapshot).to eq(
      "00000200" => 0x0000_ABCD,
      "fffffff0" => 0x1234_5678,
      "00000204" => 0x0000_0000
    )
  end
end
