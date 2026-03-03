# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "digest/sha1"
require "rhdl/import/project_writer"

RSpec.describe RHDL::Import::ProjectWriter do
  describe "#write" do
    it "writes one file per converted module and the project scaffold layout" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        src_file = File.join(dir, "rtl", "top.sv")
        FileUtils.mkdir_p(File.dirname(src_file))
        File.write(src_file, "module top; endmodule\n")

        writer = described_class.new
        result = writer.write(
          out: out,
          project_slug: "demo_import",
          modules: [
            { name: "TopOk", ruby_source: "# top\nclass TopOk; end\n" },
            { name: "LeafNode", ruby_source: "# leaf\nclass LeafNode; end\n" }
          ],
          source_files: [src_file]
        )

        expect(result[:project_file]).to eq(File.join(out, "lib", "demo_import.rb"))
        expect(result[:config_file]).to eq(File.join(out, "rhdl_import.yml"))
        expect(result[:vendor_dir]).to eq(File.join(out, "vendor", "source_hdl"))
        expect(result[:module_files]).to eq(
          "LeafNode" => File.join(out, "lib", "demo_import", "modules", "leaf_node.rb"),
          "TopOk" => File.join(out, "lib", "demo_import", "modules", "top_ok.rb")
        )

        expect(File.read(result[:project_file])).to include('require_relative "demo_import/modules/leaf_node"')
        expect(File.read(result[:project_file])).to include('require_relative "demo_import/modules/top_ok"')

        expect(File.read(result[:module_files]["LeafNode"])).to include("class LeafNode; end")
        expect(File.read(result[:module_files]["TopOk"])).to include("class TopOk; end")

        expect(File.exist?(File.join(result[:vendor_dir], "top.sv"))).to be(true)
        expect(File.read(result[:config_file])).to include("project: demo_import")
      end
    end

    it "orders project requires so dependencies are loaded before dependent modules" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")

        writer = described_class.new
        result = writer.write(
          out: out,
          project_slug: "demo_import",
          modules: [
            { name: "TopModule", dependencies: ["LeafModule"], ruby_source: "class TopModule; end\n" },
            { name: "LeafModule", dependencies: [], ruby_source: "class LeafModule; end\n" }
          ],
          source_files: []
        )

        project_source = File.read(result[:project_file])
        leaf_index = project_source.index('require_relative "demo_import/modules/leaf_module"')
        top_index = project_source.index('require_relative "demo_import/modules/top_module"')

        expect(leaf_index).not_to be_nil
        expect(top_index).not_to be_nil
        expect(leaf_index).to be < top_index
      end
    end

    it "preserves source directory and basename structure for module files and copied sources" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        rtl_root = File.join(dir, "rtl")
        alu_src = File.join(rtl_root, "core", "alu.v")
        top_src = File.join(rtl_root, "cpu", "top.sv")
        FileUtils.mkdir_p(File.dirname(alu_src))
        FileUtils.mkdir_p(File.dirname(top_src))
        File.write(alu_src, "module alu; endmodule\n")
        File.write(top_src, "module top; endmodule\n")

        writer = described_class.new
        result = writer.write(
          out: out,
          project_slug: "demo_import",
          modules: [
            { name: "Top", source_path: top_src, ruby_source: "class Top; end\n" },
            { name: "Alu", source_path: alu_src, ruby_source: "class Alu; end\n" }
          ],
          source_files: [top_src, alu_src]
        )

        expect(result[:module_files]).to eq(
          "Alu" => File.join(out, "lib", "demo_import", "modules", "core", "alu.rb"),
          "Top" => File.join(out, "lib", "demo_import", "modules", "cpu", "top.rb")
        )
        expect(File.read(result[:project_file])).to include('require_relative "demo_import/modules/core/alu"')
        expect(File.read(result[:project_file])).to include('require_relative "demo_import/modules/cpu/top"')
        expect(File.exist?(File.join(result[:vendor_dir], "core", "alu.v"))).to be(true)
        expect(File.exist?(File.join(result[:vendor_dir], "cpu", "top.sv"))).to be(true)
      end
    end

    it "copies transitive include files used by copied source files" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        rtl_root = File.join(dir, "rtl")
        top_src = File.join(rtl_root, "ao486", "pipeline", "execute_commands.v")
        include_defines = File.join(rtl_root, "ao486", "defines.v")
        include_autogen = File.join(rtl_root, "ao486", "autogen", "execute_commands.v")
        FileUtils.mkdir_p(File.dirname(top_src))
        FileUtils.mkdir_p(File.dirname(include_autogen))
        File.write(
          top_src,
          <<~VERILOG
            `include "defines.v"
            `include "autogen/execute_commands.v"
            module execute_commands;
            endmodule
          VERILOG
        )
        File.write(include_defines, "`define FOO 1\n")
        File.write(include_autogen, "wire autogen_signal = 1'b0;\n")

        writer = described_class.new
        result = writer.write(
          out: out,
          project_slug: "demo_import",
          modules: [
            { name: "ExecuteCommands", source_path: top_src, ruby_source: "class ExecuteCommands; end\n" }
          ],
          source_files: [top_src],
          source_roots: [rtl_root]
        )

        expect(File.exist?(File.join(result[:vendor_dir], "ao486", "pipeline", "execute_commands.v"))).to be(true)
        expect(File.exist?(File.join(result[:vendor_dir], "ao486", "defines.v"))).to be(true)
        expect(File.exist?(File.join(result[:vendor_dir], "ao486", "autogen", "execute_commands.v"))).to be(true)
      end
    end

    it "prunes stale generated module and vendor files from prior runs" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        rtl_dir = File.join(dir, "rtl")
        FileUtils.mkdir_p(rtl_dir)
        first_src = File.join(rtl_dir, "first.sv")
        second_src = File.join(rtl_dir, "second.sv")
        File.write(first_src, "module first; endmodule\n")
        File.write(second_src, "module second; endmodule\n")

        writer = described_class.new
        writer.write(
          out: out,
          project_slug: "demo_import",
          modules: [
            { name: "KeepMe", ruby_source: "class KeepMe; end\n" },
            { name: "RemoveMe", ruby_source: "class RemoveMe; end\n" }
          ],
          source_files: [first_src]
        )

        stale_module = File.join(out, "lib", "demo_import", "modules", "legacy_name.rb")
        File.write(stale_module, "class LegacyName; end\n")
        stale_vendor = File.join(out, "vendor", "source_hdl", "stale.sv")
        File.write(stale_vendor, "module stale; endmodule\n")

        result = writer.write(
          out: out,
          project_slug: "demo_import",
          modules: [
            { name: "KeepMe", ruby_source: "class KeepMe; end\n" }
          ],
          source_files: [second_src]
        )

        expect(File.exist?(File.join(out, "lib", "demo_import", "modules", "keep_me.rb"))).to be(true)
        expect(File.exist?(File.join(out, "lib", "demo_import", "modules", "remove_me.rb"))).to be(false)
        expect(File.exist?(stale_module)).to be(false)

        expect(File.exist?(File.join(out, "vendor", "source_hdl", "first.sv"))).to be(false)
        expect(File.exist?(File.join(out, "vendor", "source_hdl", "second.sv"))).to be(true)
        expect(File.exist?(stale_vendor)).to be(false)

        expect(result[:removed_module_files]).to include(stale_module)
        expect(result[:removed_vendor_files]).to include(stale_vendor)
      end
    end

    it "prunes stale nested module and vendor files when preserving source layout" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        rtl_root = File.join(dir, "rtl")
        first_src = File.join(rtl_root, "cluster_a", "first.sv")
        second_src = File.join(rtl_root, "cluster_b", "second.sv")
        FileUtils.mkdir_p(File.dirname(first_src))
        FileUtils.mkdir_p(File.dirname(second_src))
        File.write(first_src, "module first; endmodule\n")
        File.write(second_src, "module second; endmodule\n")

        writer = described_class.new
        writer.write(
          out: out,
          project_slug: "demo_import",
          modules: [
            { name: "First", source_path: first_src, ruby_source: "class First; end\n" }
          ],
          source_files: [first_src],
          source_roots: [rtl_root]
        )

        stale_module = File.join(out, "lib", "demo_import", "modules", "cluster_a", "legacy.rb")
        stale_vendor = File.join(out, "vendor", "source_hdl", "cluster_a", "stale.sv")
        FileUtils.mkdir_p(File.dirname(stale_module))
        FileUtils.mkdir_p(File.dirname(stale_vendor))
        File.write(stale_module, "class Legacy; end\n")
        File.write(stale_vendor, "module stale; endmodule\n")

        result = writer.write(
          out: out,
          project_slug: "demo_import",
          modules: [
            { name: "Second", source_path: second_src, ruby_source: "class Second; end\n" }
          ],
          source_files: [second_src],
          source_roots: [rtl_root]
        )

        expect(File.exist?(File.join(out, "lib", "demo_import", "modules", "cluster_a", "first.rb"))).to be(false)
        expect(File.exist?(File.join(out, "lib", "demo_import", "modules", "cluster_a", "legacy.rb"))).to be(false)
        expect(File.exist?(File.join(out, "lib", "demo_import", "modules", "cluster_b", "second.rb"))).to be(true)
        expect(File.exist?(File.join(out, "vendor", "source_hdl", "cluster_a", "first.sv"))).to be(false)
        expect(File.exist?(File.join(out, "vendor", "source_hdl", "cluster_a", "stale.sv"))).to be(false)
        expect(File.exist?(File.join(out, "vendor", "source_hdl", "cluster_b", "second.sv"))).to be(true)
        expect(result[:removed_module_files]).to include(stale_module)
        expect(result[:removed_vendor_files]).to include(stale_vendor)
      end
    end

    it "uses deterministic disambiguated filenames when module names normalize to the same base path" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        mod_a = "Foo-Bar"
        mod_b = "Foo_Bar"
        hash_a = Digest::SHA1.hexdigest(mod_a)[0, 8]
        hash_b = Digest::SHA1.hexdigest(mod_b)[0, 8]

        writer = described_class.new
        result = writer.write(
          out: out,
          project_slug: "demo_import",
          modules: [
            { name: mod_a, ruby_source: "class FooBarA; end\n" },
            { name: mod_b, ruby_source: "class FooBarB; end\n" }
          ],
          source_files: []
        )

        expect(result[:module_files].keys.sort).to eq([mod_a, mod_b].sort)
        expect(result[:module_files][mod_a]).to end_with("foo_bar__#{hash_a}.rb")
        expect(result[:module_files][mod_b]).to end_with("foo_bar__#{hash_b}.rb")
        expect(File.exist?(result[:module_files][mod_a])).to be(true)
        expect(File.exist?(result[:module_files][mod_b])).to be(true)

        project_source = File.read(result[:project_file])
        expect(project_source).to include(%(require_relative "demo_import/modules/foo_bar__#{hash_a}"))
        expect(project_source).to include(%(require_relative "demo_import/modules/foo_bar__#{hash_b}"))
      end
    end

    it "assigns collision-disambiguated filenames independent of input module order" do
      Dir.mktmpdir do |dir|
        out_a = File.join(dir, "out_a")
        out_b = File.join(dir, "out_b")
        mod_a = "Foo-Bar"
        mod_b = "Foo_Bar"

        writer = described_class.new
        first = writer.write(
          out: out_a,
          project_slug: "demo_import",
          modules: [
            { name: mod_a, ruby_source: "class FooBarA; end\n" },
            { name: mod_b, ruby_source: "class FooBarB; end\n" }
          ],
          source_files: []
        )
        second = writer.write(
          out: out_b,
          project_slug: "demo_import",
          modules: [
            { name: mod_b, ruby_source: "class FooBarB; end\n" },
            { name: mod_a, ruby_source: "class FooBarA; end\n" }
          ],
          source_files: []
        )

        normalized_first = first[:module_files].transform_values { |path| File.basename(path) }
        normalized_second = second[:module_files].transform_values { |path| File.basename(path) }
        expect(normalized_second).to eq(normalized_first)
      end
    end

    it "routes generated module source through the ruby prettyfier before writing" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        writer = described_class.new

        result = writer.write(
          out: out,
          project_slug: "demo_import",
          modules: [
            {
              name: "PrettyMe",
              ruby_source: <<~RUBY
                class PrettyMe


                  instance :u_core, "child", ports: { clk: :clk, rst_n: :rst_n, nibble: sig(:bus, width: 8)[7..4] }
                end
              RUBY
            }
          ],
          source_files: []
        )

        module_source = File.read(result[:module_files]["PrettyMe"])
        expect(module_source).not_to include("  \n")
        expect(module_source).to include('instance :u_core, "child",')
        expect(module_source).to include("  ports: {")
        expect(module_source).to include("    clk: :clk,")
        expect(module_source).to include("    rst_n: :rst_n,")
        expect(module_source).to include("    nibble: sig(:bus, width: 8)[7..4]")
        expect(module_source).not_to include("\n\n\n\n")
      end
    end
  end
end
