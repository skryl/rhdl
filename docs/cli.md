# RHDL Command Line Interface

The `rhdl` command is the top-level CLI for simulation/debugging, diagram/export flows, example runners, disk tools, and project import.

## Installation

After installing the gem, the `rhdl` command is available:

```bash
gem install rhdl
rhdl --help
```

For development in this repository, use:

```bash
bundle exec rhdl --help
```

## Commands Overview

| Command | Description |
|---------|-------------|
| `tui` | Launch interactive TUI debugger |
| `diagram` | Generate circuit diagrams |
| `export` | Export components to Verilog |
| `import` | Import Verilog/SystemVerilog projects |
| `gates` | Gate-level synthesis |
| `examples` | Run example emulators (`mos6502`, `apple2`, `gameboy`, `riscv`) |
| `disk` | Disk image utilities for Apple II workflows |
| `generate` | Generate diagrams + HDL exports |
| `clean` | Clean generated diagrams/exports/gates output |
| `regenerate` | Clean and regenerate all outputs |

## TUI Command

### Usage

```bash
rhdl tui [options] <ComponentRef>
```

### Options

| Option | Description |
|--------|-------------|
| `--signals TYPE` | Signals to display: `all`, `inputs`, `outputs`, or comma-separated list |
| `--format FORMAT` | Signal format: `auto`, `binary`, `hex`, `decimal`, `signed` |
| `--list` | List available components |
| `-h, --help` | Show help |

### Examples

```bash
rhdl tui sequential/counter
rhdl tui RHDL::HDL::ALU --signals inputs
rhdl tui --list
```

## Diagram Command

### Usage

```bash
rhdl diagram [options] [ComponentRef]
```

### Options

| Option | Description |
|--------|-------------|
| `--all` | Generate diagrams for all components |
| `--mode MODE` | Batch mode: `component`, `hierarchical`, `gate`, or `all` |
| `--clean` | Clean generated diagrams |
| `--level LEVEL` | Single-component mode: `component`, `hierarchy`, `netlist`, or `gate` |
| `--depth DEPTH` | Hierarchy depth (`N` or `all`) |
| `--bit-blasted` | Bit-blast gate-level nets |
| `--format FORMAT` | Output format: `svg`, `png`, `dot` |
| `--out DIR` | Output directory |
| `-h, --help` | Show help |

### Examples

```bash
rhdl diagram --all
rhdl diagram --all --mode gate
rhdl diagram RHDL::HDL::ALU --level component --format svg
rhdl diagram --clean
```

## Export Command

### Usage

```bash
rhdl export [options] [ComponentRef]
```

### Options

| Option | Description |
|--------|-------------|
| `--all` | Export all components |
| `--scope SCOPE` | Batch scope: `all`, `lib`, or `examples` |
| `--clean` | Clean generated HDL files |
| `--lang LANG` | Target language (`verilog`) |
| `--out DIR` | Output directory |
| `--top NAME` | Override top module/entity name |
| `-h, --help` | Show help |

### Examples

```bash
rhdl export --all
rhdl export --all --scope examples
rhdl export --lang verilog --out ./output RHDL::HDL::Counter
rhdl export --clean
```

## Import Command

### Usage

```bash
rhdl import [options] [OUT_DIR]
```

### Behavior

`rhdl import` runs the import task, calls `RHDL::Import.project(...)`, prints a short status summary, writes `reports/import_report.json` under the output directory, and exits with:

- `0` on success
- non-zero on partial conversion, check failure, or tool/internal failure

If `OUT_DIR` is omitted, output defaults to `./rhdl_import`.
At least one input mode is required: `--filelist FILE` or one/more `--src DIR`.
By default, checks run on converted detected tops; use `--check-scope` to override selection.

### Options

| Option | Description |
|--------|-------------|
| `--filelist FILE` | Input filelist (`.f`) |
| `--src DIR` | Source directory (repeatable) |
| `--exclude PATTERN` | Exclude glob pattern (repeatable) |
| `-I, --incdir DIR` | Include directory (repeatable) |
| `-D, --define MACRO[=VALUE]` | Preprocessor define (repeatable) |
| `--dependency-resolution MODE` | Dependency resolution: `none` or `parent_root_auto_scan` |
| `--compile-unit-filter MODE` | Compile-unit filtering: `all` or `modules_only` |
| `--missing-modules MODE` | Missing module policy: `fail` or `blackbox_stubs` |
| `--check-profile PROFILE` | Check profile selector (for example: `default`, `ao486_trace`, `ao486_trace_ir`, `ao486_component_parity`, `ao486_program_parity`) |
| `--top MODULE` | Top module (repeatable) |
| `--check` | Enable differential checks (default) |
| `--no-check` | Disable differential checks |
| `--check-scope SCOPE` | Check scope selector |
| `--check-backend BACKEND` | Check backend preference |
| `--expected-trace FILE` | Expected trace events JSON (for `ao486_trace`) |
| `--actual-trace FILE` | Actual trace events JSON (for `ao486_trace`) |
| `--expected-trace-cmd CMD` | Expected trace command (`stdout` JSON) |
| `--actual-trace-cmd CMD` | Actual trace command (`stdout` JSON) |
| `--trace-command-cwd DIR` | Working directory for trace commands |
| `--trace-key KEY` | Trace event key filter (repeatable) |
| `--trace-cycles N` | Cycle budget for built-in ao486 trace harness |
| `--trace-reference-root DIR` | Reference RTL root for built-in ao486 trace harness |
| `--trace-converted-export-mode MODE` | Converted trace export mode: `component` or `dsl_super` |
| `--vectors N` | Vector count for checks |
| `--seed N` | Deterministic seed for checks |
| `--report FILE` | Write import report to `FILE` |
| `--keep-temp` | Keep temporary artifacts |
| `-h, --help` | Show help |

### Examples

```bash
rhdl import --help
rhdl import --src ./rtl --top top --no-check
rhdl import --filelist rtl.f -I include -D WIDTH=32
rhdl import --src ./rtl --dependency-resolution parent_root_auto_scan --compile-unit-filter modules_only
rhdl import --src ./rtl --missing-modules blackbox_stubs --no-check
rhdl import --src ./rtl --check-profile ao486_trace --expected-trace ./expected.json --actual-trace ./actual.json
rhdl import --src ./rtl --check-profile ao486_trace --expected-trace-cmd "cat ./expected.json" --actual-trace-cmd "cat ./actual.json"
rhdl import --src ./rtl --check-profile ao486_trace --trace-command-cwd ./sim --expected-trace-cmd "./run_expected.sh" --actual-trace-cmd "./run_actual.sh"
rhdl import --src ./rtl --check-profile ao486_trace --expected-trace ./expected.json --actual-trace ./actual.json --trace-key pc --trace-key eax
rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_trace --trace-cycles 1024 examples/ao486/hdl
rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_trace --trace-converted-export-mode dsl_super examples/ao486/hdl
rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_trace_ir --trace-cycles 1024 examples/ao486/hdl
rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_program_parity --trace-cycles 256 examples/ao486/hdl
rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_trace --expected-trace-cmd "bundle exec ruby examples/ao486/tools/capture_trace.rb --mode reference --top %{top} --out %{out} --cycles 1024" --actual-trace-cmd "bundle exec ruby examples/ao486/tools/capture_trace.rb --mode converted --top %{top} --out %{out} --cycles 1024" examples/ao486/hdl
rhdl import --src examples/ao486/reference/rtl/ao486 --dependency-resolution none --compile-unit-filter modules_only --missing-modules blackbox_stubs --top ao486 --check-profile ao486_trace_ir --expected-trace-cmd "bundle exec ruby examples/ao486/tools/capture_trace.rb --mode reference --top %{top} --out %{out} --cycles 1024" --actual-trace-cmd "bundle exec ruby examples/ao486/tools/capture_trace.rb --mode converted_ir --top %{top} --out %{out} --cycles 1024" examples/ao486/hdl
rhdl import --src ./rtl ./build/imported_rhdl
```

For implementation-level import semantics, see [Import Guide](import.md).

## Gates Command

### Usage

```bash
rhdl gates [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--export` | Export all components to gate-level IR (JSON netlists) |
| `--simcpu` | Export SimCPU datapath to gate-level |
| `--stats` | Show gate-level synthesis statistics |
| `--clean` | Clean gate-level output |
| `-h, --help` | Show help |

### Examples

```bash
rhdl gates
rhdl gates --simcpu
rhdl gates --stats
rhdl gates --clean
```

## Examples Command

### Usage

```bash
rhdl examples <subcommand> [options]
```

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `mos6502` | MOS 6502 emulator |
| `apple2` | Apple II emulator |
| `gameboy` | Game Boy emulator |
| `riscv` | RISC-V emulator |

### Examples

```bash
rhdl examples mos6502 --demo
rhdl examples apple2 --mode netlist --sim jit --demo
rhdl examples gameboy --demo
rhdl examples riscv --xv6
```

Run `rhdl examples <subcommand> --help` for subcommand-specific options.

## Disk Command

### Usage

```bash
rhdl disk <command> [options] FILE
```

### Commands

| Command | Description |
|---------|-------------|
| `info` | Show disk image information |
| `convert` | Convert disk to a binary file |
| `boot` | Extract boot sector |
| `tracks` | Extract track range |
| `memdump` | Boot disk and dump memory (requires ROM) |

### Options

| Option | Description |
|--------|-------------|
| `-o, --output FILE` | Output file path |
| `-r, --rom FILE` | ROM file for booting (`memdump`) |
| `--start-track N` | Start track for extraction |
| `--end-track N` | End track for extraction |
| `--prodos` | Use ProDOS sector interleaving |
| `--max-cycles N` | Max boot cycles for `memdump` |
| `--base-addr ADDR` | Memory dump base address (hex) |
| `--end-addr ADDR` | Memory dump end address (hex) |
| `-h, --help` | Show help |

## Workflow Commands

### `generate`

```bash
rhdl generate
```

Equivalent to:

```bash
rhdl diagram --all
rhdl export --all
```

### `clean`

```bash
rhdl clean
```

Equivalent to:

```bash
rhdl diagram --clean
rhdl export --clean
rhdl gates --clean
```

### `regenerate`

```bash
rhdl regenerate
```

Equivalent to:

```bash
rhdl clean
rhdl generate
```

## See Also

- [Import Guide](import.md)
- [Debugging Guide](debugging.md)
- [Diagrams Guide](diagrams.md)
- [Export Guide](export.md)
- [RISC-V + Linux/xv6](riscv.md)
