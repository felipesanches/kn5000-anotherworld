; =============================================================================
; local_macros.inc - Additional macros not in kn5000-roms-disasm
; =============================================================================
; These macros supplement the tmp94c241.inc from the disasm repository.
; =============================================================================

; LDA_XHL_IMM24 - Load 24-bit effective address into XHL
; Encoding: f2 LL MM HH 33
LDA_XHL_IMM24 MACRO addr
	db 0f2h
	db addr & 0FFh, (addr >> 8) & 0FFh, (addr >> 16) & 0FFh
	db 033h
	ENDM

; LDA_XBC_IMM24 - Load 24-bit effective address into XBC
; Encoding: f2 LL MM HH 31
LDA_XBC_IMM24 MACRO addr
	db 0f2h
	db addr & 0FFh, (addr >> 8) & 0FFh, (addr >> 16) & 0FFh
	db 031h
	ENDM
