#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"

ROOT = File.expand_path(File.join(__dir__, "..", "..", ".."))
$LOAD_PATH.unshift(File.join(ROOT, "lib"))

require "rhdl/import/checks/ao486_trace_harness"

options = {
  mode:
    begin
      trace_kind = ENV.fetch("RHDL_IMPORT_TRACE_KIND", "expected")
      profile = ENV.fetch("RHDL_IMPORT_CHECK_PROFILE", "ao486_trace")
      if trace_kind == "actual_trace_events"
        profile == "ao486_trace_ir" ? "converted_ir" : "converted"
      else
        "reference"
      end
    end,
  top: ENV.fetch("RHDL_IMPORT_TOP", "ao486"),
  out: ENV.fetch("RHDL_IMPORT_OUT", File.join(ROOT, "examples", "ao486", "hdl")),
  source_root: File.join(ROOT, "examples", "ao486", "reference", "rtl", "ao486"),
  converted_export_mode: ENV["RHDL_IMPORT_TRACE_CONVERTED_EXPORT_MODE"],
  cycles: 512
}

OptionParser.new do |opts|
  opts.banner = "Usage: capture_trace.rb [options]"

  opts.on("--mode MODE", "reference, converted, or converted_ir") { |value| options[:mode] = value }
  opts.on("--top NAME", "Top module (default: ao486)") { |value| options[:top] = value }
  opts.on("--out DIR", "Importer output directory") { |value| options[:out] = value }
  opts.on("--source-root DIR", "Reference RTL root for mode=reference") { |value| options[:source_root] = value }
  opts.on("--converted-export-mode MODE", "Converted export mode: component or dsl_super") { |value| options[:converted_export_mode] = value }
  opts.on("--cycles N", Integer, "Number of cycles to run (default: 512)") { |value| options[:cycles] = value }
end.parse!(ARGV)

events = RHDL::Import::Checks::Ao486TraceHarness.capture(
  mode: options[:mode],
  top: options[:top],
  out: options[:out],
  cycles: options[:cycles],
  source_root: options[:source_root],
  converted_export_mode: options[:converted_export_mode],
  cwd: ROOT
)

$stdout.write(JSON.generate(events))
$stdout.write("\n")
