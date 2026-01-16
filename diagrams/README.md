# RHDL Component Diagrams

This directory contains circuit diagrams for all HDL components in RHDL.

## File Formats

Each component has three diagram files:
- `.txt` - ASCII/Unicode text diagram for terminal viewing
- `.svg` - Scalable vector graphics for web/document viewing
- `.dot` - Graphviz DOT format for custom rendering

## Rendering DOT Files

To render DOT files as PNG images using Graphviz:
```bash
dot -Tpng diagrams/cpu/datapath.dot -o cpu.png
```

## Components by Category

### Logic Gates

- [and_gate](gates/and_gate.txt) ([SVG](gates/and_gate.svg), [DOT](gates/and_gate.dot))
- [and_gate_3input](gates/and_gate_3input.txt) ([SVG](gates/and_gate_3input.svg), [DOT](gates/and_gate_3input.dot))
- [bitwise_and](gates/bitwise_and.txt) ([SVG](gates/bitwise_and.svg), [DOT](gates/bitwise_and.dot))
- [bitwise_not](gates/bitwise_not.txt) ([SVG](gates/bitwise_not.svg), [DOT](gates/bitwise_not.dot))
- [bitwise_or](gates/bitwise_or.txt) ([SVG](gates/bitwise_or.svg), [DOT](gates/bitwise_or.dot))
- [bitwise_xor](gates/bitwise_xor.txt) ([SVG](gates/bitwise_xor.svg), [DOT](gates/bitwise_xor.dot))
- [buffer](gates/buffer.txt) ([SVG](gates/buffer.svg), [DOT](gates/buffer.dot))
- [nand_gate](gates/nand_gate.txt) ([SVG](gates/nand_gate.svg), [DOT](gates/nand_gate.dot))
- [nor_gate](gates/nor_gate.txt) ([SVG](gates/nor_gate.svg), [DOT](gates/nor_gate.dot))
- [not_gate](gates/not_gate.txt) ([SVG](gates/not_gate.svg), [DOT](gates/not_gate.dot))
- [or_gate](gates/or_gate.txt) ([SVG](gates/or_gate.svg), [DOT](gates/or_gate.dot))
- [tristate_buffer](gates/tristate_buffer.txt) ([SVG](gates/tristate_buffer.svg), [DOT](gates/tristate_buffer.dot))
- [xnor_gate](gates/xnor_gate.txt) ([SVG](gates/xnor_gate.svg), [DOT](gates/xnor_gate.dot))
- [xor_gate](gates/xor_gate.txt) ([SVG](gates/xor_gate.svg), [DOT](gates/xor_gate.dot))

### Sequential Components

- [counter](sequential/counter.txt) ([SVG](sequential/counter.svg), [DOT](sequential/counter.dot))
- [d_flipflop](sequential/d_flipflop.txt) ([SVG](sequential/d_flipflop.svg), [DOT](sequential/d_flipflop.dot))
- [d_flipflop_async](sequential/d_flipflop_async.txt) ([SVG](sequential/d_flipflop_async.svg), [DOT](sequential/d_flipflop_async.dot))
- [jk_flipflop](sequential/jk_flipflop.txt) ([SVG](sequential/jk_flipflop.svg), [DOT](sequential/jk_flipflop.dot))
- [program_counter](sequential/program_counter.txt) ([SVG](sequential/program_counter.svg), [DOT](sequential/program_counter.dot))
- [register_16bit](sequential/register_16bit.txt) ([SVG](sequential/register_16bit.svg), [DOT](sequential/register_16bit.dot))
- [register_8bit](sequential/register_8bit.txt) ([SVG](sequential/register_8bit.svg), [DOT](sequential/register_8bit.dot))
- [register_load](sequential/register_load.txt) ([SVG](sequential/register_load.svg), [DOT](sequential/register_load.dot))
- [shift_register](sequential/shift_register.txt) ([SVG](sequential/shift_register.svg), [DOT](sequential/shift_register.dot))
- [sr_flipflop](sequential/sr_flipflop.txt) ([SVG](sequential/sr_flipflop.svg), [DOT](sequential/sr_flipflop.dot))
- [sr_latch](sequential/sr_latch.txt) ([SVG](sequential/sr_latch.svg), [DOT](sequential/sr_latch.dot))
- [stack_pointer](sequential/stack_pointer.txt) ([SVG](sequential/stack_pointer.svg), [DOT](sequential/stack_pointer.dot))
- [t_flipflop](sequential/t_flipflop.txt) ([SVG](sequential/t_flipflop.svg), [DOT](sequential/t_flipflop.dot))

### Arithmetic Components

- [addsub](arithmetic/addsub.txt) ([SVG](arithmetic/addsub.svg), [DOT](arithmetic/addsub.dot))
- [alu_16bit](arithmetic/alu_16bit.txt) ([SVG](arithmetic/alu_16bit.svg), [DOT](arithmetic/alu_16bit.dot))
- [alu_8bit](arithmetic/alu_8bit.txt) ([SVG](arithmetic/alu_8bit.svg), [DOT](arithmetic/alu_8bit.dot))
- [comparator](arithmetic/comparator.txt) ([SVG](arithmetic/comparator.svg), [DOT](arithmetic/comparator.dot))
- [divider](arithmetic/divider.txt) ([SVG](arithmetic/divider.svg), [DOT](arithmetic/divider.dot))
- [full_adder](arithmetic/full_adder.txt) ([SVG](arithmetic/full_adder.svg), [DOT](arithmetic/full_adder.dot))
- [half_adder](arithmetic/half_adder.txt) ([SVG](arithmetic/half_adder.svg), [DOT](arithmetic/half_adder.dot))
- [incdec](arithmetic/incdec.txt) ([SVG](arithmetic/incdec.svg), [DOT](arithmetic/incdec.dot))
- [multiplier](arithmetic/multiplier.txt) ([SVG](arithmetic/multiplier.svg), [DOT](arithmetic/multiplier.dot))
- [ripple_carry_adder](arithmetic/ripple_carry_adder.txt) ([SVG](arithmetic/ripple_carry_adder.svg), [DOT](arithmetic/ripple_carry_adder.dot))
- [subtractor](arithmetic/subtractor.txt) ([SVG](arithmetic/subtractor.svg), [DOT](arithmetic/subtractor.dot))

### Combinational Components

- [barrel_shifter](combinational/barrel_shifter.txt) ([SVG](combinational/barrel_shifter.svg), [DOT](combinational/barrel_shifter.dot))
- [bit_reverse](combinational/bit_reverse.txt) ([SVG](combinational/bit_reverse.svg), [DOT](combinational/bit_reverse.dot))
- [decoder_2to4](combinational/decoder_2to4.txt) ([SVG](combinational/decoder_2to4.svg), [DOT](combinational/decoder_2to4.dot))
- [decoder_3to8](combinational/decoder_3to8.txt) ([SVG](combinational/decoder_3to8.svg), [DOT](combinational/decoder_3to8.dot))
- [decoder_n](combinational/decoder_n.txt) ([SVG](combinational/decoder_n.svg), [DOT](combinational/decoder_n.dot))
- [demux2](combinational/demux2.txt) ([SVG](combinational/demux2.svg), [DOT](combinational/demux2.dot))
- [demux4](combinational/demux4.txt) ([SVG](combinational/demux4.svg), [DOT](combinational/demux4.dot))
- [encoder_4to2](combinational/encoder_4to2.txt) ([SVG](combinational/encoder_4to2.svg), [DOT](combinational/encoder_4to2.dot))
- [encoder_8to3](combinational/encoder_8to3.txt) ([SVG](combinational/encoder_8to3.svg), [DOT](combinational/encoder_8to3.dot))
- [lzcount](combinational/lzcount.txt) ([SVG](combinational/lzcount.svg), [DOT](combinational/lzcount.dot))
- [mux2](combinational/mux2.txt) ([SVG](combinational/mux2.svg), [DOT](combinational/mux2.dot))
- [mux4](combinational/mux4.txt) ([SVG](combinational/mux4.svg), [DOT](combinational/mux4.dot))
- [mux8](combinational/mux8.txt) ([SVG](combinational/mux8.svg), [DOT](combinational/mux8.dot))
- [muxn](combinational/muxn.txt) ([SVG](combinational/muxn.svg), [DOT](combinational/muxn.dot))
- [popcount](combinational/popcount.txt) ([SVG](combinational/popcount.svg), [DOT](combinational/popcount.dot))
- [sign_extend](combinational/sign_extend.txt) ([SVG](combinational/sign_extend.svg), [DOT](combinational/sign_extend.dot))
- [zero_detect](combinational/zero_detect.txt) ([SVG](combinational/zero_detect.svg), [DOT](combinational/zero_detect.dot))
- [zero_extend](combinational/zero_extend.txt) ([SVG](combinational/zero_extend.svg), [DOT](combinational/zero_extend.dot))

### Memory Components

- [dual_port_ram](memory/dual_port_ram.txt) ([SVG](memory/dual_port_ram.svg), [DOT](memory/dual_port_ram.dot))
- [fifo](memory/fifo.txt) ([SVG](memory/fifo.svg), [DOT](memory/fifo.dot))
- [ram](memory/ram.txt) ([SVG](memory/ram.svg), [DOT](memory/ram.dot))
- [ram_64k](memory/ram_64k.txt) ([SVG](memory/ram_64k.svg), [DOT](memory/ram_64k.dot))
- [register_file](memory/register_file.txt) ([SVG](memory/register_file.svg), [DOT](memory/register_file.dot))
- [rom](memory/rom.txt) ([SVG](memory/rom.svg), [DOT](memory/rom.dot))
- [stack](memory/stack.txt) ([SVG](memory/stack.svg), [DOT](memory/stack.dot))

### CPU Components

- [accumulator](cpu/accumulator.txt) ([SVG](cpu/accumulator.svg), [DOT](cpu/accumulator.dot))
- [datapath](cpu/datapath.txt) ([SVG](cpu/datapath.svg), [DOT](cpu/datapath.dot))
- [instruction_decoder](cpu/instruction_decoder.txt) ([SVG](cpu/instruction_decoder.svg), [DOT](cpu/instruction_decoder.dot))

## Regenerating Diagrams

To regenerate all diagrams, run:
```bash
rake diagrams:generate
```

---
*Generated by RHDL Circuit Diagram Generator*