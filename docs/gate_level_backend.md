# Gate-Level Backend Notes

## Step 0: Repo discovery

* **Component abstraction**: Behavioral simulation components live under `lib/rhdl/hdl/*` and inherit from `RHDL::HDL::SimComponent`, which defines inputs/outputs, wires, and a `propagate` method for simulation behavior. Examples include `NotGate`, `FullAdder`, `RippleCarryAdder`, and `DFlipFlop`.【F:lib/rhdl/hdl/simulation.rb†L54-L197】【F:lib/rhdl/hdl/gates.rb†L1-L214】【F:lib/rhdl/hdl/arithmetic.rb†L1-L156】【F:lib/rhdl/hdl/sequential.rb†L1-L97】
* **Signals/wires**: `RHDL::HDL::Wire` stores name, width, driver, and listeners. Connections are created via `SimComponent.connect`, which wires output changes to destination inputs.【F:lib/rhdl/hdl/simulation.rb†L54-L166】
* **Simulation ticks**: `RHDL::HDL::Simulator` advances time by ticking clocks and repeatedly calling `propagate` on all components until signals stabilize.【F:lib/rhdl/hdl/simulation.rb†L200-L267】
* **Circuit composition**: Circuits are built by instantiating `SimComponent` subclasses, connecting outputs to inputs via `SimComponent.connect`, and registering components with `Simulator`. There is no explicit graph object; wires and components are the primary structure.【F:lib/rhdl/hdl/simulation.rb†L116-L197】【F:lib/rhdl/hdl/simulation.rb†L200-L267】
* **Minimal public API for tests**: Instantiate components (e.g., `RHDL::HDL::FullAdder.new`), set inputs via `inputs[:name].set`, call `propagate` or `Simulator#run`, and read outputs via `outputs[:name].get`.

## Gate-level backend overview

The gate-level backend flattens simulation components into a gate IR (`RHDL::Gates::IR`) with dense 1-bit net indices and primitive gates. Multi-bit buses are bit-blasted into per-bit nets. The lowering pass flattens connections built via `SimComponent.connect` and emits primitive gates plus DFFs. The CPU backend evaluates gates in topological order with packed 64-lane bitmasks, while the GPU backend is currently a stub that raises a clear error when not built.

### Key files

* `lib/rhdl/export/structural/ir.rb` – Gate-level IR and JSON serialization.
* `lib/rhdl/export/structural/lower.rb` – Lowering pass from HDL components into IR, plus optional netlist dump via `RHDL_DUMP_NETLIST=1`.
* `lib/rhdl/export/structural/sim_cpu.rb` – Packed-lane CPU simulator backend.
* `lib/rhdl/export/structural/sim_gpu.rb` – GPU backend stub (optional build).

### Running the backend

```ruby
components = [RHDL::HDL::FullAdder.new('fa')]
# connect components via RHDL::HDL::SimComponent.connect as needed
sim = RHDL::Gates.gate_level(components, backend: :cpu, lanes: 64, name: 'demo')

sim.poke('fa.a', 0xffff_ffff_ffff_ffff)
sim.poke('fa.b', 0x0)
sim.poke('fa.cin', 0x0)
sim.evaluate
sum_mask = sim.peek('fa.sum')
```

### Netlist dumping

To dump a netlist JSON for debugging:

```bash
RHDL_DUMP_NETLIST=1 bundle exec rspec
```

The netlist will be written to `tmp/netlists/<name>.json`.

### Supported Components (53 total)

The lowering pass supports the following HDL components:

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
# Export all 53 components to gate-level JSON netlists
rake gates:export

# Export SynthDatapath CPU components
rake gates:simcpu

# Show synthesis statistics (gate counts per component)
rake gates:stats

# Clean gate-level output directory
rake gates:clean
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

### Limitations

* DFF reset/enable are modeled on tick boundaries for parity with the synchronous simulator flow.
* GPU backend is a stub unless a compiled extension is provided.
* Memory components (RAM, ROM, RegisterFile, FIFO, Stack) use placeholder implementations for gate-level.
