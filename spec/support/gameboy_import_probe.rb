# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'

module GameboyImportProbe
  module_function

  def ready_result
    @ready_result ||= compute_ready_result
  end

  def ready?
    ready_result.fetch(:ready)
  end

  def reason
    ready_result.fetch(:reason)
  end

  def reset!
    @ready_result = nil
  end

  def compute_ready_result
    reasons = []

    ghdl = HdlToolchain.which('ghdl')
    circt_translate = HdlToolchain.which('circt-translate')

    reasons << 'ghdl not available' unless ghdl
    reasons << 'circt-translate not available' unless circt_translate
    return { ready: false, reason: reasons.join('; ') } unless reasons.empty?

    ghdl_check = probe_ghdl_syntax(ghdl)
    reasons << ghdl_check unless ghdl_check.nil?

    circt_check = probe_circt_verilog_import(circt_translate)
    reasons << circt_check unless circt_check.nil?

    {
      ready: reasons.empty?,
      reason: reasons.empty? ? 'ok' : reasons.join('; ')
    }
  end

  def probe_ghdl_syntax(ghdl)
    file = File.expand_path('../../examples/gameboy/reference/rtl/bus_savestates.vhd', __dir__)
    return "missing probe file: #{file}" unless File.file?(file)

    Dir.mktmpdir('gb_ghdl_probe') do |workdir|
      _stdout, stderr, status = Open3.capture3(
        ghdl,
        '-a',
        '--std=08',
        "--workdir=#{workdir}",
        '--work=work',
        file
      )
      return nil if status.success?

      first = stderr.to_s.lines.first&.strip
      "ghdl unsupported syntax for bus_savestates.vhd: #{first || 'unknown error'}"
    end
  end

  def probe_circt_verilog_import(circt_translate)
    verilog = File.expand_path('../../examples/gameboy/reference/rtl/cart.v', __dir__)
    return "missing probe file: #{verilog}" unless File.file?(verilog)

    Dir.mktmpdir('gb_circt_probe') do |dir|
      out = File.join(dir, 'cart.moore.mlir')
      _stdout, stderr, status = Open3.capture3(
        circt_translate,
        '--import-verilog',
        verilog,
        '-o',
        out
      )
      return nil if status.success?

      first = stderr.to_s.lines.first&.strip
      "circt-translate unsupported import for cart.v: #{first || 'unknown error'}"
    end
  end
end
