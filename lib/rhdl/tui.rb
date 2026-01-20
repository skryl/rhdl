# HDL Simulator Terminal User Interface
# Interactive terminal-based GUI for simulation and debugging

require 'io/console'

require_relative 'tui/ansi'
require_relative 'tui/box_draw'
require_relative 'tui/panel'
require_relative 'tui/signal_panel'
require_relative 'tui/waveform_panel'
require_relative 'tui/status_panel'
require_relative 'tui/breakpoint_panel'
require_relative 'tui/screen_buffer'
require_relative 'tui/simulator_tui'
require_relative 'tui/json_protocol'
require_relative 'tui/ink_adapter'

# Backwards compatibility aliases for old class names in RHDL::HDL
module RHDL
  module HDL
    # TUI classes
    ANSI = TUI::ANSI
    BoxDraw = TUI::BoxDraw
    Panel = TUI::Panel
    SignalPanel = TUI::SignalPanel
    WaveformPanel = TUI::WaveformPanel
    StatusPanel = TUI::StatusPanel
    BreakpointPanel = TUI::BreakpointPanel
    ScreenBuffer = TUI::ScreenBuffer
    SimulatorTUI = TUI::SimulatorTUI
    JsonProtocol = TUI::JsonProtocol
    InkAdapter = TUI::InkAdapter
  end
end
