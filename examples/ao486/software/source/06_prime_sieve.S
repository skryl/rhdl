.intel_syntax noprefix
.code16
.global _start

_start:
  .byte 0xEA, 0x10, 0x00, 0xFF, 0xFF
  .fill 11, 1, 0x90

real_start:
  mov di, 0x0500
  mov cx, 128
  mov al, 1

init_flags:
  mov byte ptr [di], al
  inc di
  loop init_flags

  mov byte ptr [0x0500], 0
  mov byte ptr [0x0501], 0

  mov bx, 2

outer_loop:
  cmp bx, 12
  ja sum_primes

  mov si, 0x0500
  add si, bx
  mov al, byte ptr [si]
  cmp al, 0
  je next_prime

  mov ax, bx
  mul bx
  mov si, ax

mark_loop:
  cmp si, 127
  ja next_prime
  mov di, 0x0500
  add di, si
  mov byte ptr [di], 0
  add si, bx
  jmp mark_loop

next_prime:
  inc bx
  jmp outer_loop

sum_primes:
  xor ax, ax
  xor dx, dx
  mov bx, 2

sum_loop:
  cmp bx, 128
  jae done
  mov si, 0x0500
  add si, bx
  mov cl, byte ptr [si]
  cmp cl, 0
  je skip_add
  add ax, bx
  inc dx

skip_add:
  inc bx
  jmp sum_loop

done:
  mov word ptr [0x0260], ax
  mov word ptr [0x0262], dx

halt:
  jmp halt
