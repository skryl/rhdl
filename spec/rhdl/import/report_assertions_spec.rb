require "spec_helper"

RSpec.describe "import report skeleton assertion helpers", :import do
  let(:valid_report) { load_import_fixture_json("reports", "skeleton_success.json") }
  let(:missing_top_level_key) { load_import_fixture_json("reports", "skeleton_missing_top_level_key.json") }
  let(:missing_summary_key) { load_import_fixture_json("reports", "skeleton_missing_summary_key.json") }

  it "accepts the scaffold report JSON skeleton" do
    expect { assert_import_report_skeleton!(valid_report, status: "success") }.not_to raise_error
  end

  it "supports in-memory symbol-key reports" do
    symbolized_report = deep_symbolize(valid_report)

    expect { assert_import_report_skeleton!(symbolized_report, status: :success) }.not_to raise_error
  end

  it "fails fast when a top-level key is missing" do
    expect do
      assert_import_report_skeleton!(missing_top_level_key)
    end.to raise_error(ArgumentError, /diagnostics/)
  end

  it "fails fast when summary keys are missing" do
    expect do
      assert_import_report_skeleton!(missing_summary_key)
    end.to raise_error(ArgumentError, /checks_failed/)
  end

  def deep_symbolize(value)
    case value
    when Hash
      value.each_with_object({}) { |(key, inner), memo| memo[key.to_sym] = deep_symbolize(inner) }
    when Array
      value.map { |item| deep_symbolize(item) }
    else
      value
    end
  end
end
