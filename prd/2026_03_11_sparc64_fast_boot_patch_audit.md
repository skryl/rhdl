# SPARC64 Fast-Boot Patch Audit

## Status

In Progress - 2026-03-11

## Context

The SPARC64 fast-boot path currently relies on a patch series under:

- `examples/sparc64/patches/fast_boot`

The goal of this audit is to separate:

1. actual importer/staging bugs that should be fixed in `SystemImporter`
2. structured staging/debug transforms that could move out of raw patch files
3. true fast-boot behavioral overrides that are not importer bugs

## Findings

### Importer Bugs Already Fixed Upstream

- No remaining numbered fast-boot patch is a pure importer bug that should simply disappear as-is.
- The declaration/staging fragility around `fast_boot_prom_ifill` in `os2wb.v` and `os2wb_dual.v` has already been fixed in `SystemImporter`:
  - `strip_hoisted_os2wb_declarations`
  - `ensure_fast_boot_prom_ifill_defined`
- The staged-bundle closure now carries `bw_r_irf_register.v` as a real source instead of letting it fall behind hierarchy stubs; this is covered in `spec/examples/sparc64/runners/staged_verilog_bundle_spec.rb`.
- The duplicate-top / duplicate-basename staging issue is already fixed in the importer path and is not tied to a remaining fast-boot patch file.
- Two former raw patch-file transforms now live directly in SPARC64 staging normalization:
  - former `0006-fast-boot-imiss-ack.patch`
  - former `0017-fast-boot-irf-register-public-flat.patch`

### Patch Classification

#### Behavioral Fast-Boot Overrides

- `0001-os2wb-fast-boot-shim.patch`
  - IFU startup timing, LSU stall bypass, and `os2wb*` bridge memory knobs.
  - This is harness behavior, not importer correctness.
- `0004-fast-boot-reset-vector.patch`
  - Hard overrides reset trap PC/NPC/TID in `sparc.v`.
  - Behavioral reset redirection.
- `0005-fast-boot-nextpc.patch`
  - Forces early IFU PC / next-PC behavior in `sparc_ifu_fdp.v`.
  - Behavioral fetch redirection.
- `0007-fast-boot-suppress-wakeup-cpx.patch`
  - Changes `os2wb_dual.v` WAKEUP behavior.
  - Behavioral bridge override.
- `0008-fast-boot-boot-prom-ifill.patch`
  - Main body reclassifies low-address IFILL traffic in `os2wb*`.
  - Behavioral bridge override.
  - Note: the declaration-hoist fragility this patch exposed is already fixed in `SystemImporter`.
- `0009-fast-boot-itlb-paddr.patch`
  - Forces PROM/DRAM fetch-window ITLB and icache behavior in `sparc_ifu.v`.
  - Behavioral fetch-path override.
- `0010-fast-boot-thread0-scheduler.patch`
  - Forces thread-0 grant on reset startup in `sparc_ifu_swl.v`.
  - Behavioral scheduling override.
- `0012-fast-boot-thread0-agp.patch`
  - Forces `agp_tid_g` to thread 0 in `tlu_tcl.v`.
  - Behavioral AGP/thread override.
- `0013-fast-boot-thread0-agp-window.patch`
  - Forces `tlu_exu_agp` / `tlu_exu_agp_tid` to thread 0 in `sparc.v`.
  - Behavioral AGP/thread override.
- `0014-fast-boot-agp-reset-seed.patch`
  - Seeds `new_agp` to `2'b00` on reset in `sparc_exu_rml.v`.
  - Behavioral reset-state override.
- `0015-fast-boot-cached-ifill-way.patch`
  - Forces cached IFILL way selection in `os2wb*`.
  - Behavioral bridge/cache override.
- `0018-fast-boot-ifill-forward-mask.patch`
  - Changes `lsu_qctl2.v` IFILL-forward mask retirement behavior.
  - This may be a real RTL bug fix, but it is not an importer bug.
- `0019-fast-boot-dtlb-bypass.patch`
  - Forces low-address DTLB bypass in `lsu.v`.
  - Behavioral MMU override.

#### Migrated / Removed

- `0006-fast-boot-imiss-ack.patch`
  - Migrated into SPARC64 importer normalization for `lsu.v` / `lsu_qctl1.v`.
  - Raw patch file removed.
- `0017-fast-boot-irf-register-public-flat.patch`
  - Migrated into SPARC64 importer normalization for `bw_r_irf_register.v`.
  - Raw patch file removed.
- `0011-fast-boot-thread0-fcl-reset.patch`
  - Removed after re-check.
  - It was effectively stale scaffolding around a disabled override and only patch-fed extra debug fields.

## Recommended Follow-Up

### Keep Explicit As Behavioral Fast-Boot Overrides For Now

- `0001`
- `0004`
- `0005`
- `0007`
- `0008`
- `0009`
- `0010`
- `0012`
- `0013`
- `0014`
- `0015`
- `0018`
- `0019`

## Notes

- The earlier `0020-fast-boot-irf-write-enable-width.patch` was removed; it was a one-off patch-file detour and not an importer-level fix.
- The current raw fast-boot patch set is now narrower:
  - `0001`, `0004`, `0005`, `0007`, `0008`, `0009`, `0010`, `0012`, `0013`, `0014`, `0015`, `0018`, `0019`
- Current importer/staged-bundle coverage already pins:
  - real-source staging of `bw_r_irf_register.v`
  - importer-managed Verilator `public_flat_rw` IRF register annotations
  - importer-managed LSU `ifu_lsu_pcxpkt_e_b49` threading
  - `fast_boot_prom_ifill` declaration normalization
  - absence of `bw_r_irf_register` from generated hierarchy stubs
