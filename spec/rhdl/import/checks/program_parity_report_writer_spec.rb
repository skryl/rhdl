# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"
require "rhdl/import/checks/program_parity_report_writer"

RSpec.describe RHDL::Import::Checks::ProgramParityReportWriter do
  describe ".write" do
    it "writes program parity reports with normalized summary, mismatches, and traces" do
      Dir.mktmpdir do |dir|
        path = described_class.write(
          root_dir: dir,
          top: "ao486",
          profile: "ao486_program_parity",
          summary: {
            cycles_requested: 64,
            pc_events_compared: 12,
            instruction_events_compared: 12,
            write_events_compared: 3,
            memory_words_compared: 5,
            pass_count: 31,
            fail_count: 1,
            first_mismatch: { kind: "pc_sequence", index: 2 }
          },
          mismatches: [
            {
              kind: "pc_sequence",
              index: 2,
              reference: 0xFFFF_FFF0,
              generated_verilog: 0x0000_0000,
              generated_ir: 0xFFFF_FFF0
            }
          ],
          traces: {
            reference: {
              pc_sequence: [0xFFFF_FFF0],
              instruction_sequence: [0x0000_00EA],
              memory_writes: [],
              memory_contents: { "00000200" => 0x0000_1234 }
            },
            generated_verilog: {},
            generated_ir: {}
          }
        )

        expect(path).to eq(File.join(dir, "ao486_program_parity.json"))
        expect(File.exist?(path)).to be(true)

        parsed = JSON.parse(File.read(path))
        expect(parsed.fetch("top")).to eq("ao486")
        expect(parsed.fetch("profile")).to eq("ao486_program_parity")
        expect(parsed.dig("summary", "fail_count")).to eq(1)
        expect(parsed.dig("mismatches", 0, "kind")).to eq("pc_sequence")
        expect(parsed.dig("traces", "reference", "pc_sequence")).to eq([0xFFFF_FFF0])
        expect(parsed.dig("traces", "reference", "memory_contents", "00000200")).to eq(0x0000_1234)
      end
    end
  end
end
