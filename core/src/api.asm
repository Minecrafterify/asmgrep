; Public C ABI of libasmgrep.
;
; int asmgrep_search_file(const char *pattern, const char *path,
;                         unsigned flags, asmgrep_result **out)
; int asmgrep_search_buffer(const void *buf, size_t len,
;                           const char *pattern, size_t pattern_len,
;                           unsigned flags, asmgrep_result **out)
; size_t      asmgrep_result_count(const asmgrep_result *r)
; size_t      asmgrep_result_line_number(const asmgrep_result *r, size_t i)
; const char *asmgrep_result_text(const asmgrep_result *r, size_t i)
; size_t      asmgrep_result_length(const asmgrep_result *r, size_t i)
; void        asmgrep_free(asmgrep_result *r)
; const char *asmgrep_strerror(int status)
; const char *asmgrep_version(void)
;
; A search runs the scan driver twice over the same bytes. The first pass
; counts matching lines and the bytes needed to hold them; the second fills
; one anonymous mapping that holds the header, an entry table and a
; NUL-terminated text arena. The second pass is bounded by the capacity
; established in the first, so input that changes between passes cannot
; overflow the block. No global mutable state is used: independent searches
; may run concurrently.
;
; Result block layout:
;   0   u64 total mapping size
;   8   u64 line count
;   16  u64 arena offset
;   24  entries[count] { u64 line_number; u64 text_offset; u64 length }
;   arena offset: text arena

%include "internal.inc"

default rel
bits 64

extern ag_scan
extern ag_map_file
extern ag_unmap
extern ag_strlen
extern ag_strerror
extern ag_alloc
extern ag_free

%define HDR_SIZE        24
%define ENTRY_SIZE      24

section .text

; pass 1 callback. ctx = { u64 lines; u64 bytes }
count_cb:
    inc     qword [rdi]
    lea     rax, [rcx + 1]
    add     [rdi + 8], rax
    xor     eax, eax
    ret

; pass 2 callback.
; ctx = { u64 index; u64 entries; u64 arena_ptr; u64 base; u64 max_index; u64 arena_end }
fill_cb:
    mov     r8, [rdi]
    cmp     r8, [rdi + 32]
    jae     .abort
    mov     r10, [rdi + 16]
    lea     rax, [r10 + rcx + 1]
    cmp     rax, [rdi + 40]
    ja      .abort
    mov     [rdi + 16], rax
    inc     qword [rdi]
    lea     rax, [r8 + r8 * 2]
    mov     r9, [rdi + 8]
    lea     r9, [r9 + rax * 8]
    mov     [r9], rsi
    mov     rax, r10
    sub     rax, [rdi + 24]
    mov     [r9 + 8], rax
    mov     [r9 + 16], rcx
    mov     rsi, rdx
    mov     rdi, r10
    rep movsb
    mov     byte [rdi], 0
    xor     eax, eax
    ret
.abort:
    mov     eax, 1
    ret

; int search_common(buf, len, pattern, pattern_len, flags, out)
%define S_ARG7      0
%define S_CTX1      16
%define S_CTX2      32
%define S_OUT       80
%define S_LINES     88
%define S_BASE      96
%define S_TOTAL     104
%define S_AOFF      112
%define S_FRAME     120

search_common:
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, S_FRAME
    mov     rbx, rdi                ; buf
    mov     r12, rsi                ; len
    mov     r13, rdx                ; pattern
    mov     r14, rcx                ; pattern_len
    mov     r15d, r8d               ; flags
    mov     [rsp + S_OUT], r9
    test    r9, r9
    jz      .inval
    mov     qword [r9], 0
    test    r15d, ~FLAG_SCALAR
    jnz     .inval
    test    r13, r13
    jz      .inval
    test    rbx, rbx
    jnz     .args_ok
    test    r12, r12
    jnz     .inval
.args_ok:
    xor     eax, eax
    mov     [rsp + S_CTX1], rax
    mov     [rsp + S_CTX1 + 8], rax
    mov     eax, r15d
    mov     [rsp + S_ARG7], rax
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    mov     rcx, r14
    lea     r8, [count_cb]
    lea     r9, [rsp + S_CTX1]
    call    ag_scan
    cmp     rax, -1
    je      .inval                  ; pattern containing a newline
    mov     [rsp + S_LINES], rax
    ; Calculate count * 24 with overflow checking.
    mov rcx, rax
    shl rax, 4
    shl rcx, 3
    add rax, rcx
    jc .overflow

    ; Add header size.
    add rax, HDR_SIZE
    jc .overflow

    mov [rsp + S_AOFF], rax

    ; Add text storage size.
    add rax, [rsp + S_CTX1 + 8]
    jc .overflow

    mov [rsp + S_TOTAL], rax
    mov rdi, rax
    call ag_alloc
    test    rax, rax
    jz      .nomem
    mov     [rsp + S_BASE], rax
    mov     rcx, [rsp + S_TOTAL]
    mov     [rax], rcx
    mov     rdx, [rsp + S_LINES]
    mov     [rax + 8], rdx
    mov     rsi, [rsp + S_AOFF]
    mov     [rax + 16], rsi
    xor     r8d, r8d
    mov     [rsp + S_CTX2], r8
    lea     r8, [rax + HDR_SIZE]
    mov     [rsp + S_CTX2 + 8], r8
    lea     r8, [rax + rsi]
    mov     [rsp + S_CTX2 + 16], r8
    mov     [rsp + S_CTX2 + 24], rax
    mov     [rsp + S_CTX2 + 32], rdx
    add     rax, rcx
    mov     [rsp + S_CTX2 + 40], rax
    mov     eax, r15d
    or      eax, FLAG_LINENO
    mov     [rsp + S_ARG7], rax
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    mov     rcx, r14
    lea     r8, [fill_cb]
    lea     r9, [rsp + S_CTX2]
    call    ag_scan
    cmp     rax, -1
    je      .changed
    mov     rcx, [rsp + S_BASE]
    mov     [rcx + 8], rax          ; lines actually stored
    mov     rdx, [rsp + S_OUT]
    mov     [rdx], rcx
    xor     eax, eax
    jmp     .ret
.changed:
    mov     rdi, [rsp + S_BASE]
    mov     rsi, [rsp + S_TOTAL]
    call    ag_free
    mov     eax, -EIO
    jmp     .ret
.inval:
    mov     eax, -EINVAL
    jmp     .ret
.nomem:
    mov     eax, -ENOMEM
    jmp .ret

.overflow:
    mov eax, -EOVERFLOW
    jmp .ret
    .ret:
    add     rsp, S_FRAME
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

api_fn asmgrep_search_buffer
    jmp     search_common

api_fn asmgrep_search_file
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 24
    test    rcx, rcx
    jz      .inval
    mov     qword [rcx], 0
    test    rdi, rdi
    jz      .inval
    test    rsi, rsi
    jz      .inval
    mov     rbx, rdi
    mov     r12d, edx
    mov     r13, rcx
    mov     rdi, rsi
    lea     rsi, [rsp]
    call    ag_map_file
    test    rax, rax
    js      .ret
    mov     rdi, rbx
    call    ag_strlen
    mov     rcx, rax
    mov     rdi, [rsp]
    mov     rsi, [rsp + 8]
    mov     rdx, rbx
    mov     r8d, r12d
    mov     r9, r13
    call    search_common
    mov     r12d, eax
    lea     rdi, [rsp]
    call    ag_unmap
    mov     eax, r12d
    jmp     .ret
.inval:
    mov     eax, -EINVAL
.ret:
    add     rsp, 24
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

api_fn asmgrep_result_count
    xor     eax, eax
    test    rdi, rdi
    jz      .done
    mov     rax, [rdi + 8]
.done:
    ret

; entry address in rax, or 0 when out of range
entry_addr:
    xor     eax, eax
    test    rdi, rdi
    jz      .done
    cmp     rsi, [rdi + 8]
    jae     .done
    lea     rax, [rsi + rsi * 2]
    lea     rax, [rdi + rax * 8 + HDR_SIZE]
.done:
    ret

api_fn asmgrep_result_line_number
    call    entry_addr
    test    rax, rax
    jz      .done
    mov     rax, [rax]
.done:
    ret

api_fn asmgrep_result_length
    call    entry_addr
    test    rax, rax
    jz      .done
    mov     rax, [rax + 16]
.done:
    ret

api_fn asmgrep_result_text
    call    entry_addr
    test    rax, rax
    jz      .done
    mov     rax, [rax + 8]
    add     rax, rdi
.done:
    ret

api_fn asmgrep_free
    test    rdi, rdi
    jz      .done
    mov     rsi, [rdi]
    jmp     ag_free
.done:
    ret

api_fn asmgrep_strerror
    test    edi, edi
    jnz     .err
    lea     rax, [msg_ok]
    ret
.err:
    jns     .pos
    neg     edi
.pos:
    jmp     ag_strerror

api_fn asmgrep_version
    lea     rax, [version]
    ret

section .rodata
msg_ok:  db "Success", 0
version: db "1.0.0", 0

gnu_stack
