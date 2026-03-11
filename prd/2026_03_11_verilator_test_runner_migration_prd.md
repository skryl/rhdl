# Verilator Test Runner Migration PRD

## Status

In Progress - 2026-03-11

## Context

The SPARC64 test tree now runs real Verilator execution through the public
runner surface:

- `RHDL::Examples::SPARC64::HeadlessRunner`
- `RHDL::Examples::SPARC64::VerilatorRunner`

But this is not yet true repo-wide. A review of the current spec tree still
shows bespoke Verilator harness usage in several subsystems, especially import
parity tests that build ad hoc Verilator binaries or use custom runtime glue.

We want the test surface to converge on public runner APIs instead of custom
Verilator harnesses.

## Goals

1. Eliminate bespoke Verilator harnesses from example/system tests where a
   public runner abstraction should exist.
2. Route Verilator-backed tests through `HeadlessRunner` and/or
   `VerilatorRunner` style public APIs.
3. Keep unit seam tests for runner classes allowed when they do not create a
   custom Verilator binary path.

## Non-Goals

1. Rewriting every low-level compiler/verilator parity test in one shot.
2. Removing legitimate runner seam tests that use fake adapters for unit
   coverage.
3. Forcing cross-subsystem API convergence without first inventorying what the
   tests actually need from the harness.

## Current Inventory

### Clean In SPARC64

- `spec/examples/sparc64/runners/verilator_runner_smoke_spec.rb`
  now uses `RHDL::Examples::SPARC64::VerilatorRunner` directly.
- Remaining `adapter_factory` use in
  `spec/examples/sparc64/runners/verilator_runner_spec.rb`
  is a unit seam test, not a custom Verilator harness.

### Remaining Bespoke Verilator Harnesses

- AO486
  - `spec/examples/ao486/import/parity_spec.rb`
  - `spec/examples/ao486/import/runtime_cpu_fetch_parity_spec.rb`
  - `spec/examples/ao486/import/runtime_cpu_fetch_correctness_spec.rb`
  - `spec/examples/ao486/import/runtime_cpu_step_parity_spec.rb`
  - `spec/examples/ao486/import/runtime_cpu_arch_state_parity_spec.rb`
  - `spec/examples/ao486/import/cpu_parity_verilator_runtime_spec.rb`
  - These use `CpuParityVerilatorRuntime` and/or direct `verilator` command
    execution instead of a public headless/verilator runner.

- GameBoy
  - `spec/examples/gameboy/import/runtime_parity_3way_verilator_spec.rb`
  - `spec/examples/gameboy/import/runtime_parity_3way_spec.rb`
  - `spec/examples/gameboy/import/behavioral_ir_compiler_spec.rb`
  - These define `write_verilator_trace_harness`, `collect_verilator_trace`,
    and build ad hoc `verilator_obj` trees.

### Direct Runner Usage That May Need Policy Review

- MOS6502
  - `spec/examples/mos6502/integration/karateka_divergence_spec.rb`
  - Uses `VerilogRunner` directly, but not a custom Verilator compile path.

- Apple2 / GameBoy / RISCV
  - Several specs instantiate `VerilogRunner` directly.
  - These are not bespoke harnesses, but we may still want to standardize on
    `VerilatorRunner` naming or `HeadlessRunner` where appropriate.

## Phased Plan

### Phase 1: Inventory And Policy

#### Red

1. Audit the existing spec tree for bespoke Verilator harness patterns.
2. Separate true custom harnesses from acceptable public-runner usage.

#### Green

1. Record the inventory and target migration policy.
2. Treat SPARC64 as the first completed subsystem.

#### Exit Criteria

1. The repository has a current inventory of custom Verilator harness tests.
2. SPARC64 is confirmed clean on the public runner path.

### Phase 2: AO486 Migration

#### Red

1. Identify the exact APIs the AO486 parity tests need from
   `CpuParityVerilatorRuntime`.
2. Add/adjust runner-facing tests for the missing surface.

#### Green

1. Move AO486 Verilator-backed tests onto public runner/runtime APIs.
2. Remove direct custom harness usage from AO486 specs where the public path is
   sufficient.

#### Exit Criteria

1. AO486 import parity/correctness specs no longer build bespoke Verilator
   harnesses directly.

### Phase 3: GameBoy Migration

#### Red

1. Identify the trace/video/state APIs the GameBoy import parity tests need.
2. Add public-runner support for those outputs where missing.

#### Green

1. Replace ad hoc Verilator trace harnesses with runner-backed collection.
2. Remove custom `verilator_obj` build logic from the specs.

#### Exit Criteria

1. GameBoy import parity specs no longer own custom Verilator harness code.

### Phase 4: Naming / Direct-Runner Cleanup

#### Red

1. Inventory specs that still instantiate `VerilogRunner` directly when
   `HeadlessRunner` or `VerilatorRunner` is the intended public surface.

#### Green

1. Normalize direct construction where it improves consistency without harming
   unit seam coverage.

#### Exit Criteria

1. Public-facing Verilator test paths consistently use `HeadlessRunner` or
   `VerilatorRunner`.

## Acceptance Criteria

1. No example/system spec builds a bespoke Verilator harness when a public
   runner abstraction exists for that use case.
2. SPARC64 remains green on the public `VerilatorRunner` path.
3. The remaining migration work is tracked by subsystem instead of being hidden
   inside ad hoc test helpers.
