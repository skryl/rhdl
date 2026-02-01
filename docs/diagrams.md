# Diagram Generation

RHDL can generate visual diagrams of components at multiple abstraction levels. Diagrams are generated from internal models (no hand-authored drawings) and exported as DOT, SVG, and PNG formats.

## Overview

The diagram system supports four types of visualizations:

| Type | Description | Use Case |
|------|-------------|----------|
| **Component** | Single component with ports | Documentation, port reference |
| **Hierarchy** | Component with sub-component tree | Architecture overview |
| **Netlist** | Wire-level connectivity | Debugging connections |
| **Gate-Level** | Primitive gates and DFFs | Low-level verification |

## Quick Start

### Command Line

```bash
# Generate all diagrams (component, hierarchy, gate-level)
rhdl diagram --all

# Single component diagram
rhdl diagram RHDL::HDL::ALU --level component --format svg

# Hierarchy diagram with depth
rhdl diagram RHDL::HDL::CPU --level hierarchy --depth 2

# Gate-level diagram
rhdl diagram RHDL::HDL::RippleCarryAdder --level gate

# Output to specific directory
rhdl diagram --all --out ./my_diagrams
```

### Ruby API

```ruby
require 'rhdl'

# Create a component
component = RHDL::HDL::HalfAdder.new("half_adder")

# Generate different diagram types
component_diagram = RHDL::Diagram.component(component)
hierarchy_diagram = RHDL::Diagram.hierarchy(component, depth: 2)
netlist_diagram = RHDL::Diagram.netlist(component)

# Export to different formats
dot_string = component_diagram.to_dot
svg_string = component_diagram.to_svg  # Requires Graphviz
json_data = component_diagram.to_json

# Save directly
component_diagram.save_dot("half_adder.dot")
component_diagram.save_svg("half_adder.svg")
```

## Diagram Types

### 1. Component Diagrams

Component diagrams show a single component as a box with labeled input and output ports.

**Example Output (ASCII representation):**
```
            ┌─────────────────┐
      a ────┤                 ├──── sum
            │   HalfAdder     │
      b ────┤                 ├──── cout
            └─────────────────┘
```

**API:**
```ruby
diagram = RHDL::Diagram.component(component)
```

**Use Cases:**
- API documentation
- Port reference sheets
- Component library catalogs

### 2. Hierarchy Diagrams

Hierarchy diagrams show a component with its internal sub-components and their connections.

**Example Output (conceptual):**
```
┌────────────────────────────────────────────────────┐
│                    CPU                              │
│  ┌─────────┐    ┌─────────┐    ┌─────────────┐     │
│  │   PC    │───▶│ Decoder │───▶│    ALU      │     │
│  └─────────┘    └─────────┘    └─────────────┘     │
│       │              │               │              │
│       ▼              ▼               ▼              │
│  ┌─────────┐    ┌─────────┐    ┌─────────────┐     │
│  │  Memory │◀───│ Control │───▶│  Registers  │     │
│  └─────────┘    └─────────┘    └─────────────┘     │
└────────────────────────────────────────────────────┘
```

**API:**
```ruby
# Show 1 level of sub-components
diagram = RHDL::Diagram.hierarchy(component, depth: 1)

# Show 2 levels deep
diagram = RHDL::Diagram.hierarchy(component, depth: 2)

# Show all levels
diagram = RHDL::Diagram.hierarchy(component, depth: :all)
```

**Use Cases:**
- Architecture documentation
- Design reviews
- Understanding component structure

### 3. Netlist Diagrams

Netlist diagrams show wire-level connectivity between components and ports.

**Example Output (conceptual):**
```
        a[7:0] ─────┬──────▶ alu.a[7:0]
                    │
                    └──────▶ comparator.a[7:0]

        b[7:0] ─────────────▶ alu.b[7:0]

  alu.result[7:0] ─────────▶ register.d[7:0]

register.q[7:0] ───────────▶ result[7:0]
```

**API:**
```ruby
diagram = RHDL::Diagram.netlist(component)
```

**Use Cases:**
- Debugging connectivity issues
- Verifying port mappings
- Understanding signal flow

### 4. Gate-Level Diagrams

Gate-level diagrams show the actual primitive gates (AND, OR, XOR, NOT, MUX) and flip-flops after synthesis.

**Example Output (Full Adder):**
```
    a ──┬──────▶ XOR ──┬────▶ XOR ──▶ sum
        │              │
    b ──┼───┬──▶ XOR ──┘
        │   │
        │   └──▶ AND ──┬────▶ OR ──▶ cout
        │              │
        └──────▶ AND ──┘
                  │
   cin ──────────┴────▶
```

**API:**
```ruby
# First, get gate-level IR
ir = RHDL::Codegen::Structure::Lower.from_components([component])

# Then generate diagram
diagram = RHDL::Diagram.gate_level(ir)

# Options
diagram = RHDL::Diagram.gate_level(ir,
  bit_blasted: false,    # Collapse multi-bit buses (default)
  collapse_buses: true   # Show buses as single lines (default)
)
```

**Bit-Blasted Mode:**

For detailed analysis, use bit-blasted mode to see individual bit connections:

```bash
rhdl diagram RHDL::HDL::RippleCarryAdder --level gate --bit-blasted
```

This shows each bit of a bus as a separate net, useful for debugging but produces larger diagrams.

**Use Cases:**
- Verification against behavioral model
- Understanding synthesis results
- Educational purposes (seeing how logic is built)

## Output Formats

### DOT (Graphviz)

DOT format is always available and produces deterministic output:

```ruby
dot_string = diagram.to_dot
File.write("component.dot", dot_string)
```

DOT files can be rendered using Graphviz tools:
```bash
dot -Tsvg component.dot -o component.svg
dot -Tpng component.dot -o component.png
```

### SVG (Scalable Vector Graphics)

SVG output requires Graphviz to be installed:

```ruby
svg_string = diagram.to_svg
File.write("component.svg", svg_string)

# Or save directly
diagram.save_svg("component.svg")
```

### PNG (Raster Image)

PNG output also requires Graphviz:

```ruby
png_binary = diagram.to_png
File.write("component.png", png_binary, mode: 'wb')
```

### JSON (Data Export)

Export diagram data as JSON for custom rendering:

```ruby
json_data = diagram.to_json
```

## Installing Graphviz

Graphviz is required for SVG and PNG output.

**Ubuntu/Debian:**
```bash
sudo apt-get install graphviz
```

**macOS (Homebrew):**
```bash
brew install graphviz
```

**Windows:**
```bash
choco install graphviz
```

**Verify Installation:**
```bash
dot -V
# Should output: dot - graphviz version X.X.X
```

If Graphviz is not available, the CLI will:
1. Generate DOT files only
2. Print a warning message
3. Exit successfully (non-fatal)

## CLI Reference

### Commands

```bash
# Batch mode - generate all diagrams
rhdl diagram --all

# Batch mode with specific diagram type
rhdl diagram --all --mode component
rhdl diagram --all --mode hierarchical
rhdl diagram --all --mode gate
rhdl diagram --all --mode all  # Default: generates all types

# Single component
rhdl diagram RHDL::HDL::ALU

# Using component shorthand
rhdl diagram arithmetic/alu
rhdl diagram sequential/counter
rhdl diagram gates/and
```

### Options

| Option | Description | Values |
|--------|-------------|--------|
| `--all` | Generate for all components | - |
| `--mode MODE` | Batch diagram type | `component`, `hierarchical`, `gate`, `all` |
| `--level LEVEL` | Single component level | `component`, `hierarchy`, `netlist`, `gate` |
| `--depth DEPTH` | Hierarchy depth | Number or `all` |
| `--bit-blasted` | Show individual bits | - |
| `--format FORMAT` | Output format | `svg`, `png`, `dot` |
| `--out DIR` | Output directory | Path (default: `diagrams/`) |
| `--clean` | Delete generated diagrams | - |

### Output Structure

When using `--all`, diagrams are organized by category:

```
diagrams/
├── README.md                    # Generated index
├── gates/
│   ├── and_gate_component.svg
│   ├── and_gate_hierarchy.svg
│   └── and_gate_gate.svg
├── sequential/
│   ├── register_component.svg
│   ├── register_hierarchy.svg
│   └── register_gate.svg
├── arithmetic/
│   ├── alu_component.svg
│   ├── alu_hierarchy.svg
│   └── alu_gate.svg
├── combinational/
│   └── ...
├── memory/
│   └── ...
└── cpu/
    └── ...
```

## Internal Architecture

### Data Flow

```
Component Instance
        │
        ▼
┌───────────────────┐
│   Diagram Builder │  Creates diagram model
└───────────────────┘
        │
        ▼
┌───────────────────┐
│   Diagram Model   │  Abstract representation
└───────────────────┘
        │
        ├──────────────┬──────────────┐
        ▼              ▼              ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│ DOT Renderer│ │ SVG Renderer│ │JSON Renderer│
└─────────────┘ └─────────────┘ └─────────────┘
```

### Internal Conventions

Diagram builders rely on these internal structures:

1. **Component Interface:**
   - `inputs` - Hash of input `Wire` instances
   - `outputs` - Hash of output `Wire` instances
   - `internal_signals` - Hash of internal `Wire` instances
   - `@subcomponents` - Hash of child component instances

2. **Wire Connectivity:**
   - `Wire#driver` - Component/wire that drives this signal
   - `Wire#sinks` - Array of wires connected to this output

3. **Gate-Level IR:**
   - `ir.inputs` - Hash of input name to net index array
   - `ir.outputs` - Hash of output name to net index array
   - `ir.gates` - Array of Gate structs
   - `ir.dffs` - Array of DFF structs

## Performance Considerations

### Large Designs

Gate-level diagrams can become very large. Recommendations:

1. **Use Collapsed Buses (default):**
   ```bash
   rhdl diagram component --level gate
   # Buses shown as single lines with [7:0] notation
   ```

2. **Limit Hierarchy Depth:**
   ```bash
   rhdl diagram component --level hierarchy --depth 1
   # Only immediate children shown
   ```

3. **Generate Specific Components:**
   ```bash
   rhdl diagram RHDL::HDL::FullAdder --level gate
   # Instead of generating all components
   ```

### Gate Count Guidelines

| Gates | Rendering Time | Viewability |
|-------|---------------|-------------|
| < 100 | < 1 second | Excellent |
| 100-500 | 1-5 seconds | Good |
| 500-2000 | 5-30 seconds | Usable with zoom |
| > 2000 | > 30 seconds | Consider subsections |

## Troubleshooting

### "dot: command not found"

Graphviz is not installed. Install it using your package manager (see Installing Graphviz section).

### Empty or Minimal Diagrams

1. **Check component has ports:**
   ```ruby
   puts component.inputs.keys
   puts component.outputs.keys
   ```

2. **Ensure component is properly initialized:**
   ```ruby
   component = RHDL::HDL::ALU.new("alu", width: 8)
   # Parameters may be required
   ```

### SVG Not Rendering Correctly

1. **Try PNG format** to isolate SVG viewer issues
2. **Check DOT file** for syntax errors:
   ```bash
   dot -Tsvg component.dot -o test.svg
   ```

### Gate-Level Diagram Missing Gates

1. **Component may not support gate-level synthesis:**
   - Check if component is in the supported list (see [export.md](export.md))

2. **Lower the component first:**
   ```ruby
   ir = RHDL::Codegen::Structure::Lower.from_components([component])
   puts ir.gates.length  # Should be > 0
   ```

## Examples

### Generate Documentation for a Library

```ruby
require 'rhdl'

# List of components to document
components = [
  RHDL::HDL::AndGate,
  RHDL::HDL::OrGate,
  RHDL::HDL::Register,
  RHDL::HDL::ALU
]

components.each do |klass|
  name = klass.name.split('::').last.downcase
  comp = klass.new(name, width: 8) rescue klass.new(name)

  diagram = RHDL::Diagram.component(comp)
  diagram.save_svg("docs/#{name}.svg")

  puts "Generated #{name}.svg"
end
```

### Custom Diagram Styling (DOT)

```ruby
diagram = RHDL::Diagram.component(component)
dot = diagram.to_dot

# Customize DOT attributes
custom_dot = dot.gsub(
  'node [shape=box]',
  'node [shape=box, fillcolor=lightblue, style=filled]'
)

File.write("styled.dot", custom_dot)
system("dot -Tsvg styled.dot -o styled.svg")
```

### Comparing Behavioral vs Gate-Level

```ruby
# Behavioral diagram
behavior_diagram = RHDL::Diagram.component(component)
behavior_diagram.save_svg("adder_behavioral.svg")

# Gate-level diagram
ir = RHDL::Codegen::Structure::Lower.from_components([component])
gate_diagram = RHDL::Diagram.gate_level(ir)
gate_diagram.save_svg("adder_gates.svg")

# Now you can visually compare the abstractions
```

## File Locations

```
lib/rhdl/diagram/
├── component.rb      # Component-level diagram builder
├── hierarchy.rb      # Hierarchy diagram builder
├── netlist.rb        # Netlist diagram builder
├── gate_level.rb     # Gate-level diagram builder
├── render_svg.rb     # SVG rendering
├── render_dot.rb     # DOT format rendering
├── renderer.rb       # ASCII/Unicode circuit renderer
├── svg_renderer.rb   # SVG diagram renderer
└── methods.rb        # Extension methods for components

diagrams/             # Generated diagram output (default)
```

## See Also

- [CLI Reference](cli.md) - Full CLI documentation
- [Components](components.md) - Component library reference
- [Gate-Level Backend](gate_level_backend.md) - Gate-level synthesis details
- [Export](export.md) - Verilog and gate export
