# HDL Export (Verilog)

This document describes the HDL export support implemented by `RHDL::Export`.

## Supported subset

The export pipeline currently supports a focused subset of the RHDL DSL:

* Ports (input/output/inout) with explicit widths.
* Internal registers declared via `signal`.
* Continuous assignments (`assign`).
* Combinational processes with `if`/`else` and sequential assignments.
* Clocked processes with `if`/`else` and sequential assignments.
* Expressions:
  * Bitwise ops: `&`, `|`, `^`, `~`
  * Arithmetic: `+` and `-`
  * Shifts: `<<`, `>>`
  * Comparisons: `==`, `!=`, `<`, `>`, `<=`, `>=`
  * Concatenation and replication
  * Conditional/mux (via `assign` with a condition or `if`/`else` in a process)

Anything outside this subset will raise an error during lowering.

## Signal naming rules

* Identifiers are sanitized for HDL output:
  * Invalid characters are replaced with `_`.
  * Verilog keywords are suffixed with `_rhdl`.
  * Identifiers starting with a digit are prefixed with `_`.

## Vector conventions

* Verilog uses `[W-1:0]`.
* Width 1 is emitted as a scalar port.

## Clock/reset semantics

* Clocked processes use `posedge clk` in Verilog.
* Synchronous reset and enable can be expressed with `if`/`else` inside the
  clocked process (reset/enable are treated as data signals evaluated on
  the active clock edge).

## Running export tests locally

Verilog export tests require Icarus Verilog (`iverilog` and `vvp`).

If the toolchain is missing, the corresponding specs are skipped automatically.

Run all specs:

```
bundle exec rspec
```

Run only the HDL export specs:

```
bundle exec rspec spec/export_verilog_spec.rb
```

## Output Directory

All generated HDL files are placed in the `/export/` directory:

* `/export/verilog/` - Generated Verilog files

## Rake Tasks

```bash
# Export all DSL components to Verilog
rake hdl:export

# Export Verilog
rake hdl:verilog

# Clean generated HDL files
rake hdl:clean
```
