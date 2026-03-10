# frozen_string_literal: true

require_relative '../../../../examples/ao486/utilities/display_adapter'
require_relative '../../../../examples/ao486/utilities/runners/headless_runner'

module Ao486IntegrationSupport
  REQUIRED_RUNNER_METHODS = %i[
    software_root
    software_path
    bios_paths
    dos_path
    load_bios
    load_dos
    bios_loaded?
    dos_loaded?
    reset
    run
    state
    native?
    simulator_type
    display_buffer
    update_display_buffer
    render_display
  ].freeze

  def ao486_runner_classes
    {
      ir: RHDL::Examples::AO486::IrRunner,
      verilator: RHDL::Examples::AO486::VerilatorRunner,
      arcilator: RHDL::Examples::AO486::ArcilatorRunner
    }
  end

  def build_text_buffer(rows: RHDL::Examples::AO486::DisplayAdapter::TEXT_ROWS,
                        cols: RHDL::Examples::AO486::DisplayAdapter::TEXT_COLUMNS)
    Array.new(rows * cols * 2, 0)
  end

  def write_text(buffer, text, row:, col:, attr: 0x07,
                 cols: RHDL::Examples::AO486::DisplayAdapter::TEXT_COLUMNS)
    text.to_s.each_byte.with_index do |byte, offset|
      index = ((row * cols) + col + offset) * 2
      break if index >= buffer.length

      buffer[index] = byte
      buffer[index + 1] = attr
    end

    buffer
  end
end
