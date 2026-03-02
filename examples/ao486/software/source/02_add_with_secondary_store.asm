bits 16
org 0x000F_FFF0
mov ax, 0x0100
mov bx, 0x00ff
add ax, bx
mov [0x0204], ax
mov cx, 0x00f0
mov [0x0202], cx
jmp $
