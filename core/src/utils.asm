; Small freestanding helpers.
;
; size_t ag_strlen(const char *s)
; const char *ag_strerror(int err)       err is a positive errno value
; size_t ag_utoa(uint64_t v, char *buf)  writes decimal digits, returns length
; void *ag_alloc(size_t n)               anonymous mapping, or NULL
; void ag_free(void *p, size_t n)

%include "internal.inc"

default rel
bits 64

section .text

export_fn ag_strlen
    xor     eax, eax
.loop:
    cmp     byte [rdi + rax], 0
    je      .done
    inc     rax
    jmp     .loop
.done:
    ret

export_fn ag_strerror
    lea     rdx, [errtab]
    mov     rsi, rdx
.next:
    mov     eax, [rsi]
    test    eax, eax
    jz      .unknown
    cmp     eax, edi
    je      .found
    add     rsi, 8
    jmp     .next
.found:
    mov     eax, [rsi + 4]          ; offset of the message from errtab
    add     rax, rdx
    ret
.unknown:
    lea     rax, [msg_unknown]
    ret

export_fn ag_utoa
    mov     rax, rdi
    lea     r8, [rsi + 24]          ; fill backwards from scratch end
    mov     r9, r8
    mov     r10d, 10
.digit:
    xor     edx, edx
    div     r10
    add     dl, '0'
    dec     r8
    mov     [r8], dl
    test    rax, rax
    jnz     .digit
    mov     rcx, r9
    sub     rcx, r8                 ; length
    mov     rax, rcx
    mov     rdi, rsi
    mov     rsi, r8
.copy:
    test    rcx, rcx
    jz      .done
    mov     dl, [rsi]
    mov     [rdi], dl
    inc     rsi
    inc     rdi
    dec     rcx
    jmp     .copy
.done:
    ret

export_fn ag_alloc
    test    rdi, rdi
    jz      .fail
    mov     rsi, rdi
    xor     edi, edi
    mov     edx, PROT_READ | PROT_WRITE
    mov     r10d, MAP_PRIVATE | MAP_ANONYMOUS
    mov     r8, -1
    xor     r9d, r9d
    mov     eax, SYS_mmap
    syscall
    cmp     rax, -4095
    jae     .fail
    ret
.fail:
    xor     eax, eax
    ret

export_fn ag_free
    test    rdi, rdi
    jz      .done
    mov     eax, SYS_munmap
    syscall
.done:
    ret

section .rodata

%macro err 2
    dd %1, %2 - errtab
%endmacro

align 8
errtab:
    err 1,  msg_eperm
    err 2,  msg_enoent
    err 5,  msg_eio
    err 6,  msg_enxio
    err 12, msg_enomem
    err 13, msg_eacces
    err 20, msg_enotdir
    err 21, msg_eisdir
    err 22, msg_einval
    err 23, msg_enfile
    err 24, msg_emfile
    err 27, msg_efbig
    err 36, msg_enametoolong
    err 40, msg_eloop
    err 75, msg_eoverflow
    dd 0, 0

msg_eperm:        db "Operation not permitted", 0
msg_enoent:       db "No such file or directory", 0
msg_eio:          db "Input/output error", 0
msg_enxio:        db "No such device or address", 0
msg_enomem:       db "Cannot allocate memory", 0
msg_eacces:       db "Permission denied", 0
msg_enotdir:      db "Not a directory", 0
msg_eisdir:       db "Is a directory", 0
msg_einval:       db "Invalid argument", 0
msg_enfile:       db "Too many open files in system", 0
msg_emfile:       db "Too many open files", 0
msg_efbig:        db "File too large", 0
msg_enametoolong: db "File name too long", 0
msg_eloop:        db "Too many levels of symbolic links", 0
msg_eoverflow:    db "Value too large for defined data type", 0
msg_unknown:      db "Unknown error", 0

gnu_stack
