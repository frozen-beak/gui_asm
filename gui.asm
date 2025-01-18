global _start

BITS   64
CPU    X64

%define AF_UNIX            1
%define SOCK_STREAM        1

%define SYSCALL_SOCKET     41
%define SYSCALL_CONNECT    42
%define SYSCALL_EXIT       60
%define SYSCALL_WRITE      1

%define SIZEOF_SOCKADDR_UN 2+108

section .rodata:
    sun_path: db "/tmp/.X11-unix/X0", 0
    static sun_path:data


section .text
_start:
    ; the end
    mov rax, SYSCALL_EXIT
    xor rdi, rdi
    syscall

; Creates a UNIX domain socket (local) to connect to X11 server
; @ret fd of the socket
x11_connect_to_server:
static x11_connect_to_server:function
    push rbp
    mov  rbp, rsp

    ; open a unix socket: socket(2)
    mov rax, SYSCALL_SOCKET
    mov rdi, AF_UNIX
    mov rsi, SOCK_STREAM
    mov rdx, 0
    syscall

    cmp rax, 0
    jle die

    mov rdi, rax ; remember the fd

    sub rsp, 112 ; space to store struct `sockaddr_un` on the stack

    mov       WORD [rsp], AF_UNIX   ; Set `sockaddr_un.sun_family` to AF_UNIX
    lea       rsi,        sun_path  ; `sockaddr_un.sun_path` = [sun_path]
    mov       r12,        rdi       ; Save fd from `rdi` to `r12`.
    lea       rdi,        [rsp + 2]
    cld                             ; make sure to copy & move forward
    mov       ecx,        19        ; len of [sun_path] is 19 w/ null terminator
    rep movsb                       ; copy

    ; connect to the server: connect(2)
    mov rax, SYSCALL_CONNECT
    mov rdi, r12
    lea rsi, [rsp]
    mov rdx, SIZEOF_SOCKADDR_UN
    syscall

    cmp rax, 0
    jle die

    mov rax, rdi ; return the socket fd

    add rsp, 112

    pop rbp
    ret

die:
    mov rax, SYSCALL_EXIT
    mov rdi, 1
    syscall
