# Export Guide

This document covers exporting RHDL components to Verilog and gate-level netlists.

## Verilog Export

### Supported Subset

The export pipeline supports a focused subset of the RHDL DSL:

- Ports (input/output/inout) with explicit widths
- Internal registers declared via `signal`
- Continuous assignments (`assign`)
- Combinational processes with `if`/`else` and sequential assignments
- Clocked processes with `if`/`else` and sequential assignments
- Expressions:
  - Bitwise ops: `&`, `|`, `^`, `~`
  - Arithmetic: `+` and `-`
  - Shifts: `<<`, `>>`
  - Comparisons: `==`, `!=`, `<`, `>`, `<=`, `>=`
  - Concatenation and replication
  - Conditional/mux (via `assign` with a condition or `if`/`else` in a process)

Anything outside this subset will raise an error during lowering.

### Basic Usage

```ruby
require 'rhdl'

# Export a component to Verilog
component = MyComponent.new
verilog_code = RHDL::Export::Verilog.export(component)
```

### Signal Naming Rules

- Identifiers are sanitized for HDL output:
  - Invalid characters are replaced with `_`
  - Verilog keywords are suffixed with `_rhdl`
  - Identifiers starting with a digit are prefixed with `_`

### Vector Conventions

- Verilog uses `[W-1:0]`
- Width 1 is emitted as a scalar port

### Clock/Reset Semantics

- Clocked processes use `posedge clk` in Verilog
- Synchronous reset and enable can be expressed with `if`/`else` inside the clocked process

### Output Directory

All generated HDL files are placed in `/export/verilog/`.

### Rake Tasks

```bash
rake hdl:export    # Export DSL components to Verilog
rake hdl:verilog   # Export Verilog files
rake hdl:clean     # Clean generated HDL files
```

### Running Export Tests

Verilog export tests require Icarus Verilog (`iverilog` and `vvp`). If the toolchain is missing, specs are skipped automatically.

```bash
bundle exec rspec spec/export_verilog_spec.rb
```

---

## Gate-Level Synthesis

The gate-level backend flattens simulation components into a gate IR (`RHDL::Export::Structure::IR`) with dense 1-bit net indices and primitive gates.

### Overview

- Multi-bit buses are bit-blasted into per-bit nets
- The lowering pass flattens connections and emits primitive gates plus DFFs
- CPU backend evaluates gates in topological order with packed 64-lane bitmasks
- GPU backend is a stub (optional build)

### Key Files

| File | Description |
|------|-------------|
| `lib/rhdl/export/structure/ir.rb` | Gate-level IR and JSON serialization |
| `lib/rhdl/export/structure/lower.rb` | Lowering pass from HDL components into IR |
| `lib/rhdl/export/structure/sim_cpu.rb` | Packed-lane CPU simulator backend |
| `lib/rhdl/export/structure/sim_gpu.rb` | GPU backend stub (optional build) |

### Basic Usage

```ruby
components = [RHDL::HDL::FullAdder.new('fa')]
# connect components via RHDL::HDL::SimComponent.connect as needed
sim = RHDL::Export.gate_level(components, backend: :cpu, lanes: 64, name: 'demo')

sim.poke('fa.a', 0xffff_ffff_ffff_ffff)
sim.poke('fa.b', 0x0)
sim.poke('fa.cin', 0x0)
sim.evaluate
sum_mask = sim.peek('fa.sum')
```

### Netlist Dumping

To dump a netlist JSON for debugging:

```bash
RHDL_DUMP_NETLIST=1 bundle exec rspec
```

The netlist will be written to `tmp/netlists/<name>.json`.

### Supported Components (53 total)

**Gates (13):**
`NotGate`, `Buffer`, `AndGate`, `OrGate`, `XorGate`, `NandGate`, `NorGate`, `XnorGate`, `TristateBuffer`, `BitwiseAnd`, `BitwiseOr`, `BitwiseXor`, `BitwiseNot`

**Sequential (12):**
`DFlipFlop`, `DFlipFlopAsync`, `TFlipFlop`, `JKFlipFlop`, `SRFlipFlop`, `SRLatch`, `Register`, `RegisterLoad`, `ShiftRegister`, `Counter`, `ProgramCounter`, `StackPointer`

**Arithmetic (10):**
`HalfAdder`, `FullAdder`, `RippleCarryAdder`, `Subtractor`, `AddSub`, `Comparator`, `IncDec`, `Multiplier`, `Divider`, `ALU`

**Combinational (16):**
`Mux2`, `Mux4`, `Mux8`, `MuxN`, `Demux2`, `Demux4`, `Decoder2to4`, `Decoder3to8`, `DecoderN`, `Encoder4to2`, `Encoder8to3`, `ZeroDetect`, `SignExtend`, `ZeroExtend`, `BitReverse`, `PopCount`, `LZCount`, `BarrelShifter`

**CPU (2):**
`InstructionDecoder`, `SynthDatapath` (hierarchical composition of decoder, ALU, PC, register)

### Rake Tasks

```bash
rake gates:export   # Export all 53 components to gate-level JSON netlists
rake gates:simcpu   # Export SynthDatapath CPU components
rake gates:stats    # Show synthesis statistics (gate counts per component)
rake gates:clean    # Clean gate-level output directory
```

Output files are written to `/export/gates/` with JSON netlists and TXT summaries.

### Example Statistics

```
cpu/synth_datapath: 505 gates, 24 DFFs, 697 nets
arithmetic/alu: 187 gates, 0 DFFs, 208 nets
arithmetic/divider: 183 gates, 0 DFFs, 191 nets
combinational/barrel_shifter: 167 gates, 0 DFFs, 181 nets
cpu/instruction_decoder: 160 gates, 0 DFFs, 169 nets
arithmetic/multiplier: 131 gates, 0 DFFs, 139 nets
```

### Primitive Gates

The gate-level IR uses these primitives:

| Primitive | Description |
|-----------|-------------|
| AND | 2-input AND gate |
| OR | 2-input OR gate |
| XOR | 2-input XOR gate |
| NOT | Inverter |
| MUX | 2-to-1 multiplexer |
| BUF | Buffer |
| CONST | Constant 0 or 1 |
| DFF | D flip-flop |

### Limitations

- DFF reset/enable are modeled on tick boundaries for parity with the synchronous simulator flow
- GPU backend is a stub unless a compiled extension is provided
- Memory components (RAM, ROM, RegisterFile, FIFO, Stack) use placeholder implementations for gate-level

## See Also

- [DSL Guide](dsl.md) - DSL reference for components
- [Components Reference](components.md) - All HDL components
- [8-bit CPU](8bit_cpu.md) - CPU implementation details
