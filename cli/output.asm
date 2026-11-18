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

; long cli_write_all(int fd, const void *p, size_t n) -> 0 or -errno
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
    test    rax, rax
    jz      .zero_write
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
    jmp     .ret

.zero_write:
    mov     rax, -5             ; -EIO
    jmp     .ret
.ret:
    ret

global cli_write_all:function hidden

; long cli_flush(void) -> 0 or -errno
global cli_flush:function hidden
cli_flush:
    mov     rdx, [out_used]
    mov     qword [out_used], 0
    lea     rsi, [out_buf]
    mov     edi, 1
    jmp     cli_write_all

; long cli_put(const void *p, size_t n) -> 0 or -errno
global cli_put:function hidden
cli_put:
    push    rbx
    push    r12
    sub     rsp, 8
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
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; Scan callback: prints "[lineno:]line\n".
; lineno 0 means no prefix.
global cli_line_cb:function hidden
cli_line_cb:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 64

    ; Arguments:
    ; rdi = callback context
    ; rsi = line number
    ; rdx = line pointer
    ; rcx = line length

    mov     r13, rdi
    mov     rbx, rdx
    mov     r12, rcx

    ; Load pattern information from callback context.
    mov     r14, [r13]
    mov     r15, [r13 + 8]

    ; Save line boundaries and line number.
    mov     [rsp + 32], rbx
    lea     rax, [rbx + r12]
    mov     [rsp + 40], rax
    mov     [rsp + 56], rsi

    ; Print filename prefix when provided.
    mov     rdi, [r13 + 24]
    test    rdi, rdi
    jz      .line_number

    mov     rsi, [r13 + 32]
    call    cli_put
    test    rax, rax
    js      .fail

    lea     rdi, [filename_separator]
    mov     esi, 1
    call    cli_put
    test    rax, rax
    js      .fail

.line_number:
    ; Print line number if requested.
    mov     rsi, [rsp + 56]
    test    rsi, rsi
    jz      .color_check

    mov     rdi, rsi
    lea     rsi, [rsp]
    call    ag_utoa

    mov     byte [rsp + rax], ':'
    lea     rdi, [rsp]
    lea     rsi, [rax + 1]
    call    cli_put
    test    rax, rax
    js      .fail

.color_check:
    ; Color disabled?
    cmp     qword [r13 + 16], 0
    je      .plain

    ; Empty patterns are not highlighted.
    test    r15, r15
    jz      .plain

    ; Search for occurrences of the pattern.
.search:
    cmp     r12, r15
    jb      .tail

    xor     r8d, r8d

.compare:
    cmp     r8, r15
    jae     .found

    mov     al, [rbx + r8]
    cmp     al, [r14 + r8]
    jne     .advance

    inc     r8
    jmp     .compare

.advance:
    inc     rbx
    dec     r12
    jmp     .search

.found:
    ; Save the matching position.
    mov     [rsp + 48], rbx

    ; Print uncolored text before the match.
    mov     rax, [rsp + 32]
    mov     rsi, rbx
    sub     rsi, rax
    jz      .highlight

    mov     rdi, rax
    call    cli_put
    test    rax, rax
    js      .fail

.highlight:
    ; Start red highlighting.
    lea     rdi, [color_red]
    mov     esi, color_red_len
    call    cli_put
    test    rax, rax
    js      .fail

    ; Print the matching text.
    mov     rdi, r14
    mov     rsi, r15
    call    cli_put
    test    rax, rax
    js      .fail

    ; Reset terminal color.
    lea     rdi, [color_reset]
    mov     esi, color_reset_len
    call    cli_put
    test    rax, rax
    js      .fail

    ; Continue after the matched substring.
    mov     rbx, [rsp + 48]
    add     rbx, r15
    sub     r12, r15
    mov     [rsp + 32], rbx
    jmp     .search

.tail:
    ; Print remaining uncolored text.
    mov     rax, [rsp + 40]
    sub     rax, [rsp + 32]
    jz      .newline

    mov     rdi, [rsp + 32]
    mov     rsi, rax
    call    cli_put
    test    rax, rax
    js      .fail
    jmp     .newline

.plain:
    ; Print the entire line without highlighting.
    mov     rdi, rbx
    mov     rsi, r12
    call    cli_put
    test    rax, rax
    js      .fail

.newline:
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
    add     rsp, 64
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

section .rodata

newline: db 10
filename_separator: db ':'
color_red:   db 27, "[31m"
color_red_len equ $ - color_red

color_reset: db 27, "[0m"
color_reset_len equ $ - color_reset

section .note.GNU-stack noalloc noexec nowrite progbits
