# RISC-V + xv6 Workflow

This guide covers how xv6 is wired into the RHDL RISC-V flow: source layout, local artifact build, boot/readiness specs, and tracer tooling.

## Source Layout

- Active xv6 source tree: `examples/riscv/software/xv6`
- Legacy compatibility tree: `examples/riscv/software/xv6-rv32`
- Build helper: `examples/riscv/software/build_xv6.sh`
- Local generated artifacts: `examples/riscv/software/bin/`

`build_xv6.sh` prefers `examples/riscv/software/xv6` and falls back to `examples/riscv/software/xv6-rv32` if needed.

## Build xv6 Artifacts

```bash
./examples/riscv/software/build_xv6.sh
```

This generates local (ignored) artifacts in `examples/riscv/software/bin/`, including:

- `kernel.bin`
- `fs.img`
- `kernel.elf`
- `kernel.asm`
- `kernel.sym`
- `kernel.nm`

## Test Matrix

Run all RISC-V specs:

```bash
bundle exec rspec spec/examples/riscv/
```

xv6-focused specs:

- Privileged/readiness compatibility: `spec/examples/riscv/xv6_readiness_spec.rb`
- UART shell boot + echo flow: `spec/examples/riscv/xv6_shell_io_spec.rb`

Run only xv6-focused specs:

```bash
bundle exec rspec spec/examples/riscv/xv6_readiness_spec.rb spec/examples/riscv/xv6_shell_io_spec.rb
```

## Expected xv6 Boot Milestones

The shell I/O spec waits for UART output milestones:

- `init: starting sh`
- shell prompt `$ `
- interactive command echo/output (for example `echo rhdl_io_ok`)

## Boot Tracing Utility

Use the tracer for long or detailed boot debugging:

```bash
bundle exec ruby examples/riscv/utilities/xv6_boot_tracer.rb --core single --backend compiler
```

Useful options:

- `--core single|pipeline`
- `--backend interpreter|jit|compiler`
- `--kernel PATH`
- `--fs PATH`
- `--symbols PATH` / `--no-symbols`
- `--[no-]fast-boot`
- `--[no-]stage`
- `--[no-]mmio`

## Web Simulator Status

Current auto-generated web runner presets are derived from:

- `examples/8bit/config.json`
- `examples/mos6502/config.json`
- `examples/apple2/config.json`
- `examples/gameboy/config.json`

RISC-V is not yet included in the generated web runner preset list by default (`lib/rhdl/cli/tasks/web_generate_task.rb`, `RUNNER_CONFIG_PATHS`), so there is currently no shipped RISC-V web preset in `web/app/components/runner/config/generated_presets.mjs`.

## Artifact Hygiene

`examples/riscv/software/bin/` is intentionally ignored in `.gitignore` and treated as local build output.

If specs skip because artifacts are missing, regenerate with:

```bash
./examples/riscv/software/build_xv6.sh
```
