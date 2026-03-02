require "spec_helper"

RSpec.describe "import exit semantics helpers", :import do
  let(:status_like) { Struct.new(:exitstatus) }

  let(:scaffold_cases) { load_import_fixture_json("exit_semantics", "scaffold_cases.json") }

  it "normalizes integer and status-like values for exit semantics checks" do
    expect(normalize_import_exit_code(2)).to eq(2)
    expect(normalize_import_exit_code(status_like.new(3))).to eq(3)
  end

  it "covers non-zero scaffold cases for partial/check/tool failures" do
    scaffold_cases.fetch("non_zero_cases").each do |scenario|
      code = scenario.fetch("exit_code")

      expect(non_zero_import_exit?(code)).to be(true)
      expect(assert_non_zero_import_exit!(code)).to eq(code)
    end
  end

  it "treats zero as a success-only code" do
    zero_code = scaffold_cases.fetch("zero_case").fetch("exit_code")

    expect(non_zero_import_exit?(zero_code)).to be(false)
    expect { assert_non_zero_import_exit!(zero_code) }.to raise_error(ArgumentError, /non-zero/)
  end

  it "rejects unsupported exit payload types" do
    expect { normalize_import_exit_code("1") }.to raise_error(ArgumentError, /Integer/)
  end
end
