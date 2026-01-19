# RHDL Component Diagrams

This directory contains circuit diagrams for all HDL components in RHDL,
organized into three visualization modes.

## Diagram Modes

### Component (`component/`)
Simple block diagrams showing component interface (inputs/outputs).
Best for understanding what a component does at a high level.

### Hierarchical (`hierarchical/`)
Detailed schematics showing internal subcomponents and hierarchy.
Best for understanding how complex components are built from simpler ones.

### Gate (`gate/`)
Gate-level netlist diagrams showing primitive logic gates and flip-flops.
Only available for components that support gate-level lowering.
Best for understanding the actual hardware implementation.

## File Formats

Each component has up to three diagram files:
- `.txt` - ASCII/Unicode text diagram for terminal viewing
- `.svg` - Scalable vector graphics for web/document viewing
- `.dot` - Graphviz DOT format for custom rendering

## Rendering DOT Files

To render DOT files as PNG images using Graphviz:
```bash
dot -Tpng diagrams/gate/arithmetic/full_adder.dot -o full_adder.png
```

## Components by Category

### Logic Gates

- **and_gate**: [Component](component/gates/and_gate.txt), [Hierarchical](hierarchical/gates/and_gate.txt), [Gate](gate/gates/and_gate.dot)
- **and_gate_3input**: [Component](component/gates/and_gate_3input.txt), [Hierarchical](hierarchical/gates/and_gate_3input.txt), [Gate](gate/gates/and_gate_3input.dot)
- **bitwise_and**: [Component](component/gates/bitwise_and.txt), [Hierarchical](hierarchical/gates/bitwise_and.txt), [Gate](gate/gates/bitwise_and.dot)
- **bitwise_not**: [Component](component/gates/bitwise_not.txt), [Hierarchical](hierarchical/gates/bitwise_not.txt)
- **bitwise_or**: [Component](component/gates/bitwise_or.txt), [Hierarchical](hierarchical/gates/bitwise_or.txt), [Gate](gate/gates/bitwise_or.dot)
- **bitwise_xor**: [Component](component/gates/bitwise_xor.txt), [Hierarchical](hierarchical/gates/bitwise_xor.txt), [Gate](gate/gates/bitwise_xor.dot)
- **buffer**: [Component](component/gates/buffer.txt), [Hierarchical](hierarchical/gates/buffer.txt), [Gate](gate/gates/buffer.dot)
- **nand_gate**: [Component](component/gates/nand_gate.txt), [Hierarchical](hierarchical/gates/nand_gate.txt)
- **nor_gate**: [Component](component/gates/nor_gate.txt), [Hierarchical](hierarchical/gates/nor_gate.txt)
- **not_gate**: [Component](component/gates/not_gate.txt), [Hierarchical](hierarchical/gates/not_gate.txt), [Gate](gate/gates/not_gate.dot)
- **or_gate**: [Component](component/gates/or_gate.txt), [Hierarchical](hierarchical/gates/or_gate.txt), [Gate](gate/gates/or_gate.dot)
- **tristate_buffer**: [Component](component/gates/tristate_buffer.txt), [Hierarchical](hierarchical/gates/tristate_buffer.txt)
- **xnor_gate**: [Component](component/gates/xnor_gate.txt), [Hierarchical](hierarchical/gates/xnor_gate.txt)
- **xor_gate**: [Component](component/gates/xor_gate.txt), [Hierarchical](hierarchical/gates/xor_gate.txt), [Gate](gate/gates/xor_gate.dot)

### Sequential Components

- **counter**: [Component](component/sequential/counter.txt), [Hierarchical](hierarchical/sequential/counter.txt)
- **d_flipflop**: [Component](component/sequential/d_flipflop.txt), [Hierarchical](hierarchical/sequential/d_flipflop.txt), [Gate](gate/sequential/d_flipflop.dot)
- **d_flipflop_async**: [Component](component/sequential/d_flipflop_async.txt), [Hierarchical](hierarchical/sequential/d_flipflop_async.txt), [Gate](gate/sequential/d_flipflop_async.dot)
- **jk_flipflop**: [Component](component/sequential/jk_flipflop.txt), [Hierarchical](hierarchical/sequential/jk_flipflop.txt)
- **program_counter**: [Component](component/sequential/program_counter.txt), [Hierarchical](hierarchical/sequential/program_counter.txt)
- **register_16bit**: [Component](component/sequential/register_16bit.txt), [Hierarchical](hierarchical/sequential/register_16bit.txt)
- **register_8bit**: [Component](component/sequential/register_8bit.txt), [Hierarchical](hierarchical/sequential/register_8bit.txt)
- **register_load**: [Component](component/sequential/register_load.txt), [Hierarchical](hierarchical/sequential/register_load.txt)
- **shift_register**: [Component](component/sequential/shift_register.txt), [Hierarchical](hierarchical/sequential/shift_register.txt)
- **sr_flipflop**: [Component](component/sequential/sr_flipflop.txt), [Hierarchical](hierarchical/sequential/sr_flipflop.txt)
- **sr_latch**: [Component](component/sequential/sr_latch.txt), [Hierarchical](hierarchical/sequential/sr_latch.txt)
- **stack_pointer**: [Component](component/sequential/stack_pointer.txt), [Hierarchical](hierarchical/sequential/stack_pointer.txt)
- **t_flipflop**: [Component](component/sequential/t_flipflop.txt), [Hierarchical](hierarchical/sequential/t_flipflop.txt)

### Arithmetic Components

- **addsub**: [Component](component/arithmetic/addsub.txt), [Hierarchical](hierarchical/arithmetic/addsub.txt)
- **alu_16bit**: [Component](component/arithmetic/alu_16bit.txt), [Hierarchical](hierarchical/arithmetic/alu_16bit.txt)
- **alu_8bit**: [Component](component/arithmetic/alu_8bit.txt), [Hierarchical](hierarchical/arithmetic/alu_8bit.txt)
- **comparator**: [Component](component/arithmetic/comparator.txt), [Hierarchical](hierarchical/arithmetic/comparator.txt)
- **divider**: [Component](component/arithmetic/divider.txt), [Hierarchical](hierarchical/arithmetic/divider.txt)
- **full_adder**: [Component](component/arithmetic/full_adder.txt), [Hierarchical](hierarchical/arithmetic/full_adder.txt), [Gate](gate/arithmetic/full_adder.dot)
- **half_adder**: [Component](component/arithmetic/half_adder.txt), [Hierarchical](hierarchical/arithmetic/half_adder.txt), [Gate](gate/arithmetic/half_adder.dot)
- **incdec**: [Component](component/arithmetic/incdec.txt), [Hierarchical](hierarchical/arithmetic/incdec.txt)
- **multiplier**: [Component](component/arithmetic/multiplier.txt), [Hierarchical](hierarchical/arithmetic/multiplier.txt)
- **ripple_carry_adder**: [Component](component/arithmetic/ripple_carry_adder.txt), [Hierarchical](hierarchical/arithmetic/ripple_carry_adder.txt), [Gate](gate/arithmetic/ripple_carry_adder.dot)
- **subtractor**: [Component](component/arithmetic/subtractor.txt), [Hierarchical](hierarchical/arithmetic/subtractor.txt)

### Combinational Components

- **barrel_shifter**: [Component](component/combinational/barrel_shifter.txt), [Hierarchical](hierarchical/combinational/barrel_shifter.txt)
- **bit_reverse**: [Component](component/combinational/bit_reverse.txt), [Hierarchical](hierarchical/combinational/bit_reverse.txt)
- **decoder_2to4**: [Component](component/combinational/decoder_2to4.txt), [Hierarchical](hierarchical/combinational/decoder_2to4.txt)
- **decoder_3to8**: [Component](component/combinational/decoder_3to8.txt), [Hierarchical](hierarchical/combinational/decoder_3to8.txt)
- **decoder_n**: [Component](component/combinational/decoder_n.txt), [Hierarchical](hierarchical/combinational/decoder_n.txt)
- **demux2**: [Component](component/combinational/demux2.txt), [Hierarchical](hierarchical/combinational/demux2.txt)
- **demux4**: [Component](component/combinational/demux4.txt), [Hierarchical](hierarchical/combinational/demux4.txt)
- **encoder_4to2**: [Component](component/combinational/encoder_4to2.txt), [Hierarchical](hierarchical/combinational/encoder_4to2.txt)
- **encoder_8to3**: [Component](component/combinational/encoder_8to3.txt), [Hierarchical](hierarchical/combinational/encoder_8to3.txt)
- **lzcount**: [Component](component/combinational/lzcount.txt), [Hierarchical](hierarchical/combinational/lzcount.txt)
- **mux2**: [Component](component/combinational/mux2.txt), [Hierarchical](hierarchical/combinational/mux2.txt), [Gate](gate/combinational/mux2.dot)
- **mux4**: [Component](component/combinational/mux4.txt), [Hierarchical](hierarchical/combinational/mux4.txt)
- **mux8**: [Component](component/combinational/mux8.txt), [Hierarchical](hierarchical/combinational/mux8.txt)
- **muxn**: [Component](component/combinational/muxn.txt), [Hierarchical](hierarchical/combinational/muxn.txt)
- **popcount**: [Component](component/combinational/popcount.txt), [Hierarchical](hierarchical/combinational/popcount.txt)
- **sign_extend**: [Component](component/combinational/sign_extend.txt), [Hierarchical](hierarchical/combinational/sign_extend.txt)
- **zero_detect**: [Component](component/combinational/zero_detect.txt), [Hierarchical](hierarchical/combinational/zero_detect.txt)
- **zero_extend**: [Component](component/combinational/zero_extend.txt), [Hierarchical](hierarchical/combinational/zero_extend.txt)

### Memory Components

- **dual_port_ram**: [Component](component/memory/dual_port_ram.txt), [Hierarchical](hierarchical/memory/dual_port_ram.txt)
- **fifo**: [Component](component/memory/fifo.txt), [Hierarchical](hierarchical/memory/fifo.txt)
- **ram**: [Component](component/memory/ram.txt), [Hierarchical](hierarchical/memory/ram.txt)
- **ram_64k**: [Component](component/memory/ram_64k.txt), [Hierarchical](hierarchical/memory/ram_64k.txt)
- **register_file**: [Component](component/memory/register_file.txt), [Hierarchical](hierarchical/memory/register_file.txt)
- **rom**: [Component](component/memory/rom.txt), [Hierarchical](hierarchical/memory/rom.txt)
- **stack**: [Component](component/memory/stack.txt), [Hierarchical](hierarchical/memory/stack.txt)

### CPU Components

- **accumulator**: [Component](component/cpu/accumulator.txt), [Hierarchical](hierarchical/cpu/accumulator.txt)
- **datapath**: [Component](component/cpu/datapath.txt), [Hierarchical](hierarchical/cpu/datapath.txt)
- **instruction_decoder**: [Component](component/cpu/instruction_decoder.txt), [Hierarchical](hierarchical/cpu/instruction_decoder.txt)

## Regenerating Diagrams

```bash
# Generate all diagrams in all modes
rake diagrams:generate

# Generate only component-level diagrams
rake diagrams:component

# Generate only hierarchical diagrams
rake diagrams:hierarchical

# Generate only gate-level diagrams
rake diagrams:gate
```

---
*Generated by RHDL Circuit Diagram Generator*