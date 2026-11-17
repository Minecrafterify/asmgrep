; Buffered output for the command-line front end.

%include "internal.inc"

default rel
bits 64

%define OUT_SIZE 65536

extern ag_utoa

section .bss
align 16
out_buf:  resb OUT_SIZE
out_used: resq 1

section .text

; long cli_write_all(int fd, const void *p, size_t n)  -> 0 or -errno
global cli_write_all:function hidden
cli_write_all:
.loop:
    test    rdx, rdx
    jz      .ok
    mov     eax, SYS_write
    mov     r8, rsi
    mov     r9, rdx
    syscall
    cmp     rax, -4                 ; EINTR
    je      .retry
    test    rax, rax
    js      .ret
    add     r8, rax
    sub     r9, rax
    mov     rsi, r8
    mov     rdx, r9
    jmp     .loop
.retry:
    mov     rsi, r8
    mov     rdx, r9
    jmp     .loop
.ok:
    xor     eax, eax
.ret:
    ret

; long cli_flush(void)  -> 0 or -errno
global cli_flush:function hidden
cli_flush:
    mov     rdx, [out_used]
    mov     qword [out_used], 0
    lea     rsi, [out_buf]
    mov     edi, 1
    jmp     cli_write_all

; long cli_put(const void *p, size_t n)  -> 0 or -errno
global cli_put:function hidden
cli_put:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    mov     rax, OUT_SIZE
    sub     rax, [out_used]
    cmp     r12, rax
    jbe     .copy
    call    cli_flush
    test    rax, rax
    js      .out
    cmp     r12, OUT_SIZE
    jb      .copy
    mov     edi, 1
    mov     rsi, rbx
    mov     rdx, r12
    call    cli_write_all
    jmp     .out
.copy:
    lea     rdi, [out_buf]
    add     rdi, [out_used]
    mov     rsi, rbx
    mov     rcx, r12
    add     [out_used], r12
    rep movsb
    xor     eax, eax
.out:
    pop     r12
    pop     rbx
    ret

; Scan callback: prints "[lineno:]line\n". lineno 0 means no prefix.
global cli_line_cb:function hidden
cli_line_cb:
    push    rbx
    push    r12
    sub     rsp, 40
    mov     rbx, rdx
    mov     r12, rcx
    test    rsi, rsi
    jz      .text
    mov     rdi, rsi
    lea     rsi, [rsp]
    call    ag_utoa
    mov     byte [rsp + rax], ':'
    lea     rsi, [rax + 1]
    lea     rdi, [rsp]
    call    cli_put
    test    rax, rax
    js      .fail
.text:
    mov     rdi, rbx
    mov     rsi, r12
    call    cli_put
    test    rax, rax
    js      .fail
    lea     rdi, [newline]
    mov     esi, 1
    call    cli_put
    test    rax, rax
    js      .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 40
    pop     r12
    pop     rbx
    ret

section .rodata
newline: db 10

gnu_stack
