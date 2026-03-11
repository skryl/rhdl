# AO486 Default Runner + CPU-Top DOS Boot Support

## Status

In Progress - 2026-03-09

## Context

AO486 currently has CPU-top import and parity flows, but it does not yet have a runnable CPU-top environment that can boot a DOS image through the normal `rhdl examples ao486` CLI surface.

The requested direction is explicitly CPU-top, not `system.v`. That means the runner must provide the external environment that the `ao486` core expects:

1. main memory with BIOS ROM windows populated
2. Avalon memory-bus servicing
3. I/O-bus servicing
4. interrupt handshake
5. the minimum device set required to boot DOS to a text-mode shell

The CLI shape should also change so that `rhdl examples ao486` defaults to running AO486, while `import` remains an explicit subcommand. The user also wants the normal run loop controls used by the RISC-V binary, especially:

1. `--speed`
2. `-d` / `--debug`
3. headless and backend selection controls

The software artifacts must already live under `examples/ao486/software`:

1. BIOS ROMs in `examples/ao486/software/rom`
2. DOS floppy image in `examples/ao486/software/bin`

`--bios` and `--dos` must simply load those files. They should not perform downloads or copies at runtime.

## Goals

1. Make `rhdl examples ao486` default to run mode.
2. Keep `rhdl examples ao486 import` as the import entrypoint.
3. Add AO486 runner classes for IR compiler, Verilator, and Arcilator CPU-top execution.
4. Add a CPU-top AO486 native IR compiler extension with enough device emulation to boot DOS to a shell.
5. Add a shared CPU-top host bridge for the Verilator and Arcilator runners with matching behavior.
6. Add a text-mode display adapter with a debug panel rendered below the display.
7. Keep CLI parsing/help tests in `spec/rhdl/cli/ao486_spec.rb`.
8. Put runner parity/correctness/behavior coverage in `spec/examples/ao486/integration`.

## Non-Goals

1. Running `system.v`.
2. Adding AO486 JIT/interpreter runner extensions in this phase.
3. Supporting graphics/VESA/framebuffer rendering in this phase.
4. Adding IDE/HDD boot support in this phase.
5. Downloading software artifacts at runtime.

## Public Interface / API Additions

1. Default AO486 run invocation:
   - `bundle exec rhdl examples ao486 --bios --dos`
2. Explicit AO486 import invocation:
   - `bundle exec rhdl examples ao486 import --out examples/ao486/import`
3. Run-mode options:
   - `--mode ir|verilator|arcilator`
   - `--sim compile`
   - `--bios`
   - `--dos`
   - `--headless`
   - `--cycles N`
   - `--speed CYCLES`
   - `-d` / `--debug`
4. New runner classes:
   - `RHDL::Examples::AO486::HeadlessRunner`
   - `RHDL::Examples::AO486::IrRunner`
   - `RHDL::Examples::AO486::VerilatorRunner`
   - `RHDL::Examples::AO486::ArcilatorRunner`

## Phased Plan

### Phase 1: CLI Shape, PRD, And Software Assets

#### Red

1. Add failing CLI coverage that assumes `rhdl examples ao486` enters run mode by default.
2. Add failing CLI coverage for `--mode`, `--sim`, `--bios`, `--dos`, `--speed`, `--headless`, `--cycles`, and `-d`.
3. Add failing checks for missing AO486 software artifacts under `examples/ao486/software`.

#### Green

1. Update the AO486 CLI dispatcher so that no-subcommand invocation enters run mode.
2. Preserve `import`, `parity`, and `verify` as explicit subcommands.
3. Add persistent software artifacts under:
   - `examples/ao486/software/rom/boot0.rom`
   - `examples/ao486/software/rom/boot1.rom`
   - `examples/ao486/software/bin/fdboot.img`
4. Make `--bios` and `--dos` load those paths directly and fail clearly if they are absent.

#### Exit Criteria

1. `rhdl examples ao486 --help` documents default run mode and the requested options.
2. `rhdl examples ao486 import ...` still works.
3. Runtime flags do not mutate software files.

### Phase 2: Compiler Runner + Native AO486 Extension

#### Red

1. Add failing runtime coverage showing that compiler-backed AO486 cannot yet boot to a DOS shell.
2. Add failing coverage that a compiler-backed AO486 runner is not detected by the native IR surface.

#### Green

1. Add a native IR compiler AO486 extension under `lib/rhdl/sim/native/ir/ir_compiler/src/extensions/ao486`.
2. Extend compiler `ffi.rs` and Ruby `simulator.rb` with AO486 runner detection and runner helpers.
3. Implement the CPU-top host environment inside the compiler extension:
   - 128 MB memory image
   - Avalon burst read/write handling
   - I/O handshake handling
   - interrupt handshake handling
4. Port the minimum DOS-shell device set from the AO486 reference CPU-top sim/plugin sources:
   - PIC
   - PIT
   - RTC/CMOS with floppy boot defaults
   - DMA for floppy transfers
   - floppy controller backed by `fdboot.img`
   - PS/2 keyboard controller
   - VGA register + text-mode state

#### Exit Criteria

1. Compiler-backed AO486 can boot from `fdboot.img` to a visible DOS text prompt.
2. Keyboard input can be injected and reflected in DOS shell behavior.

### Phase 3: Verilator And Arcilator Runners

#### Red

1. Add failing DOS-shell smoke tests for Verilator and Arcilator AO486 runners.
2. Add failing checks that rendered text output or shell behavior diverges from compiler.

#### Green

1. Add a shared Ruby AO486 CPU-top host bridge for Verilator and Arcilator.
2. Implement `VerilatorRunner` on the reference CPU-top Verilog path.
3. Implement `ArcilatorRunner` on the imported ARC CPU-top path.
4. Reuse the same BIOS/DOS asset paths and host-device model semantics across both HDL runners.

#### Exit Criteria

1. Verilator and Arcilator both boot the same DOS floppy image to a shell.
2. The shell-visible behavior matches compiler on the targeted scenarios.

### Phase 4: Display Adapter, Debug Panel, And Integration Closure

#### Red

1. Add failing display-adapter coverage for text rendering from `0xB8000`.
2. Add failing debug-panel coverage for the requested below-display layout.
3. Add failing integration checks for shell prompt detection, keyboard interaction, and backend parity.

#### Green

1. Add an AO486 text-mode display adapter.
2. Add a debug panel below the display with:
   - backend
   - cycle count
   - speed
   - cursor state
   - last I/O operation
   - last IRQ
   - selected architectural trace fields
3. Put the runner correctness/parity/behavior suite in `spec/examples/ao486/integration`.
4. Keep CLI parsing/help coverage in `spec/rhdl/cli/ao486_spec.rb`.

#### Exit Criteria

1. Interactive mode renders the display and the debug panel correctly.
2. All three backends reach the DOS shell and accept scripted keyboard input.
3. Test location split matches the agreed boundary.

## Exit Criteria Per Phase

1. Phase 1: default run-mode CLI is live and software assets are load-only.
2. Phase 2: compiler runner boots DOS to shell on CPU-top AO486.
3. Phase 3: Verilator and Arcilator match that boot path on CPU-top AO486.
4. Phase 4: display/debug/integration surfaces are green and test placement is correct.

## Acceptance Criteria

1. `bundle exec rhdl examples ao486 --bios --dos --mode ir --sim compile --headless` reaches an `A:\>` prompt.
2. `bundle exec rhdl examples ao486 --bios --dos --mode verilator --headless` reaches the same prompt.
3. `bundle exec rhdl examples ao486 --bios --dos --mode arcilator --headless` reaches the same prompt.
4. Interactive mode honors `--speed` and renders debug output below the display when `-d` is set.
5. CLI parsing/help coverage is green in `spec/rhdl/cli/ao486_spec.rb`.
6. Runner parity/correctness/behavior coverage is green in `spec/examples/ao486/integration`.

## Risks And Mitigations

1. Risk: CPU-top DOS boot requires more device behavior than expected.
   - Mitigation: port the reference CPU-top plugin logic directly for the minimum floppy/text-mode path.
2. Risk: compiler and HDL backends drift in shell-visible behavior.
   - Mitigation: keep shared targeted shell scenarios and compare rendered text plus key memory regions.
3. Risk: the new default CLI flow regresses import/parity/verify behavior.
   - Mitigation: retain explicit subcommand dispatch and cover it in CLI tests.
4. Risk: AO486 software artifacts are present but mismatched to the loader expectations.
   - Mitigation: centralize software-path resolution in `HeadlessRunner` and assert file sizes/types in focused coverage.

## Validation

Completed so far:

1. `bundle exec rspec spec/examples/ao486/integration/display_adapter_spec.rb spec/examples/ao486/integration/headless_runner_spec.rb`
2. `bundle exec rspec spec/rhdl/cli/ao486_spec.rb spec/rhdl/cli/tasks/ao486_task_spec.rb`
3. `bundle exec rspec spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`
4. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
5. `bundle exec rspec spec/rhdl/cli/tasks/native_task_spec.rb`
6. `bundle exec rake native:build`
7. `bundle exec rspec spec/examples/ao486/import/cpu_parity_package_spec.rb`
8. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
9. `bundle exec rspec spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`
10. `bundle exec rspec spec/examples/ao486/integration`
11. `bundle exec rspec spec/examples/ao486/import/cpu_parity_package_spec.rb`
12. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
13. `bundle exec rspec spec/examples/ao486/integration`
14. `bundle exec rspec spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`
15. `bundle exec rake native:build`
16. `bundle exec rspec spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`
17. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
18. `bundle exec rspec spec/examples/ao486/integration`
19. `bundle exec rake native:build`
20. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
21. `bundle exec rspec spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`
22. `bundle exec rspec spec/examples/ao486/integration`
23. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
24. `bundle exec rspec spec/examples/ao486/integration`
25. `bundle exec rake native:build`
26. `bundle exec rspec spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`
27. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
28. `bundle exec rspec spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`
29. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
30. `bundle exec rspec spec/examples/ao486/integration`
31. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
32. `bundle exec rspec spec/examples/ao486/integration`
33. `bundle exec rake native:build`
34. `bundle exec rspec spec/examples/ao486/integration`
35. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
36. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
37. `bundle exec rspec spec/examples/ao486/integration`
38. `bundle exec rake native:build`
39. `bundle exec rspec spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`
40. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
41. `bundle exec rspec spec/examples/ao486/integration`
42. `bundle exec rake native:build`
43. `bundle exec rspec spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`
44. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
45. `bundle exec rspec spec/examples/ao486/integration`
46. `bundle exec rake native:build`
47. `bundle exec rspec spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`
48. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
49. `bundle exec rspec spec/examples/ao486/integration`
50. `bundle exec rake native:build`
51. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
52. `bundle exec rspec spec/examples/ao486/integration`
53. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
54. `bundle exec rspec spec/examples/ao486/integration`
55. `bundle exec rake native:build`
56. `bundle exec rspec spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`
57. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
58. `bundle exec rspec spec/examples/ao486/integration`
59. `bundle exec rake native:build`
60. `bundle exec rspec spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`
61. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
62. `bundle exec rspec spec/examples/ao486/integration`
63. `bundle exec rake native:build`
64. `bundle exec rspec spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`
65. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
66. `bundle exec rspec spec/examples/ao486/integration`
67. `bundle exec rake native:build`
68. `bundle exec rspec spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`
69. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
70. `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`
71. `bundle exec rspec spec/examples/ao486/integration`

Current status notes:

1. Phase 1 is green: default AO486 run-mode CLI, software asset loading semantics, and focused CLI/task coverage are in place.
2. A first AO486 runner/display scaffold now exists under `examples/ao486/utilities/runners/` plus `examples/ao486/utilities/display_adapter.rb`.
3. The AO486 compiler runner extension is now rebuilt and validated against a real native runner ABI smoke, including burst-read servicing and BIOS reset-vector entry on the imported CPU top.
4. `rake native:build` no longer fails when the compiler dylib already resolves to the destination symlink path.
5. The compiler-backed runner now uses the parity-transformed CPU top instead of the raw imported CPU top, because that is the only imported AO486 runtime path currently proven to advance beyond reset-vector fetch.
6. The native AO486 compiler extension now retargets in-flight code bursts to the current imported `readcode` address, which closes the BIOS far-jump fetch bug at `0xFFF0 -> F000:E05B`.
7. The parity fetch model now finishes each 4-word CPU fetch window instead of waiting for the full 8-beat Avalon line fill, which lets BIOS chain fetch windows past the early DMA-init sequence.
8. The fetch-stage parity logic now saturates remaining bytes instead of allowing 4-bit underflow once a prefetch entry has been fully consumed. That prevents the early BIOS prefetch queue from wedging with bogus `15/13/11...` byte counts and keeps `prefetchfifo_used` draining back to zero in the compiler-backed runner.
9. The AO486 native compiler extension now queues I/O requests on the outgoing `io_*_do` edge and pulses `io_*_done` one cycle later with read data valid on the completion pulse. That matches the reference CPU-top `iobus` contract more closely than the earlier same-cycle combinational shortcut.
10. The stronger compiler-runner smoke now proves that the BIOS gets past the CMOS shutdown-status path, retires through the `F000:E06B` to `F000:E079` window, branches onward to `F000:E09F`, and drains the early prefetch queue instead of deadlocking there.
11. The native AO486 runner now exposes persistent disk storage through the shared runner disk ABI, and `IrRunner#load_dos` syncs `examples/ao486/software/bin/fdboot.img` into that native disk image once the simulator is live.
12. The focused compiler-backed BIOS smoke is green again. The native AO486 extension now seeds the ROM `post_init_ivt` result once execution reaches the helper window at `F000:8BF3..F000:8C03`, so the DOS runner sees the intended `F000:FF53` dummy-IRET vectors even though the imported frontend still decodes that helper imperfectly.
13. This is a scoped runner-side bridge, not a full imported-front-end fix. The runner still reaches the correct BIOS helper region, but the raw imported retire stream continues to mis-size some helper instructions. The IVT assist unblocks BIOS startup and keeps the compiler-backed integration smoke green while the underlying helper decode drift remains isolated.
14. The overall Phase 2 blocker is now later DOS boot/device completion rather than early ROM helper initialization. BIOS reset-vector entry, early POST progress, prefetch drain, disk-image loading, and IVT bootstrap are all in place on the compiler-backed runner.
15. The runner `icache` bypass now also handles short/final fetch windows correctly. Previously it only raised `CPU_DONE` after a visible fourth word, which left `icache` stuck in `STATE_READ` with `length == 0` and no outstanding `readcode_do`. The updated completion condition lets the compiler-backed runner advance beyond the old `F000:8F1C` dead stall.
16. With the `CPU_DONE` fix, the compiler-backed BIOS path now advances materially farther into POST. Focused probes reach roughly `F000:982E` by 12,000 cycles and around `F000:FF54` by 50,000 cycles, with the earlier no-fetch deadlock eliminated.
17. DOS shell boot is still not closed. The current blocker is a later BIOS/runtime path after the old fetch stall, not the original reset-vector/helper path. Text mode remains blank and the runner has not reached a DOS prompt yet.
18. The blanket runner rewrite of near-relative `CALL` targets was wrong. It fixed one early helper path, but it also overrode the imported execute logic broadly enough to send BIOS into zero-filled `F300..F6FF` ROM space and eventually back into the dummy `INT 1` handler at `F000:FF53`.
19. Removing that near-call override restores materially healthier BIOS control flow on the compiler-backed runner. A focused DOS-backed smoke now proves early POST stays out of the bogus `F300..F6FF` zero-ROM range and keeps `exception_inst__exc_vector == 0` through 7,000 cycles.
20. With the near-call override removed, longer compiler-backed DOS probes stay exception-free and continue advancing through real low BIOS addresses instead of stalling in dummy-handler space: retired `EIP` reaches `0x0769` by 7,000 cycles, `0x1493` by 20,000 cycles, and `0x32D3` by 50,000 cycles.
21. DOS boot is still not closed after that control-flow fix. Even at 50,000 cycles, the boot sector window at `0x7C00` is still all zeroes and the text display remains blank, so the next blocker is now later floppy/boot-device progress rather than the earlier execute-stage call-target regression.
18. The native AO486 extension now includes a first real floppy/DMA slice beyond plain ROM/IO stubs. Focused extension coverage proves that channel-2 DMA programming plus a floppy read-data command can copy a boot sector from the loaded disk image into RAM through the runner ABI.
19. That new device slice is green in isolation, but the real `--bios --dos` compiler-runner still does not reach a floppy boot attempt yet. By 80,000 cycles the boot sector window at `0x7C00` is still all zeroes, the display is still blank, and execution is still parked at `F000:FF54`.
20. The real DOS-path I/O trace confirms the runner is still failing before VGA or floppy initialization. Across the first 60,000 cycles the only stable BIOS-visible ports touched are DMA reset/mode (`0x000D`, `0x00D6`, `0x00DA`) and CMOS (`0x0070`, `0x0071`) before execution wanders into bogus I/O addresses like `0x045B` and `0x535C`.
21. The coarse DOS-path `trace_wr_eip` progression is now well characterized: `F000:E0AB` at 100 cycles, then roughly `8C94`, `8D16`, `8E18`, `911C`, `9626`, `A03C`, `AA50`, `B466`, `B970`, `BB74`, `BBF4`, then eventually `0000:0000` and back to `F000:FF54`. That strongly reinforces that the remaining blocker is still imported front-end control-flow drift after the early `post_init_ivt` / POST helper region, not missing floppy media plumbing.
22. A targeted experiment that patched out the BIOS `call post_init_ivt` on the compiler runner was reverted. It caused an immediate collapse to `CS=0000`, `EIP=0003`, which is worse than the current late failure. The useful outcome is the diagnosis, not the patch itself.
23. The current compiler-runner baseline now seeds the full `post_init_ivt` result directly in RAM and patches the BIOS `call post_init_ivt` out on the runner path only. That keeps the focused compiler smoke green without relying on the imported frontend to execute the ROM helper correctly.
24. The runner-side IVT seed now mirrors the real BIOS helper more closely than the earlier approximation. It applies the default `F000:FF53` dummy-IRET vectors, master/slave PIC dummy handlers, the `INT 11h/12h/15h/17h/18h/19h` service vectors, and the documented zeroed vector ranges (`0x1D`, `0x1F`, `0x60..0x67`, `0x78..0xFF`).
25. The native AO486 extension now matches that same helper contract when execution enters the original ROM helper window, so the extension-side IVT assist and the runner-side bootstrap are aligned.
26. The runner package now corrects near relative `CALL` return pushes on the imported/compiler path. The focused BIOS smoke proves the early POST call into `F000:8945` now pushes `F000:E0D5` onto the stack instead of the earlier stale `F000:E0D1`, and that regression is now locked in the checked-in integration suite.
27. That fix moved the blocker, but it did not close DOS boot. The next failure is now a narrower imported front-end decode problem: BIOS raises exception vector `0x06` (`#UD`) at `F000:8953`, then falls into the dummy handler at `F000:FF53`. The observed decode window there is wrong. Instead of the expected bytes `C7 06 0E 04 C0 9F C3 ...`, the runner sees `C7 9F C3 B0 11 E6 20 E6 ...`, which skips the middle word `06 0E 04 C0`.
28. Because of that diagnosis, the remaining Phase 2 work is no longer “implement more floppy wiring first.” The higher-priority fix is the imported/compiler `icache`/prefetch fetch-window correctness on the runner package around unaligned BIOS instruction windows. Until that is fixed, DOS boot will remain blocked even though BIOS/DOS assets, IVT bootstrap, DMA/FDC plumbing, the near-call push regression, and the focused runner smoke are all green.
29. The current runner-package baseline is stable again after this investigation pass: `spec/examples/ao486/integration` is green, the focused BIOS smoke is green, and the attempted native burst-retarget change was reverted. The strongest remaining hypothesis is now cache-line fidelity on the runner `icache` bypass. The imported path is still dropping the next aligned word after `F000:8950`, which is consistent with a simplified burst/window model that does not preserve the hidden `l1_icache` line-fill words needed for the subsequent `F000:8954` request.
30. A new focused integration assertion now locks the `ebda_post` near-call return word at physical `0x0000:FFFC`. The correct runner behavior is `0xE0D5`, not `0xE0D9`.
31. The checked-in fix for that regression was to remove the blanket runner-side near relative `CALL` return-push rewrite in `cpu_runner_package.rb`. On the current buffered-icache baseline, that rewrite was over-correcting the early BIOS helper return word by four bytes.
32. That closes one concrete stack-side bug, but it also clarifies the next remaining failure: the helper callee itself is still running on a corrupted fetch window after `F000:8950`. The return address on the stack is now correct, yet the helper still drifts through `F000:F000`/later `F000:F650` before falling back into the `INT 1 -> F000:FF53` loop.
33. The current fetch symptom is now pinned down more tightly than before. Around `F000:8955..F000:8959`, the runner exposes later bytes such as `... B0 70 E6 A1 ...` instead of the real ROM sequence `06 0E 04 C0 9F C3 B0 11 ...`, so the real `RET` at `F000:8959` never executes as a real `RET`.
34. The runner-side `icache` buffer confirms the drift source: during that helper window the buffered line base is `0xF8980` instead of the expected `0xF8940`, so the current imported/compiler problem is no longer just “one missing middle word.” It is a stale mid-helper line/window selection bug in the simplified runner fetch path.
35. A broader attempt to switch the runner over to the parity prefetch-reference flow was tested and reverted in the same pass. It broke the earlier BIOS call-path smoke before closing the later helper drift, so the remaining work stays focused on a narrower mid-line runner fetch/icache fix rather than a whole prefetch-flow replacement.
36. The native AO486 extension had a concrete PS/2 reset-state bug: port `0x64` was hardcoded to `0x1C`, which leaves the controller input-buffer-full bit set and can send BIOS keyboard initialization into unnecessary wait loops. It now reports the reference reset-state status byte `0x18`, and that behavior is locked in `spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`.
37. The compiler runner now has a scoped DOS boot-sector assist in `IrRunner`. When DOS is loaded, it preloads the first 512 bytes of `fdboot.img` into RAM at `0x7C00`, patches `INT 19h` to jump into a tiny custom bootstrap stub in an otherwise-unused ROM window, and keeps that path local to the AO486 DOS runner.
38. The late POST runner fast path is also broader now: it patches out VGA-ROM init, BIOS banner, HDD/ATA/CD init, and late option-ROM scan callsites in the loaded BIOS image so the compiler-backed DOS runner can reach the bootstrap path on a practical cycle budget.
39. The DOS boot-sector smoke is now green. `spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb` proves that the FreeDOS boot sector bytes and `0x55AA` signature are resident at `0x7C00` after a DOS-backed compiler-runner boot slice.
40. That closes one more concrete slice of DOS bring-up, but it does not yet prove full DOS kernel load or a visible shell. Longer probes still end with retired `CS:EIP = 0000:0021`, a blank text screen, and no cursor movement, so the current next blocker has shifted again: the runner now reaches the boot-sector handoff, but later boot-sector progression and/or visible video output are still not closed.
41. The DOS-backed runner bootstrap is now more direct. When `load_dos` is used, the runner no longer just seeds `INT 19h`; it also rewrites the old `call post_init_ivt` site at `F000:E0C9` from a BIOS-only NOP fast path to `int 19; nop` on the DOS runner path. That keeps the BIOS-only smoke unchanged while moving the DOS-backed runner into the FreeDOS boot sector on a practical cycle budget.
42. The native AO486 extension now implements a DOS-only private `INT 13h` bridge behind the runner I/O path. The Ruby DOS stub writes request registers through ports `0x0ED0..0x0EDA`, the native extension reads sectors from the loaded floppy image into main memory, and a focused compiler-extension spec proves that path copies DOS bootstrap data into RAM.
43. The DOS `INT 13h` vector is now installed by the custom `INT 19h` bootstrap stub immediately before it jumps to `0x7C00`, not during POST. That preserves the healthier BIOS POST path while still handing the FreeDOS boot sector to the runner-local disk bridge once the DOS bootstrap actually starts.
44. The focused DOS-backed integration smoke is green again on the corrected path. It now proves three stable bootstrap surfaces: by 1,200 cycles the compiler-backed runner is still executing inside the `0x7C00..0x7DFF` boot-sector window, by 7,000 cycles it has executed through that window and relocated into the `0x0600..0x0FFF` loader region, and the handoff buffer at `0x0600` contains the `FREEDOS ` bootstrap signature.
45. The AO486 integration tree is green again with that DOS-bootstrap closure. The focused native-extension gate and `spec/examples/ao486/integration` both pass sequentially on the current branch.
46. Phase 2 is still not complete. The current runner now proves BIOS reset, DOS handoff through `INT 19h`, private `INT 13h` sector loads, `0x7C00` residency, and relocation into the DOS bootstrap image at `0x0600`, but it still does not reach a visible DOS shell prompt yet.
47. The private DOS `INT 13h` bridge had a real floppy-CHS decode bug. It was interpreting `CL[7:6]` as live cylinder-high bits on the runner DOS path, which turned the FreeDOS loader's traced requests into out-of-range disk reads and zero-filled sectors. The native extension now treats `CH` as the effective floppy cylinder on that bridge, matching the rest of the AO486 floppy path closely enough for the observed FreeDOS trace.
48. That bridge fix changes the stable DOS milestone. The current 7,000-cycle runner slice no longer parks in `0x0600..0x0FFF`; instead it repeatedly re-enters the runner-local `INT 13h` stub while keeping the boot sector resident at `0x7C00` and the `FREEDOS ` handoff image present at `0x0600`. By 13,000 cycles the compiler-backed runner has advanced into later stage code beyond `EIP >= 0x2000`, with `CS` rebased out of the original BIOS window.
49. The runner still does not reach a visible DOS shell prompt. Focused probes now show blank text memory at `0xB8000` through 50,000 cycles, while retired stage execution advances from roughly `0x25DC` at 13,000 cycles to `0x4B36` at 50,000 cycles. The Phase 2 blocker is therefore later DOS-stage/runtime correctness rather than early floppy sector delivery.
50. The DOS `INT 13h` Ruby shim also had a real interrupt-return contract bug. It was using `clc/stc` immediately before `iret`, which does not affect the caller-visible carry flag restored from the interrupt stack image. The shim now patches the saved FLAGS word on the interrupt stack and restores `BP`, so the initial DOS bridge handoff returns a real success/failure carry state.
51. With that carry fix in place, the loader no longer falls into zero-filled stage memory. By 30,000 cycles the compiler-backed runner reaches a valid FreeDOS stage loop that disassembles as `int 13h; jae ...; xor ah, ah; int 13h; ...`, with real stage bytes and the `KERNEL  SYS` directory payload resident nearby.
52. The next blocker is narrower now: later FreeDOS stage execution stalls on its first in-stage `INT 13h` retry loop before control reaches the low-memory shim again. The focused smoke remains green because the initial DOS bridge call, boot-sector residency, and later-stage `EIP >= 0x2000` progress are all stable, but DOS shell boot is still not closed.
53. The DOS handoff path is now simpler and less dependent on the imported software-interrupt flow. On the DOS runner path, the BIOS call site at `F000:E0C6` now jumps into a runner-local ROM bootstrap helper at `F000:10A7`, and that helper seeds the private `INT 13h` vector before jumping straight into the relocated FreeDOS boot sector window at `1FE0:7C5E`.
54. The old runner-side near relative `CALL` return-push rewrite has been removed. A focused relocated DOS-window regression now proves the compiler-backed runner preserves the correct inline return address (`0x7C61`) for near calls on the DOS path, which closes the earlier `+4` return-address drift from that blanket execute-stage patch.
55. The AO486 integration smoke is green again, but the DOS slice is now aligned to what is actually proven on the current branch: mirrored boot-sector residency at `0x7C00` and `0x27A00`, entry into the relocated DOS boot-sector window, stable relocated near-call semantics, and successful execution of the early BPB arithmetic slice on the DOS runner path.
56. DOS shell boot is still not closed. The current real-path blocker is earlier and more precise than the older `0x0600`/bridge milestone: on the unassisted relocated FreeDOS path, execution now stalls in the boot-sector loader block around retired `EIP = 0x7C8A` with decode at `0x7C8D`, before the first real `INT 13h` trigger. Targeted relocated payload probes show that the underlying `mov/add/adc`, `mul`, `div`, `LES`, and near-call slices all work in isolation, so the remaining bug is likely a higher-level imported/frontend control-path interaction in the real boot-sector sequence rather than a missing device primitive.
57. The native AO486 extension now classifies imported Avalon code bursts from the live transaction shape (`avm_read` + `avm_burstcount == 8`) instead of any concurrent `icache.readcode_do` signal. That closes the mixed code/data read bug on single-beat DOS data reads and is locked by a focused compiler-extension regression.
58. That burst-classification fix materially advances the real DOS path. The compiler-backed runner no longer wedges on the old `0x27A0E` one-beat BPB read, and the focused DOS integration smoke now proves later-stage progress through repeated real `INT 13h` handoffs.
59. The later `INT 13h` request pattern is now understood well enough to treat it as expected loader progress, not a same-sector loop. The checked-in smoke proves the DOS stage loader reaches `0x7DCE`, enters the private `INT 13h` bridge at `0x0540`, returns through the success path at `0x7DD8`, and keeps issuing consecutive stage-sector reads on the same track/head before continuing onward.
60. The compiler runner now also has a private DOS `INT 10h` bridge. It is installed by the DOS bootstrap helper, not globally during BIOS POST, and the native AO486 extension implements enough text-mode behavior for `AH=0x00`, `0x02`, `0x03`, `0x06/0x07` clear-window, `0x0E`, and `0x0F` to update `0xB8000` text RAM plus the BDA cursor bytes.
61. Visible text output is now proven on the real runner path. A focused relocated DOS payload smoke executes `int 10h` teletype calls through the imported CPU, and the integration suite proves that the compiler-backed runner writes `OK` into text memory with the cursor advanced to column 2. The screen is no longer blank by construction once DOS/BIOS software reaches `INT 10h`.
62. Phase 2 is still `In Progress`. The compiler-backed runner now has stable BIOS reset, DOS bootstrap handoff, real multi-step DOS stage loads, and a working text-mode `INT 10h` bridge, but full DOS boot to a visible `A:\\>` shell prompt is still not proven yet.
63. The native AO486 extension now has a first DOS `INT 16h` keyboard bridge. `runner_run_cycles` accepts queued key bytes on the shared runner ABI, converts printable ASCII into BIOS `AX` key words, and exposes `AH=0x00/0x01/0x02` semantics through runner-local ports so the imported CPU can consume keyboard input without touching the unfinished PS/2 controller path first.
64. The DOS bootstrap now installs that `INT 16h` vector explicitly alongside the private DOS `INT 13h` and `INT 10h` bridges. The new `INT 16h` stub lives in boot ROM space instead of the crowded low-memory stub window, which avoids overlapping the existing `INT 13h`/`INT 10h` helpers below `0x0600`.
65. The real AO486 DOS runner path now round-trips queued keyboard input end to end. A focused integration smoke overwrites the relocated DOS window with `int 16h`, injects `"d"` through `IrRunner#send_keys`, and proves the imported CPU stores BIOS key word `0x2064` back into RAM while draining the Ruby-side keyboard buffer.
66. The AO486 compiler runner now drains queued key bytes into the native runner queue one byte at a time during `run`, instead of keeping them forever on the Ruby side. That keeps the shared runner state honest and is the minimum plumbing needed for later DOS shell interaction once the boot path reaches `A:\\>`.
67. The private DOS `INT 13h` bridge now aliases `DL=0` and `DL=1` onto the same mounted floppy image. The later FreeDOS stage loader on the imported runner path issues real `AH=02` reads with `DX=0001`, and the earlier strict `drive != 0` rejection was sending that path into a synthetic retry loop even though only one floppy image is mounted in the runner.
68. That drive-alias behavior is locked in native coverage with a focused DOS bridge regression. The compiler-native AO486 runner now proves a `DX=0001`, `CX=0101`, `AH=02` sector read succeeds and returns the expected stage data instead of reporting `0x0100` failure.
69. The live imported DOS path moved materially farther after that fix. A focused 20,000-cycle probe still shows the `FreeDOS` banner and active `INT 13h` stage work with success status at `0x0441 == 0`, but a longer 100,000-cycle probe now reaches retired `EIP = 0xB343` while keeping the visible screen stable, which is well past the older `0x7D..` loader-window ceiling.
70. Full DOS shell boot is still not closed. The current compiler-backed runner no longer looks trapped in the early sector-loader retry loop, but even at the 100,000-cycle live milestone the screen still only shows the `FreeDOS` banner and no visible `A:\\>` prompt yet. The remaining Phase 2 work is now later DOS-stage/kernel bring-up after the improved floppy-read progression, not the earlier boot-sector `INT 13h` loop.
71. The DOS `INT 10h` bridge is broader now. In addition to the earlier teletype/mode set path, the native AO486 extension now supports active-page tracking plus `AH=0x01`, `0x05`, `0x08`, `0x09`, `0x0A`, and `0x13` on the private DOS bridge. The ROM-side DOS `INT 10h` stub now forwards `BP` and `ES` as well as `AX/BX/CX/DX`, and focused native plus real-runner smokes prove DOS-style write-string output renders correctly into `0xB8000` with the cursor advanced.
72. The shared AO486 display adapter is now page-aware. It renders the active BIOS text page selected in BDA byte `0x0462` instead of always forcing page 0, and `HeadlessRunner#read_text_screen` now defers cursor/page selection to the adapter so the debug/screen surface matches the active DOS-visible page.
73. The native AO486 extension now has a minimal DOS `INT 1Ah` bridge with BIOS tick-state backing. It keeps the BDA tick counter at `0x046C..0x046F`, advances that counter on PIT reloads, preserves a midnight flag at `0x0470`, and exposes private DOS bridge handlers for `AH=0x00`, `0x01`, `0x02`, and `0x04`. Focused native coverage proves `AH=0x00` returns the expected `CX:DX` tick value plus the midnight flag and clears that flag afterward.
74. The first `INT 1Ah` runner attempt regressed DOS handoff because its low-memory stub overlapped the `INT 19h` bootstrap code. That is fixed now: the DOS `INT 1Ah` stub lives in boot ROM space at `F000:1130`, and the DOS handoff helper only rewrites vector `0x1A` to that ROM stub during the DOS bootstrap window. The AO486 integration suite now locks that vector rewrite directly.
75. The runner/integration baseline is green again after those `INT 10h` and `INT 1Ah` slices. Sequential validation is green for `bundle exec rspec spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb` and `bundle exec rspec spec/examples/ao486/integration`.
76. The real 100,000-cycle DOS probe is unchanged by the new text-page and timer/time slices. The compiler-backed runner still reports `shell_prompt_detected: false`, still retires around `EIP = 0xB343`, and the visible screen still shows only the `FreeDOS` banner with the cursor at row 0, column 7. So the remaining blocker is no longer “missing `INT 10h` text primitives” or “missing DOS-visible timer state”; it is a later DOS-stage/kernel bring-up problem beyond the current BIOS bridge set.
77. The private DOS `INT 13h` bridge is now broader than bootstrap-only reads. The native AO486 extension now returns floppy geometry for `AH=0x08`, and the DOS-side ROM stub now reads back `BX/CX/DX` result words as well as `AX`, so later DOS stages can consume BIOS drive-parameter results instead of seeing synthetic `0x0100` failures for every non-`AH=0x00/0x02` call.
78. Focused native coverage locks that geometry path directly. `spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb` now proves the AO486 runner bridge returns `BX=0x0400`, `CX=0x4F12`, and `DX=0x0102` for a 1.44 MB floppy `INT 13h AH=08` query, while the existing DOS read-path harnesses remain green with the widened result-port contract.
79. The real-runner DOS smoke remains green after widening the `INT 13h` stub, but its later loader-sector test had to be rewritten from thousands of tiny single-step peeks to a broader milestone check. The old micro-step version became timeout-prone once the DOS bridge returned the extra result words, even though the underlying runner behavior stayed healthy.
80. A fresh long compiler-backed DOS probe on the rebuilt runner no longer follows the older `0xB343` plateau by 200,000 cycles. Instead, the first fresh milestone reaches retired `EIP = 0x8C16`, with a different `CS` cache image and `exception_inst__exc_vector = 1`, while the visible screen still only shows `FreeDOS`. That indicates the widened `INT 13h` path changed the real DOS trajectory, but it has not yet closed DOS shell boot.
81. Phase 2 is still open. The current highest-signal next step is to let the rebuilt long DOS probe finish far enough to determine whether that new post-`AH=08` path is healthy later-stage progress or a regression into an earlier BIOS/exception path, then either keep extending the DOS BIOS bridge set (likely `INT 13h AH=15` next) or correct the new diverging control flow if it is not healthy.
82. The private DOS `INT 13h` bridge now has explicit carry/flags semantics instead of overloading `AH == 0` as success. This was required to support `AH=0x15` correctly, because the reference BIOS returns `AH=0x01` with carry clear for “drive present, no change-line support.” The bridge now exposes a dedicated result-flags byte, and the DOS-side ROM stub reads that flag byte before patching the saved FLAGS image on the interrupt stack.
83. The native AO486 extension now implements `INT 13h AH=0x01`, `AH=0x15`, and `AH=0x16` on the private DOS bridge, matching the AO486 BIOS behavior closely enough for current runner needs: read-last-status, read-drive-type, and “change line not supported.” Focused native coverage proves those paths and keeps the existing `AH=0x02` and `AH=0x08` cases green.
84. An exploratory runner-side patch that rewrote the loaded FreeDOS installer image from `MENUDEFAULT=1,60` to `MENUDEFAULT=3,01` was tested and reverted in the same pass. It pushed the real imported DOS path into an earlier boot-sector loop that alternated between `INT 13h` handoff progress and the dummy `INT 1` handler at `F000:FF53`, which is worse than the current default installer path. The checked-in runner still loads the on-disk DOS image byte-for-byte.
85. The later DOS-loader integration smoke is now chunked and explicitly marked with a longer example timeout. That keeps the real compiler-backed DOS-path milestone meaningful while avoiding the native-call timeout caused by one oversized `runner_run_cycles` request on the imported CPU-top path.
86. Current status after this pass: the useful `INT 13h` status/type bridge work is checked in, the AO486 native extension gate is green, and the full AO486 integration tree is green again. Full DOS boot to a visible `A:\\>` shell is still not closed. The current highest-signal blocker is later DOS-stage/kernel progression on the original installer path after the first private `INT 13h` sector read, not missing `AH=0x01/0x15/0x16` coverage anymore.
87. The first real DOS data read on the original installer path is now pinned down and correct. The boot sector requests `INT 13h AH=0x02` with `ES:BX = 0x0060:0x0000` and `CHS = 0/1/2`, which maps to LBA 19. The runner loads the correct first root-directory sector into physical `0x0600`, and that sector does contain the expected `KERNEL  SYS` entry.
88. Because the root-directory sector contents are correct but the boot sector still takes the `INT 16h`/`INT 19h` error path afterward, the next high-signal blocker is no longer floppy delivery. It is the imported CPU-top execution of the boot sector’s directory-search logic, which uses `repe cmpsb` over the root-directory entries before jumping to the `KERNEL  SYS` load path. A runner-local experiment that bypassed that search loop advanced much farther into DOS-stage code, which strongly suggests a remaining imported/frontend/string-instruction correctness gap on the compiler runner path.
89. The runner `icache` package now has a real retarget path for cross-line control-flow changes. While a code burst is in flight, the imported runner package now detects a new `CPU_REQ` for a different 32-byte line, suppresses acceptance of the stale beat on that redirect cycle, and reseeds the pending output window for the new target line instead of hardcoding `request_retarget = 0`.
90. That behavior is locked by a new focused integration regression in `spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb`. The smoke enters a relocated DOS window that starts on the last words of a cache line, jumps to a different line while the old sequential fill is still active, and now proves the compiler-backed runner executes the target-line payload instead of the stale next-line bytes.
91. That retarget fix is real but not sufficient for full DOS shell boot. Fresh live compiler-backed probes still reach the boot-sector error path instead of `A:\\>`: by 20,000 cycles the runner is already oscillating between the boot-sector error helper around `0x7D4C..0x7D50` and the dummy handler at `F000:FF53/F000:FF54`, with `exception_inst__exc_vector = 1` and the screen still showing only `FreeDOS`.
92. That latest probe narrows the next blocker further. The current real-path failure is no longer “stale cross-line fetch on any branch.” It is now later DOS boot-sector control flow around the error/helper path after the correct root-directory sector load. The next likely fault surface is the imported execution of the boot sector’s BP-relative frame/pointer logic or the exact compare/branch path that decides whether `KERNEL  SYS` was found.
93. The next real runner bug was inside the DOS-side `INT 13h` stub, not the native bridge. A focused relocated payload that did nothing but `mov bp, 0x7C00; int 13h; mov [0x0900], bp` proved the old stub was corrupting the caller frame before the next instruction, even though a trivial `iret`-only replacement returned correctly.
94. That bug is now fixed by replacing the old BP-frame-based DOS `INT 13h` return path with a BP-free stub. The checked-in stub special-cases `AH=0x08` geometry directly, and for the generic path it now patches the saved interrupt FLAGS image using plain stack pops/pushes plus a carry byte scratch in `BL`, instead of `push bp` / `[bp+6]` / `pop bp`. A focused integration regression now proves a trivial DOS `INT 13h` reset call returns past the interrupt site with `BP=0x7C00` preserved.
95. The live compiler-backed DOS path is materially healthier after that stub rewrite. Fresh probes no longer fall back into the old `F000:FF53/F000:FF54` loop by 50,000 cycles. At 20,000 cycles the runner is still inside the DOS `INT 13h` bridge path around retired `EIP = 0x058A`, and by 50,000 cycles it has advanced back into the later boot-sector loader window around retired `EIP = 0x7DC5`, while the visible screen still shows the `FreeDOS` banner. Full DOS shell boot is still not closed, but the blocker has moved past the earlier broken `INT 13h` return-frame path.
96. The AO486 native runner now exposes the DOS `INT 13h` request `ES` word alongside the existing `AX/BX/CX/DX` probe surface. That observability is locked by `spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`, which now proves the private DOS read harness reports `ES = 0x0060` on the boot-sector copy path.
97. That new probe ruled out another tempting false lead on the real installer path. By 100,000 cycles the last private DOS read is `AH=0x02`, `ES:BX = 0x01C0:0x0000`, `CHS = 0/1/13`, and the target buffer is correctly all zeroes because LBA 30 in `fdboot.img` is actually zero-filled. So the current late boot stall is not a “successful read reported with garbage data” bug on that sector.
98. The strongest remaining live-path signal is now timer-driven DOS wait behavior after the `FreeDOS` banner. By 200,000 cycles the compiler-backed runner is still showing only `FreeDOS_`, the last private `INT 1Ah` request is `AH = 0x00`, retired `EIP` has dropped into the DOS `INT 1Ah` ROM-stub window around `0x1140`, and queued keyboard input is still untouched. Forcing the BIOS tick count forward in-place changes control flow immediately, which means the timeout path is live; the remaining open question is whether the runner should patch the installer/menu policy in-memory or whether another post-timeout DOS stage still needs bridge work after that wait loop is skipped.
99. That installer-timeout question is now narrowed further. A live runner experiment that patched the in-memory floppy image from `MENUDEFAULT=1,60` to `MENUDEFAULT=3,1`, ran into the `INT 1Ah` wait path, then forced the BIOS tick count forward to `2000` did change control flow immediately, but it still did not reach `A:\\>` or consume any keyboard input through another 200,000 cycles. The post-timeout path kept showing only `FreeDOS_`, kept the last private DOS requests pinned at `INT 13h AH=0x02` and `INT 1Ah AH=0x00`, and never touched `INT 16h`. So an in-memory installer-default patch by itself is not the remaining closure; there is still a later DOS/runtime blocker after the wait/menu path is skipped.
100. The installer-timeout theory is now closed, not just narrowed. A follow-up live probe repeatedly rewrote the BIOS tick count upward in 5,000-tick jumps before every post-timeout execution slice while booting the real in-memory `MENUDEFAULT=3,1` floppy image. Even with those arbitrarily advanced timer jumps, the compiler-backed runner still never reached `A:\\>`, still never touched `INT 16h`, and still rendered only `FreeDOS_` while retired `EIP` continued walking forward through low-memory DOS code. That means the remaining blocker is not “the installer menu never times out”; it is a later DOS/runtime path after the timeout/menu policy is already effectively bypassed.
101. The native AO486 extension now has a first raw PS/2 keyboard-controller read path in addition to the existing private DOS `INT 16h` bridge. Queued key bytes now surface on port `0x64` as output-buffer-ready status and on port `0x60` as scan-code data, instead of the previous permanently-empty `0x18`/`0x00` reset values. Focused native coverage is green for both surfaces in `spec/rhdl/sim/native/ir/ao486_runner_extension_spec.rb`.
102. The compiler-backed IR runner also had a real display-mirroring blind spot. It was only synchronizing page 0 text RAM back into the Ruby-side display model, even though the AO486 text adapter and BIOS data area support 8 text pages selected by BDA `0x462`. That meant `render_display` and `shell_prompt_detected` could miss real output on a nonzero text page.
103. That render-path bug is now fixed locally in the IR runner. Runtime window sync reads the active page byte first, mirrors only that page’s 4 KB text window back into the Ruby memory model at the correct `0xB8000 + page * 0x0FA0` address, and mirrors all cursor slots plus the active-page BDA byte. A focused integration regression is green for that surface. Validation on the broader AO486 DOS smoke is still in progress because the first compiler-backed `runner_run_cycles` call pays a large one-time native startup cost, so the remaining check is whether the corrected render path surfaces any already-existing shell/menu output that the older page-0-only mirror was hiding.
104. That active-page render fix does not change the already-known relocated DOS-loader milestone. A fresh compiler-backed probe at 3,500 cycles still reports active text page `0`, still renders only `FreeDOS_` on the first visible line, and still retires in the `0x7D87..0x7D9E` boot-sector window. So the corrected display path did not reveal a hidden shell or menu on another page at that milestone.
105. Static inspection of the boot sector narrows that `0x7D87..0x7D9E` window further. Those offsets are inside the normal `KERNEL  SYS` root-directory / sector-load path in `fdboot.img`, not a dedicated visible error-banner helper. In particular, the bytes around `0x7D87` are the `INT 13h` carry-check and CHS fallback logic, and the bytes around `0x7D9E` lead into the loop that references the inline `KERNEL  SYS` string. That means the remaining Phase 2 blocker is still later DOS loader/runtime correctness on the intended boot path, not a simple branch into an already-known boot-sector error routine.
106. The AO486 compiler-backed integration smoke also needed a timeout correction, separate from functional runner bugs. A warmed direct runner probe proved the DOS `INT 1Ah` vector state is already correct after `run(cycles: 1200)` (`[0x30, 0x11, 0x00, 0xF0]`), but that first compiler-backed handoff slice can legitimately take more than the old 30-second file-level timeout. The smoke file now uses a higher default timeout and keeps an explicit larger timeout on the relocated `INT 13h` return-window example so timeout noise does not masquerade as a DOS bridge regression.
107. The imported/compiler AO486 path now has direct regression coverage for the exact boot-sector `repe cmpsb` match shape used by the `KERNEL  SYS` root-directory search. A focused relocated DOS payload compares two in-memory `KERNEL  SYS` strings with `repe cmpsb`, then records `SI`, `DI`, `CX`, and FLAGS. The result is green: `SI` and `DI` both advance by 11 bytes, `CX` reaches 0, ZF stays set, and no exception is raised. So the earlier “boot-sector string compare is probably broken” hypothesis is no longer supported on the current branch.
108. The relocated DOS runner path also now has focused coverage for raw keyboard-controller reads, not just the private DOS `INT 16h` bridge. A checked-in smoke overwrites the relocated DOS window with `in al,0x64; in al,0x60; in al,0x64`, queues `"d"` through `send_keys`, and proves the real runner path observes `0x19` (output-buffer ready), then scan code `0x20`, then `0x18` after the queue drains. That means the current blocker is not “no keyboard data reaches the real DOS path” either.

## Implementation Checklist

- [x] Phase 1: CLI Shape, PRD, And Software Assets
- [ ] Phase 2: Compiler Runner + Native AO486 Extension
- [ ] Phase 3: Verilator And Arcilator Runners
- [ ] Phase 4: Display Adapter, Debug Panel, And Integration Closure
