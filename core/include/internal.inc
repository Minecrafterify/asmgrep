%ifndef ASMGREP_INTERNAL_INC
%define ASMGREP_INTERNAL_INC

%define SYS_read        0
%define SYS_write       1
%define SYS_close       3
%define SYS_fstat       5
%define SYS_mmap        9
%define SYS_munmap      11
%define SYS_exit        60
%define SYS_openat      257
%define SYS_getdents64  217
%define SYS_newfstatat  262

%define AT_FDCWD        -100
%define O_RDONLY        0
%define O_CLOEXEC       0x80000
%define O_DIRECTORY     0x10000
%define O_NOFOLLOW      0x20000
%define AT_SYMLINK_NOFOLLOW 0x100
%define PROT_READ       1
%define PROT_WRITE      2
%define MAP_PRIVATE     2
%define MAP_ANONYMOUS   0x20

%define S_IFMT          0xF000
%define S_IFREG         0x8000
%define S_IFDIR         0x4000
%define ST_MODE         24
%define ST_SIZE         48
%define STAT_SIZE       144

%define EIO             5
%define ENOMEM          12
%define EISDIR          21
%define EINVAL          22
%define EFBIG           27
%define EOVERFLOW       75
%define FLAG_LINENO     2
%define FLAG_SCALAR     1
%define SYS_ioctl       16

%define SCAN_ERROR      -1

%define DT_UNKNOWN      0
%define DT_DIR          4
%define DT_REG          8
%define DT_LNK          10

%macro export_fn 1
    global %1:function hidden
%1:
%endmacro

%macro api_fn 1
    global %1:function
%1:
%endmacro

%macro gnu_stack 0
    section .note.GNU-stack noalloc noexec nowrite progbits
%endmacro

%endif
