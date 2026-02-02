; =============================================================================
; vga.inc - VGA/LCD Controller Definitions for KN5000
; =============================================================================
; The KN5000 uses an MN89304 LCD controller with VGA-compatible registers.
; I/O ports are memory-mapped at VGA_IO_BASE (0x170000).
; Video RAM is at VIDEO_RAM_BASE (0x1A0000), 320x240 @ 8bpp.
;
; Reference: ../kn5000-docs/display-subsystem.md
; =============================================================================

; === Base Addresses ===
VGA_IO_BASE		EQU 170000h	; LCD controller I/O base
VIDEO_RAM_BASE		EQU 1A0000h	; 512KB VRAM (only 76800 bytes used for 320x240)

; === Display Dimensions ===
SCREEN_WIDTH		EQU 320		; Pixels per row
SCREEN_HEIGHT		EQU 240		; Rows
BYTES_PER_LINE		EQU 320		; Bytes per scanline (8bpp)

; === VGA I/O Ports (offsets from VGA_IO_BASE) ===
VGA_ATTR_ADDR		EQU 3C0h	; Attribute Controller Address/Data
VGA_MISC_OUTPUT		EQU 3C2h	; Miscellaneous Output Register (write)
VGA_ENABLE		EQU 3C3h	; VGA Enable
VGA_SEQ_ADDR		EQU 3C4h	; Sequencer Address
VGA_SEQ_DATA		EQU 3C5h	; Sequencer Data
VGA_DAC_MASK		EQU 3C6h	; DAC Mask
VGA_DAC_ADDR_WRITE	EQU 3C8h	; DAC Write Address
VGA_DAC_DATA		EQU 3C9h	; DAC Data (R, G, B sequentially)
VGA_GC_ADDR		EQU 3CEh	; Graphics Controller Address
VGA_GC_DATA		EQU 3CFh	; Graphics Controller Data
VGA_CRTC_ADDR		EQU 3D4h	; CRTC Address
VGA_CRTC_DATA		EQU 3D5h	; CRTC Data
VGA_INPUT_STATUS	EQU 3DAh	; Input Status 1

; === CRTC Register Indices ===
CRTC_HORIZ_TOTAL	EQU 00h
CRTC_HORIZ_DISP_END	EQU 01h
CRTC_START_HORIZ_BLANK	EQU 02h
CRTC_END_HORIZ_BLANK	EQU 03h
CRTC_START_HORIZ_RETRACE EQU 04h
CRTC_END_HORIZ_RETRACE	EQU 05h
CRTC_VERT_TOTAL		EQU 06h
CRTC_OVERFLOW		EQU 07h
CRTC_PRESET_ROW_SCAN	EQU 08h
CRTC_MAX_SCAN_LINE	EQU 09h
CRTC_CURSOR_START	EQU 0Ah
CRTC_CURSOR_END		EQU 0Bh
CRTC_START_ADDR_HIGH	EQU 0Ch
CRTC_START_ADDR_LOW	EQU 0Dh
CRTC_CURSOR_LOC_HIGH	EQU 0Eh
CRTC_CURSOR_LOC_LOW	EQU 0Fh
CRTC_VERT_RETRACE_START	EQU 10h
CRTC_VERT_RETRACE_END	EQU 11h
CRTC_VERT_DISP_END	EQU 12h
CRTC_OFFSET		EQU 13h
CRTC_UNDERLINE_LOC	EQU 14h
CRTC_START_VERT_BLANK	EQU 15h
CRTC_END_VERT_BLANK	EQU 16h
CRTC_MODE_CONTROL	EQU 17h
CRTC_LINE_COMPARE	EQU 18h

; === Graphics Controller Register Indices ===
GC_SET_RESET		EQU 00h
GC_ENABLE_SET_RESET	EQU 01h
GC_COLOR_COMPARE	EQU 02h
GC_DATA_ROTATE		EQU 03h
GC_READ_MAP_SELECT	EQU 04h
GC_GRAPHICS_MODE	EQU 05h
GC_MISC_GRAPHICS	EQU 06h
GC_COLOR_DONT_CARE	EQU 07h
GC_BIT_MASK		EQU 08h

; === Sequencer Register Indices ===
SEQ_RESET		EQU 00h
SEQ_CLOCKING_MODE	EQU 01h
SEQ_MAP_MASK		EQU 02h
SEQ_CHAR_MAP_SELECT	EQU 03h
SEQ_MEMORY_MODE		EQU 04h

; === Attribute Controller Register Indices ===
ATTR_MODE_CONTROL	EQU 10h
ATTR_OVERSCAN_COLOR	EQU 11h
ATTR_COLOR_PLANE_ENABLE	EQU 12h
ATTR_HORIZ_PIXEL_PAN	EQU 13h
ATTR_COLOR_SELECT	EQU 14h

; === Color Palette Indices (8-bit mode) ===
COLOR_BLACK		EQU 0
COLOR_WHITE		EQU 1
COLOR_RED		EQU 2
COLOR_GREEN		EQU 3
COLOR_BLUE		EQU 4
COLOR_CYAN		EQU 5
COLOR_YELLOW		EQU 6
COLOR_MAGENTA		EQU 7
COLOR_DARK_BLUE		EQU 8
