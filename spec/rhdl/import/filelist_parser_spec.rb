require "spec_helper"
require "fileutils"
require "tmpdir"
require "rhdl/import/filelist_parser"

RSpec.describe RHDL::Import::FilelistParser do
  describe ".parse" do
    let(:main_filelist) { import_fixture_path("ingestion", "filelist_case", "lists", "main.f") }

    it "parses source files, include dirs, defines, and nested filelists" do
      parsed = described_class.parse(main_filelist)
      fixture_root = import_fixture_path("ingestion", "filelist_case")

      expect(parsed).to eq(
        filelist_path: File.expand_path(main_filelist),
        source_files: [
          File.join(fixture_root, "rtl", "top.sv"),
          File.join(fixture_root, "rtl", "leaf.v"),
          File.join(fixture_root, "rtl", "excluded", "skip.sv")
        ],
        include_dirs: [
          File.join(fixture_root, "include")
        ],
        defines: [
          "FROM_MAIN=1",
          "FROM_NESTED"
        ]
      )
    end

    it "deduplicates repeated include/define directives while preserving first occurrence order" do
      filelist_dir = Dir.mktmpdir("rhdl-filelist")
      begin
        nested = File.join(filelist_dir, "nested.f")
        main = File.join(filelist_dir, "main.f")
        File.write(nested, "+incdir+./inc\n+define+FLAG\n")
        File.write(main, "+incdir+./inc\n+define+FLAG\n-f nested.f\n")

        parsed = described_class.parse(main)
        expect(parsed[:include_dirs]).to eq([File.join(filelist_dir, "inc")])
        expect(parsed[:defines]).to eq(["FLAG"])
      ensure
        FileUtils.remove_entry(filelist_dir)
      end
    end
  end
end
