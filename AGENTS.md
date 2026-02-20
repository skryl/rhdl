# Agent Guide for `rhdl`

This file is the working guide for coding agents in this repository.
`CLAUDE.md` is a symlink to this file.

## Project Summary

RHDL is a Ruby HDL toolkit with:
- DSL-based hardware component definitions
- multiple simulation backends (Ruby, IR interpreter/JIT/compiler, netlist, Verilator flows)
- CLI tooling for diagrams, exports, synthesis, and example system runners
- example systems: MOS6502, Apple II, Game Boy, and RISC-V (including xv6 workflows)
- web simulator (WASM + browser UI)

## Canonical Entry Points

- `exe/rhdl`: top-level CLI command router
- `Rakefile`: development/test/build automation
- `lib/rhdl/cli/tasks/*.rb`: shared task implementations used by CLI/rake
- `examples/*/bin/*`: example-specific runnable binaries

## Current CLI Surface

Top-level commands (`rhdl --help`):
- `tui`
- `diagram`
- `export`
- `gates`
- `examples`
- `disk`
- `generate`
- `clean`
- `regenerate`

`rhdl examples` subcommands:
- `mos6502`
- `apple2`
- `gameboy`
- `riscv`

Notes:
- `rhdl examples gameboy` execs `examples/gameboy/bin/gameboy`.
- `rhdl examples riscv` execs `examples/riscv/bin/riscv`.
- RISC-V defaults to `--mode ir --sim compile`.
- RISC-V `--xv6` forces UART I/O mode.

## Current Rake Tasks

Use `bundle exec rake -T` to inspect full task list.

Common tasks:
- `bundle exec rake spec`
- `bundle exec rake spec:lib`
- `bundle exec rake spec:hdl`
- `bundle exec rake spec:mos6502`
- `bundle exec rake spec:apple2`
- `bundle exec rake spec:riscv`

Parallel:
- `bundle exec rake pspec`
- `bundle exec rake pspec:lib`
- `bundle exec rake pspec:hdl`
- `bundle exec rake pspec:mos6502`
- `bundle exec rake pspec:apple2`
- `bundle exec rake pspec:riscv`

Spec benchmarks:
- `bundle exec rake spec:bench:all[20]`
- `bundle exec rake spec:bench:riscv[20]`

Simulation benchmarks:
- `bundle exec rake bench:gates`
- `bundle exec rake bench:mos6502[5000000]`
- `bundle exec rake bench:apple2[5000000]`
- `bundle exec rake bench:gameboy[1000]`
- `bundle exec rake bench:ir[5000000]`

Other:
- `bundle exec rake native:build`
- `bundle exec rake native:check`
- `bundle exec rake web:build`
- `bundle exec rake web:generate`
- `bundle exec rake web:start`

Do not document or introduce non-existent tasks like `rake hdl:*`, `rake diagrams:*`, or `rake generate_all`.

## Repository Structure (Practical)

- `lib/rhdl/`: core library and shared CLI task classes
- `examples/`: runnable systems and utilities
  - `examples/apple2/`
  - `examples/mos6502/`
  - `examples/gameboy/`
  - `examples/riscv/`
- `spec/`: tests, generally mirroring implementation paths
- `docs/`: user docs
- `web/`: browser simulator app

## Documentation Source of Truth

- RISC-V + xv6 docs live in `docs/riscv.md` (not a separate redirect page).
- Web architecture docs are part of `docs/web_simulator.md` under:
  - `## Web App Architecture`
- Keep README links aligned with those locations.

When changing user-facing behavior:
1. Update `README.md` (top-level usage/docs links).
2. Update relevant document in `docs/`.
3. Update CLI `--help` text if command semantics changed.

## Coding Guidelines for Agents

1. Prefer minimal, targeted changes.
2. Keep CLI task logic in shared task classes where applicable:
   - `lib/rhdl/cli/tasks/*.rb`
3. Keep example-runner behavior in example utilities:
   - `examples/<system>/utilities/tasks/*`
   - `examples/<system>/utilities/runners/*`
4. Add/update tests alongside code changes.
5. Mirror source/test paths where possible.
6. Avoid introducing stale docs or command aliases that are not implemented.

## Testing Expectations

Before finishing a change, run the smallest relevant test set first, then broaden as needed.

Examples:
- RISC-V runner/task changes:
  - `bundle exec rspec spec/examples/riscv/utilities/tasks/run_task_spec.rb`
- CLI task changes:
  - `bundle exec rspec spec/rhdl/cli/tasks/<task>_spec.rb`
- broader confidence:
  - `bundle exec rake spec:riscv`
  - `bundle exec rake spec`

If a native backend is unavailable (for example IR compiler extension), tests should fail clearly or be conditionally skipped with explicit reason.

## Common Pitfalls to Avoid

- Do not assume docs are current; verify command names in `exe/rhdl` and `Rakefile`.
- Do not introduce or keep broken README/doc links.
- Do not force raw terminal mode behavior unless explicitly intended.
- For interactive runners, ensure `Ctrl+C` handling and mode toggles work in normal terminal usage.

## Quick Validation Checklist

For CLI/doc changes:
1. `rhdl <command> --help` text matches behavior.
2. README command snippets are executable as written.
3. `rg` shows no stale links/references after doc moves.

For runner changes:
1. Headless mode still works.
2. Interactive controls still work (`Ctrl+C`, escape/command mode).
3. Debug output path is visible when debug mode is enabled.
