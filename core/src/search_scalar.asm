; Scalar substring search: the reference implementation.
;
; size_t ag_find_scalar(const uint8_t *hay, size_t hay_len,
;                       const uint8_t *pat, size_t pat_len)
;
; Returns the offset of the first occurrence of pat in hay, or -1.
; An empty pattern matches at offset 0.

%include "internal.inc"

default rel
bits 64

section .text

export_fn ag_find_scalar
    test    rcx, rcx
    jz      .empty
    cmp     rcx, rsi
    ja      .none
    mov     r8, rsi
    sub     r8, rcx                 ; last valid start offset
    movzx   r9d, byte [rdx]         ; first pattern byte
    xor     eax, eax
.outer:
    cmp     rax, r8
    ja      .none
    cmp     byte [rdi + rax], r9b
    jne     .next
    mov     r11d, 1
.verify:
    cmp     r11, rcx
    jae     .found
    lea     r10, [rax + r11]
    mov     r10b, [rdi + r10]
    cmp     r10b, [rdx + r11]
    jne     .next
    inc     r11
    jmp     .verify
.next:
    inc     rax
    jmp     .outer
.found:
    ret
.empty:
    xor     eax, eax
    ret
.none:
    mov     rax, -1
    ret

gnu_stack
