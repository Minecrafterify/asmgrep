
; Command-line parsing.
;
; struct cli_opts {
;     uint64_t flags;
;     const char *pattern;
;     char **operands;
;     uint64_t operand_count;
; };
;
; int cli_parse(int argc, char **argv, struct cli_opts *o)
;     Returns 0 on success, 2 after printing a diagnostic on a usage error.

%include "internal.inc"

default rel
bits 64

extern ag_strlen
extern cli_write_all

section .text

; int streq(const char *a, const char *b)
streq:
.loop:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .no
    test    al, al
    jz      .yes
    inc     rdi
    inc     rsi
    jmp     .loop
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; void err_msg(const char *s)
err_msg:
    push    rbx
    mov     rbx, rdi
    mov     edi, 2
    lea     rsi, [prefix]
    mov     edx, prefix_len
    call    cli_write_all
    mov     rdi, rbx
    call    ag_strlen
    mov     rdx, rax
    mov     edi, 2
    mov     rsi, rbx
    call    cli_write_all
    pop     rbx
    ret

; int usage_error(const char *msg)
usage_error:
    sub     rsp, 8
    call    err_msg
    mov     edi, 2
    lea     rsi, [try_help]
    mov     edx, try_help_len
    call    cli_write_all
    mov     eax, 2
    add     rsp, 8
    ret

global cli_parse:function hidden
cli_parse:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 16

    mov     r12, rdi                ; argc
    mov     r13, rsi                ; argv
    mov     r14, rdx                ; opts

    xor     eax, eax
    mov     [r14], rax              ; flags
    mov     [r14 + 8], rax          ; pattern
    mov     [r14 + 16], rax         ; operands
    mov     [r14 + 24], rax         ; operand_count

    mov     ebx, 1                  ; argv index
    xor     r15d, r15d              ; options-ended flag

.next_arg:
    cmp     rbx, r12
    jae     .finish

    mov     rdi, [r13 + rbx * 8]
    inc     rbx

    test    r15, r15
    jnz     .positional

    cmp     byte [rdi], '-'
    jne     .positional
    cmp     byte [rdi + 1], 0
    je      .positional             ; lone "-" is an operand
    cmp     byte [rdi + 1], '-'
    je      .long_opt

    lea     rsi, [rdi + 1]

.short_loop:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .next_arg

    cmp     al, 'n'
    je      .s_n
    cmp     al, 'c'
    je      .s_c
    cmp     al, 'h'
    je      .s_h
    cmp     al, 'V'
    je      .s_v
    cmp     al, 'r'
    je      .s_r
    cmp     al, 'R'
    je      .s_R

    lea     rdi, [rsp]
    mov     byte [rdi], al
    mov     byte [rdi + 1], 0
    jmp     .bad_short

.s_n:
    or      qword [r14], 1
    inc     rsi
    jmp     .short_loop

.s_c:
    or      qword [r14], 2
    inc     rsi
    jmp     .short_loop

.s_h:
    or      qword [r14], 8
    inc     rsi
    jmp     .short_loop

.s_v:
    or      qword [r14], 16
    inc     rsi
    jmp     .short_loop

.s_r:
    or      qword [r14], 128
    and     qword [r14], -257
    inc     rsi
    jmp     .short_loop

.s_R:
    or      qword [r14], 256
    and     qword [r14], -129
    inc     rsi
    jmp     .short_loop

.bad_short:
    lea     rdi, [msg_invalid]
    call    err_msg
    lea     rdi, [rsp]
    call    err_msg_tail
    mov     eax, 2
    jmp     .out

.long_opt:
    cmp     byte [rdi + 2], 0
    jne     .long_named
    mov     r15d, 1
    jmp     .next_arg

.long_named:
    mov     r8, rdi

    lea     rsi, [opt_help]
    call    streq
    test    eax, eax
    jnz     .l_help

    mov     rdi, r8
    lea     rsi, [opt_version]
    call    streq
    test    eax, eax
    jnz     .l_version

    mov     rdi, r8
    lea     rsi, [opt_scalar]
    call    streq
    test    eax, eax
    jnz     .l_scalar

    mov     rdi, r8
    lea     rsi, [opt_recursive]
    call    streq
    test    eax, eax
    jnz     .l_recursive

    mov     rdi, r8
    lea     rsi, [opt_recursive_follow]
    call    streq
    test    eax, eax
    jnz     .l_recursive_follow

    mov     rdi, r8
    lea     rsi, [opt_color_auto]
    call    streq
    test    eax, eax
    jnz     .l_color_auto

    mov     rdi, r8
    lea     rsi, [opt_color_always]
    call    streq
    test    eax, eax
    jnz     .l_color_always

    mov     rdi, r8
    lea     rsi, [opt_color_never]
    call    streq
    test    eax, eax
    jnz     .l_color_never

    lea     rdi, [msg_unrec]
    call    err_msg
    mov     rdi, r8
    call    err_msg_tail
    mov     eax, 2
    jmp     .out

.l_help:
    or      qword [r14], 8
    jmp     .next_arg

.l_version:
    or      qword [r14], 16
    jmp     .next_arg

.l_scalar:
    or      qword [r14], 4
    jmp     .next_arg

.l_recursive:
    or      qword [r14], 128
    and     qword [r14], -257
    jmp     .next_arg

.l_recursive_follow:
    or      qword [r14], 256
    and     qword [r14], -129
    jmp     .next_arg

.l_color_auto:
    and     qword [r14], -97
    jmp     .next_arg

.l_color_always:
    and     qword [r14], -97
    or      qword [r14], 32
    jmp     .next_arg

.l_color_never:
    and     qword [r14], -97
    or      qword [r14], 64
    jmp     .next_arg

.positional:
    cmp     qword [r14 + 8], 0
    jne     .operand

    mov     [r14 + 8], rdi
    jmp     .next_arg

.operand:
    cmp     qword [r14 + 16], 0
    jne     .store_operand

    lea     rax, [r13 + 8]
    mov     [r14 + 16], rax

.store_operand:
    mov     rax, [r14 + 24]
    inc     rax
    mov     [r13 + rax * 8], rdi
    inc     qword [r14 + 24]
    jmp     .next_arg

.finish:
    test    qword [r14], 8 | 16
    jnz     .ok

    cmp     qword [r14 + 8], 0
    je      .no_pat

    cmp     qword [r14 + 24], 0
    je      .no_file

.ok:
    xor     eax, eax
    jmp     .out

.no_pat:
    lea     rdi, [msg_nopat]
    call    usage_error
    jmp     .out

.no_file:
    lea     rdi, [msg_nofile]
    call    usage_error

.out:
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; Prints rdi followed by the usage hint.
err_msg_tail:
    sub     rsp, 8
    mov     rbx, rdi
    call    ag_strlen
    mov     rdx, rax
    mov     edi, 2
    mov     rsi, rbx
    call    cli_write_all
    mov     edi, 2
    lea     rsi, [quote_nl]
    mov     edx, quote_nl_len
    call    cli_write_all
    mov     edi, 2
    lea     rsi, [try_help]
    mov     edx, try_help_len
    call    cli_write_all
    add     rsp, 8
    ret

section .rodata
prefix:      db "asmgrep: "
prefix_len   equ $ - prefix
try_help:    db "Try 'asmgrep --help' for more information.", 10
try_help_len equ $ - try_help
quote_nl:    db 10
quote_nl_len equ $ - quote_nl

opt_help:            db "--help", 0
opt_version:         db "--version", 0
opt_scalar:          db "--scalar", 0
opt_recursive:       db "--recursive", 0
opt_recursive_follow: db "--dereference-recursive", 0

msg_invalid: db "invalid option: -", 0
msg_unrec:   db "unrecognized option: ", 0
msg_extra:   db "too many arguments", 10, 0
msg_nopat:   db "missing pattern", 10, 0
msg_nofile:  db "missing file operand", 10, 0

opt_color_auto:   db "--color=auto", 0
opt_color_always: db "--color=always", 0
opt_color_never:  db "--color=never", 0

gnu_stack
