BITS 64
CPU  X64

%define SYSCALL_EXIT 60

global  _start

section .text
_start:
    mov rax, SYSCALL_EXIT
    xor rdi, rdi
    syscall
