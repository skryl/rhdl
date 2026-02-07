# RHDL IR Web Simulator (p5.js + WASM)

This app runs RHDL IR simulator backends in the browser via WebAssembly and renders live VCD waveforms with p5.js.

## Features

- Load RHDL-generated IR JSON
- Select backend (`interpreter`, `jit`, `compiler`)
- Preconfigured runner presets (Generic, CPU, Apple II)
- One-click Apple II runner setup (IR + ROM load)
- Step, run, pause, reset simulation
- Clocked stepping (forced clock edge) or unclocked ticking
- Tunable run pacing: `Cycles/Frame` and `UI Every` (cycles) to batch simulation and reduce UI/VCD overhead
- Live VCD streaming from Rust tracer to the browser
- Watch list + current value table
- Value breakpoints (`signal == value`)
- Export full VCD file for GTKWave
- Tabbed workspace:
  - `1. I/O`: Apple II display + `HIRES`, `COLOR`, `SOUND` toggles, keyboard input queue, debug registers
  - `2. VCD + Signals`: waveform canvas, watch table, event log
  - `3. Memory`: RAM browser + direct byte writes + memory dump loading
  - `4. Components`: source-backed component details (`RHDL` + `Verilog`) when source bundles are present
- Memory dump utilities:
  - `Save Dump` exports current Apple II RAM to `.bin` and stores it as "last saved"
  - `Download Snapshot` exports current Apple II RAM as a portable `.rhdlsnap` file (includes `startPc` when available)
  - `Load Dump` accepts both raw binary dumps and `.rhdlsnap` snapshot files
  - `Load Last Saved` restores the most recently saved dump from browser storage
  - `Reset (Vector)` resets the Apple II runner from the Memory tab, with optional manual reset-vector override (`$B82A` / `0xB82A`)

## Build WASM

Use the helper script (builds backends for `wasm32-unknown-unknown` and copies artifacts into `web/pkg/`):

```bash
cd lib/rhdl/codegen/ir/sim/web
./build_wasm.sh
```

`ir_compiler` is built as AOT for web:
- `build_wasm.sh` runs `ir_compiler`'s `aot_codegen` over `samples/apple2.json` by default.
- Then it builds `ir_compiler.wasm` with `--features aot`.
- Override the IR source with `AOT_IR=/absolute/or/relative/path/to/ir.json ./build_wasm.sh`.

Manual equivalent (interpreter):

```bash
cd lib/rhdl/codegen/ir/sim/ir_interpreter
rustup target add wasm32-unknown-unknown
cargo build --release --target wasm32-unknown-unknown
cp target/wasm32-unknown-unknown/release/ir_interpreter.wasm ../web/pkg/ir_interpreter.wasm
```

## Run Web UI

Serve the `web` directory with any static file server:

```bash
cd lib/rhdl/codegen/ir/sim/web
python3 -m http.server 8080
```

Open [http://localhost:8080](http://localhost:8080).

## Notes

- The selected dropdown sample is loaded automatically on startup (default: `samples/apple2.json`).
- Backend selection is in the left control panel.
- `interpreter` is the default browser backend.
- `compiler` in the web UI is `ir_compiler` AOT (precompiled wasm), not runtime `rustc` compilation in-browser.
- Apple II runner assets are included:
  - `samples/apple2.json` (from `examples/apple2/hdl/apple2`)
  - `samples/apple2_sources.json` (`RHDL` + `Verilog` sources for Apple II components)
  - `samples/apple2_schematic.json` (precomputed schematic connectivity for Apple II)
  - `samples/cpu_sources.json` (`RHDL` + `Verilog` sources for CPU components)
  - `samples/cpu_schematic.json` (precomputed schematic connectivity for CPU)
  - `samples/appleiigo.rom` (12KB system ROM)
  - `samples/karateka_mem.bin` + `samples/karateka_mem_meta.txt` for quick dump load
- Regenerate web artifacts (IR + source + schematic):
  - `bundle exec rake web:generate`
- Memory tab supports:
  - arbitrary dump file load at offset (via Apple II RAM interface)
  - one-click Karateka dump load (patches reset vector and resets to dump PC)
- Clock options are labeled by execution mode:
  - `forced`: direct process clock stepping (`tick_forced`)
  - `driven`: toggle external clock (for example top-level `clk`) and propagate through combinational logic
- The UI consumes incremental VCD chunks from `trace_take_live_vcd()` each frame.
