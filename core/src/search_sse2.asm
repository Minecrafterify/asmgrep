; SSE2 substring search with adaptive anchor selection.
;
; For sufficiently large buffers and patterns, sample 64 evenly
; spaced haystack bytes and select the least frequent byte among
; five positions in the pattern.
;
; SSE2 scans for that anchor. Candidate matches are verified
; against the complete pattern.
;
; Short patterns and small buffers retain the last-byte anchor.

%include "internal.inc"

default rel
bits 64

section .text

export_fn ag_find_sse2
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     [rsp], r8

    ; Empty pattern matches at offset zero.
    test    rcx, rcx
    jz      .empty

    ; Pattern longer than haystack cannot match.
    cmp     rcx, rsi
    ja      .none

    ; Dedicated one-byte SSE2 search.
    cmp     rcx, 1
    jne     .general

    movzx   eax, byte [rdx]
    movd    xmm1, eax
    punpcklbw xmm1, xmm1
    punpcklwd xmm1, xmm1
    pshufd  xmm1, xmm1, 0

    xor     eax, eax

.one_byte_block:
    lea     r8, [rax + 64]
    cmp     r8, rsi
    ja      .one_byte_tail

    ; First 16 bytes.
    movdqu  xmm0, [rdi + rax]
    pcmpeqb xmm0, xmm1
    pmovmskb r9d, xmm0
    test    r9d, r9d
    jnz     .one_byte_found

    ; Next 16 bytes.
    movdqu  xmm2, [rdi + rax + 16]
    pcmpeqb xmm2, xmm1
    pmovmskb r9d, xmm2
    test    r9d, r9d
    jnz     .one_byte_found_16

    ; Next 16 bytes.
    movdqu  xmm2, [rdi + rax + 32]
    pcmpeqb xmm2, xmm1
    pmovmskb r9d, xmm2
    test    r9d, r9d
    jnz     .one_byte_found_32

    ; Final 16 bytes.
    movdqu  xmm2, [rdi + rax + 48]
    pcmpeqb xmm2, xmm1
    pmovmskb r9d, xmm2
    test    r9d, r9d
    jnz     .one_byte_found_48

    add     rax, 64
    jmp     .one_byte_block

.one_byte_found_16:
    add     rax, 16
    jmp     .one_byte_found

.one_byte_found_32:
    add     rax, 32
    jmp     .one_byte_found

.one_byte_found_48:
    add     rax, 48

.one_byte_found:
    bsf     r9d, r9d
    add     rax, r9
    jmp     .return
.one_byte_tail:
    cmp     rax, rsi
    jae     .none

    mov     r8b, [rdi + rax]
    cmp     r8b, [rdx]
    je      .return

    inc     rax
    jmp     .one_byte_tail

.general:
    ; Reuse an anchor selected by an earlier search in this scan.
    mov     r8, [rsp]
    cmp     qword [r8], -1
    je      .select_anchor

    mov     r14, [r8]
    jmp     .anchor_selected

.select_anchor:
    ; Default anchor: final pattern byte.
    mov     r14, rcx
    dec     r14

    ; Adaptive selection is worthwhile only for larger inputs.
    cmp     rcx, 8
    jb      .anchor_selected

    cmp     rsi, 4096
    jb      .anchor_selected


    ; Sample 64 evenly spaced haystack positions.
    mov     r13, 64
    mov     r15, rsi
    shr     r15, 6

    ; Lowest observed frequency so far.
    mov     r11, -1
    xor     r8d, r8d

    ; Long patterns get 64 anchor candidates.
    cmp     rcx, 64
    jae     .sample_many

.sample_candidate:
    ; Existing five-position strategy for shorter patterns.
    cmp     r8d, 0
    je      .anchor_zero

    cmp     r8d, 1
    je      .anchor_quarter

    cmp     r8d, 2
    je      .anchor_middle

    cmp     r8d, 3
    je      .anchor_three_quarters

    ; Final byte.
    mov     r12, rcx
    dec     r12
    jmp     .count_anchor

.anchor_zero:
    xor     r12d, r12d
    jmp     .count_anchor

.anchor_quarter:
    mov     r12, rcx
    shr     r12, 2
    jmp     .count_anchor

.anchor_middle:
    mov     r12, rcx
    shr     r12, 1
    jmp     .count_anchor

.anchor_three_quarters:
    lea     r12, [rcx + rcx*2]
    shr     r12, 2
    jmp     .count_anchor

.sample_many:
    ; Position = index * (pattern_length - 1) / 63.
    ; Save rcx and rdx because MUL and DIV use rdx:rax.
    push    rcx
    push    rdx

    mov     rbx, rcx
    dec     rbx

    mov     rax, r8
    mul     rbx

    mov     ebx, 63
    div     rbx

    mov     r12, rax

    pop     rdx
    pop     rcx

.count_anchor:
    ; Byte being evaluated.
    movzx   ebx, byte [rdx + r12]

    xor     r10d, r10d
    xor     r9d, r9d

.sample_loop:
    ; Sample position = sample index * stride.
    mov     rax, r9
    imul    rax, r15

    cmp     byte [rdi + rax], bl
    jne     .sample_next_byte

    inc     r10

.sample_next_byte:
    inc     r9
    cmp     r9, r13
    jb      .sample_loop

    ; Keep the anchor with the lowest frequency.
    cmp     r10, r11
    jae     .next_anchor

    mov     r11, r10
    mov     r14, r12

.next_anchor:
    inc     r8

    cmp     rcx, 64
    jae     .many_next

    cmp     r8, 5
    jb      .sample_candidate
    jmp     .anchor_selected

.many_next:
    cmp     r8, 64
    jb      .sample_many
    jmp     .anchor_selected


.anchor_selected:
    ; Cache the selected anchor for subsequent searches.
    mov     r8, [rsp]
    mov     [r8], r14

    ; Broadcast selected anchor byte.
    movzx   eax, byte [rdx + r14]
    movd    xmm1, eax
    punpcklbw xmm1, xmm1
    punpcklwd xmm1, xmm1
    pshufd  xmm1, xmm1, 0

    ; Legal anchor positions:
    ; [anchor, hay_len - pat_len + anchor].
    ; r8 holds the exclusive upper bound.
    mov     r8, rsi
    sub     r8, rcx
    add     r8, r14
    inc     r8

    ; Start at the first legal anchor position.
    mov     rax, r14

.block:
    ; Only load a complete 16-byte vector inside the legal range.
    lea     r9, [rax + 16]
    cmp     r9, r8
    ja      .tail

    movdqu  xmm0, [rdi + rax]
    pcmpeqb xmm0, xmm1
    pmovmskb r10d, xmm0

    test    r10d, r10d
    jz      .advance

.candidate:
    ; Find next matching anchor position.
    bsf     r11d, r10d
    lea     r9, [rax + r11]

    ; Convert anchor position to candidate start pointer.
    mov     r12, r9
    sub     r12, r14
    add     r12, rdi

    ; Verify the complete pattern.
    xor     r11d, r11d

.verify:
    ; Compare 16 bytes at a time.
    mov     r9, rcx
    sub     r9, r11
    cmp     r9, 16
    jb      .verify_tail

    movdqu  xmm0, [r12 + r11]
    movdqu  xmm2, [rdx + r11]

    pcmpeqb xmm0, xmm2
    pmovmskb r9d, xmm0

    ; All 16 bytes must match.
    cmp     r9d, 0xffff
    jne     .next_bit

    add     r11, 16
    jmp     .verify

.verify_tail:
    ; Handle remaining bytes.
    cmp     r11, rcx
    jae     .found

    mov     bl, [r12 + r11]
    cmp     bl, [rdx + r11]
    jne     .next_bit

    inc     r11
    jmp     .verify_tail
.next_bit:
    ; Clear lowest set bit and try another candidate.
    lea     r11d, [r10 - 1]
    and     r10d, r11d
    jnz     .candidate

.advance:
    add     rax, 16
    jmp     .block

.tail:
    ; Scalar handling of remaining legal anchor positions.
    cmp     rax, r8
    jae     .none

    mov     bl, [rdi + rax]
    cmp     bl, [rdx + r14]
    jne     .tail_next

    ; Convert anchor position to candidate start pointer.
    mov     r12, rax
    sub     r12, r14
    add     r12, rdi

    xor     r11d, r11d

.tail_verify:
    ; Compare 16 bytes at a time.
    mov     r9, rcx
    sub     r9, r11
    cmp     r9, 16
    jb      .tail_verify_scalar

    movdqu  xmm0, [r12 + r11]
    movdqu  xmm2, [rdx + r11]

    pcmpeqb xmm0, xmm2
    pmovmskb r9d, xmm0

    cmp     r9d, 0xffff
    jne     .tail_next

    add     r11, 16
    jmp     .tail_verify

.tail_verify_scalar:
    cmp     r11, rcx
    jae     .found

    mov     bl, [r12 + r11]
    cmp     bl, [rdx + r11]
    jne     .tail_next

    inc     r11
    jmp     .tail_verify_scalar

.tail_next:
    inc     rax
    jmp     .tail

.found:
    ; Return candidate start offset.
    mov     rax, r12
    sub     rax, rdi
    jmp     .return

.empty:
    xor     eax, eax
    jmp     .return

.none:
    mov     rax, -1

.return:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

gnu_stack
