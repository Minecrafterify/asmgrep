; Memory-mapped file access.
;
; struct ag_mapping { const uint8_t *addr; size_t len; };
;
; long ag_map_file(const char *path, struct ag_mapping *m)
;     Maps path read-only. Returns 0 or -errno. Empty files produce
;     addr = NULL, len = 0 without creating a mapping.
; void ag_unmap(struct ag_mapping *m)
;     Releases a mapping created by ag_map_file. Safe on empty mappings.

%include "internal.inc"

default rel
bits 64

extern ag_file_open
extern ag_file_size

section .text

export_fn ag_map_file
    push    rbx
    push    r12
    push    r13
    mov     r12, rsi
    xor     eax, eax
    mov     [r12], rax
    mov     [r12 + 8], rax
    call    ag_file_open
    test    rax, rax
    js      .out
    mov     rbx, rax                ; fd
    mov     edi, ebx
    call    ag_file_size
    test    rax, rax
    js      .close_err
    jz      .close_ok               ; empty file
    mov     r13, rax                ; size
    xor     edi, edi
    mov     rsi, r13
    mov     edx, PROT_READ
    mov     r10d, MAP_PRIVATE
    mov     r8d, ebx
    xor     r9d, r9d
    mov     eax, SYS_mmap
    syscall
    cmp     rax, -4095
    jae     .close_err
    mov     [r12], rax
    mov     [r12 + 8], r13
.close_ok:
    xor     r13d, r13d
    jmp     .close
.close_err:
    mov     r13, rax                ; remember the error across close
.close:
    mov     edi, ebx
    mov     eax, SYS_close
    syscall
    mov     rax, r13
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

export_fn ag_unmap
    mov     rsi, [rdi + 8]
    test    rsi, rsi
    jz      .done
    mov     rax, [rdi]
    mov     qword [rdi], 0
    mov     qword [rdi + 8], 0
    mov     rdi, rax
    mov     eax, SYS_munmap
    syscall
.done:
    ret

gnu_stack
