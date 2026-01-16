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

* `lib/rhdl/gates/ir.rb` – Gate-level IR and JSON serialization.
* `lib/rhdl/gates/lower.rb` – Lowering pass from HDL components into IR, plus optional netlist dump via `RHDL_DUMP_NETLIST=1`.
* `lib/rhdl/gates/sim_cpu.rb` – Packed-lane CPU simulator backend.
* `lib/rhdl/gates/sim_gpu.rb` – GPU backend stub (optional build).

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

### Limitations

* Lowering currently supports: `NotGate`, `Buffer`, `AndGate`, `OrGate`, `XorGate`, `BitwiseAnd`, `BitwiseOr`, `BitwiseXor`, `Mux2`, `HalfAdder`, `FullAdder`, `RippleCarryAdder`, `DFlipFlop`, and `DFlipFlopAsync`.
* DFF reset/enable are modeled on tick boundaries for parity with the synchronous simulator flow.
* GPU backend is a stub unless a compiled extension is provided.
