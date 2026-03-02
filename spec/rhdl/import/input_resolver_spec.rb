require "spec_helper"
require "rhdl/import/input_resolver"
require "fileutils"
require "tmpdir"

RSpec.describe RHDL::Import::InputResolver do
  describe ".resolve" do
    it "resolves filelist mode with exclusion filtering and frontend passthrough capture" do
      filelist = import_fixture_path("ingestion", "filelist_case", "lists", "main.f")
      cli_incdir = import_fixture_path("ingestion", "autoscan_case", "src", "sub")

      resolved = described_class.resolve(
        filelist: filelist,
        exclude: ["**/excluded/**"],
        incdir: [cli_incdir],
        define: ["FROM_CLI=1"]
      )

      filelist_root = import_fixture_path("ingestion", "filelist_case")
      expect(resolved[:mode]).to eq(:filelist)
      expect(resolved[:source_files]).to eq(
        [
          File.join(filelist_root, "rtl", "top.sv"),
          File.join(filelist_root, "rtl", "leaf.v")
        ]
      )
      expect(resolved[:include_dirs]).to eq(
        [
          File.join(filelist_root, "include"),
          cli_incdir
        ]
      )
      expect(resolved[:defines]).to eq(["FROM_MAIN=1", "FROM_NESTED", "FROM_CLI=1"])
      expect(resolved[:frontend_input]).to eq(
        source_files: resolved[:source_files],
        include_dirs: resolved[:include_dirs],
        defines: resolved[:defines]
      )
    end

    it "autoscan mode discovers verilog/systemverilog files deterministically and applies excludes" do
      src_dir = import_fixture_path("ingestion", "autoscan_case", "src")

      resolved = described_class.resolve(
        src: [src_dir],
        exclude: ["**/excluded/**"],
        incdir: [File.join(src_dir, "sub")],
        define: ["SCAN_DEF=1"]
      )

      expect(resolved[:mode]).to eq(:autoscan)
      expect(resolved[:source_files]).to eq(
        [
          File.join(src_dir, "a_first.v"),
          File.join(src_dir, "sub", "middle.sv"),
          File.join(src_dir, "z_last.sv")
        ]
      )
      expect(resolved[:include_dirs]).to eq(
        [
          File.join(src_dir, "sub"),
          src_dir
        ]
      )
      expect(resolved[:defines]).to eq(["SCAN_DEF=1"])
      expect(resolved[:frontend_input][:source_files]).to eq(resolved[:source_files])
    end

    it "supports parent-root dependency autoscan from a nested src root" do
      Dir.mktmpdir do |dir|
        rtl_root = File.join(dir, "rtl")
        ao486_dir = File.join(rtl_root, "ao486")
        common_dir = File.join(rtl_root, "common")
        FileUtils.mkdir_p(ao486_dir)
        FileUtils.mkdir_p(common_dir)

        top_file = File.join(ao486_dir, "top.v")
        helper_file = File.join(common_dir, "helper.v")
        File.write(top_file, "module top; endmodule\n")
        File.write(helper_file, "module helper; endmodule\n")

        resolved = described_class.resolve(
          src: [ao486_dir],
          dependency_resolution: "parent_root_auto_scan"
        )

        expect(resolved[:source_files]).to eq([top_file, helper_file])
        expect(resolved[:include_dirs]).to eq([ao486_dir, rtl_root, common_dir])
      end
    end

    it "filters non-module compile units when compile_unit_filter is modules_only" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        FileUtils.mkdir_p(src_dir)

        module_file = File.join(src_dir, "mod.v")
        include_fragment = File.join(src_dir, "fragment.v")
        File.write(module_file, "module mod; endmodule\n")
        File.write(include_fragment, "assign x = y;\n")

        resolved = described_class.resolve(
          src: [src_dir],
          compile_unit_filter: "modules_only"
        )

        expect(resolved[:source_files]).to eq([module_file])
      end
    end
  end
end
