; =============================================================================
; main.asm - Custom KN5000 Boot ROM: Hello World
; =============================================================================
; A minimal boot ROM for the Technics KN5000 that:
;   1. Initializes essential hardware (watchdog, memory, ports)
;   2. Initializes the VGA display controller
;   3. Draws "Hello World" text on screen
;   4. Sends "It is working!" to the serial port (computer interface)
;
; Target: TMP94C241F (TLCS-900/H2) @ 25 MHz
; ROM Size: 2MB (0xE00000 - 0xFFFFFF)
; Reset Vector: 0xFFFEE0
;
; Build: make
; Test: Run in MAME kn5000 driver with custom ROM set
;
; This code reuses shared components from ../kn5000-roms-disasm/
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
; Memory Map Constants
; =============================================================================
STACK_TOP		EQU 001000h	; Stack in internal RAM
OFFSCREEN_BUFFER_1	EQU 280000h	; Offscreen buffer (required by vga_init)

; Screen dimensions
SCREEN_WIDTH		EQU 320
SCREEN_HEIGHT		EQU 240

; Colors (palette indices)
COLOR_BLACK		EQU 0
COLOR_WHITE		EQU 1
COLOR_DARK_BLUE		EQU 8

; Serial port constants
SC0MOD_8N1		EQU 069h	; 8-bit, no parity, 1 stop, baud gen
BR0CR_38400		EQU 006h	; 38400 baud

; =============================================================================
; ROM Layout
; =============================================================================
	org 0E00000h		; Program ROM base address

; Fill with 0xFF until code section
	rept 0F0000h		; ~960KB of padding
	db 0FFh
	endm

; =============================================================================
; Code Section (starts at 0xEF0000)
; =============================================================================
	org 0EF0000h

; Jump to Reset_Handler (VGA code is included first for macro definitions)
	jp Reset_Handler

; =============================================================================
; Include shared VGA I/O and initialization routines
; (defines Write_VGA_Register, VGA_Setup, and macros like VGA_SEQUENCER)
; =============================================================================
	include "vga_io.asm"
	include "vga_init.asm"

; =============================================================================
; Entry Point - Called after hardware reset
; =============================================================================
Reset_Handler:
	; =========================================================================
	; Include shared hardware initialization from kn5000-roms-disasm
	; This initializes: watchdog, clock, ports, timers, memory controller, DRAM
	; =========================================================================
	include "boot_hw_init.asm"

	; Set up stack pointer (after hardware init)
	LDA_XWA_IMM24 STACK_TOP
	ld XSP, XWA

	; Initialize VGA display using shared code
	CALR VGA_Setup

	; The shared VGA_Setup leaves registers set for buffer init:
	;   XWA = OFFSCREEN_BUFFER_1, BC = 0808h, DE = 38400
	; We skip the offscreen buffer stuff and just clear video RAM directly

	; Clear screen to dark blue
	CALR Clear_Screen

	; Draw "Hello World" message
	CALR Draw_Hello_World

	; Initialize serial port
	CALR Serial_Init

	; Send message to computer interface
	CALR Send_Serial_Message

	; Turn screen on (sequencer clocking mode)
	VGA_SEQUENCER 01h, 001h

	; Enter infinite loop
Main_Loop:
	halt
	jr Main_Loop

; =============================================================================
; Default_Handler - Default interrupt handler for unused vectors
; =============================================================================
Default_Handler:
	halt
	jr Default_Handler

; =============================================================================
; Clear_Screen - Fill screen with dark blue (color 8)
; =============================================================================
Clear_Screen:
	LDA_XDE_IMM24 VIDEO_RAM_BASE
	ld XBC, SCREEN_WIDTH * SCREEN_HEIGHT	; 76800 bytes
	ld A, COLOR_DARK_BLUE

.clear_loop:
	ld (XDE), A
	inc 1, XDE
	dec 1, XBC
	or XBC, XBC		; Set Z flag based on full 32-bit value
	jr NZ, .clear_loop

	ret

; =============================================================================
; Draw_Hello_World - Draw "Hello World" text centered on screen
; =============================================================================
Draw_Hello_World:
	; Calculate screen position: center of screen
	; X = (320 - 11*8) / 2 = 116
	; Y = (240 - 8) / 2 = 116
	; Offset = Y * 320 + X = 116 * 320 + 116 = 37236

	LDA_XDE_IMM24 VIDEO_RAM_BASE
	add XDE, 37236		; Center position

	; Draw the string
	LDA_XHL_IMM24 Str_HelloWorld
	CALR Draw_String

	ret

; =============================================================================
; Draw_String - Draw null-terminated string at screen position
; Input: XHL = string pointer, XDE = screen position (VRAM address)
; =============================================================================
Draw_String:
.draw_loop:
	ld A, (XHL)
	or A, A			; Check for null terminator
	ret Z

	push XDE
	push XHL
	CALR Draw_Char		; Draw character at (XDE), char in A
	pop XHL
	pop XDE

	add XDE, 8		; Move to next character position
	inc 1, XHL
	jr .draw_loop

; =============================================================================
; Draw_Char - Draw a single 8x8 character
; Input: A = ASCII character, XDE = screen position
; =============================================================================
Draw_Char:
	; Calculate font data offset: (A - 32) * 8
	sub A, 32		; ASCII offset
	EXTZ_WA			; Zero-extend A to WA

	; Multiply by 8 (shift left 3)
	sla 1, WA
	sla 1, WA
	sla 1, WA

	; Get font data address
	LDA_XHL_IMM24 Font_8x8
	add XHL, XWA

	; Draw 8 rows
	ld C, 8			; Row counter

.row_loop:
	ld A, (XHL)		; Get font row bitmap
	push XDE
	push XHL

	; Draw 8 pixels
	ld B, 8			; Column counter

.pixel_loop:
	bit 7, A		; Test MSB
	jr Z, .skip_pixel

	; Draw white pixel
	push WA
	ld (XDE), COLOR_WHITE
	pop WA

.skip_pixel:
	inc 1, XDE
	sla 1, A		; Shift to next bit
	dec 1, B
	or B, B
	jr NZ, .pixel_loop

	pop XHL
	pop XDE

	; Move to next row
	add XDE, SCREEN_WIDTH
	inc 1, XHL
	dec 1, C
	or C, C
	jr NZ, .row_loop

	ret

; =============================================================================
; Serial_Init - Initialize SC0 for computer interface (38400 baud)
; =============================================================================
Serial_Init:
	ld (SC0MOD), SC0MOD_8N1
	ld (BR0CR), BR0CR_38400
	ld (SC0CR), 000h
	ret

; =============================================================================
; Send_Serial_Message - Send "It is working!" to serial port
; =============================================================================
Send_Serial_Message:
	LDA_XHL_IMM24 Str_ItIsWorking

.send_loop:
	ld A, (XHL)
	or A, A			; Check for null terminator
	ret Z

	CALR Serial_Send_Byte
	inc 1, XHL
	jr .send_loop

; =============================================================================
; Serial_Send_Byte - Send single byte via SC0
; Input: A = byte to send
; =============================================================================
Serial_Send_Byte:
	push BC
	push DE

	; Wait for TX buffer empty (bit 1 of SC0CR) with timeout
	ld DE, 0FFFFh		; Timeout counter
.wait_tx_empty:
	ld C, (SC0CR)
	bit 1, C
	jr NZ, .tx_ready
	dec 1, DE
	or DE, DE
	jr NZ, .wait_tx_empty
	jr .send_done		; Timeout - skip send

.tx_ready:
	ld (SC0BUF), A

.send_done:
	pop DE
	pop BC
	ret

; =============================================================================
; Data Section
; =============================================================================
Str_HelloWorld:
	db "Hello World", 0

Str_ItIsWorking:
	db "It is working!", 13, 10, 0

; =============================================================================
; Font Data - Simple 8x8 bitmap font (ASCII 32-127)
; =============================================================================
Font_8x8:
	; Space (32)
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
	; ! (33)
	db 018h, 018h, 018h, 018h, 018h, 000h, 018h, 000h
	; " (34)
	db 06Ch, 06Ch, 06Ch, 000h, 000h, 000h, 000h, 000h
	; # (35)
	db 06Ch, 06Ch, 0FEh, 06Ch, 0FEh, 06Ch, 06Ch, 000h
	; $ (36)
	db 018h, 03Eh, 060h, 03Ch, 006h, 07Ch, 018h, 000h
	; % (37)
	db 000h, 0C6h, 0CCh, 018h, 030h, 066h, 0C6h, 000h
	; & (38)
	db 038h, 06Ch, 038h, 076h, 0DCh, 0CCh, 076h, 000h
	; ' (39)
	db 018h, 018h, 030h, 000h, 000h, 000h, 000h, 000h
	; ( (40)
	db 00Ch, 018h, 030h, 030h, 030h, 018h, 00Ch, 000h
	; ) (41)
	db 030h, 018h, 00Ch, 00Ch, 00Ch, 018h, 030h, 000h
	; * (42)
	db 000h, 066h, 03Ch, 0FFh, 03Ch, 066h, 000h, 000h
	; + (43)
	db 000h, 018h, 018h, 07Eh, 018h, 018h, 000h, 000h
	; , (44)
	db 000h, 000h, 000h, 000h, 000h, 018h, 018h, 030h
	; - (45)
	db 000h, 000h, 000h, 07Eh, 000h, 000h, 000h, 000h
	; . (46)
	db 000h, 000h, 000h, 000h, 000h, 018h, 018h, 000h
	; / (47)
	db 006h, 00Ch, 018h, 030h, 060h, 0C0h, 080h, 000h
	; 0 (48)
	db 07Ch, 0C6h, 0CEh, 0D6h, 0E6h, 0C6h, 07Ch, 000h
	; 1 (49)
	db 018h, 038h, 018h, 018h, 018h, 018h, 07Eh, 000h
	; 2 (50)
	db 07Ch, 0C6h, 006h, 01Ch, 030h, 066h, 0FEh, 000h
	; 3 (51)
	db 07Ch, 0C6h, 006h, 03Ch, 006h, 0C6h, 07Ch, 000h
	; 4 (52)
	db 01Ch, 03Ch, 06Ch, 0CCh, 0FEh, 00Ch, 01Eh, 000h
	; 5 (53)
	db 0FEh, 0C0h, 0C0h, 0FCh, 006h, 0C6h, 07Ch, 000h
	; 6 (54)
	db 038h, 060h, 0C0h, 0FCh, 0C6h, 0C6h, 07Ch, 000h
	; 7 (55)
	db 0FEh, 0C6h, 00Ch, 018h, 030h, 030h, 030h, 000h
	; 8 (56)
	db 07Ch, 0C6h, 0C6h, 07Ch, 0C6h, 0C6h, 07Ch, 000h
	; 9 (57)
	db 07Ch, 0C6h, 0C6h, 07Eh, 006h, 00Ch, 078h, 000h
	; : (58)
	db 000h, 018h, 018h, 000h, 000h, 018h, 018h, 000h
	; ; (59)
	db 000h, 018h, 018h, 000h, 000h, 018h, 018h, 030h
	; < (60)
	db 00Ch, 018h, 030h, 060h, 030h, 018h, 00Ch, 000h
	; = (61)
	db 000h, 000h, 07Eh, 000h, 000h, 07Eh, 000h, 000h
	; > (62)
	db 030h, 018h, 00Ch, 006h, 00Ch, 018h, 030h, 000h
	; ? (63)
	db 07Ch, 0C6h, 00Ch, 018h, 018h, 000h, 018h, 000h
	; @ (64)
	db 07Ch, 0C6h, 0DEh, 0DEh, 0DEh, 0C0h, 078h, 000h
	; A (65)
	db 038h, 06Ch, 0C6h, 0FEh, 0C6h, 0C6h, 0C6h, 000h
	; B (66)
	db 0FCh, 066h, 066h, 07Ch, 066h, 066h, 0FCh, 000h
	; C (67)
	db 03Ch, 066h, 0C0h, 0C0h, 0C0h, 066h, 03Ch, 000h
	; D (68)
	db 0F8h, 06Ch, 066h, 066h, 066h, 06Ch, 0F8h, 000h
	; E (69)
	db 0FEh, 062h, 068h, 078h, 068h, 062h, 0FEh, 000h
	; F (70)
	db 0FEh, 062h, 068h, 078h, 068h, 060h, 0F0h, 000h
	; G (71)
	db 03Ch, 066h, 0C0h, 0C0h, 0CEh, 066h, 03Ah, 000h
	; H (72)
	db 0C6h, 0C6h, 0C6h, 0FEh, 0C6h, 0C6h, 0C6h, 000h
	; I (73)
	db 03Ch, 018h, 018h, 018h, 018h, 018h, 03Ch, 000h
	; J (74)
	db 01Eh, 00Ch, 00Ch, 00Ch, 0CCh, 0CCh, 078h, 000h
	; K (75)
	db 0E6h, 066h, 06Ch, 078h, 06Ch, 066h, 0E6h, 000h
	; L (76)
	db 0F0h, 060h, 060h, 060h, 062h, 066h, 0FEh, 000h
	; M (77)
	db 0C6h, 0EEh, 0FEh, 0FEh, 0D6h, 0C6h, 0C6h, 000h
	; N (78)
	db 0C6h, 0E6h, 0F6h, 0DEh, 0CEh, 0C6h, 0C6h, 000h
	; O (79)
	db 07Ch, 0C6h, 0C6h, 0C6h, 0C6h, 0C6h, 07Ch, 000h
	; P (80)
	db 0FCh, 066h, 066h, 07Ch, 060h, 060h, 0F0h, 000h
	; Q (81)
	db 07Ch, 0C6h, 0C6h, 0C6h, 0D6h, 07Ch, 00Eh, 000h
	; R (82)
	db 0FCh, 066h, 066h, 07Ch, 06Ch, 066h, 0E6h, 000h
	; S (83)
	db 03Ch, 066h, 030h, 018h, 00Ch, 066h, 03Ch, 000h
	; T (84)
	db 07Eh, 05Ah, 018h, 018h, 018h, 018h, 03Ch, 000h
	; U (85)
	db 0C6h, 0C6h, 0C6h, 0C6h, 0C6h, 0C6h, 07Ch, 000h
	; V (86)
	db 0C6h, 0C6h, 0C6h, 0C6h, 06Ch, 038h, 010h, 000h
	; W (87)
	db 0C6h, 0C6h, 0D6h, 0FEh, 0FEh, 0EEh, 0C6h, 000h
	; X (88)
	db 0C6h, 06Ch, 038h, 038h, 06Ch, 0C6h, 0C6h, 000h
	; Y (89)
	db 066h, 066h, 066h, 03Ch, 018h, 018h, 03Ch, 000h
	; Z (90)
	db 0FEh, 0C6h, 08Ch, 018h, 032h, 066h, 0FEh, 000h
	; [ (91)
	db 03Ch, 030h, 030h, 030h, 030h, 030h, 03Ch, 000h
	; \ (92)
	db 0C0h, 060h, 030h, 018h, 00Ch, 006h, 002h, 000h
	; ] (93)
	db 03Ch, 00Ch, 00Ch, 00Ch, 00Ch, 00Ch, 03Ch, 000h
	; ^ (94)
	db 010h, 038h, 06Ch, 0C6h, 000h, 000h, 000h, 000h
	; _ (95)
	db 000h, 000h, 000h, 000h, 000h, 000h, 000h, 0FFh
	; ` (96)
	db 030h, 018h, 00Ch, 000h, 000h, 000h, 000h, 000h
	; a (97)
	db 000h, 000h, 078h, 00Ch, 07Ch, 0CCh, 076h, 000h
	; b (98)
	db 0E0h, 060h, 07Ch, 066h, 066h, 066h, 0DCh, 000h
	; c (99)
	db 000h, 000h, 07Ch, 0C6h, 0C0h, 0C6h, 07Ch, 000h
	; d (100)
	db 01Ch, 00Ch, 07Ch, 0CCh, 0CCh, 0CCh, 076h, 000h
	; e (101)
	db 000h, 000h, 07Ch, 0C6h, 0FEh, 0C0h, 07Ch, 000h
	; f (102)
	db 038h, 06Ch, 064h, 0F0h, 060h, 060h, 0F0h, 000h
	; g (103)
	db 000h, 000h, 076h, 0CCh, 0CCh, 07Ch, 00Ch, 0F8h
	; h (104)
	db 0E0h, 060h, 06Ch, 076h, 066h, 066h, 0E6h, 000h
	; i (105)
	db 018h, 000h, 038h, 018h, 018h, 018h, 03Ch, 000h
	; j (106)
	db 006h, 000h, 00Eh, 006h, 006h, 066h, 066h, 03Ch
	; k (107)
	db 0E0h, 060h, 066h, 06Ch, 078h, 06Ch, 0E6h, 000h
	; l (108)
	db 038h, 018h, 018h, 018h, 018h, 018h, 03Ch, 000h
	; m (109)
	db 000h, 000h, 0ECh, 0FEh, 0D6h, 0D6h, 0D6h, 000h
	; n (110)
	db 000h, 000h, 0DCh, 066h, 066h, 066h, 066h, 000h
	; o (111)
	db 000h, 000h, 07Ch, 0C6h, 0C6h, 0C6h, 07Ch, 000h
	; p (112)
	db 000h, 000h, 0DCh, 066h, 066h, 07Ch, 060h, 0F0h
	; q (113)
	db 000h, 000h, 076h, 0CCh, 0CCh, 07Ch, 00Ch, 01Eh
	; r (114)
	db 000h, 000h, 0DCh, 076h, 060h, 060h, 0F0h, 000h
	; s (115)
	db 000h, 000h, 07Eh, 0C0h, 07Ch, 006h, 0FCh, 000h
	; t (116)
	db 030h, 030h, 0FCh, 030h, 030h, 036h, 01Ch, 000h
	; u (117)
	db 000h, 000h, 0CCh, 0CCh, 0CCh, 0CCh, 076h, 000h
	; v (118)
	db 000h, 000h, 0C6h, 0C6h, 0C6h, 06Ch, 038h, 000h
	; w (119)
	db 000h, 000h, 0C6h, 0D6h, 0D6h, 0FEh, 06Ch, 000h
	; x (120)
	db 000h, 000h, 0C6h, 06Ch, 038h, 06Ch, 0C6h, 000h
	; y (121)
	db 000h, 000h, 0C6h, 0C6h, 0C6h, 07Eh, 006h, 0FCh
	; z (122)
	db 000h, 000h, 0FEh, 0CCh, 018h, 032h, 0FEh, 000h
	; { (123)
	db 00Eh, 018h, 018h, 070h, 018h, 018h, 00Eh, 000h
	; | (124)
	db 018h, 018h, 018h, 000h, 018h, 018h, 018h, 000h
	; } (125)
	db 070h, 018h, 018h, 00Eh, 018h, 018h, 070h, 000h
	; ~ (126)
	db 076h, 0DCh, 000h, 000h, 000h, 000h, 000h, 000h
	; DEL (127) - solid block
	db 0FFh, 0FFh, 0FFh, 0FFh, 0FFh, 0FFh, 0FFh, 0FFh

; =============================================================================
; Reset Handler Location (0xFFFEE0)
; =============================================================================
	org 0FFFEE0h

Reset_Entry:
	jp Reset_Handler

; =============================================================================
; Fill gap between reset entry and vector table
; =============================================================================
	org 0FFFEE4h

	rept 01Ch
	db 0FFh
	endm

; =============================================================================
; Interrupt Vector Table (0xFFFF00 - 0xFFFFFF)
; =============================================================================
	org 0FFFF00h

VECTOR_TABLE:
	dd 00FFFEE0h		; Vector 0: Reset
	dd Default_Handler	; Vector 1
	dd Default_Handler	; Vector 2
	dd Default_Handler	; Vector 3
	dd Default_Handler	; Vector 4
	dd Default_Handler	; Vector 5
	dd Default_Handler	; Vector 6
	dd Default_Handler	; Vector 7

	rept 56
	dd Default_Handler
	endm

; =============================================================================
; End of ROM
; =============================================================================
	end
