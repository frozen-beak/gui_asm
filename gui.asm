BITS 64
CPU  X64

%define SYSCALL_EXIT  60
%define SYSCALL_WRITE 1
%define STDOUT        1

global  _start

section .text
_start:
    call print_hello

    mov rax, SYSCALL_EXIT
    xor rdi, rdi
    syscall

print_hello:
    push rbp      ; save current stack pointer in stack
    mov  rbp, rsp

    sub rsp, 16 ; allocate 5 bytes in stack

    mov BYTE [rsp],     'h'
    mov BYTE [rsp + 1], 'e'
    mov BYTE [rsp + 2], 'l'
    mov BYTE [rsp + 3], 'l'
    mov BYTE [rsp + 4], 'o'

    ; write to STDOUT
    mov rax, SYSCALL_WRITE
    mov rdi, STDOUT
    lea rsi, [rbp]         ; restore original rsi address
    mov rdx, 5             ; size of output
    syscall

    call print_world

    add rsp, 16 ; restore stack pointer to original value
    pop rbp     ; restore rbp

    ret

print_world:
    push rbp
    mov  rbp, rsp

    sub rsp, 16

    mov BYTE [rsp],     'w'
    mov BYTE [rsp + 1], 'o'
    mov BYTE [rsp + 2], 'r'
    mov BYTE [rsp + 3], 'l'
    mov BYTE [rsp + 4], 'd'
    mov BYTE [rsp + 5], 0

    mov rax, SYSCALL_WRITE
    mov rdi, STDOUT
    lea rsi, [rbp]
    mov rdx, 6
    syscall

    add rsp, 16
    pop rbp

    ret
