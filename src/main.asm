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
; Reference Documentation:
;   ../kn5000-docs/memory-map.md
;   ../kn5000-docs/boot-sequence.md
;   ../kn5000-docs/display-subsystem.md
;   ../kn5000-docs/cpu-subsystem.md
; =============================================================================

	cpu 96c141		; TLCS-900/H target
	page 0
	maxmode on

; Include hardware definitions
	include "includes/sfr.inc"
	include "includes/vga.inc"
	include "includes/macros.inc"

; =============================================================================
; Memory Map Constants
; =============================================================================
STACK_TOP		EQU 001000h	; Stack in internal RAM
RAM_BASE		EQU 200000h	; External RAM start
INTER_CPU_LATCH		EQU 120000h	; Inter-CPU communication

; =============================================================================
; ROM Layout
; =============================================================================
; Fill the first part of ROM with 0xFF (unprogrammed flash)
; The actual code starts near the end where the reset vector points

	org 0E00000h		; Program ROM base address

; Fill with 0xFF until code section
	rept 0F0000h		; ~960KB of padding
	db 0FFh
	endm

; =============================================================================
; Code Section (starts at 0xEF0000)
; =============================================================================
	org 0EF0000h

; =============================================================================
; Entry Point - Called after hardware reset
; =============================================================================
Reset_Handler:
	; Disable watchdog immediately
	ld (WDMOD), WDMOD_DISABLE
	ld (WDCR), WDCR_DISABLE

	; Set up stack pointer
	LDA_XWA_IMM24 STACK_TOP
	ld XSP, XWA

	; Initialize hardware
	CALR Hardware_Init

	; Initialize VGA display
	CALR VGA_Init

	; Clear screen to dark blue
	CALR Clear_Screen

	; Draw "Hello World" message
	CALR Draw_Hello_World

	; Initialize serial port
	CALR Serial_Init

	; Send message to computer interface
	CALR Send_Serial_Message

	; Enter infinite loop
Main_Loop:
	halt
	jr Main_Loop

; =============================================================================
; Default_Handler - Default interrupt handler for unused vectors
; =============================================================================
Default_Handler:
	halt
	jr Default_Handler	; Loop forever

; =============================================================================
; Hardware_Init - Initialize essential hardware
; =============================================================================
Hardware_Init:
	; Clock configuration
	ld (CLKMOD), 004h

	; Configure I/O ports for address/data bus
	ld (P2FC), 0FFh		; Port 2 = data bus low
	ld (P3FC), 0FFh		; Port 3 = data bus high
	ld (P7), 0FFh		; Port 7 data
	ld (P7FC), 01Fh		; Port 7 function
	ld (P7CR), 000h		; Port 7 control

	; Address bus ports
	ld (PA), 0FEh
	ld (PAFC), 008h
	ld (PB), 0FFh
	ld (PBFC), 01Fh
	ld (PC), 0FFh
	ld (PCFC), 0FFh
	ld (PD), 0FFh
	ld (PDFC), 0FFh
	ld (PE), 0FFh
	ld (PEFC), 0FFh
	ld (PH), 0FFh
	ld (PHFC), 0FFh

	; Timer configuration (needed for serial baud rate)
	ld (T01MOD), 01Dh
	ld (T23MOD), 01Dh

	; Memory controller - Block chip select configuration
	ld (B0CSL), 011h
	ld (B0CSH), 080h
	ld (B1CSL), 033h
	ld (B1CSH), 081h
	ld (B2CSL), 011h
	ld (B2CSH), 0C2h
	ld (B3CSL), 022h
	ld (B3CSH), 08Ah
	ld (B4CSL), 011h
	ld (B4CSH), 082h
	ld (B5CSL), 022h
	ld (B5CSH), 081h

	; Memory start address registers
	ld (MSAR0), 01Eh
	ld (MSAR1), 010h
	ld (MSAR2), 0C0h
	ld (MSAR3), 000h
	ld (MSAR4), 080h
	ld (MSAR5), 000h

	; Memory address mask registers
	ld (MAMR0), 00Fh
	ld (MAMR1), 03Fh
	ld (MAMR2), 07Fh
	ld (MAMR3), 01Fh
	ld (MAMR4), 0FFh
	ld (MAMR5), 0FFh

	; DRAM initialization with timing delays
	ld BC, 0400h
;.dram_pause1:
;	dec 1, BC
;	jr NZ, .dram_pause1

	ld (DRAM1REF), 081h	; Enable DRAM refresh

	ld BC, 2000h
;.dram_pause2:
;	dec 1, BC
;	jr NZ, .dram_pause2

	ld (DRAM1REF), 071h
	ld (DRAM1CRL), 08Bh
	ld (DRAM1CRH), 058h
	res 4, (PMEMCR)

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
; Serial_Init - Initialize SC0 for computer interface (38400 baud)
; =============================================================================
Serial_Init:
	; Configure serial mode: 8N1, baud rate generator, RX enabled
	ld (SC0MOD), SC0MOD_8N1

	; Set baud rate to 38400
	ld (BR0CR), BR0CR_38400

	; Clear control register (no interrupts)
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
	; Timeout - skip send
	jr .send_done

.tx_ready:
	; Send byte
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
	db "It is working!", 13, 10, 0	; Include CR+LF

; =============================================================================
; Include VGA driver (display routines and font data)
; =============================================================================
	include "vga.asm"

; =============================================================================
; Reset Handler Location (0xFFFEE0)
; =============================================================================
; The vector table at 0xFFFF00 points here. This is a jump trampoline
; to the actual boot code.

	org 0FFFEE0h

Reset_Entry:
	jp Reset_Handler	; Jump to actual boot code at 0xEF0000

; =============================================================================
; Fill gap between reset entry and vector table
; =============================================================================
	org 0FFFEE4h

	; Padding from 0xFFFEE4 to 0xFFFEFF (28 bytes)
	rept 01Ch
	db 0FFh
	endm

; =============================================================================
; Interrupt Vector Table (0xFFFF00 - 0xFFFFFF)
; =============================================================================
; The CPU reads from this table on reset and interrupts.
; Each entry is a 32-bit address (little-endian).
;
; Vector 0 (at 0xFFFF00): Reset - CPU reads this on power-on
; Vectors 1-63: Interrupt handlers (we point them to a default handler)

	org 0FFFF00h

VECTOR_TABLE:
	; Vector 0: Reset - points to Reset_Entry at 0xFFFEE0
	dd 00FFFEE0h

	; Vectors 1-7: Point to default handler (halt)
	dd Default_Handler	; Vector 1
	dd Default_Handler	; Vector 2
	dd Default_Handler	; Vector 3
	dd Default_Handler	; Vector 4
	dd Default_Handler	; Vector 5
	dd Default_Handler	; Vector 6
	dd Default_Handler	; Vector 7

	; Vectors 8-63: Fill with default handler address
	; Each vector is 4 bytes, we need 56 more vectors (8-63)
	rept 56
	dd Default_Handler
	endm

; =============================================================================
; End of ROM
; =============================================================================
	end
