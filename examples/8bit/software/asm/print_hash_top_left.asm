; print_hash_top_left.asm
; Writes '#' to display address 0x0800 and halts.
;
; Pointer scratch:
;   0x0E = pointer high
;   0x0F = pointer low

LDI 0x08
STA 0x0E

LDI 0x00
STA 0x0F

LDI 0x23      ; '#'
STA [0x0E, 0x0F]

HLT

; Assembled bytes:
; A0 08 2E A0 00 2F A0 23 20 0E 0F F0
