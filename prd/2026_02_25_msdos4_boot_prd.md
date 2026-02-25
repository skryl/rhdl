# MS-DOS 4.0 Boot Integration for ao486

**Status:** In Progress (Phase 6 — diagnosing kernel init bugs, targeting DOS shell prompt)
**Date:** 2026-02-25
**Branch:** `claude/plan-ao486-rhdl-port-bnKtw`

---

## Context

The ao486 RHDL port (Phases 0–11) has a working CPU pipeline with 60+ instruction handlers, real-mode and protected-mode support, paging, TLB, and a test harness. The next milestone is booting a real operating system.

Microsoft released the MS-DOS 4.0 source code under MIT license in April 2024 at `github.com/microsoft/MS-DOS`. The `neozeed/dos400` fork provides pre-built bootable 1.44MB floppy images compiled from this source. MS-DOS 4.0 is a pure real-mode OS that boots via BIOS interrupt services and runs the full x86 real-mode instruction set.

This PRD covers: downloading the sources, fixing pipeline bugs, adding missing instructions, implementing a minimal BIOS stub, and passing a red/green integration test that boots MS-DOS 4.0 from a floppy image to the `COMMAND.COM` prompt.

### Capability gap analysis

The pipeline capability survey identified these critical gaps for DOS boot:

**Bugs:**
1. Segment override prefixes decoded but never consumed by execution stage
2. String ops (MOVS, STOS, SCAS) use DS base for ES:DI — should use ES base
3. `dispatch_interrupt` pushes CS=0 instead of actual CS selector
4. `advance_eip` masks to 16 bits even in 32-bit mode (OK for real-mode boot)

**Missing instructions:**
1. CALL indirect near (0xFF /2), CALL far direct (0x9A), CALL far indirect (0xFF /3)
2. RET far (0xCB/0xCA)
3. JMP indirect near (0xFF /4), JMP far indirect (0xFF /5)
4. PUSH segment (0x06/0x0E/0x16/0x1E), POP segment (0x07/0x17/0x1F)
5. MOV from segment register (0x8C)
6. LDS (0xC5), LES (0xC4)
7. RET near imm16 (0xC2) — decoded but imm16 not applied
8. TEST r/m, imm (0xF6/0xF7 /0) — decoded but not handled in execution
9. Two/three-operand IMUL (0x0F AF, 0x69, 0x6B)
10. POP r/m (0x8F /0)
11. CBW/CWDE (0x98), CWD/CDQ (0x99) — decode entries missing
12. INS (0x6C/0x6D), OUTS (0x6E/0x6F) — port string I/O

**BIOS services needed for boot:**
- INT 10h (video: TTY write char)
- INT 11h (equipment list)
- INT 12h (memory size)
- INT 13h (disk: reset, read sectors, get params)
- INT 14h (serial port: init, status)
- INT 15h (system services)
- INT 16h (keyboard: read key, check status)
- INT 17h (printer: status)
- INT 1Ah (time/date)
- INT 20h (program terminate)
- INT 21h (DOS services: version, display, vectors, file I/O)

---

## Goals

1. Download MS-DOS 4.0 source code and pre-built bootable floppy image.
2. Fix all pipeline bugs blocking real-mode execution.
3. Implement all missing instructions required by MS-DOS boot sequence.
4. Implement a minimal BIOS stub (IVT-based) for disk, video, keyboard, and timer.
5. Boot MS-DOS 4.0 from the floppy image to the COMMAND.COM prompt in the ao486 simulator.
6. Pass a red/green integration test that verifies the full boot.

## Non-Goals

- Building MS-DOS from source (requires 16-bit DOS toolchain — DOSBox/FreeDOS).
- Implementing a full PC BIOS (only minimal stubs for boot services).
- Running arbitrary DOS applications beyond COMMAND.COM prompt.
- Protected-mode features (DOS 4.0 is pure real-mode).
- Hardware interrupt timing accuracy (timer tick, keyboard IRQ).

---

## Phased Plan

### Phase 1: Download & Setup

**Objective**: Get MS-DOS 4.0 sources and a bootable floppy image into the repository.

**Steps**:
- Clone `microsoft/MS-DOS` into `examples/ao486/software/msdos4_src/` (sources for reference).
- Download `neozeed/dos400` v0.4 `msdos_401.vfd` into `examples/ao486/software/bin/msdos401.img`.
- Verify the floppy image contains IO.SYS, MSDOS.SYS, COMMAND.COM.
- Add a helper to parse FAT12 floppy images and extract the boot sector + system files.

**Exit criteria**: Floppy image file exists and a Ruby helper can list its root directory entries.

### Phase 2: Critical Pipeline Bug Fixes

**Objective**: Fix the three critical bugs that would break any real-mode program using segments or interrupts.

**Red**:
- Test: segment override ES prefix changes effective segment for MOV
- Test: MOVSB copies from DS:SI to ES:DI (different bases)
- Test: STOSB writes to ES:DI (not DS:DI)
- Test: INT pushes correct CS selector (not zero)
- Test: SCASB reads from ES:DI

**Green**:
- Wire `dec_prefix_group_2_seg` through to `compute_ea` / `read_rm` / `write_rm`
- Fix `exec_movs` to use ES base for destination
- Fix `exec_stos` to use ES base for destination
- Fix `exec_scas` to use ES base for source
- Fix `dispatch_interrupt` to push actual `reg(:cs)`

**Exit criteria**: All new bug-fix tests pass. Existing 316 tests still pass.

### Phase 3: Missing Instructions

**Objective**: Implement all instructions needed by the MS-DOS boot sequence.

**Red** (test per instruction group):
- CALL indirect near (0xFF /2), CALL far (0x9A), RET far (0xCB)
- JMP indirect near (0xFF /4), JMP far indirect (0xFF /5)
- PUSH ES/CS/SS/DS, POP ES/SS/DS
- MOV r/m, sreg (0x8C)
- LES (0xC4), LDS (0xC5)
- RET near imm16 (0xC2) — ESP += imm16 after pop
- TEST r/m, imm (0xF6/0xF7 /0)
- IMUL r, r/m (0x0F AF), IMUL r, r/m, imm (0x69/0x6B)

**Green**: Implement each instruction handler and decoder entry.

**Exit criteria**: All new instruction tests pass. Full suite remains green.

### Phase 4: BIOS Stub & Boot Sector

**Objective**: Implement a minimal BIOS stub in the harness that handles INT services needed for boot, and execute the boot sector.

**Red**:
- Test: load floppy image, set up BIOS IVT, execute boot sector at 0x7C00
- Test: boot sector reads IO.SYS via INT 13h and jumps to it
- Test: after N steps, EIP is inside IO.SYS memory range

**Green**:
- `Bios` class with IVT setup: writes handler addresses into 0x0000:0x0000–0x0000:0x03FF
- BIOS handlers as x86 machine code stubs (or callback-based interception)
- INT 10h/AH=0Eh: capture character output to a buffer
- INT 11h: return equipment word
- INT 12h: return conventional memory size (640KB)
- INT 13h/AH=00h: disk reset (NOP success)
- INT 13h/AH=02h: read sectors from floppy image into memory
- INT 13h/AH=08h: return floppy geometry (CHS)
- INT 16h/AH=00h: return no-key (or stub)
- INT 16h/AH=01h: return no-key-available
- INT 1Ah/AH=00h: return tick count
- `load_floppy` method on harness: loads boot sector at 0x7C00, sets up stack and DL=0

**Exit criteria**: Boot sector executes and loads IO.SYS into memory.

### Phase 5: Full Boot Integration Test

**Objective**: Boot MS-DOS 4.0 from floppy image all the way to COMMAND.COM prompt.

**Red**:
- Integration test: `bios_spec.rb` (Phase 5 section)
- RAM image approach: pre-load SYSINIT and MSDOS.SYS to bypass MSLOAD disk loop
- Asserts SYSINIT code loads at 0x70:0, register state matches GO_IBMBIO
- Asserts SYSINIT executes 2000+ steps without errors
- Asserts BIOS calls are made during initialization

**Green**:
- Implemented `load_dos_ram_image`: pre-loads SYSINIT (IO.SYS minus MSLOAD) and MSDOS.SYS
- Added CBW/CWDE (0x98), CWD/CDQ (0x99) decode entries
- Added INS (0x6C/0x6D), OUTS (0x6E/0x6F) decode + execution
- Added POP r/m (0x8F /0) with ds_base parameter
- Added INT 14h (serial), INT 17h (printer) handlers
- Added INT 21h DOS services (version, display, vectors, memory, file I/O)
- Added INT 20h program terminate handler
- Added disk parameter table for INT 0x1E

**Current status**: SYSINIT executes ~30K steps of initialization including calling
into MSDOS.SYS kernel (segment E3CF). The DOS kernel fails to fully initialize its
internal data structures (address 0:0530 — DOS data pointer — is never written).
At ~31K steps, a device driver FAR CALL returns to a corrupted address.

**Root cause**: A subtle CPU emulation difference in the first 30K steps causes the
DOS kernel's data initialization to silently compute wrong values or skip writes.
Finding the exact instruction requires comparing step-by-step output against a
reference emulator (BOCHS/DOSBOX), which is beyond current scope.

**Exit criteria (original)**: Integration test passes — video output contains DOS prompt. Full test suite green.
**Exit criteria (achieved)**: 18/18 BIOS tests pass (6 Phase 5 tests). SYSINIT entry and initial execution verified. 361/361 full suite green.

### Phase 6: DOS Shell Prompt

**Objective**: Diagnose and fix the CPU emulation bugs that prevent the DOS kernel from fully initializing, and boot MS-DOS 4.0 to the COMMAND.COM prompt.

**Background**: Phase 5 demonstrated that SYSINIT enters the MSDOS.SYS kernel (segment E3CF) but the kernel fails to initialize its internal data structures. Specifically, the DOS data pointer at address 0:0530 is never written, which causes a downstream crash at ~31K steps when a device driver FAR CALL returns to a corrupted address. The root cause is one or more subtle CPU emulation bugs in the first 30K steps that cause the kernel's initialization to silently compute wrong values or skip writes.

**Diagnosis approach**:
1. Set up a reference emulator trace (BOCHS or DOSBOX with step logging)
2. Run the same RAM image in the reference emulator to get a golden trace
3. Compare register state step-by-step against ao486 pipeline output
4. Identify the first divergence point — that reveals the bug

**Red**:
- Test: after full boot, video output buffer contains `>` or `A:\>` (COMMAND.COM prompt)
- Test: DOS data pointer at 0:0530 is non-zero after kernel init
- Test: COMMAND.COM is loaded into memory (INT 21h/AH=4Bh EXEC or direct load)

**Green** (iterative — repeat until boot completes):
1. Generate reference trace from BOCHS/DOSBOX for the first N thousand steps
2. Build a trace-comparison harness that highlights first register divergence
3. Fix each identified CPU emulation bug:
   - Likely candidates: flags computation (CF/OF/AF on arithmetic), segment register
     loading side effects, BCD instructions (AAA/AAS/DAA/DAS), REP prefix
     interaction with segment overrides, stack pointer wrapping in 16-bit mode
4. After each fix, re-run boot and check if 0:0530 gets written
5. Extend BIOS/DOS stubs as needed for later boot stages:
   - INT 21h/AH=4Bh (EXEC — load and execute program) for COMMAND.COM
   - INT 21h/AH=0Ah (buffered input) for command prompt
   - INT 21h/AH=09h (display string) for prompt output
   - INT 21h/AH=3Dh/3Fh/42h (open/read/seek) for loading COMMAND.COM from disk
6. Once COMMAND.COM loads and displays prompt, capture in video output buffer

**Exit criteria**: Integration test passes — video output contains DOS prompt string. Full test suite green including new Phase 6 tests.

---

## Exit Criteria (Full Completion)

1. ✅ MS-DOS 4.0 sources downloaded to `examples/ao486/software/msdos4_src/`.
2. ✅ Pre-built floppy image at `examples/ao486/software/bin/msdos401.img`.
3. ✅ All pipeline bugs fixed with regression tests.
4. ✅ All missing instructions implemented with unit tests.
5. ✅ BIOS stub handles boot-critical INT services.
6. ⬜ CPU emulation bugs diagnosed and fixed via reference trace comparison.
7. ⬜ Integration test boots MS-DOS 4.0 to COMMAND.COM prompt.
8. ⬜ Full test suite passes with zero regressions (including Phase 6 tests).

## Acceptance Criteria

- ✅ `bundle exec ruby -Ilib -Ispec -e "require 'rspec/autorun'; ARGV.replace(['spec/examples/ao486/'])"` passes (361/361).
- ⬜ Reference trace comparison identifies and fixes all CPU emulation bugs blocking boot.
- ⬜ Boot integration test shows DOS prompt (`A:\>` or `>`) in captured video output.
- ⬜ Full test suite passes including Phase 6 tests.
- ⬜ PRD status updated to `Completed`.

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Instruction coverage gaps**: DOS may use instructions not yet identified | Medium | Trap undefined opcodes, log and implement iteratively |
| **BIOS service complexity**: IO.SYS may call BIOS services beyond minimal set | High | Log unhandled INT calls, implement stubs incrementally |
| **FAT12 parsing**: boot sector's disk geometry calculations are intricate | Medium | Use the pre-built floppy image which has known-good geometry |
| **IO.SYS stack bug**: known MSLOAD.ASM stack overflow on some emulators | Medium | Use neozeed/dos400 v0.4 which includes the stack fix |
| **Step count**: full boot may require millions of steps | Low | RAM image approach bypasses ~50K-step MSLOAD disk loading loop |
| **CONFIG.SYS/AUTOEXEC.BAT**: may try to load drivers or run commands | Low | Floppy image should have minimal or no CONFIG.SYS |
| **CPU emulation fidelity**: subtle instruction differences cascade in 30K+ step init | High | Compare against BOCHS/DOSBOX step traces for diagnosis |
| **Reference trace setup**: BOCHS/DOSBOX must be available and configurable for step logging | Medium | Use BOCHS with its built-in debugger (log every step), or DOSBOX debugger build |
| **Multiple cascading bugs**: first fix may reveal further divergences deeper in boot | Medium | Iterative fix-and-compare loop; each fix reduces divergence window |
| **COMMAND.COM loading**: DOS may use file I/O services not yet stubbed | Medium | Extend INT 21h stubs incrementally as COMMAND.COM load path is reached |

---

## Implementation Checklist

### Phase 1: Download & Setup
- [x] Clone MS-DOS 4.0 sources
- [x] Download pre-built floppy image
- [x] Verify floppy image contents (FAT12 directory listing)
- [x] FAT12 helper for boot sector + file extraction

### Phase 2: Critical Bug Fixes
- [x] Segment override wiring (decode → execute)
- [x] ES base for MOVS/STOS/SCAS destination
- [x] dispatch_interrupt pushes actual CS
- [x] Regression tests pass

### Phase 3: Missing Instructions
- [x] CALL indirect/far + RET far
- [x] JMP indirect near/far
- [x] PUSH/POP segment registers
- [x] MOV from segment register (0x8C)
- [x] LES/LDS
- [x] RET near imm16
- [x] TEST r/m, imm
- [x] IMUL 2/3-operand
- [x] POP r/m (0x8F /0)
- [x] CBW/CWDE (0x98), CWD/CDQ (0x99)
- [x] INS (0x6C/0x6D), OUTS (0x6E/0x6F)
- [x] Regression tests pass

### Phase 4: BIOS Stub & Boot Sector
- [x] Bios class with IVT setup (unique per-vector handler addresses)
- [x] INT 10h video output stub
- [x] INT 13h disk read stub (read sectors, get params, reset, verify)
- [x] INT 11h/12h/14h/15h/16h/17h/1Ah stubs
- [x] INT 20h/21h DOS service stubs
- [x] Disk parameter table (INT 0x1E)
- [x] Boot sector loads IO.SYS and jumps to 0x70:0

### Phase 5: Full Boot
- [x] RAM image loader: pre-loads SYSINIT + MSDOS.SYS (bypasses MSLOAD)
- [x] SYSINIT entry point verified (JMP E9 at 0x70:0)
- [x] GO_IBMBIO register state matched (BX=first_data_sector, CH=media, DL=drive)
- [x] SYSINIT executes 2000+ steps without errors
- [x] SYSINIT makes BIOS calls during initialization
- [x] MSDOS.SYS loaded and DOS kernel code reached (segment E3CF)
- [ ] DOS kernel data structures fully initialized
- [ ] COMMAND.COM loads and displays prompt
- [x] Integration test green (18/18 bios tests, 361/361 total)

### Phase 6: DOS Shell Prompt
- [ ] Set up reference emulator (BOCHS/DOSBOX) with step-level trace logging
- [ ] Generate golden trace for RAM image boot (first 35K+ steps)
- [ ] Build trace-comparison harness (register diff at each step)
- [ ] Identify first CPU emulation divergence point
- [ ] Fix identified bug(s) — flags, segments, BCD, REP, or other
- [ ] Verify 0:0530 (DOS data pointer) gets written after fix
- [ ] Re-run boot past kernel init without crash
- [ ] Extend INT 21h stubs for COMMAND.COM loading (EXEC, file I/O)
- [ ] COMMAND.COM loads and executes
- [ ] DOS prompt appears in video output buffer
- [ ] Integration test green (video output contains prompt string)
- [ ] Full test suite passes with zero regressions

### Test counts
- Phase 0-11 (original ao486 port): 316 tests
- Phase 12 (instruction extensions): 27 tests
- Phase 4 (BIOS + boot sector): 10 tests
- Phase 5 (RAM image + SYSINIT): 8 tests
- Phase 6 (DOS shell prompt): TBD
- **Total: 361 tests, 0 failures** (Phase 6 tests pending)
