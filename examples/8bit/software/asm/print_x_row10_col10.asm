; print_x_row10_col10.asm
; Writes 'X' to display row 10, column 10.
;
; Display base = 0x0800, width = 80
; Address = 0x0800 + (10 * 80) + 10 = 0x0B2A
;
; Pointer scratch:
;   0x0E = pointer high
;   0x0F = pointer low

LDI 0x0B
STA 0x0E

LDI 0x2A
STA 0x0F

LDI 0x58      ; 'X'
STA [0x0E, 0x0F]

HLT

; Assembled bytes:
; A0 0B 2E A0 2A 2F A0 58 20 0E 0F F0
