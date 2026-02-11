; =============================================================================
; main.asm - Another World VM for KN5000
; =============================================================================
; Unified platform wrapper for dual-target build:
;   - TARGET_MAINCPU: Standalone main CPU ROM (0xE00000, for MAME testing)
;   - TARGET_EXTENSION: HDAE5000 extension board ROM (0x280000)
;
; Build: make maincpu  OR  make extension
;
; Target: TMP94C241F (TLCS-900/H2) @ 25 MHz
; =============================================================================

	cpu 96c141		; TLCS-900/H target
	page 0
	maxmode on

; =============================================================================
; Include shared definitions from kn5000-roms-disasm
; =============================================================================
	include "sfr_tmp94c241.asm"
	include "vga_constants.asm"
	include "tmp94c241.inc"

; Local macros not in the disasm repo
	include "local_macros.inc"

; =============================================================================
; RAM Section (target-specific base address)
; =============================================================================
; MAINCPU:   Uses 1MB DRAM at 0x000000-0x0FFFFF (stack in 0x000-0xFFF)
; EXTENSION: Uses 512KB extension board SRAM at 0x200000-0x27FFFF
	ifdef TARGET_MAINCPU
	ORG 010000h
	endif
	ifdef TARGET_EXTENSION
	ORG 0200000h
	endif

VM_VARIABLES:	DW	256 DUP (?)

THREADS_DATA:	DW	64*2 DUP (?)  ; For each of the 64 threads:

VM_IS_CHANNEL_ACTIVE:	DB	64*2 DUP (?)   ; For each of the 64 threads:

CURRENT_THREAD: DB ?
VM_PC:				DW ?
VM_STACK_POINTER: DD ?
VM_STACK: DW 256 DUP (?)

POLYGON_NUM_POINTS:	DB ?
POLYGON_BBOX_W:		DW ?					; uint16_t
POLYGON_BBOX_H:		DW ?					; uint16_t
POLYGON_POINTS:		DW	50 DUP (?, ?, ?)
POLYGON_XMIN:	DW ?						; int16_t
POLYGON_XMAX:	DW ?						; int16_t
POLYGON_YMIN:	DW ?						; int16_t
POLYGON_YMAX:	DW ?						; int16_t
HLINEY:		DW ?							; int16_t
CUR_LINE:			; uint32_t
CUR_LINE_LOW:	DW ?
CUR_LINE_HIGH:	DW ?

CPT1:				; uint32_t
CPT1_LOW:	DW ?
CPT1_HIGH:	DW ?

CPT2:				; uint32_t
CPT2_LOW:	DW ?
CPT2_HIGH:	DW ?

STEP1:				; int32_t
STEP1_LOW:	DW ?
STEP1_HIGH:	DW ?

STEP2:				; int32_t
STEP2_LOW:	DW ?
STEP2_HIGH:	DW ?

; int16_t x1, x2;
X1:			DW ?
X2:			DW ?

; 	uint16_t h;
POLYGON_H:	DW ?
DX:			DW ?	; int16_t

;	int16_t xmax, xmin
LINE_XMIN:	DW ?
LINE_XMAX:	DW ?
CUR_PAGE_PTR_1: DD ?
CUR_PAGE_PTR_2: DD ?
CUR_PAGE_PTR_3: DD ?
CUR_VIDEO_DATA: DD ?			; Pointer to current video polygon data (VIDEO_1 or VIDEO_2)
CUR_ZOOM: DW ?					; uint16_t zoom for polygon scaling (default 0x40)

STRING_X0: DW ?

SYSTEM_TICKS:        DD ?		; 32-bit tick counter (ISR-incremented, 12500 Hz)
FRAME_START_TICKS:   DD ?		; Tick count at frame start
LAST_FRAME_TICKS:    DW ?		; Elapsed ticks of last frame (for diagnostics)
FRAME_OVERRAN:       DB ?		; 1 if last frame exceeded budget, 0 otherwise

REQUESTED_NEXT_PART: DW ?		; Part switch request (0 = no request)
CURRENT_PART_ID: DW ?			; Current game part ID

; =============================================================================
; Main CPU ROM Layout
; =============================================================================
	ifdef TARGET_MAINCPU

STACK_TOP		EQU 001000h	; Stack in internal RAM
OFFSCREEN_BUFFER_1	EQU 060000h	; Offscreen buffer (required by vga_init, in DRAM)

	ORG 0E00000h

; Fill with 0xFF until code section
	rept 0F0000h		; ~960KB of padding
	db 0FFh
	endm

	ORG 0EF0000h

; Jump to Reset_Handler (VGA code is included first for macro definitions)
	jp Reset_Handler

; Include shared VGA I/O and initialization routines
	include "vga_io.asm"
	include "vga_init.asm"
	ret			; VGA_Setup has no ret (designed for inline use)

; Entry Point - Called after hardware reset
Reset_Handler:
	include "boot_hw_init.asm"

	; Set up stack pointer (after hardware init)
	LDA_XWA_IMM24 STACK_TOP
	ld XSP, XWA

	; Initialize VGA display using shared code
	CALR VGA_Setup

	; Turn screen on (sequencer clocking mode)
	VGA_SEQUENCER 01h, 001h

	jp ENTRY

	endif ; TARGET_MAINCPU

; =============================================================================
; Extension Board ROM Layout
; =============================================================================
	ifdef TARGET_EXTENSION

	ORG 0280000h

EXTENSION_HEADER:
	db 'XAPR'
	dd POINTERS
	JP ENTRY
POINTERS:
	db 0Eh, 00h, 00h, 00h; EMPTY_ROUTINE
	db 0Eh, 00h, 00h, 00h; EMPTY_ROUTINE
	db 0Eh, 00h, 00h, 00h; EMPTY_ROUTINE
	db 0Eh, 00h, 00h, 00h; EMPTY_ROUTINE
	db 0Eh, 00h, 00h, 00h; EMPTY_ROUTINE

	endif ; TARGET_EXTENSION

; =============================================================================
; VM Code (shared between both targets)
; =============================================================================
	include "another_world_vm.asm"

; =============================================================================
; ROM End (target-specific)
; =============================================================================
	ifdef TARGET_MAINCPU

INTT1_Handler:
	PUSH XWA
	LD XWA, (SYSTEM_TICKS)
	INC 1, XWA
	LD (SYSTEM_TICKS), XWA
	POP XWA
	RETI

Default_Handler:
	halt
	jr Default_Handler

; Reset Handler Location
	ORG 0FFFEE0h
Reset_Entry:
	jp Reset_Handler

; Fill gap between reset entry and vector table
	ORG 0FFFEE4h
	rept 01Ch
	db 0FFh
	endm

; Interrupt Vector Table
	ORG 0FFFF00h
VECTOR_TABLE:
	dd 00FFFEE0h		; Vector 0: Reset
	dd Default_Handler	; Vector 1
	dd Default_Handler	; Vector 2
	dd Default_Handler	; Vector 3
	dd Default_Handler	; Vector 4
	dd Default_Handler	; Vector 5
	dd Default_Handler	; Vector 6
	dd Default_Handler	; Vector 7

	rept 13				; Entries 8-20 (offsets 0x20-0x50)
	dd Default_Handler
	endm
	dd INTT1_Handler		; Entry 21 (offset 0x54): INTT1
	rept 42				; Entries 22-63 (offsets 0x58-0xFC)
	dd Default_Handler
	endm

	endif ; TARGET_MAINCPU

	ifdef TARGET_EXTENSION

	ORG 02FFFFFh
	db 0FFh

	endif ; TARGET_EXTENSION

; =============================================================================
; End of ROM
; =============================================================================
	end
