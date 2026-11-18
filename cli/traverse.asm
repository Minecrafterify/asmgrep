
; asmgrep command-line file traversal.
;
; int cli_traverse(struct cli_opts *opts,
;                  void *callback_context,
;                  size_t pattern_length);
;
; Returns:
;   0 = at least one matching line
;   1 = no matches
;   2 = one or more errors

%include "internal.inc"

default rel
bits 64

extern ag_map_file
extern ag_unmap
extern ag_scan
extern ag_strlen
extern ag_strerror
extern ag_utoa

extern cli_put
extern cli_flush
extern cli_line_cb
extern cli_write_all

; cli_opts offsets
%define OPT_FLAGS       0
%define OPT_PATTERN     8
%define OPT_OPERANDS    16
%define OPT_COUNT       24

; Callback context offsets
%define CTX_PATTERN     0
%define CTX_PATLEN      8
%define CTX_COLOR       16
%define CTX_FILENAME    24
%define CTX_FILENAMELEN 32

; Local stack frame
%define T_MAP           0
%define T_FLAGS         16
%define T_COUNT         24
%define T_OPERAND       32
%define T_STATUS        40
%define T_CTX           48
%define T_SCRATCH       96
%define T_SIZE          168

section .text

global cli_traverse:function hidden

cli_traverse:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, T_SIZE

    ; Arguments:
    ; rdi = cli_opts *
    ; rsi = callback context *
    ; rdx = pattern length

    mov     r12, rdi
    mov     r13, rsi
    mov     r14, [r12 + OPT_OPERANDS]
    mov     r15, [r12 + OPT_COUNT]

    mov     qword [rsp + T_COUNT], 0
    mov     qword [rsp + T_STATUS], 1
    mov     qword [rsp + T_FLAGS], 0

    ; ag_scan flags:
    ; -n enables line numbers, except with -c.
    mov     rax, [r12 + OPT_FLAGS]

    test    al, 2
    jnz     .no_line_numbers

    test    al, 1
    jz      .no_line_numbers

    or      qword [rsp + T_FLAGS], FLAG_LINENO

.no_line_numbers:
    test    al, 4
    jz      .flags_ready

    or      qword [rsp + T_FLAGS], FLAG_SCALAR

.flags_ready:
    ; Filename prefix is needed for multiple operands.
    cmp     r15, 1
    ja      .multiple_operands

    mov     qword [r13 + CTX_FILENAME], 0
    mov     qword [r13 + CTX_FILENAMELEN], 0
    jmp     .operand_loop

.multiple_operands:
    ; The actual filename is set for each operand below.

.operand_loop:
    test    r15, r15
    jz      .finished

    mov     rbx, [r14]
    add     r14, 8
    dec     r15

    mov     [rsp + T_OPERAND], rbx

    ; Set callback filename context.
    cmp     qword [r12 + OPT_COUNT], 1
    je      .no_filename

    mov     [r13 + CTX_FILENAME], rbx

    mov     rdi, rbx
    call    ag_strlen
    mov     [r13 + CTX_FILENAMELEN], rax
    jmp     .map_file

.no_filename:
    mov     qword [r13 + CTX_FILENAME], 0
    mov     qword [r13 + CTX_FILENAMELEN], 0

.map_file:
    mov     rdi, [rsp + T_OPERAND]
    lea     rsi, [rsp + T_MAP]
    call    ag_map_file

    test    rax, rax
    js      .file_error

    ; Scan this file.
    mov     rdi, [rsp + T_MAP]
    mov     rsi, [rsp + T_MAP + 8]
    mov     rdx, [r12 + OPT_PATTERN]
    mov     rcx, [r13 + CTX_PATLEN]

    test    qword [r12 + OPT_FLAGS], 2
    jnz     .count_only

    lea     r8, [cli_line_cb]
    jmp     .scan

.count_only:
    xor     r8d, r8d

.scan:
    mov     r9, r13

    ; Seventh argument: ag_scan flags.
    sub     rsp, 16
    mov     rax, [rsp + 16 + T_FLAGS]
    mov     [rsp], rax

    call    ag_scan

    add     rsp, 16

    mov     [rsp + T_COUNT], rax

    ; Always unmap successfully mapped files.
    lea     rdi, [rsp + T_MAP]
    call    ag_unmap

    cmp     qword [rsp + T_COUNT], -1
    je      .scan_error

    ; Aggregate match status.
    ; Errors have priority over matches.
    cmp     qword [rsp + T_COUNT], 0
    jle     .count_output

    cmp     qword [rsp + T_STATUS], 2
    je     .count_output

    mov     qword [rsp + T_STATUS], 0

.count_output:
    test    qword [r12 + OPT_FLAGS], 2
    jz      .next_operand

    ; Print count, with filename prefix when applicable.
    cmp     qword [r13 + CTX_FILENAME], 0
    je      .print_count

    mov     rdi, [r13 + CTX_FILENAME]
    mov     rsi, [r13 + CTX_FILENAMELEN]
    call    cli_put

    test    rax, rax
    js      .output_error

    lea     rdi, [count_separator]
    mov     esi, 1
    call    cli_put

    test    rax, rax
    js      .output_error

.print_count:
    mov     rdi, [rsp + T_COUNT]
    lea     rsi, [rsp + T_SCRATCH]
    call    ag_utoa

    mov     byte [rsp + T_SCRATCH + rax], 10

    lea     rdi, [rsp + T_SCRATCH]
    lea     rsi, [rsp + T_SCRATCH + rax + 1]
    sub     rsi, rdi

    call    cli_put

    test    rax, rax
    js      .output_error

.next_operand:
    jmp     .operand_loop

.file_error:
    ; Report an error for this operand.
    mov     rdi, rax
    neg     rdi
    call    ag_strerror

    mov     rbx, rax

    mov     edi, 2
    lea     rsi, [error_prefix]
    mov     edx, error_prefix_len
    call    cli_write_all

    mov     rdi, [rsp + T_OPERAND]
    call    ag_strlen
    mov     rdx, rax
    mov     rsi, [rsp + T_OPERAND]
    mov     edi, 2
    call    cli_write_all

    mov     edi, 2
    lea     rsi, [error_separator]
    mov     edx, error_separator_len
    call    cli_write_all

    mov     rdi, rbx
    call    ag_strlen
    mov     rdx, rax
    mov     rsi, rbx
    mov     edi, 2
    call    cli_write_all

    mov     edi, 2
    lea     rsi, [newline]
    mov     edx, 1
    call    cli_write_all

    mov     qword [rsp + T_STATUS], 2
    jmp     .next_operand

.scan_error:
    mov     qword [rsp + T_STATUS], 2
    jmp     .next_operand

.output_error:
    mov     qword [rsp + T_STATUS], 2
    jmp     .next_operand

.finished:
    call    cli_flush

    test    rax, rax
    js      .return_error

    mov     eax, [rsp + T_STATUS]
    jmp     .return

.return_error:
    mov     eax, 2

.return:
    add     rsp, T_SIZE
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

section .rodata

count_separator:  db ':'

error_prefix:     db 'asmgrep: '
error_prefix_len equ $ - error_prefix

error_separator:     db ': '
error_separator_len  equ $ - error_separator

newline: db 10

section .note.GNU-stack noalloc noexec nowrite progbits
