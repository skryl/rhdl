# xv6 Readiness Phases (CPU + Pipelined CPU)

This checklist is intentionally scoped to a fully-completable milestone in this iteration.

## Phase 1 - Red: Privileged Compatibility Specs

- [x] Add spec coverage for `wfi` non-trapping no-op behavior on single-cycle `cpu`.
- [x] Add spec coverage for `wfi` non-trapping no-op behavior on `pipelined_cpu`.
- [x] Add spec coverage for `sfence.vma` non-trapping no-op behavior on single-cycle `cpu`.
- [x] Add spec coverage for `sfence.vma` non-trapping no-op behavior on `pipelined_cpu`.
- [x] Add spec coverage for `mip`/`sip` CSR read behavior on single-cycle `cpu`.
- [x] Add spec coverage for `mip`/`sip` CSR read behavior on `pipelined_cpu`.
- [x] Add differential parity coverage for these flows.

## Phase 2 - Green: Hardware Implementation

- [x] Implement `wfi` decode/execute path as legal no-op in single-cycle `cpu`.
- [x] Implement `wfi` decode/execute path as legal no-op in `pipelined_cpu`.
- [x] Implement `sfence.vma` decode/execute path as legal no-op in single-cycle `cpu`.
- [x] Implement `sfence.vma` decode/execute path as legal no-op in `pipelined_cpu`.
- [x] Implement hardware-backed `mip` read behavior in single-cycle `cpu`.
- [x] Implement hardware-backed `mip` read behavior in `pipelined_cpu`.
- [x] Implement hardware-backed `sip` read behavior (delegated pending bits) in single-cycle `cpu`.
- [x] Implement hardware-backed `sip` read behavior (delegated pending bits) in `pipelined_cpu`.
- [x] Add assembler encodings for `wfi` and `sfence.vma`.

## Phase 3 - Green+: Suite Validation

- [x] Run focused xv6-readiness specs on JIT backend.
- [x] Run full `spec/examples/riscv` suite on JIT backend.
- [x] Mark checklist complete.

## Phase 4 - RV32A Hardware (xv6 lock primitives)

- [x] Add red tests for LR/SC and AMO word operations on single-cycle `cpu`.
- [x] Add red tests for LR/SC and AMO word operations on `pipelined_cpu`.
- [x] Add differential parity coverage for RV32A sequences.
- [x] Add assembler encodings for `lr.w`, `sc.w`, and all RV32A word AMOs.
- [x] Implement hardware reservation-set tracking in single-cycle `cpu`.
- [x] Implement hardware reservation-set tracking in `pipelined_cpu`.
- [x] Implement AMO read-modify-write datapath in single-cycle `cpu`.
- [x] Implement AMO read-modify-write datapath in `pipelined_cpu`.
- [x] Validate full RISC-V suite on JIT backend.

## Phase 5 - Remaining Full xv6 Bring-up (pending)

- [x] Implement Sv32 page-table walk and address translation in hardware for instruction + data accesses.
- [x] Implement translation-fault traps (`mcause/scause` + `mtval/stval`) with correct privilege routing.
- [x] Add privileged-mode memory permission checks (U/S, R/W/X, SUM/MXR where applicable).
- [x] Add translation invalidation behavior tied to `sfence.vma`.
- [ ] Add xv6 boot integration test (kernel reaches scheduler/user init) on single-cycle `cpu`.
- [x] Keep `pipelined_cpu` at architectural parity via differential tests for each Sv32 milestone.
- [x] Implement and validate block-device path required for xv6 filesystem/runtime (virtio-blk or project-equivalent hardware device).
- [ ] Add end-to-end xv6 smoke tests (boot, console IO, process spawn, simple FS ops).

### Phase 5 progress (current iteration)

- [x] Implement Sv32 hardware page-walk + translation for **data accesses** (load/store path) on single-cycle `cpu`.
- [x] Implement Sv32 hardware page-walk + translation for **data accesses** (load/store path) on `pipelined_cpu`.
- [x] Implement load/store page-fault trap causes (`13`/`15`) with `mtval/stval` fault-VA writes and delegation routing.
- [x] Add red/green tests for mapped Sv32 load/store translation and unmapped load/store faults on both cores.
- [x] Add differential parity tests for Sv32 mapped data translation and load page-fault (`mcause`/`mtval`) behavior.
- [x] Extend Sv32 to instruction fetch translation + instruction page-fault (`12`) behavior.
- [x] Add red/green tests for mapped Sv32 instruction translation and unmapped instruction page-fault behavior on both cores.
- [x] Add differential parity tests for Sv32 instruction translation and instruction page-fault (`mcause`/`mtval`) behavior.
- [x] Add hardware privilege-mode tracking (`M/S/U`) across trap entry and `mret`/`sret` on both cores.
- [x] Enforce Sv32 PTE permission checks for instruction/data accesses (`U/S`, `R/W/X`, `SUM`, `MXR`) on both cores.
- [x] Add red/green tests for Sv32 permission behavior (S-mode execute of U page fault, SUM gating for U data pages, MXR load from X-only page).
- [x] Add differential parity tests for Sv32 permission-check milestones to keep pipeline parity.
- [x] Add hardware iTLB/dTLB cache path (direct-mapped) to both cores for Sv32 translation reuse.
- [x] Wire `sfence.vma` / `satp` write invalidation into both TLBs in both cores.
- [x] Add red/green tests for iTLB/dTLB cache persistence and `sfence.vma` invalidation.
- [x] Add differential parity tests for the TLB + invalidation milestone.
- [x] Add hardware `virtio-blk` MMIO peripheral with queue-state registers (`QUEUE_SEL/NUM/READY`, descriptor/driver/device addresses, status + interrupt ack).
- [x] Implement queued block request execution (`IN`/`OUT`) against backing disk storage using descriptor chains and used-ring completion.
- [x] Route `virtio-blk` interrupts through PLIC source 1 in both harness paths (`cpu` and `pipelined_cpu`).
- [x] Add red/green peripheral specs + IR harness MMIO specs + differential parity test for virtio MMIO register behavior.
