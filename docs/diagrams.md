# Diagram Generation

RHDL can generate visual diagrams of components across abstraction levels. Diagrams are generated from internal models (no hand-authored drawings) and exported as DOT and SVG (PNG optional when Graphviz is available).

## Internal representation assumptions

Diagram builders rely on the following internal conventions:

- Components are `RHDL::HDL::SimComponent` (or subclasses) that expose `inputs`, `outputs`, and `internal_signals` as hashes of `Wire` instances.
- Subcomponents are tracked in `@subcomponents` (via `add_subcomponent`) and can be traversed by inspecting that instance variable.
- Connectivity is discovered by inspecting `Wire#driver` and `Wire#sinks`, which are populated via `SimComponent.connect`.
- Gate-level diagrams operate directly on `RHDL::Gates::IR`, where nets are integer IDs and inputs/outputs are named buses with arrays of net IDs.

## API

```ruby
component = RHDL::HDL::HalfAdder.new("half_adder")

diagram = RHDL::Diagram.component(component)
dot = diagram.to_dot
json = diagram.to_json
```

Available APIs:

- `RHDL::Diagram.component(component)`
- `RHDL::Diagram.hierarchy(component, depth: 1..N or :all)`
- `RHDL::Diagram.netlist(component)`
- `RHDL::Diagram.gate_level(gate_ir, bit_blasted: false, collapse_buses: true)`

## CLI

```
bin/rhdl diagram HalfAdder --level component
bin/rhdl diagram CPU6502 --level hierarchy --depth 2
bin/rhdl diagram CPU6502 --level gate --bit-blasted
```

Options:

- `--level component|hierarchy|netlist|gate`
- `--depth N|all` (hierarchy)
- `--bit-blasted` (gate-level)
- `--format svg|png|dot`
- `--out <dir>`

## Output formats

- DOT is always available and deterministic.
- SVG/PNG require Graphviz (`dot`). If Graphviz is not available, the CLI falls back to writing a `.dot` file and prints a warning.

## Notes

- Gate-level diagrams can grow quickly; use collapsed buses by default and enable `--bit-blasted` only when necessary.
- Hierarchy depth controls the number of subcomponent levels included in the diagram.
