# 8bit CPU Software Programs

This folder contains small assembled programs for the `examples/8bit` CPU.

Each program is provided as:
- An annotated source file in `asm/`
- A raw binary image in `bin/`

## Program List

1. `conway_glider_80x24`
Runs a Conway's Game of Life glider animation on a wrapping `80x24` text grid.
The program uses precomputed toroidal glider generations and streams them to the
display as `#` cells.

2. `mandelbrot_80x24`
Computes and renders an `80x24` Mandelbrot set at runtime using fixed-point
math and lookup tables (`.` for in-set points, `#` for escaped points).

3. `print_hash_top_left`
Prints `#` at screen row 0, column 0 (`0x0800`).

4. `print_x_row10_col10`
Prints `X` at screen row 10, column 10 (`0x0B2A`).

The screen memory base is `0x0800` with a linear `80x24` text layout.
