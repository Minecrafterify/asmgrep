; Line-processing subsystem and scan driver.
;
; size_t ag_memchr(const uint8_t *p, size_t n, uint8_t byte)   -> index, or n
; size_t ag_memrchr(const uint8_t *p, size_t n, uint8_t byte)  -> index, or -1
; size_t ag_count_byte(const uint8_t *p, size_t n, uint8_t byte)
;
; size_t ag_scan(const uint8_t *buf, size_t len,
;                const uint8_t *pat, size_t pat_len,
;                int (*cb)(void *ctx, size_t lineno,
;                          const uint8_t *line, size_t line_len),
;                void *ctx, unsigned flags)
;
; Visits every line of buf containing pat exactly once, in order, and
; returns the number of matching lines, or -1 on error. cb may be NULL
; (count only). A non-zero return from cb aborts the scan with -1. Line
; numbers (1-based) are supplied only when FLAG_LINENO is set; otherwise
; the callback receives 0. FLAG_SCALAR selects the scalar reference search.
; Patterns containing a newline are rejected. The final line need not end
; with a newline. No state is kept outside the caller's stack.

%include "internal.inc"

default rel
bits 64

extern ag_find_scalar
extern ag_find_sse2

section .text

%macro broadcast 2                  ; broadcast(xmm, r32)
    movd    %1, %2
    punpcklbw %1, %1
    punpcklwd %1, %1
    pshufd  %1, %1, 0
%endmacro

export_fn ag_memchr
    broadcast xmm1, edx
    xor     eax, eax
.block:
    lea     rcx, [rax + 16]
    cmp     rcx, rsi
    ja      .tail
    movdqu  xmm0, [rdi + rax]
    pcmpeqb xmm0, xmm1
    pmovmskb ecx, xmm0
    test    ecx, ecx
    jnz     .hit
    add     rax, 16
    jmp     .block
.hit:
    bsf     ecx, ecx
    add     rax, rcx
    ret
.tail:
    cmp     rax, rsi
    jae     .done
    cmp     [rdi + rax], dl
    je      .done
    inc     rax
    jmp     .tail
.done:
    ret

export_fn ag_memrchr
    broadcast xmm1, edx
    mov     rax, rsi
.block:
    cmp     rax, 16
    jb      .tail
    movdqu  xmm0, [rdi + rax - 16]
    pcmpeqb xmm0, xmm1
    pmovmskb ecx, xmm0
    test    ecx, ecx
    jnz     .hit
    sub     rax, 16
    jmp     .block
.hit:
    bsr     ecx, ecx
    lea     rax, [rax + rcx - 16]
    ret
.tail:
    test    rax, rax
    jz      .none
    dec     rax
    cmp     [rdi + rax], dl
    jne     .tail
    ret
.none:
    mov     rax, -1
    ret

export_fn ag_count_byte
    broadcast xmm1, edx
    pxor    xmm3, xmm3
    xor     eax, eax
.outer:
    cmp     rsi, 16
    jb      .tail
    mov     rcx, rsi
    shr     rcx, 4
    cmp     rcx, 255                ; byte lanes hold at most 255 counts
    jbe     .chunk
    mov     ecx, 255
.chunk:
    mov     r8, rcx
    shl     r8, 4
    sub     rsi, r8
    pxor    xmm2, xmm2
.inner:
    movdqu  xmm0, [rdi]
    pcmpeqb xmm0, xmm1
    psubb   xmm2, xmm0              ; subtracting -1 adds one per match
    add     rdi, 16
    dec     rcx
    jnz     .inner
    psadbw  xmm2, xmm3
    movq    r9, xmm2
    add     rax, r9
    movhlps xmm2, xmm2
    movq    r9, xmm2
    add     rax, r9
    jmp     .outer
.tail:
    test    rsi, rsi
    jz      .done
    cmp     [rdi], dl
    jne     .skip
    inc     rax
.skip:
    inc     rdi
    dec     rsi
    jmp     .tail
.done:
    ret

%define L_CB    rbp - 48
%define L_CTX   rbp - 56
%define L_FLG   rbp - 64
%define L_CNT   rbp - 72
%define L_LNO   rbp - 80            ; newlines in buf[0, L_POS)
%define L_POS   rbp - 88
%define L_LS    rbp - 96            ; line start
%define L_LE    rbp - 104           ; line end (index of newline or len)

export_fn ag_scan
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 72
    mov     rbx, rdi                ; buf
    mov     r12, rsi                ; len
    mov     r13, rdx                ; pat
    mov     r14, rcx                ; pat_len
    mov     [L_CB], r8
    mov     [L_CTX], r9
    mov     eax, [rbp + 16]
    mov     [L_FLG], rax
    xor     eax, eax
    mov     [L_CNT], rax
    mov     [L_LNO], rax
    mov     [L_POS], rax
    xor     r15d, r15d              ; search cursor (always a line start)

    test    r14, r14
    jz      .loop
    mov     rdi, r13
    mov     rsi, r14
    mov     edx, 10
    call    ag_memchr
    cmp     rax, r14
    jb      .error                  ; pattern contains a newline

.loop:
    cmp     r15, r12
    jae     .done
    lea     rdi, [rbx + r15]
    mov     rsi, r12
    sub     rsi, r15
    mov     rdx, r13
    mov     rcx, r14
    test    dword [L_FLG], FLAG_SCALAR
    jnz     .scalar
    call    ag_find_sse2
    jmp     .found
.scalar:
    call    ag_find_scalar
.found:
    cmp     rax, -1
    je      .done
    add     rax, r15                ; absolute match offset
    mov     r10, rax

    ; line start: last newline in [cursor, match), else the cursor
    lea     rdi, [rbx + r15]
    mov     rsi, r10
    sub     rsi, r15
    mov     edx, 10
    push    r10
    push    r10                     ; keep stack 16-byte aligned
    call    ag_memrchr
    pop     r10
    pop     r10
    cmp     rax, -1
    je      .ls_cursor
    lea     rax, [r15 + rax + 1]
    jmp     .ls_set
.ls_cursor:
    mov     rax, r15
.ls_set:
    mov     [L_LS], rax

    ; line end: first newline at or after the match, else len
    lea     rdi, [rbx + r10]
    mov     rsi, r12
    sub     rsi, r10
    mov     edx, 10
    mov     r11, r10
    push    r11
    push    r11
    call    ag_memchr
    pop     r11
    pop     r11
    add     rax, r11
    mov     [L_LE], rax

    inc     qword [L_CNT]
    cmp     qword [L_CB], 0
    je      .advance

    xor     edx, edx
    test    dword [L_FLG], FLAG_LINENO
    jz      .call_cb
    mov     rsi, [L_POS]
    mov     rax, [L_LS]
    lea     rdi, [rbx + rsi]
    mov     rsi, rax
    sub     rsi, [L_POS]
    mov     edx, 10
    call    ag_count_byte
    add     [L_LNO], rax
    mov     rax, [L_LS]
    mov     [L_POS], rax
    mov     rdx, [L_LNO]
    inc     rdx
.call_cb:
    mov     rdi, [L_CTX]
    mov     rsi, rdx
    mov     rax, [L_LS]
    lea     rdx, [rbx + rax]
    mov     rcx, [L_LE]
    sub     rcx, rax
    call    [L_CB]
    test    eax, eax
    jnz     .error

.advance:
    mov     r15, [L_LE]
    cmp     r15, r12
    jae     .done
    inc     r15                     ; skip the newline
    jmp     .loop

.done:
    mov     rax, [L_CNT]
    jmp     .out
.error:
    mov     rax, -1
.out:
    add     rsp, 72
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

gnu_stack
