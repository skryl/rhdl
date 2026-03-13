# AO486 Import Patch Directory PRD

## Status
Completed 2026-03-09

## Context
AO486 import flows currently read directly from the checked-in reference RTL tree and have no built-in way to apply a staged patch series before import. That makes it awkward to test or gate importer work that depends on small RTL deltas while keeping the source tree untouched.

## Goals
1. Add a checked-in `examples/ao486/patches/` directory for AO486 import patch series.
2. Add an importer option that applies all patches from a given directory before import.
3. Apply patches only to a staged workspace copy, never to the checked-in reference tree.
4. Keep the feature available to both `SystemImporter` and `CpuImporter`.

## Non-Goals
1. Automatically applying AO486 patches by default.
2. Changing AO486 reference RTL in this PRD.
3. Adding non-AO486 generic importer patch support outside the AO486 importers.

## Phased Plan
### Phase 1: Importer Staging Support
Red:
1. Add failing focused specs for staged patch application and source isolation.
2. Confirm current importers cannot consume a patch directory.

Green:
1. Add `patches_dir:` to AO486 importers.
2. Stage a copy of the AO486 source tree in the workspace when patches are requested.
3. Apply patch files in deterministic filename order before import.
4. Ensure subsequent import staging uses the patched workspace tree.

Refactor:
1. Keep patch staging logic shared in `SystemImporter` with minimal `CpuImporter` overrides.

Exit Criteria:
1. Both importers accept `patches_dir:`.
2. Patches are applied to the staged copy only.
3. Focused importer specs are green.

## Acceptance Criteria
1. `examples/ao486/patches/` exists in the repo.
2. `SystemImporter` and `CpuImporter` accept a patch-directory option.
3. Patch files are applied deterministically before import.
4. The checked-in AO486 reference tree is not modified during importer runs.

## Risks and Mitigations
1. Risk: patch application changes existing import behavior unintentionally.
   Mitigation: keep the option opt-in and default to no patches.
2. Risk: patch paths resolve against the wrong root.
   Mitigation: apply patches against the staged AO486 source-search root used by the importer.
3. Risk: retries or fallback strategies reapply patches inconsistently.
   Mitigation: prepare one staged patched tree per importer run and reuse it.

## Implementation Checklist
- [x] Add focused failing specs for patch-directory support.
- [x] Add staged patch application support to `SystemImporter`.
- [x] Thread patch-directory support through `CpuImporter`.
- [x] Add `examples/ao486/patches/`.
- [x] Run focused AO486 importer specs.
- [x] Mark PRD complete when validation is green.

## Validation
1. `bundle exec rspec spec/examples/ao486/import/system_importer_spec.rb`
   - result: `12 examples, 0 failures`
2. `bundle exec rspec spec/examples/ao486/import/cpu_importer_spec.rb`
   - result: `4 examples, 0 failures`
3. `bundle exec rspec spec/examples/ao486/import/cpu_trace_package_spec.rb`
   - result: `3 examples, 0 failures`

## Update 2026-03-09
1. The importer-side `patches_dir:` support remains available for ad hoc staged patch series.
2. The checked-in `examples/ao486/patches/` directory was removed after the unpatched Arcilator/import flow became the standard path.
3. Callers that still need staged RTL deltas should supply their own patch directory explicitly.
