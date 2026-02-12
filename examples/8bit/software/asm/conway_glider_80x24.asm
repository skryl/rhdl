; conway_glider_80x24.asm
;
; Conway glider demo for the examples/8bit CPU.
; The display is treated as a toroidal 80x24 grid (wrap-around on both axes).
;
; Implementation notes:
; - Program entry point is 0x20.
; - Uses precomputed 32 glider frames (row/col pairs) generated from
;   Conway's Game of Life on an 80x24 torus.
; - Each loop:
;   1) Erase current frame with space (' ')
;   2) Advance frame index (mod 32)
;   3) Draw next frame with '#'
;
; Memory layout used by the binary image:
;   0x0200..0x0217 : row high-byte table for display base 0x0800, width 80
;   0x0220..0x0237 : row low-byte table
;   0x0300..0x031F : frame pointer low-byte table
;   0x0320..0x033F : frame pointer high-byte table
;   0x0400..       : packed frame data (5 cells/frame, row+col bytes)
;
; The assembled binary is:
;   examples/8bit/software/bin/conway_glider_80x24.bin
