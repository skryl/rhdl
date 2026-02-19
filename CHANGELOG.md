# Changelog

All notable changes to RHDL will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added `docs/riscv_xv6.md` with a dedicated xv6 workflow for RISC-V:
  - source tree layout
  - local artifact generation via `examples/riscv/software/build_xv6.sh`
  - xv6 readiness/shell spec commands
  - boot tracer usage
  - current web runner integration status

### Changed

- Updated RISC-V docs to include xv6 compatibility coverage and direct commands for `xv6_readiness_spec` and `xv6_shell_io_spec`.
- Updated web simulator docs to document current runner preset/default behavior, startup backend defaults, and integration test suite coverage.
- Updated top-level README documentation links/descriptions to include RISC-V + xv6 workflow guidance.
- Clarified `.gitignore` intent for local `examples/riscv/software/bin/` xv6 build outputs.

## [1.0.0] - 2025-01-18

### Added

- Initial stable release as a Ruby gem
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
