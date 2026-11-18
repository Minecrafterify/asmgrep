
; asmgrep command-line traversal.
; x86-64 Linux NASM implementation.

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

%define OPT_FLAGS           0
%define OPT_PATTERN         8
%define OPT_OPERANDS        16
%define OPT_COUNT           24

%define CTX_PATTERN         0
%define CTX_PATLEN          8
%define CTX_COLOR           16
%define CTX_FILENAME        24
%define CTX_FILENAMELEN     32

; Main traversal frame
%define T_MAP               0
%define T_FLAGS             16
%define T_COUNT             24
%define T_OPERAND           32
%define T_STATUS            40
%define T_SCRATCH           96
%define T_STAT              128
%define T_SIZE              12568

; Recursive walker frame
%define W_FD                0
%define W_READ              8
%define W_POS               16
%define W_PATH_LEN          24
%define W_ENTRY_LEN         32
%define W_CHILD_LEN         40
%define W_STAT              48

%define W_DENTS             192
%define W_DENTS_SIZE        8192

%define W_PATH              8384
%define W_PATH_SIZE         4096

%define W_PARENT            12480
%define W_DEV               12488
%define W_INO               12496
%define W_MAP               12504
%define W_COUNT             12520
%define W_SCRATCH           12528
%define W_FRAME_SIZE        12568

%define DIRENT_RECLEN       16
%define DIRENT_NAME         19
%define DIRENT_MIN_SIZE     20

%define ST_DEV              0
%define ST_INO              8

%define S_IFLNK             0xA000
%define WALK_ENAMETOOLONG   36

section .text

global cli_traverse:function hidden
global cli_walk_dir:function hidden

; ============================================================
; cli_traverse(opts, ctx)
; ============================================================

cli_traverse:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, T_SIZE

    mov     r12, rdi
    mov     r13, rsi
    mov     r14, [r12 + OPT_OPERANDS]
    mov     r15, [r12 + OPT_COUNT]

    mov     qword [rsp + T_COUNT], 0
    mov     qword [rsp + T_STATUS], 1
    mov     qword [rsp + T_FLAGS], 0

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
    cmp     r15, 1
    ja      .operand_loop

    mov     qword [r13 + CTX_FILENAME], 0
    mov     qword [r13 + CTX_FILENAMELEN], 0

.operand_loop:
    test    r15, r15
    jz      .finished

    mov     rbx, [r14]
    add     r14, 8
    dec     r15

    mov     [rsp + T_OPERAND], rbx

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
    test    qword [r12 + OPT_FLAGS], 384
    jz      .open_file

    mov     edi, AT_FDCWD
    mov     rsi, [rsp + T_OPERAND]
    lea     rdx, [rsp + T_STAT]
    xor     r10d, r10d

    test    qword [r12 + OPT_FLAGS], 128
    jz      .stat_call

    mov     r10d, AT_SYMLINK_NOFOLLOW

.stat_call:
    mov     eax, SYS_newfstatat
    syscall

    test    rax, rax
    js      .open_file

    mov     eax, [rsp + T_STAT + ST_MODE]
    and     eax, S_IFMT
    cmp     eax, S_IFDIR
    je      .directory_operand

.open_file:
    mov     rdi, [rsp + T_OPERAND]
    lea     rsi, [rsp + T_MAP]
    call    ag_map_file
    jmp     .map_result

.directory_operand:
    mov     rdi, [rsp + T_OPERAND]
    mov     rsi, r12
    mov     rdx, r13
    lea     rcx, [rsp + T_STATUS]
    xor     r8d, r8d
    call    cli_walk_dir
    jmp     .operand_loop

.map_result:
    test    rax, rax
    js      .file_error

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

    sub     rsp, 16
    mov     rax, [rsp + 16 + T_FLAGS]
    mov     [rsp], rax

    call    ag_scan

    add     rsp, 16

    mov     [rsp + T_COUNT], rax

    lea     rdi, [rsp + T_MAP]
    call    ag_unmap

    cmp     qword [rsp + T_COUNT], -1
    je      .scan_error

    cmp     qword [rsp + T_COUNT], 0
    jle     .count_output

    cmp     qword [rsp + T_STATUS], 2
    je      .count_output

    mov     qword [rsp + T_STATUS], 0

.count_output:
    test    qword [r12 + OPT_FLAGS], 2
    jz      .operand_loop

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

    jmp     .operand_loop

.file_error:
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
    jmp     .operand_loop

.scan_error:
    mov     qword [rsp + T_STATUS], 2
    jmp     .operand_loop

.output_error:
    mov     qword [rsp + T_STATUS], 2
    jmp     .operand_loop

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


; ============================================================
; cli_walk_dir(path, opts, ctx, status, parent_frame)
;
; rdi = path
; rsi = opts
; rdx = ctx
; rcx = status pointer
; r8  = parent walker frame (NULL at root)
; ============================================================

cli_walk_dir:
    push    rbp
    mov     rbp, rsp

    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    sub     rsp, W_FRAME_SIZE

    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
    mov     r15, rdi

    mov     [rsp + W_PARENT], r8
    mov     qword [rsp + W_FD], -1
    mov     qword [rsp + W_POS], 0
    mov     qword [rsp + W_READ], 0

    ; Copy directory path into this frame.
    mov     rdi, r15
    call    ag_strlen

    cmp     rax, W_PATH_SIZE - 1
    jae     .path_error

    mov     [rsp + W_PATH_LEN], rax

    lea     rdi, [rsp + W_PATH]
    mov     rsi, r15
    mov     rcx, rax
    rep     movsb
    mov     byte [rdi], 0

    ; Stat directory.
    mov     edi, AT_FDCWD
    lea     rsi, [rsp + W_PATH]
    lea     rdx, [rsp + W_STAT]
    xor     r10d, r10d

    test    qword [r12 + OPT_FLAGS], 128
    jz      .stat_directory

    mov     r10d, AT_SYMLINK_NOFOLLOW

.stat_directory:
    mov     eax, SYS_newfstatat
    syscall

    test    rax, rax
    js      .walk_error

    mov     eax, [rsp + W_STAT + ST_MODE]
    and     eax, S_IFMT
    cmp     eax, S_IFDIR
    jne     .walk_done

    ; Save this directory's identity.
    mov     rax, [rsp + W_STAT + ST_DEV]
    mov     [rsp + W_DEV], rax

    mov     rax, [rsp + W_STAT + ST_INO]
    mov     [rsp + W_INO], rax

    ; Check ancestors to prevent symlink cycles.
    mov     rbx, [rsp + W_PARENT]

.cycle_check:
    test    rbx, rbx
    jz      .open_directory

    mov     rax, [rsp + W_DEV]
    cmp     rax, [rbx + W_DEV]
    jne     .parent_next

    mov     rax, [rsp + W_INO]
    cmp     rax, [rbx + W_INO]
    je      .walk_done

.parent_next:
    mov     rbx, [rbx + W_PARENT]
    jmp     .cycle_check

.open_directory:
    mov     edi, AT_FDCWD
    lea     rsi, [rsp + W_PATH]
    mov     edx, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    xor     r10d, r10d
    mov     eax, SYS_openat
    syscall

    test    rax, rax
    js      .walk_error

    mov     [rsp + W_FD], rax

.read_directory:
    mov     rdi, [rsp + W_FD]
    lea     rsi, [rsp + W_DENTS]
    mov     edx, W_DENTS_SIZE
    mov     eax, SYS_getdents64
    syscall

    test    rax, rax
    js      .read_error

    test    rax, rax
    jz      .close_directory

    mov     [rsp + W_READ], rax
    mov     qword [rsp + W_POS], 0

.next_entry:
    mov     rax, [rsp + W_POS]
    cmp     rax, [rsp + W_READ]
    jae     .read_directory

    lea     rbx, [rsp + W_DENTS]
    add     rbx, rax

    ; Validate record length.
    movzx   ecx, word [rbx + DIRENT_RECLEN]
    cmp     ecx, DIRENT_MIN_SIZE
    jb      .corrupt_directory

    add     rax, rcx
    cmp     rax, [rsp + W_READ]
    ja      .corrupt_directory

    mov     [rsp + W_POS], rax
    mov     [rsp + W_ENTRY_LEN], rcx

    ; Skip "." and "..".
    cmp     byte [rbx + DIRENT_NAME], '.'
    jne     .entry_name

    cmp     byte [rbx + DIRENT_NAME + 1], 0
    je      .next_entry

    cmp     byte [rbx + DIRENT_NAME + 1], '.'
    jne     .entry_name

    cmp     byte [rbx + DIRENT_NAME + 2], 0
    je      .next_entry

.entry_name:
    lea     rdi, [rbx + DIRENT_NAME]
    xor     ecx, ecx

.name_length:
    mov     edx, [rsp + W_ENTRY_LEN]
    sub     edx, DIRENT_NAME
    cmp     ecx, edx
    jae     .corrupt_directory

    cmp     byte [rdi + rcx], 0
    je      .name_ready

    inc     ecx
    jmp     .name_length

.name_ready:
    mov     [rsp + W_CHILD_LEN], rcx

    ; Calculate child path length.
    mov     rax, [rsp + W_PATH_LEN]
    mov     rcx, rax

    test    rcx, rcx
    jz      .no_separator

    cmp     byte [rsp + W_PATH + rcx - 1], '/'
    je      .no_separator

    inc     rcx

.no_separator:
    add     rcx, [rsp + W_CHILD_LEN]

    cmp     rcx, W_PATH_SIZE - 1
    jae     .path_error_close

    ; Append slash if necessary.
    mov     rax, [rsp + W_PATH_LEN]

    test    rax, rax
    jz      .copy_child_name

    cmp     byte [rsp + W_PATH + rax - 1], '/'
    je      .copy_child_name

    mov     byte [rsp + W_PATH + rax], '/'
    inc     rax

.copy_child_name:
    lea     rdi, [rsp + W_PATH + rax]
    lea     rsi, [rbx + DIRENT_NAME]
    mov     rcx, [rsp + W_CHILD_LEN]
    rep     movsb
    mov     byte [rdi], 0

    ; lstat child.
    mov     edi, AT_FDCWD
    lea     rsi, [rsp + W_PATH]
    lea     rdx, [rsp + W_STAT]
    mov     r10d, AT_SYMLINK_NOFOLLOW
    mov     eax, SYS_newfstatat
    syscall

    test    rax, rax
    js      .child_stat_error

    mov     eax, [rsp + W_STAT + ST_MODE]
    and     eax, S_IFMT

    cmp     eax, S_IFLNK
    jne     .classify_child

    ; -r skips all symlinks found during traversal.
    ; -R follows symlinks to files and directories.
    test    qword [r12 + OPT_FLAGS], 256
    jz      .next_entry

    ; Follow symlink target (-R).
    mov     edi, AT_FDCWD
    lea     rsi, [rsp + W_PATH]
    lea     rdx, [rsp + W_STAT]
    xor     r10d, r10d
    mov     eax, SYS_newfstatat
    syscall

    test    rax, rax
    js      .child_stat_error

    mov     eax, [rsp + W_STAT + ST_MODE]
    and     eax, S_IFMT
.follow_link:
    mov     edi, AT_FDCWD
    lea     rsi, [rsp + W_PATH]
    lea     rdx, [rsp + W_STAT]
    xor     r10d, r10d
    mov     eax, SYS_newfstatat
    syscall

    test    rax, rax
    js      .child_stat_error

    mov     eax, [rsp + W_STAT + ST_MODE]
    and     eax, S_IFMT

.classify_child:
    cmp     eax, S_IFDIR
    je      .child_directory

    cmp     eax, S_IFREG
    je      .child_file

    jmp     .next_entry

.child_directory:
    ; Recursive call; parent frame is this frame's base.
    lea     rdi, [rsp + W_PATH]
    mov     rsi, r12
    mov     rdx, r13
    mov     rcx, r14
    mov     r8, rsp
    call    cli_walk_dir

    jmp     .next_entry

.child_file:
    ; Map file.
    lea     rdi, [rsp + W_PATH]
    lea     rsi, [rsp + W_MAP]
    call    ag_map_file

    test    rax, rax
    js      .child_map_error

    ; Set callback filename.
    lea     rax, [rsp + W_PATH]
    mov     [r13 + CTX_FILENAME], rax

    mov     rdi, rax
    call    ag_strlen
    mov     [r13 + CTX_FILENAMELEN], rax

    ; ag_scan arguments.
    mov     rdi, [rsp + W_MAP]
    mov     rsi, [rsp + W_MAP + 8]
    mov     rdx, [r12 + OPT_PATTERN]
    mov     rcx, [r13 + CTX_PATLEN]

    test    qword [r12 + OPT_FLAGS], 2
    jnz     .file_count_mode

    lea     r8, [cli_line_cb]
    jmp     .file_scan

.file_count_mode:
    xor     r8d, r8d

.file_scan:
    mov     r9, r13

    sub     rsp, 16
    mov     qword [rsp], 0

    ; -n, unless -c.
    test    qword [r12 + OPT_FLAGS], 2
    jnz     .file_scan_flags

    test    qword [r12 + OPT_FLAGS], 1
    jz      .file_scan_flags

    mov     qword [rsp], FLAG_LINENO

.file_scan_flags:
    test    qword [r12 + OPT_FLAGS], 4
    jz      .file_scan_call

    or      qword [rsp], FLAG_SCALAR

.file_scan_call:
    call    ag_scan
    add     rsp, 16

    mov     [rsp + W_COUNT], rax

    lea     rdi, [rsp + W_MAP]
    call    ag_unmap

    cmp     qword [rsp + W_COUNT], -1
    je      .scan_failed

    ; -c output: filename:count
    test    qword [r12 + OPT_FLAGS], 2
    jz      .file_status

    lea     rdi, [rsp + W_PATH]
    mov     rsi, [r13 + CTX_FILENAMELEN]
    call    cli_put

    test    rax, rax
    js      .output_failed

    lea     rdi, [count_separator]
    mov     esi, 1
    call    cli_put

    test    rax, rax
    js      .output_failed

    mov     rdi, [rsp + W_COUNT]
    lea     rsi, [rsp + W_SCRATCH]
    call    ag_utoa

    mov     byte [rsp + W_SCRATCH + rax], 10

    lea     rdi, [rsp + W_SCRATCH]
    lea     rsi, [rsp + W_SCRATCH + rax + 1]
    sub     rsi, rdi
    call    cli_put

    test    rax, rax
    js      .output_failed

.file_status:
    cmp     qword [rsp + W_COUNT], 0
    jle     .next_entry

    cmp     dword [r14], 2
    je      .next_entry

    mov     dword [r14], 0
    jmp     .next_entry

.scan_failed:
    lea     rdi, [rsp + W_PATH]
    mov     esi, EIO
    call    walk_report_error
    mov     dword [r14], 2
    jmp     .next_entry

.child_map_error:
    mov     rsi, rax
    neg     rsi
    lea     rdi, [rsp + W_PATH]
    call    walk_report_error
    mov     dword [r14], 2
    jmp     .next_entry

.child_stat_error:
    mov     rsi, rax
    neg     rsi
    lea     rdi, [rsp + W_PATH]
    call    walk_report_error
    mov     dword [r14], 2
    jmp     .next_entry

.output_failed:
    mov     dword [r14], 2
    jmp     .next_entry

.read_error:
    mov     rsi, rax
    neg     rsi
    lea     rdi, [rsp + W_PATH]
    call    walk_report_error
    mov     dword [r14], 2
    jmp     .close_directory

.corrupt_directory:
    lea     rdi, [rsp + W_PATH]
    mov     esi, EIO
    call    walk_report_error
    mov     dword [r14], 2
    jmp     .close_directory

.path_error_close:
    lea     rdi, [rsp + W_PATH]
    mov     esi, WALK_ENAMETOOLONG
    call    walk_report_error
    mov     dword [r14], 2
    jmp     .close_directory

.close_directory:
    mov     rdi, [rsp + W_FD]
    mov     eax, SYS_close
    syscall

    test    rax, rax
    jns     .walk_done

    mov     rsi, rax
    neg     rsi
    lea     rdi, [rsp + W_PATH]
    call    walk_report_error
    mov     dword [r14], 2
    jmp     .walk_done

.walk_error:
    mov     rsi, rax
    neg     rsi
    lea     rdi, [rsp + W_PATH]
    call    walk_report_error
    mov     dword [r14], 2
    jmp     .walk_done

.path_error:
    mov     rdi, r15
    mov     esi, WALK_ENAMETOOLONG
    call    walk_report_error
    mov     dword [r14], 2
    jmp     .walk_done

.walk_done:
    add     rsp, W_FRAME_SIZE
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret


; ============================================================
; walk_report_error(path, positive_errno)
; ============================================================

walk_report_error:
    push    rbp
    mov     rbp, rsp

    push    rbx
    push    r12
    push    r13
    sub     rsp, 8

    mov     r12, rdi
    mov     r13, rsi

    mov     rdi, r13
    call    ag_strerror
    mov     rbx, rax

    mov     edi, 2
    lea     rsi, [error_prefix]
    mov     edx, error_prefix_len
    call    cli_write_all

    mov     rdi, r12
    call    ag_strlen

    mov     rdx, rax
    mov     rsi, r12
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

    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret


section .rodata

count_separator: db ':'

error_prefix: db 'asmgrep: '
error_prefix_len equ $ - error_prefix

error_separator: db ': '
error_separator_len equ $ - error_separator

newline: db 10

section .note.GNU-stack noalloc noexec nowrite progbits
