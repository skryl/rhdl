# Agent Guide for `rhdl`

This file is the working guide for coding agents in this repository.
`CLAUDE.md` is a symlink to this file.

## Default Process

1. Understand the request and constraints.
2. Find existing design docs (`prd/`, issue notes, prior PRDs) before creating new ones.
3. Use phased planning plus red/green testing for implementation.
4. Ship incrementally and keep status/checklists current.

## PRD Process

### When To Use A PRD

Create or update a PRD when work involves one or more of:

1. Multiple phases or milestones.
2. Cross-cutting changes across subsystems.
3. Non-obvious tradeoffs, risk, or unclear scope.
4. New test strategy, migration, or rollout criteria.

For very small, single-file fixes, a brief in-message plan is enough.

### Where To Put It

1. Store in `prd/`.
2. Use naming: `YYYY_MM_DD_<topic>_prd.md` (or `_prd.md` when explicitly requested).

### Required Sections

1. Status (`Proposed`, `In Progress`, `Completed` + date when completed).
2. Context.
3. Goals and non-goals.
4. Phased plan with clear red/green steps.
5. Exit criteria per phase.
6. Acceptance criteria for full completion.
7. Risks and mitigations.
8. Implementation checklist with phase checkboxes.

## Red/Green Execution Rules

For each phase:

1. **Red**
   - Add failing tests or a failing reproducible check first.
   - Capture the baseline failure signal.
2. **Green**
   - Implement the minimum change set needed to pass the new tests.
   - Re-run targeted tests and immediate regression checks.
3. **Refactor**
   - Refactor only after green.
   - Keep behavior unchanged during refactor.

Do not mark a phase complete until its exit criteria are met.

## Testing Gates

Run gates from specific to broad:

1. Unit/op-level tests for changed behavior.
2. Integration tests across touched boundaries.
3. End-to-end/runtime parity checks where relevant.
4. CI-facing or task-level command checks (rake tasks, linters, smoke scripts) for touched workflows.

If a gate cannot run locally, document exactly what was not run and why.

## Completion Criteria

Treat work as complete only when all are true:

1. Phase checklist items are updated.
2. New/updated tests are green.
3. Regressions in touched areas are checked.
4. PRD status reflects reality (`Completed` only when fully done).


## Project Summary

RHDL is a Ruby HDL toolkit with:
- DSL-based hardware component definitions
- multiple simulation backends (Ruby, IR interpreter/JIT/compiler, netlist, Verilator flows)
- CLI tooling for diagrams, exports, synthesis, and example system runners
- example systems: MOS6502, Apple II, Game Boy, and RISC-V (including xv6 workflows)
- web simulator (WASM + browser UI)
- desktop app (Electrobun wrapper for the web simulator)

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
- `bundle exec rake spec[lib]`
- `bundle exec rake spec[hdl]`
- `bundle exec rake spec[ao486]`
- `bundle exec rake spec[gameboy]`
- `bundle exec rake spec[mos6502]`
- `bundle exec rake spec[apple2]`
- `bundle exec rake spec[riscv]`
- `bundle exec rake spec[sparc64]`

Parallel:
- `bundle exec rake pspec`
- `bundle exec rake pspec[lib]`
- `bundle exec rake pspec[hdl]`
- `bundle exec rake pspec[ao486]`
- `bundle exec rake pspec[gameboy]`
- `bundle exec rake pspec[mos6502]`
- `bundle exec rake pspec[apple2]`
- `bundle exec rake pspec[riscv]`
- `bundle exec rake pspec[sparc64]`

Spec benchmarks:
- `bundle exec rake spec:bench[all,20]`
- `bundle exec rake spec:bench[gameboy,20]`
- `bundle exec rake spec:bench[riscv,20]`

Simulation benchmarks:
- `bundle exec rake bench`
- `bundle exec rake bench[mos6502,5000000]`
- `bundle exec rake bench[apple2,5000000]`
- `bundle exec rake bench[gameboy,1000]`
- `bundle exec rake bench[ir,5000000]`
- `bundle exec rake bench:web[apple2,5000000]`
- `bundle exec rake bench:web[riscv,100000]`

Other:
- `bundle exec rake native:build`
- `bundle exec rake native:check`
- `bundle exec rake web:build`
- `bundle exec rake web:bundle`
- `bundle exec rake web:bundle:prod`
- `bundle exec rake web:generate`
- `bundle exec rake web:start`

Desktop (Electrobun):
- `bundle exec rake desktop:install`
- `bundle exec rake desktop:dev`
- `bundle exec rake desktop:build`
- `bundle exec rake desktop:release`
- `bundle exec rake desktop:clean`

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
- `web/`: browser simulator app (TypeScript, bundled with Bun)
  - `web/app/`: application source (`.ts` files)
  - `web/test/`: tests (`bun test`)
  - `web/build.ts`: Bun build script
  - `web/dist/`: bundled output (gitignored)
  - `web/desktop/`: Electrobun desktop app wrapper

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
If test dependencies are missing, install or build them before running the affected tests.

Examples:
- RISC-V runner/task changes:
  - `bundle exec rspec spec/examples/riscv/utilities/tasks/run_task_spec.rb`
- CLI task changes:
  - `bundle exec rspec spec/rhdl/cli/tasks/<task>_spec.rb`
- broader confidence:
  - `bundle exec rake spec[riscv]`
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
