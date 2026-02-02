; =============================================================================
; macros.inc - TLCS-900/H2 Helper Macros for ASL Assembler
; =============================================================================
; These macros provide encodings for TMP94C241 instructions that are not
; directly supported by ASL 1.42 Beta [Bld 298].
;
; Reference: ../kn5000-roms-disasm/tmp94c241.inc
; =============================================================================

; -----------------------------------------------------------------------------
; Block Copy Instructions
; -----------------------------------------------------------------------------

; LDIR_94 - Load, Increment, Repeat (TMP94C241 encoding)
; Copies bytes from (XHL) to (XDE), count in XBC
; Note: ASL generates 85 11 (TMP96C141 encoding), we need 83 11
LDIR_94 MACRO
	db 083h, 011h
	ENDM

; LDI - Load, Increment (single byte copy)
LDI MACRO
	db 085h, 010h
	ENDM

; LDIR - Load, Increment, Repeat (85 encoding)
LDIR MACRO
	db 085h, 011h
	ENDM

; -----------------------------------------------------------------------------
; 24-bit Address Loading
; -----------------------------------------------------------------------------

; LDA_XWA_IMM24 - Load 24-bit effective address into XWA
; Encoding: f2 LL MM HH 30
LDA_XWA_IMM24 MACRO value
	db 0f2h, value & 0FFh, (value >> 8) & 0FFh, (value >> 16) & 0FFh, 030h
	ENDM

; LDA_XDE_IMM24 - Load 24-bit effective address into XDE
; Encoding: f2 LL MM HH 32
LDA_XDE_IMM24 MACRO addr
	db 0f2h
	db addr & 0FFh, (addr >> 8) & 0FFh, (addr >> 16) & 0FFh
	db 032h
	ENDM

; LDA_XHL_IMM24 - Load 24-bit effective address into XHL
; Encoding: f2 LL MM HH 33
LDA_XHL_IMM24 MACRO addr
	db 0f2h
	db addr & 0FFh, (addr >> 8) & 0FFh, (addr >> 16) & 0FFh
	db 033h
	ENDM

; -----------------------------------------------------------------------------
; Call Instructions
; -----------------------------------------------------------------------------

; CALR - Call relative (shorter encoding than CALL)
; Encoding: 1e LL HH (16-bit signed relative offset)
CALR MACRO target
	db 01eh
	dw target - $ - 2
	ENDM

; CALL_ABS24 - Call absolute with 24-bit address
; Encoding: 1d LL MM HH
CALL_ABS24 MACRO target
	db 01dh, target & 0FFh, (target >> 8) & 0FFh, (target >> 16) & 0FFh
	ENDM

; -----------------------------------------------------------------------------
; Jump Instructions
; -----------------------------------------------------------------------------

; JRL_T - Jump relative long (always true)
; Encoding: 78 LL HH
JRL_T MACRO target
	db 078h
	dw target - $ - 2
	ENDM

; -----------------------------------------------------------------------------
; Memory Store Macros
; -----------------------------------------------------------------------------

; LD_MEM24_IMM8 - Store 8-bit immediate to 24-bit memory address
; Encoding: c2 LL MM HH 00 VV
LD_MEM24_IMM8 MACRO addr, value
	db 0c2h
	db addr & 0FFh, (addr >> 8) & 0FFh, (addr >> 16) & 0FFh
	db 000h
	db value & 0FFh
	ENDM

; LD_MEM24_IMM16 - Store 16-bit immediate to 24-bit memory address
; Encoding: f2 LL MM HH 02 VV WW
LD_MEM24_IMM16 MACRO addr, value
	db 0f2h
	db addr & 0FFh, (addr >> 8) & 0FFh, (addr >> 16) & 0FFh
	db 02h
	db value & 0FFh, (value >> 8) & 0FFh
	ENDM

; -----------------------------------------------------------------------------
; Register Load Helpers
; -----------------------------------------------------------------------------

; LD_A - Load immediate byte into A
LD_A MACRO value
	db 021h, value
	ENDM

; LD_C - Load immediate byte into C
LD_C MACRO value
	db 023h, value
	ENDM

; LD_L - Load immediate byte into L
LD_L MACRO value
	db 027h, value
	ENDM

; -----------------------------------------------------------------------------
; Zero Extension
; -----------------------------------------------------------------------------

; EXTZ_WA - Zero-extend A to WA (clear W, keep A)
EXTZ_WA MACRO
	db 0d8h, 012h
	ENDM

; EXTZ_BC - Zero-extend C to BC (clear B, keep C)
EXTZ_BC MACRO
	db 0d9h, 012h
	ENDM

; -----------------------------------------------------------------------------
; VGA I/O Helper Macros
; -----------------------------------------------------------------------------

; VGA_WRITE_PORT - Write byte to VGA port (requires XDE = VGA_IO_BASE)
; Port offset in WA, val in C
VGA_WRITE_PORT MACRO port, val
	ld WA, port
	ld C, val
	CALR Write_VGA_Register
	ENDM

; VGA_WRITE_INDEXED - Write to indexed VGA register pair (addr, data)
; Writes regidx to addrport, then regval to dataport
VGA_WRITE_INDEXED MACRO addrport, dataport, regidx, regval
	ld WA, addrport
	ld C, regidx
	CALR Write_VGA_Register
	ld WA, dataport
	ld C, regval
	CALR Write_VGA_Register
	ENDM
