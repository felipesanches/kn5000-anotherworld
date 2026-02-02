; =============================================================================
; vga.asm - VGA Display Driver for KN5000
; =============================================================================
; VGA/LCD controller routines for the MN89304 display controller.
; Provides initialization, palette setup, and text drawing functions.
;
; Public routines:
;   VGA_Init        - Initialize VGA controller
;   Clear_Screen    - Fill screen with background color
;   Draw_String     - Draw null-terminated string at position
;   Draw_Char       - Draw single 8x8 character
;
; Reference: ../kn5000-docs/display-subsystem.md
; =============================================================================

; =============================================================================
; VGA_Init - Initialize VGA/LCD controller
; =============================================================================
VGA_Init:
	; Enable VGA
	LDA_XWA_IMM24 VGA_IO_BASE
	add XWA, VGA_ENABLE
	ld (XWA), 001h

	; Set miscellaneous output register
	LDA_XWA_IMM24 VGA_IO_BASE
	add XWA, VGA_MISC_OUTPUT
	ld (XWA), 0E3h		; 25 MHz dot clock

	; Reset sequencer
	CALR VGA_Seq_Write_00_00	; Reset
	CALR VGA_Seq_Write_01_21	; Clocking mode (screen off during init)
	CALR VGA_Seq_Write_00_03	; Release reset
	CALR VGA_Seq_Write_02_0F	; Map mask (all planes)
	CALR VGA_Seq_Write_03_00	; Character map select
	CALR VGA_Seq_Write_04_06	; Memory mode

	; Graphics controller setup
	CALR VGA_GC_Write_00_00		; Set/Reset
	CALR VGA_GC_Write_01_00		; Enable Set/Reset
	CALR VGA_GC_Write_03_00		; Data Rotate
	CALR VGA_GC_Write_04_00		; Read Map Select
	CALR VGA_GC_Write_05_00		; Graphics Mode
	CALR VGA_GC_Write_06_01		; Misc Graphics
	CALR VGA_GC_Write_08_FF		; Bit Mask

	; CRTC timing configuration
	CALR VGA_CRTC_Write_11_00	; Unlock protected registers

	CALR VGA_CRTC_Write_00_65	; Horizontal Total
	CALR VGA_CRTC_Write_01_27	; Horizontal Display End (320/8-1 = 39 = 0x27)
	CALR VGA_CRTC_Write_06_F3	; Vertical Total
	CALR VGA_CRTC_Write_07_10	; Overflow
	CALR VGA_CRTC_Write_12_EF	; Vertical Display End (240-1 = 239 = 0xEF)
	CALR VGA_CRTC_Write_13_14	; Offset (320/2/8 = 20 = 0x14)
	CALR VGA_CRTC_Write_10_F2	; Vertical Retrace Start
	CALR VGA_CRTC_Write_11_80	; Vertical Retrace End + lock

	; Set start address to 0
	CALR VGA_CRTC_Write_0C_00	; Start Address High
	CALR VGA_CRTC_Write_0D_00	; Start Address Low

	; DAC setup - set palette mask
	LDA_XWA_IMM24 VGA_IO_BASE
	add XWA, VGA_DAC_MASK
	ld (XWA), 0FFh

	; Set up basic color palette
	CALR Setup_Palette

	; Turn screen on
	CALR VGA_Seq_Write_01_01	; Clocking mode (screen on)

	ret

; =============================================================================
; VGA Sequencer Write Helpers
; =============================================================================
VGA_Seq_Write_00_00:
	ld A, SEQ_RESET
	ld C, 000h
	jr VGA_Seq_Write
VGA_Seq_Write_01_21:
	ld A, SEQ_CLOCKING_MODE
	ld C, 021h
	jr VGA_Seq_Write
VGA_Seq_Write_00_03:
	ld A, SEQ_RESET
	ld C, 003h
	jr VGA_Seq_Write
VGA_Seq_Write_02_0F:
	ld A, SEQ_MAP_MASK
	ld C, 00Fh
	jr VGA_Seq_Write
VGA_Seq_Write_03_00:
	ld A, SEQ_CHAR_MAP_SELECT
	ld C, 000h
	jr VGA_Seq_Write
VGA_Seq_Write_04_06:
	ld A, SEQ_MEMORY_MODE
	ld C, 006h
	jr VGA_Seq_Write
VGA_Seq_Write_01_01:
	ld A, SEQ_CLOCKING_MODE
	ld C, 001h
	; Fall through

VGA_Seq_Write:
	; Write A to SEQ_ADDR, C to SEQ_DATA
	push XDE
	LDA_XDE_IMM24 VGA_IO_BASE
	add XDE, VGA_SEQ_ADDR
	ld (XDE), A
	inc 1, XDE
	ld (XDE), C
	pop XDE
	ret

; =============================================================================
; VGA Graphics Controller Write Helpers
; =============================================================================
VGA_GC_Write_00_00:
	ld A, GC_SET_RESET
	ld C, 000h
	jr VGA_GC_Write
VGA_GC_Write_01_00:
	ld A, GC_ENABLE_SET_RESET
	ld C, 000h
	jr VGA_GC_Write
VGA_GC_Write_03_00:
	ld A, GC_DATA_ROTATE
	ld C, 000h
	jr VGA_GC_Write
VGA_GC_Write_04_00:
	ld A, GC_READ_MAP_SELECT
	ld C, 000h
	jr VGA_GC_Write
VGA_GC_Write_05_00:
	ld A, GC_GRAPHICS_MODE
	ld C, 000h
	jr VGA_GC_Write
VGA_GC_Write_06_01:
	ld A, GC_MISC_GRAPHICS
	ld C, 001h
	jr VGA_GC_Write
VGA_GC_Write_08_FF:
	ld A, GC_BIT_MASK
	ld C, 0FFh
	; Fall through

VGA_GC_Write:
	; Write A to GC_ADDR, C to GC_DATA
	push XDE
	LDA_XDE_IMM24 VGA_IO_BASE
	add XDE, VGA_GC_ADDR
	ld (XDE), A
	inc 1, XDE
	ld (XDE), C
	pop XDE
	ret

; =============================================================================
; VGA CRTC Write Helpers
; =============================================================================
VGA_CRTC_Write_11_00:
	ld A, CRTC_VERT_RETRACE_END
	ld C, 000h
	jr VGA_CRTC_Write
VGA_CRTC_Write_00_65:
	ld A, CRTC_HORIZ_TOTAL
	ld C, 065h
	jr VGA_CRTC_Write
VGA_CRTC_Write_01_27:
	ld A, CRTC_HORIZ_DISP_END
	ld C, 027h
	jr VGA_CRTC_Write
VGA_CRTC_Write_06_F3:
	ld A, CRTC_VERT_TOTAL
	ld C, 0F3h
	jr VGA_CRTC_Write
VGA_CRTC_Write_07_10:
	ld A, CRTC_OVERFLOW
	ld C, 010h
	jr VGA_CRTC_Write
VGA_CRTC_Write_12_EF:
	ld A, CRTC_VERT_DISP_END
	ld C, 0EFh
	jr VGA_CRTC_Write
VGA_CRTC_Write_13_14:
	ld A, CRTC_OFFSET
	ld C, 014h
	jr VGA_CRTC_Write
VGA_CRTC_Write_10_F2:
	ld A, CRTC_VERT_RETRACE_START
	ld C, 0F2h
	jr VGA_CRTC_Write
VGA_CRTC_Write_11_80:
	ld A, CRTC_VERT_RETRACE_END
	ld C, 080h
	jr VGA_CRTC_Write
VGA_CRTC_Write_0C_00:
	ld A, CRTC_START_ADDR_HIGH
	ld C, 000h
	jr VGA_CRTC_Write
VGA_CRTC_Write_0D_00:
	ld A, CRTC_START_ADDR_LOW
	ld C, 000h
	; Fall through

VGA_CRTC_Write:
	; Write A to CRTC_ADDR, C to CRTC_DATA
	push XDE
	LDA_XDE_IMM24 VGA_IO_BASE
	add XDE, VGA_CRTC_ADDR
	ld (XDE), A
	inc 1, XDE
	ld (XDE), C
	pop XDE
	ret

; =============================================================================
; Setup_Palette - Initialize DAC color palette
; =============================================================================
Setup_Palette:
	; Set DAC write address to 0
	LDA_XWA_IMM24 VGA_IO_BASE
	add XWA, VGA_DAC_ADDR_WRITE
	ld (XWA), 000h

	; Get DAC data port address
	LDA_XDE_IMM24 VGA_IO_BASE
	add XDE, VGA_DAC_DATA

	; Color 0: Black (0, 0, 0)
	ld (XDE), 000h
	ld (XDE), 000h
	ld (XDE), 000h

	; Color 1: White (63, 63, 63) - 6-bit DAC values
	ld (XDE), 03Fh
	ld (XDE), 03Fh
	ld (XDE), 03Fh

	; Color 2: Red (63, 0, 0)
	ld (XDE), 03Fh
	ld (XDE), 000h
	ld (XDE), 000h

	; Color 3: Green (0, 63, 0)
	ld (XDE), 000h
	ld (XDE), 03Fh
	ld (XDE), 000h

	; Color 4: Blue (0, 0, 63)
	ld (XDE), 000h
	ld (XDE), 000h
	ld (XDE), 03Fh

	; Color 5: Cyan (0, 63, 63)
	ld (XDE), 000h
	ld (XDE), 03Fh
	ld (XDE), 03Fh

	; Color 6: Yellow (63, 63, 0)
	ld (XDE), 03Fh
	ld (XDE), 03Fh
	ld (XDE), 000h

	; Color 7: Magenta (63, 0, 63)
	ld (XDE), 03Fh
	ld (XDE), 000h
	ld (XDE), 03Fh

	; Color 8: Dark Blue (0, 0, 16) - background color
	ld (XDE), 000h
	ld (XDE), 000h
	ld (XDE), 010h

	ret

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
	jr NZ, .clear_loop

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
	jr NZ, .pixel_loop

	pop XHL
	pop XDE

	; Move to next row
	add XDE, SCREEN_WIDTH
	inc 1, XHL
	dec 1, C
	jr NZ, .row_loop

	ret

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
