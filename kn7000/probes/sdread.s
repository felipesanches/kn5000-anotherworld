# Load from SD in the HOOK (firmware task context, where fopen works), not in our
# own task. open/read/close = fopen_api/fread_api/fclose_api (the framework file
# methods). Record FILE* and bytes-read for a lua to check.
.include "../src/platform.inc"
.equ FOPEN,   0x48585E2A
.equ FREAD,   0x48585E50
.equ FREADHLP, 0x483ECA09   # func_483ECA06_entry(a0=buf, a1=FILE, d0=size, d1=count)
.equ FCLOSE,  0x48585E65
.mnbase 0x502B6000
hook:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d0, (0x10, sp)
    mov     d1, (0x14, sp)
    mov     a0, (0x18, sp)
    mov     a1, (0x1c, sp)
    # --- SD load, synchronously, on the firmware's loading task ---
    mov     path, a0
    mov     mode, a1
    mov     FOPEN, a2
    calls   (a2)                    # a0 = FILE
    mov     0x44100000, a3
    mov     a0, (a3)                # record FILE*
    cmp     0, a0
    beq     h_resume
    mov     a0, a1                  # FILE
    mov     0x50200000, a0          # buffer in WORK RAM (DMA-able)
    mov     1, d0                   # size = 1 byte per element
    mov     0x1000, d1              # count
    mov     FREAD, a2               # fread_api -- a plain, calls-safe function
    calls   (a2)                    # d0 = bytes read
    mov     0x44100000, a3
    mov     d0, (4, a3)
    mov     (0x44100000), a0        # FILE
    mov     FCLOSE, a2
    calls   (a2)
h_resume:
    mov     0xCAFE, d0
    mov     0x44100000, a3
    mov     d0, (8, a3)
    mov     (0x10, sp), d0
    mov     (0x14, sp), d1
    mov     (0x18, sp), a0
    mov     (0x1c, sp), a1
    add     0x20, sp
    movm    (sp), [d2,d3,a2,a3]
    movm    [a2,a3], (sp)           # the two displaced XapEntry instructions
    add     -8, sp
    jmp     0x5029B005
path:
    .asciz "C:\TECHNICS\DATA\MYSET.MUP"
    .align 2
mode:
    .asciz "rb"
