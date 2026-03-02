# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "rhdl/import/missing_module_signature_extractor"

RSpec.describe RHDL::Import::MissingModuleSignatureExtractor do
  describe ".augment" do
    it "extracts named parameter and port bindings from source instantiations" do
      Dir.mktmpdir do |dir|
        source_path = File.join(dir, "top.v")
        File.write(
          source_path,
          <<~VERILOG
            module top;
              ext_mem #(
                .WIDTH(32),
                .DEPTH(1024)
              ) u_ext_mem (
                .clk(clk),
                .addr(addr),
                .data_o(data_o)
              );
            endmodule
          VERILOG
        )

        signatures = described_class.augment(
          signatures: [
            { name: "ext_mem", ports: [], parameters: [] }
          ],
          source_files: [source_path]
        )

        expect(signatures).to eq(
          [
            {
              name: "ext_mem",
              ports: %w[addr clk data_o],
              parameters: %w[DEPTH WIDTH],
              referenced_by: []
            }
          ]
        )
      end
    end

    it "preserves existing signatures and ignores comments" do
      Dir.mktmpdir do |dir|
        source_path = File.join(dir, "top.v")
        File.write(
          source_path,
          <<~VERILOG
            module top;
              // ghost_module #(.WIDTH(1)) u_ghost (.a(a));
              /* ext_mem #(.DEPTH(1)) u_hidden (.a(a)); */
              ext_mem u_ext_mem (
                .clk(clk),
                .rst(rst)
              );
            endmodule
          VERILOG
        )

        signatures = described_class.augment(
          signatures: [
            { name: "ext_mem", ports: ["existing"], parameters: ["WIDTH"], referenced_by: ["top"] }
          ],
          source_files: [source_path]
        )

        expect(signatures).to eq(
          [
            {
              name: "ext_mem",
              ports: %w[clk existing rst],
              parameters: ["WIDTH"],
              referenced_by: ["top"]
            }
          ]
        )
      end
    end
  end
end
