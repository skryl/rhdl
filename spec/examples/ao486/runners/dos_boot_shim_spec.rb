# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "tmpdir"

require_relative "../../../../examples/ao486/utilities/runners/dos_boot_shim"

RSpec.describe RHDL::Examples::AO486::DosBootShim do
  def build_disk_image
    Tempfile.new(["ao486_dos_disk", ".img"]).tap do |file|
      bytes = Array.new(1474560, 0)
      bytes[0] = 0xEB
      bytes[1] = 0x3C
      bytes[2] = 0x90
      bytes[510] = 0x55
      bytes[511] = 0xAA
      file.binmode
      file.write(bytes.pack("C*"))
      file.flush
    end
  end

  it "builds a real-mode bootstrap binary without synthetic shell output strings" do
    disk = build_disk_image
    shim = described_class.new(disk_image_path: disk.path)
    binary = shim.binary

    expect(described_class::LOAD_ADDRESS).to eq(0x000F_0000)
    expect(binary.bytesize).to be > 256
    expect(binary).to include(described_class::BOOT_FAIL_MESSAGE)
    expect(binary).not_to include("Bad command or file name")
    expect(binary).not_to include("Starting MS-DOS")
    expect(binary.bytes).to include(0xCD, 0x13) # INT 13h entry points exist
    expect(binary.bytes).to include(0xCD, 0x10) # INT 10h entry points exist
    expect(binary.bytes).to include(0xCD, 0x16) # INT 16h entry points exist
  ensure
    disk&.close!
  end

  it "raises on a missing disk image path" do
    missing_path = File.join(Dir.tmpdir, "does_not_exist_ao486_dos.img")
    expect do
      described_class.new(disk_image_path: missing_path)
    end.to raise_error(ArgumentError, /DOS disk image not found/)
  end
end
