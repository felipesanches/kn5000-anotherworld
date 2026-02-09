; =============================================================================
; main.asm - Custom KN5000 Boot ROM: Hexdump Utility
; =============================================================================
; A minimal boot ROM for the Technics KN5000 that:
;   1. Initializes essential hardware (watchdog, memory, ports)
;   2. Initializes the VGA display controller
;   3. Displays a hex dump viewer with title, bordered frame, colored
;      address column, and data display of boot code
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
COLOR_CYAN		EQU 2		; Address text
COLOR_LIGHT_GRAY	EQU 3		; Borders/separator
COLOR_YELLOW		EQU 4		; Title text
COLOR_DARK_BLUE		EQU 8

; RAM variables (internal RAM, above Extended SFR region at 0x100-0x1FF)
TEXT_COLOR		EQU 000200h	; 1 byte: current drawing color
ADDR_BUF		EQU 000201h	; 3 bytes: address display value (little-endian)

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
	ret			; VGA_Setup has no ret (designed for inline use)

; =============================================================================
; Entry Point - Called after hardware reset                      [0xEF09C5]
; =============================================================================
Reset_Handler:
	; =========================================================================
	; Minimal hardware initialization (local, trimmed from original)
	; Initializes: watchdog, clock, ports, memory controller, DRAM
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

	; Set up additional palette colors (cyan, light gray, yellow)
	CALR Setup_Palette

	; Draw hexdump of boot code with UI
	CALR Draw_Hexdump

	; Turn screen on (sequencer clocking mode)
	VGA_SEQUENCER 01h, 001h

	; TODO: Re-enable serial port code after VGA troubleshooting
	; CALR Serial_Init
	; CALR Send_Serial_Message

	; Enter infinite loop
Main_Loop:						; [0xEF0B36]
	halt
	jr Main_Loop

; =============================================================================
; Default_Handler - Default interrupt handler for unused vectors [0xEF0B39]
; =============================================================================
Default_Handler:
	halt
	jr Default_Handler

; =============================================================================
; Clear_Screen - Fill screen with dark blue (color 8)            [0xEF0B3C]
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
; Draw_Hexdump - Display hex dump with title, border, and address column
; 8 bytes per line, 27 lines = 216 bytes of boot code
; Input: none
; =============================================================================
Draw_Hexdump:
	; --- Draw title (yellow, centered) ---
	ld A, COLOR_YELLOW
	ld (TEXT_COLOR), A
	LDA_XHL_IMM24 Str_Title
	LDA_XDE_IMM24 VIDEO_RAM_BASE
	add XDE, 4 * SCREEN_WIDTH + 72	; Y=4, X=72
	CALR Draw_String

	; --- Draw border ---
	CALR Draw_Border

	; --- Initialize address buffer with Reset_Handler address ---
	ld A, Reset_Handler & 0FFh
	ld (ADDR_BUF), A
	ld A, Reset_Handler >> 8 & 0FFh
	ld (ADDR_BUF + 1), A
	ld A, Reset_Handler >> 16 & 0FFh
	ld (ADDR_BUF + 2), A

	; --- Set up for data display ---
	LDA_XHL_IMM24 Reset_Handler	; Source: boot code in ROM
	LDA_XDE_IMM24 VIDEO_RAM_BASE
	add XDE, 17 * SCREEN_WIDTH + 36 ; Y=17, X=36 (inside border)

	ld C, 27			; 27 lines

.line_loop:
	push XDE			; Save line start position
	push XHL			; Save source pointer
	push BC				; Save counters

	; --- Draw address in light gray (3 bytes = 6 hex digits, tight) ---
	ld A, COLOR_LIGHT_GRAY
	ld (TEXT_COLOR), A

	; High byte of address (byte 2)
	ld A, (ADDR_BUF + 2)
	push XDE
	CALR Draw_Hex_Byte_Tight
	pop XDE
	add XDE, 16			; Advance past 2 chars

	; Middle byte of address (byte 1)
	ld A, (ADDR_BUF + 1)
	push XDE
	CALR Draw_Hex_Byte_Tight
	pop XDE
	add XDE, 16			; Advance past 2 chars

	; Low byte of address (byte 0)
	ld A, (ADDR_BUF)
	push XDE
	CALR Draw_Hex_Byte_Tight
	pop XDE
	add XDE, 16 + 8		; Advance past 2 chars + separator gap

	; --- Draw 8 data bytes in white ---
	ld A, COLOR_WHITE
	ld (TEXT_COLOR), A
	pop BC				; Restore counters
	pop XHL				; Restore source pointer
	ld B, 8				; 8 bytes per line

.byte_loop:
	push XHL
	push BC
	ld A, (XHL)			; Read byte from ROM
	CALR Draw_Hex_Byte		; Draw "XX " and advance XDE by 24
	pop BC
	pop XHL

	inc 1, XHL			; Next source byte
	dec 1, B
	or B, B
	jr NZ, .byte_loop

	; --- Increment address buffer by 8 ---
	ld A, (ADDR_BUF)
	add A, 8
	ld (ADDR_BUF), A
	ld A, (ADDR_BUF + 1)
	adc A, 0
	ld (ADDR_BUF + 1), A
	ld A, (ADDR_BUF + 2)
	adc A, 0
	ld (ADDR_BUF + 2), A

	; --- Move to next line ---
	pop XDE				; Restore line start
	add XDE, 8 * SCREEN_WIDTH	; Move down one character row (8 pixels)
	dec 1, C
	or C, C
	jr NZ, .line_loop

	ret

; =============================================================================
; Draw_Hex_Byte - Draw one byte as two hex digits plus space gap
; Input: A = byte value, XDE = screen position
; Output: XDE advanced by 24 pixels (3 char widths)
; =============================================================================
Draw_Hex_Byte:
	push WA				; Save original byte

	; High nibble
	srl 1, A
	srl 1, A
	srl 1, A
	srl 1, A
	CALR Nibble_To_Ascii
	push XDE
	CALR Draw_Char
	pop XDE
	add XDE, 8			; Advance one char width

	; Low nibble
	pop WA				; Restore original byte
	and A, 0Fh
	CALR Nibble_To_Ascii
	push XDE
	CALR Draw_Char
	pop XDE
	add XDE, 16			; Advance past char + space gap

	ret

; =============================================================================
; Draw_Hex_Byte_Tight - Draw one byte as two hex digits (no trailing space)
; Input: A = byte value, XDE = screen position
; Output: XDE advanced by 16 pixels (2 char widths)
; =============================================================================
Draw_Hex_Byte_Tight:
	push WA				; Save original byte

	; High nibble
	srl 1, A
	srl 1, A
	srl 1, A
	srl 1, A
	CALR Nibble_To_Ascii
	push XDE
	CALR Draw_Char
	pop XDE
	add XDE, 8			; Advance one char width

	; Low nibble
	pop WA				; Restore original byte
	and A, 0Fh
	CALR Nibble_To_Ascii
	push XDE
	CALR Draw_Char
	pop XDE
	add XDE, 8			; Advance one char width (no space gap)

	ret

; =============================================================================
; Setup_Palette - Program VGA DAC entries 2-4 for UI colors
; =============================================================================
Setup_Palette:
	; Start writing at palette index 2 (cyan)
	VGA_WRITE VGA_DAC_ADDR_WRITE, COLOR_CYAN

	; Cyan (R=0, G=0Fh, B=0Fh) - index 2
	VGA_WRITE VGA_DAC_DATA, 0
	VGA_WRITE VGA_DAC_DATA, 0Fh
	VGA_WRITE VGA_DAC_DATA, 0Fh

	; Light Gray (R=0Ah, G=0Ah, B=0Ah) - auto-increments to index 3
	VGA_WRITE VGA_DAC_DATA, 0Ah
	VGA_WRITE VGA_DAC_DATA, 0Ah
	VGA_WRITE VGA_DAC_DATA, 0Ah

	; Yellow (R=0Fh, G=0Fh, B=0) - auto-increments to index 4
	VGA_WRITE VGA_DAC_DATA, 0Fh
	VGA_WRITE VGA_DAC_DATA, 0Fh
	VGA_WRITE VGA_DAC_DATA, 0

	ret

; =============================================================================
; Draw_Border - Draw bordered frame with vertical separator
; Box: (35,16) to (284,233), separator at X=88
; =============================================================================
Draw_Border:
	ld A, COLOR_LIGHT_GRAY

	; Top horizontal line: (35, 16), length 250
	LDA_XDE_IMM24 VIDEO_RAM_BASE
	add XDE, 16 * SCREEN_WIDTH + 35
	ld BC, 250
	CALR Draw_Hline

	; Bottom horizontal line: (35, 233), length 250
	LDA_XDE_IMM24 VIDEO_RAM_BASE
	add XDE, 233 * SCREEN_WIDTH + 35
	ld BC, 250
	CALR Draw_Hline

	; Left vertical line: (35, 16), height 218
	LDA_XDE_IMM24 VIDEO_RAM_BASE
	add XDE, 16 * SCREEN_WIDTH + 35
	ld BC, 218
	CALR Draw_Vline

	; Right vertical line: (284, 16), height 218
	LDA_XDE_IMM24 VIDEO_RAM_BASE
	add XDE, 16 * SCREEN_WIDTH + 284
	ld BC, 218
	CALR Draw_Vline

	; Separator vertical line: (88, 16), height 218
	LDA_XDE_IMM24 VIDEO_RAM_BASE
	add XDE, 16 * SCREEN_WIDTH + 88
	ld BC, 218
	CALR Draw_Vline

	ret

; =============================================================================
; Draw_Hline - Draw horizontal line
; Input: XDE = start VRAM address, BC = length, A = color
; =============================================================================
Draw_Hline:
	ld (XDE), A
	inc 1, XDE
	dec 1, BC
	or BC, BC
	jr NZ, Draw_Hline
	ret

; =============================================================================
; Draw_Vline - Draw vertical line
; Input: XDE = start VRAM address, BC = height, A = color
; =============================================================================
Draw_Vline:
	ld (XDE), A
	add XDE, SCREEN_WIDTH
	dec 1, BC
	or BC, BC
	jr NZ, Draw_Vline
	ret

; =============================================================================
; Nibble_To_Ascii - Convert 0-15 to ASCII '0'-'9' or 'A'-'F'
; Input: A = nibble (0-15)
; Output: A = ASCII character
; =============================================================================
Nibble_To_Ascii:
	cp A, 10
	jr C, .digit
	add A, 'A' - 10
	ret
.digit:
	add A, '0'
	ret

; =============================================================================
; Draw_String - Draw null-terminated string at screen position   [0xEF0B67]
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
; Draw_Char - Draw a single 8x8 character                        [0xEF0B7E]
; Input: A = ASCII character, XDE = screen position
; =============================================================================
Draw_Char:
	; Calculate font data offset: (A - 32) * 8
	sub A, 32		; ASCII offset
	EXTZ_WA			; Zero-extend A to WA (clears W)
	EXTZ_XWA		; Zero-extend WA to XWA (clears upper 16 bits)

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

	; Draw pixel in current text color
	push WA
	ld A, (TEXT_COLOR)
	ld (XDE), A
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
; Serial_Init - Initialize SC0 for computer interface (38400)    [0xEF0BC1]
; =============================================================================
Serial_Init:
	ld (SC0MOD), SC0MOD_8N1
	ld (BR0CR), BR0CR_38400
	ld (SC0CR), 000h
	ret

; =============================================================================
; Send_Serial_Message - Send "It is working!" to serial port     [0xEF0BCB]
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
; Serial_Send_Byte - Send single byte via SC0                    [0xEF0BDD]
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
Str_Title:
	db "KN5000 hexdump utility", 0

Str_ItIsWorking:
	db "It is working!", 13, 10, 0

; =============================================================================
; Font Data
; =============================================================================
	include "font_8x8.asm"

; =============================================================================
; Reset Handler Location                                         [0xFFFEE0]
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
; Interrupt Vector Table                                         [0xFFFF00]
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
