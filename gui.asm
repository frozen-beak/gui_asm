global _start

BITS   64
CPU    X64

%define AF_UNIX            1
%define SOCK_STREAM        1

%define SYSCALL_READ       0
%define SYSCALL_WRITE      1
%define SYSCALL_POLL       7
%define SYSCALL_SOCKET     41
%define SYSCALL_CONNECT    42
%define SYSCALL_EXIT       60
%define SYSCALL_FCNTL      72

%define SIZEOF_SOCKADDR_UN 2+108

section .rodata:

    sun_path: db "/tmp/.X11-unix/X0", 0
    static sun_path:data

    hello_world: db "Hello, World!", 0
    static hello_world:data

section .data

    id: dd 0
    static id:data

    id_base: dd 0
    static id_base:data

    id_mask: dd 0
    static id_mask:data

    root_visual_id: dd 0
    static root_visual_id:data

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

; Send the handshake to X11 server and read the returned info
; @param rdi - The socket fd
; @ret rax - The window root id (uint32_t)
x11_send_handshake:
static x11_send_handshake:function
    push rbp
    mov  rbp, rsp

    sub rsp, 1 << 15 ; 2^15 (space for read buffer)
    
    mov BYTE [rsp + 0], 'l' ; set `order` to "l" (i.e. little endian)
    mov WORD [rsp + 2], 11  ; set `major` version

    ; send the handshake to server: write(2)
    mov rax, SYSCALL_WRITE
    mov rdi, rdi
    lea rsi, [rsp]
    mov rdx, 12
    syscall

    cmp rax, 12 ; check if all bytes are written
    jnz die

    ; read the server response (first 8 bytes): read(2)
    ; using stack for the read buffer
    ; 
    ; 📝 NOTE: The X11 server first replies with 8 bytes. Once these 
    ; are read, it replies with a much bigger message.
    mov rax, SYSCALL_READ
    mov rdi, rdi
    lea rsi, [rsp]
    mov rdx, 8
    syscall

    ; check if server responded with 8 bytes
    cmp rax, 8
    jnz die

    ; check if server sent 'success' (i.e. 1)
    cmp BYTE [rsp], 1
    jnz die

    ; read the rest of the server response: read(2)
    ;
    ; 📝 NOTE: we're using the stack for read buffer
    mov rax, SYSCALL_READ
    mov rdi, rdi
    lea rsi, [rsp]
    mov rdx, 1 << 15
    syscall

    ; check that the server replied w/ something
    cmp rax, 0
    jle die

    ; set [id_base] globally
    mov edx,             DWORD [rsp + 4]
    mov DWORD [id_base], edx

    ; set [id_mask] globally
    mov edx,             DWORD [rsp + 8]
    mov DWORD [id_mask], edx

    ; read the info we need, skip over the rest
    lea rdi, [rsp] ; pointer that will skip over some data

    mov   cx,  WORD [rsp + 16] ; vendor length (v) (16 bits)
    movzx rcx, cx              ; move from 16 to 64 bit register w/ padding

    mov   al,  BYTE [rsp + 21] ; no. of formats (n) (8 bits) (can be -ve)
    movzx rax, al              ; move from 8 to 64 bit register w/ padding
    imul  rax, 8               ; sizeof(format) == 8

    add rdi, 32  ; skip the connection setup
    add rdi, rcx ; skip over the vendor info (v)

    ; skip over the padding
    add rdi, 3
    and rdi, -4 ; make sure `rdi` is multiple of 4

    add rdi, rax ; skip over format info (n*8)

    mov eax, DWORD [rdi] ; store and return [window_root_id]

    ; set the [root_visual_id] globally
    mov edx,                    DWORD [rdi + 32]
    mov DWORD [root_visual_id], edx

    add rsp, 1 << 15
    pop rbp
    ret

; Increment the global id
; @ret The new id
x11_next_id:
    push rbp
    mov  rbp, rsp

    mov eax, DWORD [id]      ; load the global [id]
    mov edi, DWORD [id_base] ; load the global [id_base]
    mov edx, DWORD [id_mask] ; load the global [id_mask]

    ; return -> `id_mask & (id) | id_base`
    add eax, edx
    or  eax, edi

    add DWORD [id], 1 ; increment [id]

    pop rbp
    ret

; open the font on the server side
; @param rdi: The socket fd
; @param esi: The font id
x11_open_font:
static x11_open_font:function
    push rbp
    mov  rbp, rsp

    %define OPEN_FONT_NAME_BYTE_COUNT  5
    %define OPEN_FONT_PADDING          ((4 - (OPEN_FONT_NAME_BYTE_COUNT % 4)) % 4)
    %define OPEN_FONT_PACKET_U32_COUNT (3 + (OPEN_FONT_NAME_BYTE_COUNT + OPEN_FONT_PADDING) / 4)
    %define X11_OP_REQ_OPEN_FONT       0x2d

    sub rsp,                    6 * 8
    mov DWORD [rsp + 0 * 4],    X11_OP_REQ_OPEN_FONT | (OPEN_FONT_NAME_BYTE_COUNT << 16)
    mov DWORD [rsp + 1 * 4],    esi
    mov DWORD [rsp + 2 * 4],    OPEN_FONT_NAME_BYTE_COUNT
    mov BYTE [rsp + 3 * 4 + 0], 'f'
    mov BYTE [rsp + 3 * 4 + 1], 'i'
    mov BYTE [rsp + 3 * 4 + 2], 'x'
    mov BYTE [rsp + 3 * 4 + 3], 'e'
    mov BYTE [rsp + 3 * 4 + 4], 'd'

    mov rax, SYSCALL_WRITE
    mov rdi, rdi
    lea rsi, [rsp]
    mov rdx, OPEN_FONT_PACKET_U32_COUNT * 4
    syscall

    cmp rax, OPEN_FONT_PACKET_U32_COUNT * 4
    jnz die
  
    add rsp, 6 * 8

    pop rbp
    ret

; Create x11 graphical context
; @param rdi: socket fd
; @param rsi: graphical context id
; @param edx: window root id
; @param ecx: font id
x11_create_gc:
static x11_create_gc:function
    push rbp
    mov  rbp, rsp

    sub rsp, 8 * 8

    %define X11_OP_REQ_CREATE_GC 0x37
    %define X11_FLAG_GC_BG       0x00000004
    %define X11_FLAG_GC_FG       0x00000008
    %define X11_FLAG_GC_FONT     0x00004000
    %define X11_FLAG_GC_EXPOSE   0x00010000
    
    %define CREATE_GC_FLAGS             X11_FLAG_GC_BG | X11_FLAG_GC_FG | X11_FLAG_GC_FONT
    %define CREATE_GC_PACKET_FLAG_COUNT 3
    %define CREATE_GC_PACKET_U32_COUNT  (4 + CREATE_GC_PACKET_FLAG_COUNT)
    %define MY_COLOR_RGB                0x0000fff

    mov DWORD [rsp + 0 * 4], X11_OP_REQ_CREATE_GC | (CREATE_GC_PACKET_U32_COUNT << 16)
    mov DWORD [rsp + 1 * 4], esi
    mov DWORD [rsp + 2 * 4], edx
    mov DWORD [rsp + 3 * 4], CREATE_GC_FLAGS
    mov DWORD [rsp + 4 * 4], MY_COLOR_RGB
    mov DWORD [rsp + 5 * 4], 0
    mov DWORD [rsp + 6 * 4], ecx

    mov rax, SYSCALL_WRITE
    mov rdi, rdi
    lea rsi, [rsp]
    mov rdx, CREATE_GC_PACKET_U32_COUNT * 4
    syscall

    cmp rax, CREATE_GC_PACKET_U32_COUNT * 4
    jnz die

    add rsp, 8 * 8

    pop rbp
    ret

    
die:
    mov rax, SYSCALL_EXIT
    mov rdi, 1
    syscall
