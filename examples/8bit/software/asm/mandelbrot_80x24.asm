; mandelbrot_80x24.asm
;
; Runtime Mandelbrot renderer for the examples/8bit CPU.
;
; This program computes the set at runtime and writes an 80x24 text image into
; display memory starting at 0x0800. Each pixel is rendered as:
;   '.' = inside / did not escape by max iterations
;   '#' = escaped
;
; Numeric model:
; - Fixed-point scale: 4
; - Max iterations: 12
; - Escape test: z^2 > 4 (implemented via 8-bit lookup classification)
;
; Binary memory layout:
;   0x0000..0x0002 : trampoline (JMP_LONG 0x0400)
;   0x0100..0x01FF : magnitude class table
;                    class 2 => <= 15, class 1 => 16..64, class 0 => > 64
;   0x0200..0x024F : X coordinate lookup table (80 entries, scaled)
;   0x0300..0x0317 : Y coordinate lookup table (24 entries, scaled)
;   0x0400..       : Mandelbrot program code
;
; Low-memory scratch (0x00..0x0F) is used for ALU operations because this ISA's
; arithmetic op operands are nibble-encoded memory addresses for 1-byte forms.
;
; Generated binary:
;   examples/8bit/software/bin/mandelbrot_80x24.bin
