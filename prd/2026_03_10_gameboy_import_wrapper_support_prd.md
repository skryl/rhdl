# Game Boy Import Wrapper Support PRD

Status: Completed - 2026-03-10

## Context

The generated Game Boy import wrapper currently sits directly on top of imported `gb` and relies on the runner to drive `ce`, `ce_n`, and `ce_2x`.

The reference implementation routes `gb` through wrapper-level support modules, notably `speedcontrol`. We want the import flow and generated wrapper to bring that module into the imported tree and use it in the wrapper instead of approximating that behavior in the runner.

## Goals

- Import wrapper-support modules needed by the generated Game Boy wrapper.
- Use imported `speedcontrol` in the generated wrapper so clock enables are generated inside the imported tree.
- Keep the runnable top as the generated `Gameboy` wrapper.

## Non-Goals

- Switching the import root from `gb` to the full MiSTer `emu` top.
- Pulling the full MiSTer platform shell into the runnable wrapper.
- Completing full SGB border/video fidelity in this pass.
- Importing `sgb` in this pass.

## Phased Plan

### Phase 1: Import `speedcontrol`

Red:
- Add importer expectations that `speedcontrol` is included in the mixed import manifest/report.

Green:
- Extend VHDL synth target configuration so `speedcontrol` is available in the import output.

Exit criteria:
- Import reports/components expose imported `speedcontrol`.

### Phase 2: Generate `speedcontrol`-Backed Wrapper

Red:
- Add wrapper generation tests that fail until the wrapper instantiates imported `speedcontrol`.

Green:
- Update generated Ruby/Verilog wrapper generation to use imported `speedcontrol` when present.

Exit criteria:
- Generated wrapper no longer requires external `ce`, `ce_n`, or `ce_2x` inputs when imported `speedcontrol` is available.

### Phase 3: Runner Integration

Red:
- Add/update runner tests for direct-Verilog wrapper compilation inputs and port expectations.

Green:
- Update direct-Verilog and HDL-backed runner assumptions to match the new wrapper contract.

Exit criteria:
- Import-backed Verilator flows resolve the generated wrapper without externally driving wrapper-level clock-enable inputs.

## Acceptance Criteria

- A fresh Game Boy import includes imported `speedcontrol`.
- The generated wrapper instantiates imported `speedcontrol` when that module is available.
- Relevant importer and runner specs pass.

## Risks And Mitigations

- VHDL-synthesized `speedcontrol` naming may be hashed or rewritten.
  Mitigation: resolve support component names from the import report instead of hardcoding them.

## Checklist

- [x] Phase 1 importer support landed
- [x] Phase 2 wrapper generation landed
- [x] Phase 3 runner/test updates landed
