
; asmgrep command-line entry point.

%include "internal.inc"

default rel
bits 64

%define VERSION_STR "asmgrep 1.0.0", 10

extern cli_parse
extern cli_write_all
extern ag_strlen
extern ag_memchr
extern cli_traverse

; ------------------------------------------------------------
; Stack frame
; ------------------------------------------------------------

%define F_OPTS      0
%define F_PATLEN    48
%define F_SCRATCH   56
%define F_CTX       104
%define F_SIZE      160

; Callback context:
; +0  pattern pointer
; +8  pattern length
; +16 color enabled
; +24 filename pointer
; +32 filename length

section .text

global _start:function

_start:
    ; Preserve argc and argv before aligning the stack.
    mov     rdi, [rsp]
    lea     rsi, [rsp + 8]

    and     rsp, -16
    sub     rsp, F_SIZE

    ; Parse command-line arguments.
    lea     rdx, [rsp + F_OPTS]
    call    cli_parse

    test    eax, eax
    jnz     exit_with

    ; Help and version.
    mov     rax, [rsp + F_OPTS]

    test    eax, 8
    jnz     show_help

    test    eax, 16
    jnz     show_version

    ; --------------------------------------------------------
    ; Calculate pattern length.
    ; --------------------------------------------------------

    mov     rdi, [rsp + F_OPTS + 8]
    call    ag_strlen

    mov     [rsp + F_PATLEN], rax

    ; Reject patterns containing newline.
    mov     rdi, [rsp + F_OPTS + 8]
    mov     rsi, rax
    mov     edx, 10
    call    ag_memchr

    cmp     rax, [rsp + F_PATLEN]
    jb      bad_pattern

    ; --------------------------------------------------------
    ; Initialize callback context.
    ; --------------------------------------------------------

    mov     rax, [rsp + F_OPTS + 8]
    mov     [rsp + F_CTX], rax

    mov     rax, [rsp + F_PATLEN]
    mov     [rsp + F_CTX + 8], rax

    mov     qword [rsp + F_CTX + 16], 0
    mov     qword [rsp + F_CTX + 24], 0
    mov     qword [rsp + F_CTX + 32], 0

    ; --------------------------------------------------------
    ; Color configuration.
    ; --------------------------------------------------------

    mov     rax, [rsp + F_OPTS]

    ; --color=always
    test    rax, 32
    jnz     .color_on

    ; --color=never
    test    rax, 64
    jnz     .color_done

    ; --color=auto: detect terminal.
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

    ; --------------------------------------------------------
    ; Execute traversal.
    ; --------------------------------------------------------

    lea     rdi, [rsp + F_OPTS]
    lea     rsi, [rsp + F_CTX]
    call    cli_traverse

    mov     edi, eax
    jmp     exit_with


; ============================================================
; Help
; ============================================================

show_help:
    mov     edi, 1
    lea     rsi, [help_text]
    mov     edx, help_len
    call    cli_write_all

    xor     edi, edi
    jmp     exit_with


; ============================================================
; Version
; ============================================================

show_version:
    mov     edi, 1
    lea     rsi, [version_text]
    mov     edx, version_len
    call    cli_write_all

    xor     edi, edi
    jmp     exit_with


; ============================================================
; Invalid pattern
; ============================================================

bad_pattern:
    lea     rdi, [msg_badpat]
    call    fail_msg

    jmp     exit_with


; ============================================================
; Error reporting
; ============================================================

; Prints:
; asmgrep: <message>
;
; Returns edi = 2.

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


; Writes a null-terminated string to stderr.
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


; ============================================================
; Process exit
; ============================================================

exit_with:
    mov     eax, SYS_exit
    syscall


section .rodata

prefix:
    db "asmgrep: "
prefix_len equ $ - prefix

msg_badpat:
    db "pattern must not contain a newline", 10, 0

version_text:
    db VERSION_STR
version_len equ $ - version_text

help_text:
    db "Usage: asmgrep [OPTION]... PATTERN FILE...", 10, 10

    db "Search for an exact, case-sensitive substring.", 10, 10

    db "Options:", 10
    db "  -n                     prefix matching lines with line numbers", 10
    db "  -c                     print matching line counts", 10
    db "      --scalar           use scalar search instead of SSE2", 10
    db "      --color=WHEN       color matches: auto, always, never", 10
    db "  -r, --recursive        recursively search directories", 10
    db "  -R, --dereference-recursive", 10
    db "                         recursively follow directory symlinks", 10
    db "      --                 end of options", 10
    db "  -h, --help             display this help and exit", 10
    db "  -V, --version          display version and exit", 10, 10

    db "Exit status:", 10
    db "  0  at least one matching line", 10
    db "  1  no matching lines", 10
    db "  2  error", 10

help_len equ $ - help_text

gnu_stack
