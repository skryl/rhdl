.intel_syntax noprefix
.code16
.global _start

_start:
  .byte 0xEA, 0x10, 0x00, 0xFF, 0xFF
  .fill 11, 1, 0x90

real_start:
  mov di, 0x0300
  mov cx, 32
  mov ax, 0x1357

init_cells:
  mov word ptr [di], ax
  add ax, 0x1111
  add di, 2
  loop init_cells

  mov bp, 24

generation_loop:
  mov si, 0x0300
  mov di, 0x0340
  mov dx, word ptr [si + 62]
  mov cx, 32

cell_loop:
  mov ax, word ptr [si]
  mov bx, word ptr [si + 2]
  cmp cx, 1
  jne have_right
  mov bx, word ptr [0x0300]

have_right:
  xor bx, dx
  add bx, ax
  rol bx, 1
  xor bx, 0x9E37
  mov word ptr [di], bx

  mov dx, ax
  add si, 2
  add di, 2
  loop cell_loop

  mov si, 0x0340
  mov di, 0x0300
  mov cx, 32

copy_back:
  mov ax, word ptr [si]
  mov word ptr [di], ax
  add si, 2
  add di, 2
  loop copy_back

  dec bp
  jnz generation_loop

  mov si, 0x0300
  xor ax, ax
  xor dx, dx
  mov cx, 32

checksum_loop:
  add ax, word ptr [si]
  adc dx, 0
  add si, 2
  loop checksum_loop

  mov word ptr [0x0240], ax
  mov word ptr [0x0242], dx

halt:
  jmp halt
