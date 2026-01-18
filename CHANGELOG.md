# Changelog

All notable changes to RHDL will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-01-18

### Added

- Initial release as a Ruby gem
- Gate-level HDL simulation with signal propagation
- MOS 6502 CPU implementation (behavioral model)
- HDL export to Verilog
- Interactive terminal GUI (TUI) for debugging
- Diagram generation (SVG, PNG, DOT formats)
- Component library:
  - Logic gates (AND, OR, XOR, NOT, NAND, NOR, XNOR, Buffer, Tristate)
  - Arithmetic (Adder, Subtractor, Multiplier, Divider, ALU, Comparator)
  - Sequential (D/T/JK/SR flip-flops, Register, Counter, ProgramCounter)
  - Combinational (Mux, Demux, Decoder, Encoder, BarrelShifter)
  - Memory (RAM, ROM, RegisterFile, Stack, FIFO)
- Gate-level synthesis for 53 HDL components
- Parallel test execution support
- Apple II terminal emulator demo
