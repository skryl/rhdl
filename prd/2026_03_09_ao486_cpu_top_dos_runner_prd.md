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

## Implementation Checklist

- [x] Phase 1: CLI Shape, PRD, And Software Assets
- [ ] Phase 2: Compiler Runner + Native AO486 Extension
- [ ] Phase 3: Verilator And Arcilator Runners
- [ ] Phase 4: Display Adapter, Debug Panel, And Integration Closure
