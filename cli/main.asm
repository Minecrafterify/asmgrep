; asmgrep command-line entry point.

%include "internal.inc"

default rel
bits 64

%define VERSION_STR "asmgrep 1.0.0", 10

extern cli_parse
extern cli_write_all
extern cli_flush
extern cli_put
extern cli_line_cb
extern ag_map_file
extern ag_unmap
extern ag_scan
extern ag_strlen
extern ag_strerror
extern ag_memchr
extern ag_utoa

; frame layout (relative to rsp after prologue)
%define F_OPTS      0               ; flags, pattern, file
%define F_MAP       24              ; addr, len
%define F_PATLEN    40
%define F_SCRATCH   48              ; scratch space
%define F_STACKARG  80
%define F_CTX       96              ; callback context
; F_CTX + 0: pattern pointer
; F_CTX + 8: pattern length
; F_CTX + 16: color enabled
%define F_SIZE      128

section .text

global _start:function
_start:
    mov     rdi, [rsp]
    lea     rsi, [rsp + 8]
    and     rsp, -16
    sub     rsp, F_SIZE
    lea     rdx, [rsp + F_OPTS]
    call    cli_parse
    test    eax, eax
    jnz     exit_with

    mov     rax, [rsp + F_OPTS]
    test    eax, 8
    jnz     show_help
    test    eax, 16
    jnz     show_version

    mov     rdi, [rsp + F_OPTS + 8]
    call    ag_strlen
    mov     [rsp + F_PATLEN], rax
    mov     rdi, [rsp + F_OPTS + 8]
    mov     rsi, rax
    mov     edx, 10
    call    ag_memchr
    cmp     rax, [rsp + F_PATLEN]
    jb      bad_pattern

    ; Set up callback context.
    mov     rax, [rsp + F_OPTS + 8]
    mov     [rsp + F_CTX], rax
    mov     rax, [rsp + F_PATLEN]
    mov     [rsp + F_CTX + 8], rax
    mov     qword [rsp + F_CTX + 16], 0

    ; --color=always
    mov     rax, [rsp + F_OPTS]
    test    rax, 32
    jnz     .color_on

    ; --color=never
    test    rax, 64
    jnz     .color_done

    ; --color=auto: check whether stdout is a terminal.
    mov     eax, SYS_ioctl
    mov     edi, 1
    mov     esi, 0x5413
    lea     rdx, [rsp + F_SCRATCH]
    syscall

    test    rax, rax
    js      .color_done

.color_on:
    mov     qword [rsp + F_CTX + 16], 1

.color_done:

    mov     rdi, [rsp + F_OPTS + 16]
    lea     rsi, [rsp + F_MAP]
    call    ag_map_file
    test    rax, rax
    js      file_error

    ; scan flags: line numbers only when printing lines with -n
    mov     rax, [rsp + F_OPTS]
    xor     ecx, ecx
    test    al, 2
    jnz     .no_numbers
    test    al, 1
    jz      .no_numbers
    or      ecx, FLAG_LINENO
.no_numbers:
    test    al, 4
    jz      .flags_done
    or      ecx, FLAG_SCALAR
.flags_done:
    mov     [rsp + F_STACKARG], rcx

    lea     r8, [cli_line_cb]
    test    al, 2
    jz      .have_cb
    xor     r8d, r8d                ; -c: count only
.have_cb:
    mov     rdi, [rsp + F_MAP]
    mov     rsi, [rsp + F_MAP + 8]
    mov     rdx, [rsp + F_OPTS + 8]
    mov     rcx, [rsp + F_PATLEN]
    lea     r9, [rsp + F_CTX]
    sub     rsp, 16
    mov     rax, [rsp + 16 + F_STACKARG]
    mov     [rsp], rax
    call    ag_scan
    add     rsp, 16
    mov     [rsp + F_STACKARG + 8], rax     ; keep match count (slot 88)

    lea     rdi, [rsp + F_MAP]
    call    ag_unmap

    mov     rax, [rsp + F_STACKARG + 8]
    cmp     rax, -1
    je      write_error

    test    byte [rsp + F_OPTS], 2
    jz      .finish
    mov     rdi, rax
    lea     rsi, [rsp + F_SCRATCH]
    call    ag_utoa
    mov     byte [rsp + F_SCRATCH + rax], 10
    lea     rsi, [rsp + F_SCRATCH + rax + 1]
    lea     rdi, [rsp + F_SCRATCH]
    mov     rdx, rsi
    sub     rdx, rdi
    mov     rsi, rdx
    call    cli_put
    test    rax, rax
    js      write_error
.finish:
    call    cli_flush
    test    rax, rax
    js      write_error
    xor     edi, edi
    cmp     qword [rsp + F_STACKARG + 8], 0
    jne     exit_with
    mov     edi, 1
    jmp     exit_with

show_help:
    mov     edi, 1
    lea     rsi, [help_text]
    mov     edx, help_len
    call    cli_write_all
    xor     edi, edi
    jmp     exit_with

show_version:
    mov     edi, 1
    lea     rsi, [version_text]
    mov     edx, version_len
    call    cli_write_all
    xor     edi, edi
    jmp     exit_with

bad_pattern:
    lea     rdi, [msg_badpat]
    call    fail_msg
    jmp     exit_with

file_error:
    neg     rax
    mov     edi, eax
    call    ag_strerror
    mov     r12, rax
    mov     edi, 2
    lea     rsi, [prefix]
    mov     edx, prefix_len
    call    cli_write_all
    mov     rdi, [rsp + F_OPTS + 16]
    call    write_cstr_err
    mov     edi, 2
    lea     rsi, [colon_sp]
    mov     edx, 2
    call    cli_write_all
    mov     rdi, r12
    call    write_cstr_err
    mov     edi, 2
    lea     rsi, [nl]
    mov     edx, 1
    call    cli_write_all
    mov     edi, 2
    jmp     exit_with

write_error:
    lea     rdi, [msg_write]
    call    fail_msg
    jmp     exit_with

; Prints "asmgrep: " + rdi to stderr, leaves 2 in edi.
fail_msg:
    push    rbx
    mov     rbx, rdi
    mov     edi, 2
    lea     rsi, [prefix]
    mov     edx, prefix_len
    call    cli_write_all
    mov     rdi, rbx
    call    write_cstr_err
    mov     edi, 2
    pop     rbx
    ret

write_cstr_err:
    push    rbx
    mov     rbx, rdi
    call    ag_strlen
    mov     rdx, rax
    mov     rsi, rbx
    mov     edi, 2
    call    cli_write_all
    pop     rbx
    ret

exit_with:
    mov     edi, edi
    mov     eax, SYS_exit
    syscall

section .rodata
prefix:       db "asmgrep: "
prefix_len    equ $ - prefix
colon_sp:     db ": "
nl:           db 10
msg_badpat:   db "pattern must not contain a newline", 10, 0
msg_write:    db "write error", 10, 0
version_text: db VERSION_STR
version_len   equ $ - version_text
help_text:
    db "Usage: asmgrep [OPTION]... PATTERN FILE", 10
    db "Print the lines of FILE that contain PATTERN as an exact,", 10
    db "case-sensitive substring.", 10, 10
    db "  -n          prefix each line with its line number", 10
    db "  -c          print only the number of matching lines", 10
    db "      --scalar  use the scalar reference search instead of SSE2", 10
    db "      --color=WHEN  color matches: auto, always, or never", 10
    db "      --      end of options", 10
    db "  -h, --help  display this help and exit", 10
    db "  -V, --version  display version and exit", 10, 10
    db "Exit status: 0 if a line matched, 1 if none matched, 2 on error.", 10
help_len equ $ - help_text

gnu_stack
