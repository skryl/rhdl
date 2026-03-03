.intel_syntax noprefix
.code16
.global _start

_start:
  .byte 0xEA, 0x10, 0x00, 0xFF, 0xFF
  .fill 11, 1, 0x90

real_start:
  mov di, 0x03C0
  mov bx, 0x1357
  mov cx, 8

seed_loop:
  xor ax, ax
  mov bp, 80

iterate_loop:
  mov dx, ax
  mul dx
  add ax, bx
  adc dx, 0
  xor ax, dx
  rol ax, 1
  add ax, 0x1234
  dec bp
  jnz iterate_loop

  mov word ptr [di], ax
  add di, 2

  mov ax, bx
  shl ax, 1
  add ax, bx
  shl ax, 2
  add ax, bx
  add ax, 0x0123
  mov bx, ax

  loop seed_loop

  mov si, 0x03C0
  xor ax, ax
  xor dx, dx
  mov cx, 8

sum_loop:
  add ax, word ptr [si]
  adc dx, 0
  add si, 2
  loop sum_loop

  mov word ptr [0x0250], ax
  mov word ptr [0x0252], dx

halt:
  jmp halt
