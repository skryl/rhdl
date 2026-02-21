# RHDL Linux Patch Series

`examples/riscv/build_linux.sh` applies local Linux patches from this directory before each build.

## Supported Patch Format

- Use `*.patch` or `*.diff` files.
- Generate patches against `examples/riscv/software/linux` (the Linux submodule root).
- Unified diffs with `a/` and `b/` paths are recommended (`git format-patch` or `git diff --binary`).

## Patch Order

Patch application order is deterministic: files are applied in `LC_ALL=C` lexicographic filename order.

Use zero-padded numeric prefixes to define an explicit series:

- `0001-<topic>.patch`
- `0002-<topic>.patch`
- `0003-<topic>.patch`

## Workflow

1. Keep `examples/riscv/software/linux` as upstream source (submodule checkout).
2. Store all local Linux source changes as patch files in this directory.
3. Run `./examples/riscv/build_linux.sh` to clean, apply patches, and build artifacts in `examples/riscv/software/bin`.
