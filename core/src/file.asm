; File access.
;
; long ag_file_open(const char *path)
;     Opens path read-only. Returns a descriptor or -errno.
; long ag_file_size(int fd)
;     Returns the size of a regular file, or -errno. Non-regular files
;     yield -EINVAL and directories -EISDIR; sizes that do not fit a signed 64-bit value yield -EFBIG.

%include "internal.inc"

default rel
bits 64

section .text

export_fn ag_file_open
    mov     rsi, rdi
    mov     edi, AT_FDCWD
    mov     edx, O_RDONLY | O_CLOEXEC
    xor     r10d, r10d
    mov     eax, SYS_openat
    syscall
    ret

export_fn ag_file_size
    sub     rsp, 152                ; struct stat, keeps rsp 16-byte aligned
    mov     rsi, rsp
    mov     eax, SYS_fstat
    syscall
    test    rax, rax
    js      .out
    mov     eax, [rsp + ST_MODE]
    and     eax, S_IFMT
    cmp     eax, S_IFREG
    jne     .notreg_check
    mov     rax, [rsp + ST_SIZE]
    test    rax, rax
    jns     .out
    mov     rax, -EFBIG
    jmp     .out
.notreg_check:
    cmp     eax, S_IFDIR
    jne     .notreg
    mov     rax, -EISDIR
    jmp     .out
.notreg:
    mov     rax, -EINVAL
.out:
    add     rsp, 152
    ret

gnu_stack
