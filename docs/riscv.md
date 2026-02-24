# RISC-V RV32 in RHDL (Linux + xv6)

## CPU overview

- `single`: single-cycle core focused on bring-up/debug determinism.
- `pipeline`: 5-stage core for higher-throughput execution.
- Both cores share a common ISA decode/control surface.
- Both cores share a common CSR/privilege model.
- Both cores share a common MMIO device shape (CLINT, PLIC, UART, virtio-blk).
- Linux and xv6 flows use the same runner stack and software artifact layout.
- Core selection is runtime-configurable via `--core single|pipeline`.

## What this page covers

- How to build and run RISC-V programs, xv6, and Linux
- Current CLI defaults and artifact expectations
- Linux source + patch workflow
- Current core/ISA support surface
- Test entry points and web preset integration

## Quick start

### 1. Build native backends

```bash
bundle exec rake native:build
```

### 2. Build software artifacts

```bash
# xv6 artifacts (kernel.bin + fs.img)
./examples/riscv/software/build_xv6.sh

# Linux kernel + DTB + BusyBox rootfs artifacts
./examples/riscv/software/build_linux.sh
```

### 3. Run

```bash
# Run a raw RISC-V binary
rhdl examples riscv path/to/program.bin

# Run xv6 (forces UART mode)
rhdl examples riscv --xv6

# Run Linux (forces UART mode; defaults kernel/initramfs/dtb if omitted)
rhdl examples riscv --linux
```

## CLI behavior (`rhdl examples riscv`)

`rhdl examples riscv` delegates to `examples/riscv/bin/riscv`.

### Core defaults

- CLI default core: `single`
- Core override: `--core single|pipeline`

### Mode defaults

- Default mode: `--mode ir`
- Default simulator backend in IR mode: `--sim compile`

### xv6 mode

- Enable with `--xv6`
- Forces `--io uart`
- Default artifacts:
  - `examples/riscv/software/bin/kernel.bin`
  - `examples/riscv/software/bin/fs.img`
- Optional overrides:
  - `--kernel <path>`
  - `--fs <path>`

### Linux mode

- Enable with `--linux`
- Forces `--io uart`
- Default artifacts (auto-filled if omitted):
  - `--kernel examples/riscv/software/bin/linux_kernel.bin`
  - `--initramfs examples/riscv/software/bin/linux_initramfs.cpio`
  - `--dtb examples/riscv/software/bin/rhdl_riscv_virt.dtb`
- Optional address overrides:
  - `--kernel-addr` (default `0x80400000`)
  - `--initramfs-addr` (default `0x84000000`)
  - `--dtb-addr` (default `0x87f00000`)

## Software tree layout

- `examples/riscv/software/linux`:
  Linux source submodule (upstream tree)
- `examples/riscv/software/linux_patches`:
  local patch series applied by the Linux build script
- `examples/riscv/software/xv6`:
  preferred xv6 source tree (if present)
- `examples/riscv/software/xv6-rv32`:
  fallback xv6 source tree
- `examples/riscv/software/bin`:
  generated local artifacts

## Linux workflow

### Source + patches

Linux source is tracked as a submodule at:

- `examples/riscv/software/linux`

Initialize/update:

```bash
git submodule update --init --recursive examples/riscv/software/linux
```

Local Linux changes should be stored as patch files in:

- `examples/riscv/software/linux_patches`

Patch files are applied in deterministic lexicographic order during build.

### Build command

```bash
./examples/riscv/software/build_linux.sh
```

Default behavior:

- cleans Linux source/build outputs (unless `--no-clean`)
- applies local patches from `linux_patches`
- configures kernel from `rv32_defconfig`
- applies the RV32 minimum-size profile (unless `--no-min-profile`)
- builds BusyBox initramfs + ext image via Buildroot (unless `--no-rootfs`)
- emits kernel, DTB, initramfs, and fs image artifacts into `software/bin`

Notable outputs:

- `linux_kernel.bin`
- `linux_kernel.elf`
- `linux_kernel.map`
- `linux_kernel.config`
- `rhdl_riscv_virt.dtb`
- `linux_initramfs.cpio`
- `linux_fs.img`
- `linux_busybox`
- `linux_rootfs.config`

### Runtime handoff details

Linux loading uses a bootstrap handoff that:

- loads kernel/initramfs/DTB into memory
- patches DTB initrd bounds to match loaded initramfs
- sets entry/boot context and jumps to kernel entry

## xv6 workflow

Build xv6 artifacts:

```bash
./examples/riscv/software/build_xv6.sh
```

Outputs:

- `examples/riscv/software/bin/kernel.bin`
- `examples/riscv/software/bin/kernel.elf`
- `examples/riscv/software/bin/kernel.sym`
- `examples/riscv/software/bin/kernel.asm`
- `examples/riscv/software/bin/kernel.nm`
- `examples/riscv/software/bin/fs.img`

Run:

```bash
rhdl examples riscv --xv6
```

## Current core and ISA surface

### Core options

- `single`: single-cycle implementation
- `pipeline`: 5-stage pipeline implementation

Both share decode/MMIO infrastructure and can run through the native RISC-V runner.

### Supported ISA/extensions (current project surface)

- Base: `RV32I`
- Integer: `M`
- Atomics: `A` + `Zacas` subset (`amocas.w`)
- Compressed: `C` subset
- Float: `F` subset (`flw`, `fsw`, `fmv.x.w`, `fmv.w.x`, `fcsr` interaction)
- Vector: `V` subset (`vsetvli`, `vmv*`, `vadd` subset)
- System/support: `Zicsr`, `Zifencei`, `sfence.vma`
- Additional subsets:
  - `Zawrs` (`wrs.nto`, `wrs.sto`)
  - `Zba` subset (`sh1add`, `sh2add`, `sh3add`)
  - `Zbb` subset (`andn`, `orn`, `xnor`, `min/max`, `minu/maxu`)
  - `Zbkb` subset (`pack`, `packh`)
  - `Zbc` subset (`clmul`, `clmulh`, `clmulr`)
  - `Zicbop`, `Zicbom`, `Zicboz` encodings currently modeled as safe no-ops

## Test entry points

Targeted RISC-V task/CLI tests:

```bash
bundle exec rspec spec/examples/riscv/utilities/tasks/run_task_spec.rb
bundle exec rspec spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb
```

Linux compatibility + boot milestones:

```bash
bundle exec rspec spec/examples/riscv/linux_privilege_boot_spec.rb
bundle exec rspec spec/examples/riscv/linux_csr_mmio_compat_spec.rb
bundle exec rspec spec/examples/riscv/linux_mmio_interrupt_spec.rb
bundle exec rspec spec/examples/riscv/linux_boot_milestones_spec.rb
```

Extension-focused coverage:

```bash
bundle exec rspec spec/examples/riscv/rv32c_extension_spec.rb
bundle exec rspec spec/examples/riscv/rv32f_extension_spec.rb
bundle exec rspec spec/examples/riscv/rvv_extension_spec.rb
bundle exec rspec spec/examples/riscv/zba_extension_spec.rb
bundle exec rspec spec/examples/riscv/zbb_extension_spec.rb
bundle exec rspec spec/examples/riscv/zbkb_extension_spec.rb
bundle exec rspec spec/examples/riscv/zbc_extension_spec.rb
bundle exec rspec spec/examples/riscv/zawrs_extension_spec.rb
bundle exec rspec spec/examples/riscv/zacas_extension_spec.rb
bundle exec rspec spec/examples/riscv/zicbo_extension_spec.rb
```

Broader:

```bash
bundle exec rake spec:riscv
```

## Web simulator integration

RISC-V web presets are generated from:

- `examples/riscv/config.json` (xv6 preset)
- `examples/riscv/config_linux.json` (Linux preset)

Generated preset IDs include:

- `riscv`
- `riscv_linux`

If preset defaults or software artifacts change, regenerate web assets:

```bash
bundle exec rake web:generate
```

## Troubleshooting

- `Error: Linux kernel/initramfs/dtb not found`:
  run `./examples/riscv/software/build_linux.sh` or pass explicit paths.
- `Error: xv6 kernel/fs image not found`:
  run `./examples/riscv/software/build_xv6.sh`.
- Linux mode and xv6 mode are mutually exclusive:
  use either `--linux` or `--xv6`, not both.
- For reproducible Linux changes:
  keep source edits as patch files in `examples/riscv/software/linux_patches`, not ad-hoc dirty submodule changes.

---

## Full architecture reference

This section keeps the detailed architecture at the end of the page for design/debug use.

## Architecture overview

The RISC-V example includes two core implementations:

- single-cycle core (`examples/riscv/hdl/cpu.rb`)
- pipelined core (`examples/riscv/hdl/pipeline/cpu.rb`)

Both cores share the same ISA decode/control surface, CSR model, and MMIO platform shape.

## Single-cycle architecture

### Datapath sketch

```text
+-----------------------------------------------------------------------------+
|                         RV32 single-cycle datapath                          |
+-----------------------------------------------------------------------------+
|                                                                             |
|  PC -> IFetch -> Decode -> RegFile -> ALU -> Mem/MMIO -> Writeback         |
|   |       |          |         |        |         |               |         |
|   |       |          |         |        |         |               |         |
|   +-> PC select <----+         +--------+---------+---------------+         |
|        (pc+4/branch/jump/jalr)                                                  |
|                                                                             |
+-----------------------------------------------------------------------------+
```

### Main blocks

| Block | File | Role |
|---|---|---|
| CPU top | `examples/riscv/hdl/cpu.rb` | Integrates decode, execute, CSR, MMIO, control |
| Decoder | `examples/riscv/hdl/decoder.rb` | Instruction decode + control generation |
| ALU | `examples/riscv/hdl/alu.rb` | Integer ALU (+ extension ops) |
| Immediate generator | `examples/riscv/hdl/imm_gen.rb` | I/S/B/U/J immediate construction |
| Integer reg file | `examples/riscv/hdl/register_file.rb` | x0..x31 architectural regs |
| CSR file | `examples/riscv/hdl/csr_file.rb` | privilege/exception/interrupt CSR state |
| Memory model | `examples/riscv/hdl/memory.rb` | instruction/data backing store |
| MMIO devices | `examples/riscv/hdl/{clint,plic,uart,virtio_blk}.rb` | platform devices |

### Debug/state visibility

Core debug signals exposed to runners include:

- `debug_pc`
- `debug_inst`
- `debug_x1`, `debug_x2`, `debug_x10`, `debug_x11`

These are used by CLI debug panels and boot milestone tests.

## 5-stage pipeline architecture

### Pipeline stages

- IF: instruction fetch + next-PC path
- ID: decode + register read + immediate generation
- EX: ALU/branch target/compare
- MEM: load/store + MMIO access
- WB: register writeback

### Pipeline state and glue blocks

| Block | File |
|---|---|
| Pipeline top | `examples/riscv/hdl/pipeline/cpu.rb` |
| IF/ID register | `examples/riscv/hdl/pipeline/if_id_reg.rb` |
| ID/EX register | `examples/riscv/hdl/pipeline/id_ex_reg.rb` |
| EX/MEM register | `examples/riscv/hdl/pipeline/ex_mem_reg.rb` |
| MEM/WB register | `examples/riscv/hdl/pipeline/mem_wb_reg.rb` |
| Pipeline harness | `examples/riscv/hdl/pipeline/ir_harness.rb` |

### Hazard behavior

- forwarding for common RAW dependencies
- stalls for unresolved load-use dependencies
- control redirection/flush for taken branch/jump paths

## Platform and memory/MMIO model

The cores run with a `virt`-style MMIO layout compatible with current Linux/xv6 flows.

Major devices:

- CLINT: timer/software interrupt source
- PLIC: external interrupt routing/claim/complete
- UART 16550-compatible interface for console I/O
- virtio-blk MMIO disk path used by filesystem-based boot flows

The Linux DTB generated by `build_linux.sh` models this platform, including chosen bootargs and initrd bounds.

## Privilege, traps, and virtual memory

Current boot flows rely on:

- machine and supervisor privilege transitions (`mret`, `sret`)
- delegated trap behavior through CSR configuration
- Sv32 path including `satp` programming and `sfence.vma`
- timer/external interrupt handling through CLINT + PLIC

These behaviors are covered by Linux compatibility specs under `spec/examples/riscv/linux_*`.

## Linux boot loading model

`HeadlessRunner#load_linux` (`examples/riscv/utilities/runners/headless_runner.rb`) performs:

- kernel load to configured physical address
- optional initramfs load
- optional DTB load
- DTB patching for initrd bounds
- bootstrap program load and PC handoff into Linux entry path

For pipeline core, compatibility patching adjusts DTB ISA/bootargs for the configured pipeline profile.

## Instruction encoding reference

### Base instruction formats

```text
R-type:  funct7 | rs2 | rs1 | funct3 | rd | opcode
I-type:  imm[11:0] | rs1 | funct3 | rd | opcode
S-type:  imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
B-type:  imm[12|10:5] | rs2 | rs1 | funct3 | imm[4:1|11] | opcode
U-type:  imm[31:12] | rd | opcode
J-type:  imm[20|10:1|11|19:12] | rd | opcode
```

### Core base classes

| Class | Examples |
|---|---|
| Integer arithmetic | `add`, `sub`, `addi`, `sll`, `srl`, `sra`, `and`, `or`, `xor` |
| Comparisons | `slt`, `sltu`, `slti`, `sltiu` |
| Loads/stores | `lb/lh/lw/lbu/lhu`, `sb/sh/sw` |
| Control flow | `beq/bne/blt/bge/bltu/bgeu`, `jal`, `jalr` |
| Upper immediates | `lui`, `auipc` |
| System | `ecall`, CSR ops, fence path |

## Extension subsets currently exercised

| Extension | Representative instructions |
|---|---|
| `M` | `mul`, `div`, `rem` families |
| `A` + `Zacas` subset | `lr.w`, `sc.w`, AMO word ops, `amocas.w` |
| `C` subset | mixed-width compressed integer/control-flow set |
| `F` subset | `flw`, `fsw`, `fmv.x.w`, `fmv.w.x` |
| `V` subset | `vsetvli`, `vmv.v.x`, `vmv.s.x`, `vmv.x.s`, `vadd.vv`, `vadd.vx` |
| `Zawrs` | `wrs.nto`, `wrs.sto` |
| `Zba` subset | `sh1add`, `sh2add`, `sh3add` |
| `Zbb` subset | `andn`, `orn`, `xnor`, `min/max`, `minu/maxu` |
| `Zbkb` subset | `pack`, `packh` |
| `Zbc` subset | `clmul`, `clmulh`, `clmulr` |
| `Zicsr` / `Zifencei` | CSR read/write ops, `fence.i` |
| `Zicbop` / `Zicbom` / `Zicboz` | encodings accepted; modeled as safe no-ops in current memory model |

## Runner architecture notes

- CLI runner task: `examples/riscv/utilities/tasks/run_task.rb`
- Headless runner: `examples/riscv/utilities/runners/headless_runner.rb`
- Native backends are expected for Linux/xv6 boot workflows
- Debug pane displays core type and architectural debug registers
- UART interactive mode supports shell interaction used by Linux and xv6 flows
