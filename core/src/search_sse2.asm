; SSE2 substring search.
;
; size_t ag_find_sse2(const uint8_t *hay, size_t hay_len,
;                     const uint8_t *pat, size_t pat_len)
;
; Same contract as ag_find_scalar. The first pattern byte is broadcast into
; an XMM register and compared against 16 haystack bytes at a time. Each set
; bit of the resulting mask is a candidate start, verified byte by byte.
; Vector loads are issued only while 16 bytes remain inside the buffer; the
; final partial block is handled by a scalar tail loop.

%include "internal.inc"

default rel
bits 64

section .text

export_fn ag_find_sse2
    push    rbx
    test    rcx, rcx
    jz      .empty
    cmp     rcx, rsi
    ja      .none
    mov     r8, rsi
    sub     r8, rcx                 ; last valid start offset
    movzx   eax, byte [rdx]
    movd    xmm1, eax
    punpcklbw xmm1, xmm1
    punpcklwd xmm1, xmm1
    pshufd  xmm1, xmm1, 0
    xor     eax, eax                ; block offset
.block:
    lea     r9, [rax + 16]
    cmp     r9, rsi
    ja      .tail
    movdqu  xmm0, [rdi + rax]
    pcmpeqb xmm0, xmm1
    pmovmskb r10d, xmm0
    test    r10d, r10d
    jz      .advance
.candidate:
    bsf     r11d, r10d
    lea     r9, [rax + r11]
    cmp     r9, r8
    ja      .none
    add     r9, rdi                 ; pointer to candidate
    mov     r11d, 1
.verify:
    cmp     r11, rcx
    jae     .found
    mov     bl, [r9 + r11]
    cmp     bl, [rdx + r11]
    jne     .next_bit
    inc     r11
    jmp     .verify
.next_bit:
    lea     r11d, [r10 - 1]
    and     r10d, r11d              ; clear lowest set bit
    jnz     .candidate
.advance:
    add     rax, 16
    jmp     .block
.tail:
    cmp     rax, r8
    ja      .none
    lea     r9, [rdi + rax]
    mov     bl, [r9]
    cmp     bl, [rdx]
    jne     .tail_next
    mov     r11d, 1
.tail_verify:
    cmp     r11, rcx
    jae     .found
    mov     bl, [r9 + r11]
    cmp     bl, [rdx + r11]
    jne     .tail_next
    inc     r11
    jmp     .tail_verify
.tail_next:
    inc     rax
    jmp     .tail
.found:
    mov     rax, r9
    sub     rax, rdi
    pop     rbx
    ret
.empty:
    xor     eax, eax
    pop     rbx
    ret
.none:
    mov     rax, -1
    pop     rbx
    ret

gnu_stack
