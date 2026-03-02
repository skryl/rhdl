bits 16
org 0x000F_FFF0
mov ax, 0x1001
mov bx, 0x0022
add ax, bx
mov [0x0200], ax
jmp $
