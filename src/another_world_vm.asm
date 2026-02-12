; (c) 2024 Felipe Correa da Silva Sanches <juca@members.fsf.org>
; Licensed under GPL version 2 or later.
;
; This is a port of the Another World VM (initially supporting only non-interactive
; playback of the game intro) to run from an extension board on a
; Technics SX-KN5000 musical keyboard.
;
; This program must replace the hd-ae5000_v2_01i.ic4 ROM of the extension board.
;
; This implementation is derived from my port of the Another World VM
; as a high-level emulation on MAME
;
; And that port was derived from Fabien Sanglard's AW-VM available at:
; https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter
;
; The assembler I am using is compiled from source-code downloaded from
; http://john.ccac.rwth-aachen.de:8000/as/index.html
;
; Game assets must be extracted from an original copy of the game
; using the scripts provided at:
; https://github.com/felipesanches/AnotherWorld_VMTools
;
; === EQU Constants (shared) ===
PC_OFFSET			EQU 0  ; 16 bits
REQUESTED_PC_OFFSET	EQU 2  ; 16 bits
INACTIVE_THREAD		EQU 0FFFFh
DELETE_THIS_THREAD	EQU 0FFFEh
NO_REQUEST 			EQU 0FFFFh
TICKS_PER_SLICE		EQU 250		; ~20ms at 12500 Hz tick rate (80 µs/tick)

CURRENT_STATE	EQU 0  ; boolean stored as a byte
REQUESTED_STATE	EQU 1  ; boolean stored as a byte

FROZEN	EQU 0
NOT_FROZEN EQU 1

; These off-screen video pages are stored in external RAM:
; MAINCPU: in DRAM at 0x020000-0x05FFFF
; EXTENSION: in extension board SRAM at 0x240000-0x27FFFF
	ifdef TARGET_MAINCPU
PAGE_BITMAP_0 EQU 020000h
PAGE_BITMAP_1 EQU 030000h
PAGE_BITMAP_2 EQU 040000h
PAGE_BITMAP_3 EQU 050000h
	endif
	ifdef TARGET_EXTENSION
PAGE_BITMAP_0 EQU 240000h
PAGE_BITMAP_1 EQU 250000h
PAGE_BITMAP_2 EQU 260000h
PAGE_BITMAP_3 EQU 270000h
	endif

; VM variable indices (used by the game engine)
VM_VARIABLE_RANDOM_SEED		EQU 03Ch
VM_VARIABLE_LAST_KEYCHAR	EQU 0DAh
VM_VARIABLE_HERO_POS_UP_DOWN	EQU 0E5h
VM_VARIABLE_HERO_ACTION		EQU 0FAh
VM_VARIABLE_HERO_POS_JUMP_DOWN	EQU 0FBh
VM_VARIABLE_HERO_POS_LEFT_RIGHT	EQU 0FCh
VM_VARIABLE_HERO_POS_MASK	EQU 0FDh
VM_VARIABLE_HERO_ACTION_POS_MASK EQU 0FEh
VM_VARIABLE_SCROLL_Y		EQU 0F9h

; Game part IDs (from reference: parts.h)
GAME_PART_FIRST			EQU 03E80h
GAME_PART_PROTECTION	EQU 03E80h	; Part 0: Copy protection
GAME_PART_INTRO			EQU 03E81h	; Part 1: Introduction cinematic
GAME_PART_WATER			EQU 03E82h	; Part 2: Water / lake
GAME_PART_JAIL			EQU 03E83h	; Part 3: Jail / prison
GAME_PART_CITADEL		EQU 03E84h	; Part 4: Citadel
GAME_PART_BATTLECHAR	EQU 03E85h	; Part 5: Battle cinematic
GAME_PART_ARENA			EQU 03E86h	; Part 6: Arena
GAME_PART_FINAL			EQU 03E87h	; Part 7: Final / ending
GAME_PART_PASSWORD1		EQU 03E88h	; Part 8: Password entry
GAME_PART_PASSWORD2		EQU 03E89h	; Part 9: Password entry (alt)
GAME_PART_LAST			EQU 03E89h
GAME_NUM_PARTS			EQU 10
NUM_MEM_LIST			EQU 091h

CALC_LINE_XMAX_AND_XMIN:
	; int16_t xmax = MAX(x1, x2);
	LD WA, (X1)
	CP WA, (X2)
	JP GT, XMAX_OK
	LD WA, (X2)
XMAX_OK:
	LD (LINE_XMAX), WA
	
	; int16_t xmin = MIN(x1, x2);
	LD WA, (X1)
	CP WA, (X2)
	JP LT, XMIN_OK
	LD WA, (X2)
XMIN_OK:
	LD (LINE_XMIN), WA
	RET

drawLineN:
	; Inputs:
	; C = color
	PUSH XIX
	PUSH XHL
	
	CALL CALC_LINE_XMAX_AND_XMIN

	; for (int16_t x=xmin; x<=xmax; x++)
	; 	m_curPagePtr1->pix(m_hliney, x) = color;
	LD XIX, (CUR_LINE)
	LD HL, (LINE_XMIN)
	EXTS XHL
	ADD XIX, XHL
	LD HL, (LINE_XMAX)
	SUB HL, (LINE_XMIN)
	INC HL				; inclusive range: xmax-xmin+1 pixels

drawLineN_loop:
	LDB (XIX), C
	INC XIX
	DJNZ HL, drawLineN_loop
	
	POP XHL
	POP XIX
	RET

drawLineP:
	; Copy pixels from PAGE_BITMAP_0 to curPagePtr1
	PUSH XIX
	PUSH XIY
	PUSH XHL

	CALL CALC_LINE_XMAX_AND_XMIN

	; Destination: CUR_LINE + LINE_XMIN (in curPagePtr1)
	LD XIX, (CUR_LINE)
	LD HL, (LINE_XMIN)
	EXTS XHL
	ADD XIX, XHL

	; Source: PAGE_BITMAP_0 + HLINEY*320 + LINE_XMIN
	LD XIY, PAGE_BITMAP_0
	LD XWA, 0
	LD WA, (HLINEY)
	LD DE, 320
	MUL XWA, DE
	ADD XIY, XWA
	LD XHL, 0
	LD HL, (LINE_XMIN)
	EXTS XHL
	ADD XIY, XHL

	; Loop: copy xmax-xmin+1 pixels
	LD HL, (LINE_XMAX)
	SUB HL, (LINE_XMIN)
	INC HL				; inclusive range: xmax-xmin+1 pixels

drawLineP_loop:
	LD C, (XIY)			; color = page_bitmap_0[y][x]
	LDB (XIX), C			; curPagePtr1[y][x] = color
	INC XIX
	INC XIY
	DJNZ HL, drawLineP_loop

	POP XHL
	POP XIY
	POP XIX
	RET

drawLineBlend:
	; Blend: read existing pixel, apply (color & 7) | 8
	PUSH XIX
	PUSH XHL

	CALL CALC_LINE_XMAX_AND_XMIN

	; curPagePtr1 scanline pointer
	LD XIX, (CUR_LINE)
	LD HL, (LINE_XMIN)
	EXTS XHL
	ADD XIX, XHL
	LD HL, (LINE_XMAX)
	SUB HL, (LINE_XMIN)
	INC HL				; inclusive range: xmax-xmin+1 pixels

drawLineBlend_loop:
	LD C, (XIX)			; color = curPagePtr1[y][x]
	ANDB C, 07h			; color &= 0x07
	ORB C, 08h			; color |= 0x08
	LDB (XIX), C			; curPagePtr1[y][x] = blended color
	INC XIX
	DJNZ HL, drawLineBlend_loop

	POP XHL
	POP XIX
	RET

drawPoint:
	PUSH XIX
	PUSH DE				; save x
	LD XWA, 0
	LD WA, HL			; XWA = y (zero-extended 32-bit)
	LD DE, 320
	MUL XWA, DE			; XWA = y * 320
	POP DE				; restore x
	EXTZ XDE			; zero-extend x to 32-bit
	ADD XWA, XDE			; XWA = y*320 + x
	LD XIX, (CUR_PAGE_PTR_1)
	ADD XIX, XWA
	LDB (XIX), C			; write 1 byte (color)
	POP XIX
	RET

text MACRO stringid, x, y, color
	LD WA, stringid
	LD DE, x
	LD HL, y
	LD B, color
	CALL DRAW_STRING
	ENDM


BREAK:
	; This is a temporary placeholder
	; while we still do not emulate
	; the VM thread execution

	LD A, 0FEh		; end-of-frame
	CALL UPDATE_DISPLAY
	CALL PAUSE
	RET


UPDATE_DISPLAY:
	; A: PageID
	CP A, 0FEh
	JP EQ, _UPDATE_DISPLAY

	CP A, 0FFh
	JP EQ, _UPDATE_DISPLAY_PAGEID_FF

_UPDATE_DISPLAY_PAGEID_NOT_FE_OR_FF:
	CALL GET_PAGE_PTR
	LD (CUR_PAGE_PTR_2), XWA
	JP _UPDATE_DISPLAY
	
_UPDATE_DISPLAY_PAGEID_FF:
	LD XIY, (CUR_PAGE_PTR_2)
	LD XWA, (CUR_PAGE_PTR_3)
	LD (CUR_PAGE_PTR_2), XWA
	LD (CUR_PAGE_PTR_3), XIY

_UPDATE_DISPLAY:
	LD XHL, (CUR_PAGE_PTR_2)
	LD XDE, 001a0000h + 20*320	; vga memory, skipping the first 20 lines because the image has 320x200 resolution and the screen has 320x240
	LD XBC, 320 * 200 / 2		; bitmap data length in 16-bit words (320x200 pixels)
	LDIRW
	RET


VIDEO_START:
	LD XIX, PAGE_BITMAP_2
	LD (CUR_PAGE_PTR_1), XIX
	LD (CUR_PAGE_PTR_2), XIX
	LD XIX, PAGE_BITMAP_1
	LD (CUR_PAGE_PTR_3), XIX
	; CUR_VIDEO_DATA is set by initForPart from the resource table
	RET

; initForPart: Reset all threads and prepare for a new game part
; Input: WA = partId
initForPart:
	LD (CURRENT_PART_ID), WA

	; Reset VM state
	LD XIX, VM_STACK
	LD (VM_STACK_POINTER), XIX

	; Reset all threads: inactive and unfrozen
	LD IX, 0
_initForPart_loop:
	PUSH IX
	SLA 2, IX
	EXTZ XIX
	ADD XIX, THREADS_DATA
	LDW (XIX + PC_OFFSET), INACTIVE_THREAD
	LDW (XIX + REQUESTED_PC_OFFSET), NO_REQUEST
	POP IX

	PUSH IX
	SLA 1, IX
	EXTZ XIX
	ADD XIX, VM_IS_CHANNEL_ACTIVE
	LD (XIX + CURRENT_STATE), NOT_FROZEN
	LD (XIX + REQUESTED_STATE), NOT_FROZEN
	POP IX

	INC IX
	CP IX, 64
	JP NE, _initForPart_loop

	; Start thread 0 at PC=0
	LDW (THREADS_DATA + PC_OFFSET), 0

	; Set variable 0xE4 = 0x14 (as per reference)
	LD A, 0E4h
	LD DE, 014h
	CALL _write_vm_var

	; Load resource pointers from PART_RESOURCE_TABLE
	; Table index = (partId - GAME_PART_FIRST) * 16 (4 DDs per entry)
	LD WA, (CURRENT_PART_ID)
	SUB WA, GAME_PART_FIRST
	; WA = part index (0-9)
	SLA 4, WA			; WA = index * 16
	EXTZ XWA
	ADD XWA, PART_RESOURCE_TABLE

	; XWA now points to: [palette_ptr, bytecode_ptr, video1_ptr, video2_ptr]
	LD XIX, XWA
	LD XWA, (XIX + 4)	; bytecode pointer
	LD (CUR_BYTECODE), XWA
	LD XWA, (XIX + 8)	; video1 pointer
	LD (CUR_VIDEO_DATA), XWA
	LD (CUR_VIDEO_1), XWA
	LD XWA, (XIX + 12)	; video2 pointer
	LD (CUR_VIDEO_2), XWA
	LD XWA, (XIX + 0)	; palette pointer
	LD (CUR_PALETTES), XWA
	RET


GAME_RESET:
	CALL VIDEO_START

	; Zero all VM variables (256 x 16-bit = 512 bytes)
	LD XDE, VM_VARIABLES
	LD WA, 0
	LD BC, 256
_zero_vars_loop:
	LD (XDE), WA
	INC 2, XDE
	DJNZ BC, _zero_vars_loop

	LDB (CURRENT_THREAD), 0
	LDW (VM_PC), 0
	LD XIX, VM_STACK
	LD (VM_STACK_POINTER), XIX

	; All threads are initially disabled and unfrozen
	LD IX, 0
_setup_threads__loop:

	PUSH IX
	SLA 2, IX
	EXTZ XIX
	ADD XIX, THREADS_DATA
	LDW (XIX + PC_OFFSET), INACTIVE_THREAD
	LDW (XIX + REQUESTED_PC_OFFSET), NO_REQUEST
	POP IX

	PUSH IX
	SLA 1, IX
	EXTZ XIX
	ADD XIX, VM_IS_CHANNEL_ACTIVE
	LD (XIX + CURRENT_STATE), NOT_FROZEN
	LD (XIX + REQUESTED_STATE), NOT_FROZEN
	POP IX

	INC IX
	CP IX, 64
	JP NE, _setup_threads__loop

	; Start thread 0 at PC=0 (matching initForPart behavior)
	LDW (THREADS_DATA + PC_OFFSET), 0

	; Initialize VM_VARIABLE_RANDOM_SEED with a fixed seed (no RTC available)
	LD A, VM_VARIABLE_RANDOM_SEED
	LD DE, 1234h			; Fixed seed value
	CALL _write_vm_var

	; VM_HACK_INIT_VAR_54_WITH_81: Required for Interplay logo display
	LD A, 054h
	LD DE, 0081h
	CALL _write_vm_var

	; Copy protection bypass: Set the variables that the protection
	; bytecode (resource 0x15) would set when the correct code wheel
	; answer is entered. Without these, protection checks kill all threads.
	; Water/Citadel check: var[0xBC] & 0x0010, var[0xF2] == 0x0FA0, var[0xDC] == 0x21
	; Password screen adds: var[0xC6] & 0x80
	LD A, 0BCh
	LD DE, 0010h
	CALL _write_vm_var
	LD A, 0C6h
	LD DE, 0080h
	CALL _write_vm_var
	LD A, 0F2h
	LD DE, 0FA0h
	CALL _write_vm_var
	LD A, 0DCh
	LD DE, 021h
	CALL _write_vm_var

	; Start directly on the intro (Part 1), skipping the code wheel
	; protection screen (Part 0). Part 1 bytecode at PC=0 does its own
	; initialization (video init, display loop, sound loads, etc.).
	LDW (REQUESTED_NEXT_PART), 0
	LD WA, GAME_PART_INTRO
	CALL initForPart

	RET

ENTRY:
	EI 0 ; Enable interrupts (INTT1 timer ISR)

	ifdef TARGET_MAINCPU
	CALL _cpanel_init		; Initialize control panel serial protocol
	endif

	CALL GAME_RESET

	; Initialize frame start time
	LD XWA, (SYSTEM_TICKS)
	LD (FRAME_START_TICKS), XWA

MAIN_LOOP:
	CALL EXECUTE_INSTRUCTION
	JP MAIN_LOOP

LONG_PAUSE:
	LD BC, 0
LONG_PAUSE_LOOP1:
	LD DE, 080h
LONG_PAUSE_LOOP2:
	DJNZ DE, LONG_PAUSE_LOOP2
	DJNZ BC, LONG_PAUSE_LOOP1
	RET

PAUSE:
	; Timer-based frame delay using VM variable 0xFF (pause slices).
	; Each slice = ~20ms. Polls SYSTEM_TICKS until elapsed >= target.
	; DJNZ fallback counter exits if timer ISR doesn't fire.

	; Read VM variable 0xFF (pause slices)
	LD A, 0FFh
	CALL _read_vm_var		; DE = var[0xFF]

	; Cap slices at 1-5 range
	LD A, E
	CP A, 0
	JP NE, _pause_nonzero
	LD A, 1
_pause_nonzero:
	CP A, 6
	JP ULT, _pause_capped
	LD A, 5
_pause_capped:
	; Compute target_ticks = slices * TICKS_PER_SLICE
	LD D, 0
	LD E, A					; DE = capped slices (1-5)
	LD WA, TICKS_PER_SLICE	; WA = 250
	MUL XWA, DE			; XWA = target_ticks (16-bit result in WA)
	LD XBC, XWA			; XBC = target_ticks (preserved across loop)

	; Check for overrun: elapsed already >= target?
	LD XWA, (SYSTEM_TICKS)
	LD XDE, (FRAME_START_TICKS)
	SUB XWA, XDE			; XWA = elapsed ticks
	CP XWA, XBC
	JP UGE, _pause_overrun

	; Poll timer with DJNZ fallback (65536 iterations ≈ 80ms safety net)
	LD HL, 0				; fallback counter
_pause_wait:
	LD XWA, (SYSTEM_TICKS)
	LD XDE, (FRAME_START_TICKS)
	SUB XWA, XDE			; XWA = elapsed
	CP XWA, XBC
	JP UGE, _pause_done_ok
	DJNZ HL, _pause_wait
	; Fallback expired — exit (timer may not be running)

_pause_done_ok:
	LD (LAST_FRAME_TICKS), WA
	LDB (FRAME_OVERRAN), 0
	RET

_pause_overrun:
	LD (LAST_FRAME_TICKS), WA
	LDB (FRAME_OVERRAN), 1
	RET

readAndDrawPolygon:
	; Inputs:
	; XIX: polygon data pointer
	; DE: x
	; HL: y
	; B: color (Black = FFh)
	; CUR_ZOOM: 16-bit zoom value (default = 0x40)
	PUSH DE
	PUSH HL
	PUSH BC
	
	LD A, (XIX)
	INC XIX
	CP A, 0C0H
	JP ULT, VALUE_IS_LT_C0

VALUE_IS_GTE_C0:

	CP B, 128
	JP ULT, COLOR_BIT_7_IS_OFF
	LD B, A
	ANDB B, 03Fh				;	if (color & 0x80) color = i & 0x3F;
COLOR_BIT_7_IS_OFF:
	
	;(&m_polygonData[m_data_offset], zoom);
	call readVertices

	; (color, pt)
	CALL fillPolygon

	JP end_of_readAndDrawPolygon

VALUE_IS_LT_C0: ; for now, here we simply assume value is == 2 without checking.
	;(CUR_ZOOM, pt)

	PUSH XIX
	PUSH BC ; B=color
	PUSH DE ; x
	PUSH HL ; y
	CALL readAndDrawPolygonHierarchy
	POP HL
	POP DE
	POP BC
	POP XIX

end_of_readAndDrawPolygon:
	POP BC
	POP HL
	POP DE
	RET

readVertices:
	PUSH XIX
	PUSH DE
	PUSH HL
	PUSH BC

	LD DE, (CUR_ZOOM)	; 16-bit zoom

	LD WA, 0
	LD A, (XIX)
	INC XIX
	MUL XWA, DE			; *= ZOOM
	SRL 2, XWA			; /= default_zoom (40h): unsigned shift by 6
	SRL 4, XWA
	LD (POLYGON_BBOX_W), WA

	LD WA, 0
	LD A, (XIX)
	INC XIX
	MUL XWA, DE			; *= ZOOM
	SRL 2, XWA			; /= default_zoom (40h): unsigned shift by 6
	SRL 4, XWA
	LD (POLYGON_BBOX_H), WA

	LD B, (XIX)
	INC XIX
	LD (POLYGON_NUM_POINTS), B

	LD XIY, POLYGON_POINTS

READ_THE_COORDINATES:

	LD WA, 0
	LD A, (XIX)
	INC XIX
	MUL XWA, DE			; *= ZOOM
	SRL 2, XWA			; /= default_zoom (40h): unsigned shift by 6
	SRL 4, XWA
	LD (XIY), WA
	INC 2, XIY

	LD WA, 0
	LD A, (XIX)
	INC XIX
	MUL XWA, DE			; *= ZOOM
	SRL 2, XWA			; /= default_zoom (40h): unsigned shift by 6
	SRL 4, XWA
	LD (XIY), WA
	INC 2, XIY

	DJNZ B, READ_THE_COORDINATES

	POP BC
	POP HL
	POP DE
	POP XIX	
	RET

fillPolygon:
	; DE: x
	; HL: y
	; B: color (Black = FFh)

	PUSH BC
	LD C, B
	LD B, 0

	;if (m_polygon.bbox_w == 0 && m_polygon.bbox_h == 1 && m_polygon.numPoints == 4)
	CPW (POLYGON_BBOX_W), 0
	JP NZ, NOT_A_POINT
	CPW (POLYGON_BBOX_H), 1
	JP NZ, NOT_A_POINT
	CP (POLYGON_NUM_POINTS), 4
	JP NZ, NOT_A_POINT
	
	;(color, pt.x, pt.y);
	CALL drawPoint
	JP end_of_fillPolygon
	
	NOT_A_POINT:

	PUSH IX
	; int16_t xmin = pt.x - m_polygon.bbox_w / 2;
	LD IX, (POLYGON_BBOX_W)
	SRA 1, IX
	LD (POLYGON_XMIN), DE
	SUB (POLYGON_XMIN), IX

	; int16_t xmax = pt.x + m_polygon.bbox_w / 2;
	LD (POLYGON_XMAX), DE
	ADD (POLYGON_XMAX), IX

	; int16_t ymin = pt.y - m_polygon.bbox_h / 2;
	LD IX, (POLYGON_BBOX_H)
	SRA 1, IX
	LD (POLYGON_YMIN), HL
	SUB (POLYGON_YMIN), IX

	; int16_t ymax = pt.y + m_polygon.bbox_h / 2;	
	LD (POLYGON_YMAX), HL
	ADD (POLYGON_YMAX), IX
	POP IX


	;if (xmin >= 320 || xmax < 0 || ymin >= 200 || ymax < 0)
	;	return;
	CPW (POLYGON_XMIN), 320
	JP GE, end_of_fillPolygon
	CPW (POLYGON_XMAX), 0
	JP LT, end_of_fillPolygon
	CPW (POLYGON_YMIN), 200
	JP GE, end_of_fillPolygon
	CPW (POLYGON_YMAX), 0
	JP LT, end_of_fillPolygon


	LD WA, (POLYGON_YMIN)
	LD (HLINEY), WA

	LD XIX, POLYGON_POINTS				; i = 0;
	LD XIY, POLYGON_POINTS
	LD XWA, 0
	LD A, (POLYGON_NUM_POINTS)
	DEC A
	SLA 2, XWA
	ADD XIY, XWA						; j = m_polygon.numPoints - 1;

	; x2 = m_polygon.points[i].x + xmin;
	LD WA, (XIX)
	ADD WA, (POLYGON_XMIN)
	LD (X2), WA

	; x1 = m_polygon.points[j].x + xmin;
	LD WA, (XIY)
	ADD WA, (POLYGON_XMIN)
	LD (X1), WA

	INC 4, XIX		; 	i++;
	DEC 4, XIY		; 	j--;


	CP C, 10h
	JP Z, BLEND
	JP UGT, LINE_P

	LD XHL, drawLineN	; 	drawFct = &another_world_vm_state::drawLineN;
	JP AFTER_SETTING_DRAW_CALLBACK

	LINE_P:
	LD XHL, drawLineP	; 	drawFct = &another_world_vm_state::drawLineP;
	JP AFTER_SETTING_DRAW_CALLBACK

	BLEND:
	LD XHL, drawLineBlend

AFTER_SETTING_DRAW_CALLBACK:

	; uint32_t cpt1 = ((uint32_t) x1) << 16;
	LD WA, (X1)
	EXTS XWA
	SLA 16, XWA
	LD (CPT1), XWA

	; uint32_t cpt2 = ((uint32_t) x2) << 16;
	LD WA, (X2)
	EXTS XWA
	SLA 16, XWA
	LD (CPT2), XWA

POLYGON_RASTER_LOOP:
	DEC 2, (POLYGON_NUM_POINTS)

	CP (POLYGON_NUM_POINTS), 0
	JP Z, end_of_fillPolygon		; 	if (m_polygon.numPoints == 0) break;


	; 	int32_t step1 = calcStep(m_polygon.points[j + 1], m_polygon.points[j], h);
	PUSH XHL ; SAVE DRAW_FUNC_PTR
	PUSH XIX
	PUSH XIY
	
	; pt1 = j+1 / pt2 = j
	LD XIX, XIY
	INC 4, XIX
	LD XHL, STEP1
	CALL calcStep

	POP XIY
	POP XIX

	; 	int32_t step2 = calcStep(m_polygon.points[i - 1], m_polygon.points[i], h);
	PUSH XIX
	PUSH XIY

	; pt1 = i-1 / pt2 = i
	LD XIY, XIX
	DEC 4, XIX
	LD XHL, STEP2
	CALL calcStep

	; CUR_LINE = CUR_PAGE_PTR_1 + HLINEY * 320 (signed multiply for negative HLINEY)
	LD WA, (HLINEY)
	EXTS XWA			; sign-extend HLINEY to 32 bits
	LD DE, 320
	MULS XWA, DE		; XWA = HLINEY * 320 (signed)
	LD XIX, (CUR_PAGE_PTR_1)
	ADD XIX, XWA
	LD (CUR_LINE), XIX

	POP XIY
	POP XIX
	POP XHL ; RESTORE DRAW_FUNC_PTR

	INC 4, XIX		; 	i++;
	DEC 4, XIY		; 	j--;

	LDW (CPT1_LOW), 07FFFh		; 	cpt1 = (cpt1 & 0xFFFF0000) | 0x7FFF;
	LDW (CPT2_LOW), 08000h		; 	cpt2 = (cpt2 & 0xFFFF0000) | 0x8000;

	CPW (POLYGON_H), 0
	JP Z, POLYGON_H_IS_ZERO
	
FOR_H_LOOP:			; for (; h != 0; --h)
	CPW (HLINEY), 0
	JP LT, AFTER_DRAWFUNC_CALL

	LD WA, (CPT1_HIGH)		; x1 = cpt1 >> 16;
	LD (X1), WA

	LD WA, (CPT2_HIGH)		; x2 = cpt2 >> 16;
	LD (X2), WA


	; if (x1 < 320 && x2 >= 0)
	CPW (X1), 320
	JP GE, AFTER_DRAWFUNC_CALL
	CPW (X2), 0
	JP LT, AFTER_DRAWFUNC_CALL

	;	if (x1 < 0) x1 = 0;
	CPW (X1), 0
	JP GE, X1_NOT_NEGATIVE	
	LDW (X1), 0
X1_NOT_NEGATIVE:

	;   if (x2 > 319) x2 = 319;
	CPW (X2), 319
	JP LE, X2_LESS_THAN_SCREEN_W
	LDW (X2), 319
X2_LESS_THAN_SCREEN_W:
	
	;(x1, x2, color);
	CALL (XHL) ; drawfunc

AFTER_DRAWFUNC_CALL:

	LD WA, (STEP1_LOW)
	ADD (CPT1_LOW), WA
	LD WA, (STEP1_HIGH)
	ADC (CPT1_HIGH), WA	; 	cpt1 += step1;

	LD WA, (STEP2_LOW)
	ADD (CPT2_LOW), WA
	LD WA, (STEP2_HIGH)
	ADC (CPT2_HIGH), WA	; 	cpt2 += step2;

	INCW (HLINEY)

	; Advance CUR_LINE by 320 unconditionally (even for skipped scanlines)
	ADDW (CUR_LINE_LOW), 320
	ADCW (CUR_LINE_HIGH), 0

	CPW (HLINEY), 199
	JP GT, end_of_fillPolygon	; if (m_hliney > 199) return; (exit polygon)

	DECW (POLYGON_H)
	JP NZ, FOR_H_LOOP

	JP POLYGON_RASTER_LOOP

POLYGON_H_IS_ZERO:
	LD WA, (STEP1_LOW)
	ADD (CPT1_LOW), WA
	LD WA, (STEP1_HIGH)
	ADC (CPT1_HIGH), WA	; 	cpt1 += step1;
	
	LD WA, (STEP2_LOW)
	ADD (CPT2_LOW), WA
	LD WA, (STEP2_HIGH)
	ADC (CPT2_HIGH), WA	; 	cpt2 += step2;

	JP POLYGON_RASTER_LOOP

end_of_fillPolygon:
	POP BC
	RET


calcStep:
	; Inputs:
	; XHL = ptr to STEP_1 or STEP_2
	; XIX = p1
	; XIY = p2

	PUSHW 4000h		; uint16_t v = 0x4000;

	LD WA, (XIY)
	LD (DX), WA		; dx = p2.x

	LD WA, (XIX)
	SUB (DX), WA		; dx -= p1.x;

	INC 2, XIX
	INC 2, XIY
	
	LD WA, (XIY)
	LD (POLYGON_H), WA		; dy = p2.y

	LD WA, (XIX)
	SUB (POLYGON_H), WA		; dy -= p1.y

	CPW (POLYGON_H), 0
	JP LE, POLYGON_H_IS_LE_ZERO  ; if (dy>0)
	
	LD WA, (XSP)
	EXTS XWA
	LD DE, (POLYGON_H)
	DIV XWA, DE
	LD (XSP), WA			; v = 0x4000/(POLYGON_H)

POLYGON_H_IS_LE_ZERO:
	
	LD WA, (DX)
	EXTS XWA

	LD DE, (XSP)		; v
	MULS XWA, DE
	SLA 2, XWA
	LD (XHL), XWA		; return dx * v * 4

	INC 2, XSP
	RET


readAndDrawPolygonHierarchy:
	LD DE, (CUR_ZOOM)	; 16-bit zoom
	;	pt.x -= m_polygonData[m_data_offset++] * zoom / DEFAULT_ZOOM;
	LD WA, 0
	LD A, (XIX)
	INC XIX
	LD HL, (XSP + 6)
	MUL XWA, DE			; PT.X *= ZOOM
	SRL 2, XWA			; PT.X /= default_zoom (40h): unsigned 32-bit shift by 6
	SRL 4, XWA
	SUB HL, WA
	LD (XSP + 6), HL

	;	pt.y -= m_polygonData[m_data_offset++] * zoom / DEFAULT_ZOOM;
	LD WA, 0
	LD A, (XIX)
	INC XIX
	LD HL, (XSP + 4)
	MUL XWA, DE			; PT.Y *= ZOOM
	SRL 2, XWA			; PT.Y /= default_zoom (40h): unsigned 32-bit shift by 6
	SRL 4, XWA
	SUB HL, WA
	LD (XSP + 4), HL

	ld B, 0
	LD C, (XIX)		; num_children - 1
	INC XIX
	INC BC			; BC = num_children

children_loop:
	LD WA, (XIX); offset 
	INC 2, XIX
	EX W, A
	PUSH WA
	PUSHW (XSP + 8); po.x = pt.x
	PUSHW (XSP + 8); po.y = pt.y

	; po.x += m_polygonData[m_data_offset++] * zoom / DEFAULT_ZOOM;
	LD WA, 0
	LD A, (XIX)
	INC XIX
	LD HL, (XSP + 2)
	MUL XWA, DE			; PO.X *= ZOOM
	SRL 2, XWA			; PO.X /= default_zoom (40h): unsigned 32-bit shift by 6
	SRL 4, XWA
	ADD HL, WA
	LD (XSP + 2), HL
	
	; po.y += m_polygonData[m_data_offset++] * zoom / DEFAULT_ZOOM;
	LD WA, 0
	LD A, (XIX)
	INC XIX
	LD HL, (XSP)
	MUL XWA, DE			; PO.Y *= ZOOM
	SRL 2, XWA			; PO.Y /= default_zoom (40h): unsigned 32-bit shift by 6
	SRL 4, XWA
	ADD HL, WA
	LD (XSP), HL

	PUSH DE			; save zoom
	LD DE, 0FFh				; uint16_t color = 0xFF;
	LD HL, (XSP + 6) ;offset
	AND HL, 8000h
	JP Z, OFFSET_BIT15_NOT_SET
	LD DE, 0
	LD E,(XIX)				; 	color = m_polygonData[m_data_offset++] & 0x7F;
	AND E, 7Fh
	INC 2, XIX				; 	m_data_offset++; //and waste a byte...
OFFSET_BIT15_NOT_SET:

	PUSH XIX			;	 uint16_t backup = m_data_offset;
	LD XIX, (CUR_VIDEO_DATA)
	LD WA, (XSP + 0Ah) ;offset
	SLA 1, WA		 ; m_data_offset = (offset & 0x7FFF) * 2;
	EXTZ XWA
	ADD XIX, XWA
	
	LD HL, DE
	; here L is the computed new color
	; and BC is the children loop counter

	; B needs color, DE needs x param
	; zoom is in CUR_ZOOM (memory)

	LD DE, (XSP + 4)	; restore zoom in DE for next loop iteration

	PUSH BC
	LD B, L		; color
	LD DE, (XSP + 0ah)		; PO.x
	LD HL, (XSP + 08h)		; PO.y
	; (color, CUR_ZOOM, po)
	CALL readAndDrawPolygon
	POP BC
	POP XIX				; m_data_offset = backup;
	POP DE		; restore zoom

	ADD XSP, 6 ; local vars offset, po.x, po.y (INC only supports 1,2,4,8)
	DJNZ BC, children_loop
	RET


LOAD_SCREEN:
; Input: XHL = pointer to 32000 bytes of 4bpp Amiga planar screen data
; Converts to 8bpp chunky and writes 64000 bytes to PAGE_BITMAP_0
; Planar format: 4 bitplanes x 8000 bytes (320x200 / 8 bits per byte)
; Each source byte produces 8 destination pixels.
; Clobbers: XWA, XBC, XDE, XHL; preserves XIX
	PUSH XIX

	LD (BMP_SRC_PTR), XHL		; save source base pointer
	LD XDE, PAGE_BITMAP_0		; destination: page 0 buffer
	LD IX, 8000					; outer loop: 8000 byte positions

_bmp_outer:
	; Load one byte from each of the 4 bitplanes
	LD XHL, (BMP_SRC_PTR)
	LD A, (XHL)					; plane 0 (bit 0 of pixel color)
	PUSH XHL
	ADD XHL, 8000
	LD B, (XHL)					; plane 1 (bit 1)
	ADD XHL, 8000
	LD C, (XHL)					; plane 2 (bit 2)
	ADD XHL, 8000
	LD W, (XHL)					; plane 3 (bit 3)
	POP XHL
	INC XHL
	LD (BMP_SRC_PTR), XHL		; advance source pointer

	; Convert 8 pixels from MSB to LSB
	; A=plane0, B=plane1, C=plane2, W=plane3
	LD H, 8						; pixel counter (8 pixels per byte)
_bmp_pixel:
	LD L, 0
	; Extract MSB from each plane (p3 first → bit 3 of pixel)
	SLA 1, W					; plane 3 MSB → carry
	RL L						; carry → L bit 0
	SLA 1, C					; plane 2 MSB → carry
	RL L						; carry → L bit 0, prev → bit 1
	SLA 1, B					; plane 1 MSB → carry
	RL L						; carry → L bit 0
	SLA 1, A					; plane 0 MSB → carry
	RL L						; L = (p3<<3)|(p2<<2)|(p1<<1)|p0
	LD (XDE), L
	INC XDE
	DJNZ H, _bmp_pixel

	DJNZ IX, _bmp_outer

	POP XIX
	RET

SETUP_PALETTE:
	; WA: palette index (0-63), already extracted by caller (opcode 0x0B does SRA 8)
	; XWA: zero-extended by caller (EXTZ XWA)
	; Palette format: 2 bytes per color, 0x0RGB (4 bits per channel)
	; Byte 0: 0000_RRRR (low nibble = red)
	; Byte 1: GGGG_BBBB (high nibble = green, low nibble = blue)

	; Compute byte offset: palette_index * 32
	SLA 1, WA			; * 2
	SLA 4, WA			; * 16 → total * 32 (each palette = 16 colors × 2 bytes)
	LD XHL, (CUR_PALETTES)
	ADD XHL, XWA		; XHL = palette data pointer

	; Set VGA DAC write index to 0
	; (Write_VGA_Register preserves XHL, XIX, XIY, BC)
	LDW WA, 3c8h
	LDW BC, 0
	CALR Write_VGA_Register

	PUSH XIX
	LD XIX, 16			; loop counter (XIX preserved by Write_VGA_Register)

PALETTE_LOOP:
	; red: low nibble of byte 0
	LD A, (XHL)
	AND A, 0Fh
	LD C, A				; MN89304 DAC is 4-bit (0-15), no scaling needed
	LDW WA, 3c9h
	CALR Write_VGA_Register
	INC XHL

	; green: high nibble of byte 1
	LD A, (XHL)
	SRL 4, A			; logical shift right to extract high nibble
	LD C, A
	LDW WA, 3c9h
	CALR Write_VGA_Register

	; blue: low nibble of byte 1
	LD A, (XHL)
	AND A, 0Fh
	LD C, A
	LDW WA, 3c9h
	CALR Write_VGA_Register
	INC XHL

	DEC 1, XIX
	CP IX, 0
	JP NE, PALETTE_LOOP
	POP XIX
	RET


DRAW_STRING:
; WA: stringId
; DE: x
; HL: y
; B: color

	DEC DE
	SLA 3, DE 	;	x = 8 * (x-1);
	LDW (STRING_X0), DE	;	uint16_t x0 = x;
	LD XIX, STRING_INDEX
	EXTS XWA
	ADD XIX, XWA
	ADD XIX, XWA
	LD IX, (XIX)
	EXTS XIX
	ADD XIX, STRING_DATA
	LD C, (XIX)
	INC XIX

DRAW_STRING_LOOP:
	CP C, 0
	RET Z		;	for (; *c != '\0'; c++)

	CP C, 10	;		if (*c == '\n')
	JP NE, NOT_A_LINE_BREAK

LINE_BREAK:
	INC 8, HL			; y+=8;
	LD DE, (STRING_X0)	; x=x0;
	LD C, (XIX)
	INC XIX
	JP DRAW_STRING_LOOP

NOT_A_LINE_BREAK:
	CALL DRAW_CHAR
	INC 8, DE		; x+=8
	LD C, (XIX)
	INC XIX
	JP DRAW_STRING_LOOP


DRAW_CHAR:
	; DE: x
	; HL: y
	; B: color
	; C: character

	LD WA, 0
	LD A, C
	SUB A, 020h
	EXTS XWA
	SLA 3, XWA
	LD XIY, BITMAP_FONT
	ADD XIY, XWA

	PUSH XIX
	PUSH XHL
	PUSH BC

	EXTS XDE
	EXTS XHL

	LD XIX, (CUR_PAGE_PTR_1)
	MUL XHL, 320
	ADD XIX, XHL
	ADD XIX, XDE

	LD WA, 8
DRAW_CHAR_J_LOOP:
	LD C, (XIY)
	INC XIY			; uint8_t row = font[(character - ' ') * 8 + j];

	LD QWA, 8
DRAW_CHAR_I_LOOP:
	SLA 1, C
	JP NC, DONT_PLOT_THIS_PIXEL
	LD (XIX), B
DONT_PLOT_THIS_PIXEL:
	INC XIX
	DJNZ QWA, DRAW_CHAR_I_LOOP

	DEC 8, XIX
	ADD XIX, 320
	DJNZ WA, DRAW_CHAR_J_LOOP

	POP BC
	POP XHL
	POP XIX
	RET


GET_PAGE_PTR:
	; A: pageId

	CP A, 0FFh
	JP NE, PAGEID_NOT_FF
	LD XWA, (CUR_PAGE_PTR_3)
	RET

PAGEID_NOT_FF:
	CP A, 0FEh
	JP NE, PAGEID_NOT_FE
	LD XWA, (CUR_PAGE_PTR_2)
	RET

PAGEID_NOT_FE:
	CP A, 0
	JP NE, _not_page0
	LD XWA, PAGE_BITMAP_0
	RET
_not_page0:
	CP A, 1
	JP NE, _not_page1
	LD XWA, PAGE_BITMAP_1
	RET
_not_page1:
	CP A, 2
	JP NE, _not_page2
	LD XWA, PAGE_BITMAP_2
	RET
_not_page2:
	CP A, 3
	JP NE, _not_page3
	LD XWA, PAGE_BITMAP_3
	RET
_not_page3:
	; Any other page ID defaults to page 0
	LD XWA, PAGE_BITMAP_0
	RET


; _read_vm_var: Read vm_variable[A] into DE
; Input: A = variable index (0-255)
; Output: DE = variable value (16-bit signed)
; Clobbers: XIY, XWA
_read_vm_var:
	LD W, 0
	SLA 1, WA
	EXTZ XWA
	LD XIY, VM_VARIABLES
	ADD XIY, XWA
	LD DE, (XIY)
	RET

; _write_vm_var: Write DE to vm_variable[A]
; Input: A = variable index (0-255), DE = value
; Clobbers: XIY, XWA
_write_vm_var:
	LD W, 0
	SLA 1, WA
	EXTZ XWA
	LD XIY, VM_VARIABLES
	ADD XIY, XWA
	LD (XIY), DE
	RET


	ifdef TARGET_MAINCPU
; _cpanel_send_byte: Send/receive one byte via SC1 synchronous I/O
; In sync mode, writing SC1BUF simultaneously sends and receives.
; Polls INTRX1 (RX complete) flag in INTES1 to know when the byte
; has been fully clocked in, then reads the received byte from SC1BUF.
; Uses AND instead of BIT (MAME has known flag bugs with DEC; BIT
; might be similarly affected). Includes timeout to prevent hangs.
; Input: A = byte to send
; Output: A = byte received
; Clobbers: A only (DE preserved via stack)
_cpanel_send_byte:
	LD (INTCLR), 022h		; Clear INTRX1 pending (bit 3 of INTES1)
	LD (SC1BUF), A			; Start 8-bit synchronous transfer
	PUSH DE
	LD DE, 0				; Timeout counter (65536 iterations ~57ms at 16MHz)
.wait:
	LD A, (INTES1)			; Read interrupt status
	AND A, 008h				; Test INTRX1 (RX complete) — bit 3
	JR NZ, .done			; Exit when set
	DJNZ DE, .wait			; Decrement timeout, loop if not expired
	; Timeout: serial transfer did not complete
	POP DE
	LD A, 0					; Return 0 on timeout
	RET
.done:
	POP DE
	LD A, (SC1BUF)			; Read received byte
	RET

; _cpanel_query_segment: Query a control panel button segment
; Sends 2-byte command, then 2 dummy bytes to clock in response.
; Input: B = command (0x20=left panel, 0xE0=right panel), C = segment number
; Output: A = button bitmap
; Clobbers: A only (B, C preserved)
_cpanel_query_segment:
	LD A, B					; Send command byte
	CALL _cpanel_send_byte
	LD A, C					; Send segment byte
	CALL _cpanel_send_byte
	LD A, 0FFh				; Send dummy (clock in header)
	CALL _cpanel_send_byte	; A = header (discard)
	LD A, 0FFh				; Send dummy (clock in bitmap)
	CALL _cpanel_send_byte	; A = button bitmap
	RET

; _cpanel_init: Initialize control panel serial protocol
; Sends the 5-command init sequence matching the original firmware.
; Each command is followed by a delay. The cpanel MCUs respond with
; sync packets; we consume them via the standard 4-byte exchange.
; Must be called once before any _cpanel_query_segment calls.
; Clobbers: A, B, C, DE
_cpanel_init:
	; Init command 1: 1F DA
	LD B, 01Fh
	LD C, 0DAh
	CALL _cpanel_query_segment
	CALL _cpanel_delay

	; Init command 2: 1F 1A
	LD B, 01Fh
	LD C, 01Ah
	CALL _cpanel_query_segment
	CALL _cpanel_delay

	; Init command 3: 1D 00
	LD B, 01Dh
	LD C, 000h
	CALL _cpanel_query_segment
	CALL _cpanel_delay

	; Init command 4: DD 03
	LD B, 0DDh
	LD C, 003h
	CALL _cpanel_query_segment
	CALL _cpanel_delay

	; Init command 5: 1E 80
	LD B, 01Eh
	LD C, 080h
	CALL _cpanel_query_segment
	CALL _cpanel_delay

	; Clear serial interrupt flags (original firmware uses INTCLR)
	LD (INTCLR), 023h		; Clear INTTX1 pending
	LD (INTCLR), 022h		; Clear INTRX1 pending
	RET

; _cpanel_delay: Inter-command delay for init sequence
; Matches the original firmware's DELAY_3000_LOOPS between init commands.
; Clobbers: DE
_cpanel_delay:
	PUSH DE
	LD DE, 3000h
.loop:
	DJNZ DE, .loop
	POP DE
	RET

	endif ; TARGET_MAINCPU

INPUT_UPDATE_PLAYER:
	ifdef TARGET_MAINCPU

	; Query CPR_SEG4 (right panel segment 4) for direction buttons
	; CPR_SEG4: bit1=UP(PART:RIGHT2), bit4=LEFT(CONDUCTOR:LEFT),
	;           bit5=DOWN(CONDUCTOR:RIGHT2), bit6=RIGHT(CONDUCTOR:RIGHT1)
	LD B, 0E0h				; Right panel command
	LD C, 004h				; Segment 4
	CALL _cpanel_query_segment
	LD H, A					; H = CPR_SEG4 bitmap

	; Query CPL_SEG4 (left panel segment 4) for action button
	; CPL_SEG4: bit3=ACTION(VARIATION 4)
	LD B, 020h				; Left panel command
	; C still = 004h
	CALL _cpanel_query_segment
	LD L, A					; L = CPL_SEG4 bitmap

	; Query CPL_SEG10 (left panel segment 10) for OTHER PARTS/TR button
	; CPL_SEG10: bit3=OTHER PARTS/TR
	; B still = 020h (left panel)
	LD C, 00Ah				; Segment 10
	CALL _cpanel_query_segment
	; A = CPL_SEG10 bitmap
	AND A, 008h				; bit 3 = OTHER PARTS/TR
	JR Z, _input_no_password
	LD WA, GAME_PART_PASSWORD1
	LD (REQUESTED_NEXT_PART), WA
_input_no_password:

	; Process button bitmaps into VM variables.
	; Follows reference input_updatePlayer() logic:
	;   lr = 0; if RIGHT: lr=1, m|=1; if LEFT: lr=-1, m|=2; write LEFT_RIGHT=lr
	;   ud = 0; if DOWN: ud=1, m|=4; if UP: ud=-1, m|=8; write JUMP_DOWN=ud
	;   write UP_DOWN = UP ? -1 : 0
	;   write POS_MASK = m
	;   button = 0; if ACTION: button=1, m|=0x80; write HERO_ACTION=button
	;   write ACTION_POS_MASK = m
	; _write_vm_var clobbers XWA/XIY only — H, L, C all preserved.
	; Uses AND (not BIT) for flag testing — MAME has known flag bugs with BIT.
	LD C, 0					; mask = 0

	; --- LEFT_RIGHT: compute in DE, then write once ---
	LD DE, 0				; lr = 0 (default: no movement)
	LD A, H
	AND A, 040h				; RIGHT = CONDUCTOR: RIGHT 1 (bit 6)
	JR Z, _input_no_right
	LD DE, 1				; lr = 1
	SET 0, C				; mask |= 1
_input_no_right:
	LD A, H
	AND A, 010h				; LEFT = CONDUCTOR: LEFT (bit 4)
	JR Z, _input_no_left
	LD DE, 0FFFFh			; lr = -1 (overrides RIGHT)
	SET 1, C				; mask |= 2
_input_no_left:
	LD A, VM_VARIABLE_HERO_POS_LEFT_RIGHT
	CALL _write_vm_var		; Always write lr (even if 0)

	; --- JUMP_DOWN: ud reflects both DOWN and UP (UP overrides) ---
	LD DE, 0				; ud = 0 (default: no movement)
	LD A, H
	AND A, 020h				; DOWN = CONDUCTOR: RIGHT 2 (bit 5)
	JR Z, _input_no_down
	LD DE, 1				; ud = 1
	SET 2, C				; mask |= 4
_input_no_down:
	LD A, H
	AND A, 002h				; UP = PART SELECT: RIGHT 2 (bit 1)
	JR Z, _input_no_up_jd
	LD DE, 0FFFFh			; ud = -1 (UP overrides DOWN)
	SET 3, C				; mask |= 8
_input_no_up_jd:
	LD A, VM_VARIABLE_HERO_POS_JUMP_DOWN
	CALL _write_vm_var		; Write ud

	; --- UP_DOWN: -1 if UP, 1 if DOWN, 0 if neither ---
	; Reference: if UP, force -1; else write ud (which is 1 for DOWN, 0 for neither)
	; Reuse ud already computed for JUMP_DOWN (DE still has it after _write_vm_var)
	; Recompute since _write_vm_var clobbers DE:
	LD DE, 0				; ud = 0
	LD A, H
	AND A, 020h				; DOWN = CONDUCTOR: RIGHT 2 (bit 5)
	JR Z, _input_no_down_ud
	LD DE, 1				; ud = 1
_input_no_down_ud:
	LD A, H
	AND A, 002h				; UP = PART SELECT: RIGHT 2 (bit 1)
	JR Z, _input_no_up
	LD DE, 0FFFFh			; ud = -1 (UP overrides DOWN)
_input_no_up:
	LD A, VM_VARIABLE_HERO_POS_UP_DOWN
	CALL _write_vm_var		; Write ud (-1/0/1)

	; --- POS_MASK ---
	LD D, 0
	LD E, C					; DE = mask
	LD A, VM_VARIABLE_HERO_POS_MASK
	CALL _write_vm_var

	; --- ACTION: 1 if pressed, 0 otherwise; set mask bit 7 ---
	LD DE, 0				; button = 0
	LD A, L
	AND A, 008h				; ACTION = VARIATION 4 (bit 3)
	JR Z, _input_no_action
	SET 7, C				; mask |= 0x80
	LD DE, 1				; button = 1
_input_no_action:
	LD A, VM_VARIABLE_HERO_ACTION
	CALL _write_vm_var

	; --- ACTION_POS_MASK ---
	LD D, 0
	LD E, C					; DE = mask (with bit 7 if action)
	LD A, VM_VARIABLE_HERO_ACTION_POS_MASK
	CALL _write_vm_var

	RET

	else ; TARGET_EXTENSION
	RET
	endif


CHECK_THREAD_REQUESTS:

	; Check if a part switch has been requested
	LD WA, (REQUESTED_NEXT_PART)
	CP WA, 0
	JP EQ, _no_part_switch

	; Validate part ID range before switching
	CP WA, GAME_PART_FIRST
	JP ULT, _invalid_part_switch
	CP WA, GAME_PART_LAST
	JP UGT, _invalid_part_switch

	; Part switch requested - call initForPart (WA = partId)
	CALL initForPart
_invalid_part_switch:
	LDW (REQUESTED_NEXT_PART), 0
_no_part_switch:

	LD A, 0
_check_thread_reqs__loop:

	; thread->state = thread->requested_state;
	; Applied unconditionally every frame (freeze/unfreeze persists
	; until explicitly changed by another resetThread call).
	; Reference: thread->state = thread->requested_state; (no clearing)
	PUSH WA
	SLA 1, WA
	EXTZ XWA
	ADD XWA, VM_IS_CHANNEL_ACTIVE
	LD E, (XWA + REQUESTED_STATE)
	LD (XWA + CURRENT_STATE), E
	POP WA

	PUSH WA
	SLA 2, WA
	EXTZ XWA
	ADD XWA, THREADS_DATA
	LD DE, (XWA + REQUESTED_PC_OFFSET)
	POP WA
	CP DE, NO_REQUEST
	JP EQ, _check_thread_reqs__next_loop

	PUSH WA
	SLA 2, WA
	EXTZ XWA
	ADD XWA, THREADS_DATA
	LD BC, (XWA + REQUESTED_PC_OFFSET)
	CP DE, DELETE_THIS_THREAD
	JP NE, _dont_delete_this_thread
	LD BC, INACTIVE_THREAD
_dont_delete_this_thread:
	LDW (XWA + PC_OFFSET), BC
	LDW (XWA + REQUESTED_PC_OFFSET), NO_REQUEST
	POP WA

_check_thread_reqs__next_loop:
	INC A
	CP A, 64
	JP NE, _check_thread_reqs__loop

_end_of__check_thread_reqs:
	RET

.
NEXT_THREAD:
	LD WA, 0
	LD A, (CURRENT_THREAD)

_next_thread__do_loop:
	INC A
	CP A, 64
	JP NE, _not_end_of_frame
	; == END OF FRAME ==
	LDB (CURRENT_THREAD), 0
	CALL INPUT_UPDATE_PLAYER		; Once per frame (matches reference HLE)
	CALL CHECK_THREAD_REQUESTS
	LD A, 0FEh
	CALL UPDATE_DISPLAY

	; Record frame start time for next frame
	LD XWA, (SYSTEM_TICKS)
	LD (FRAME_START_TICKS), XWA

	LD WA, 0			; Must clear W (clobbered by LD XWA above); thread scan uses W=0
_not_end_of_frame:

;	while(current->state == FROZEN || current->PC == INACTIVE_THREAD);
	PUSH WA
	SLA 1, WA
	EXTZ XWA
	ADD XWA, VM_IS_CHANNEL_ACTIVE
	LD E, (XWA + CURRENT_STATE)
	POP WA
	CP E, FROZEN
	JP EQ, _next_thread__do_loop

	PUSH WA
	SLA 2, WA
	EXTZ XWA
	ADD XWA, THREADS_DATA
	LD DE, (XWA + PC_OFFSET)
	POP WA
	CP DE, INACTIVE_THREAD
	JP EQ, _next_thread__do_loop

_exit_do_loop:
	LD (CURRENT_THREAD), A
	SLA 2, WA
	EXTZ XWA
	ADD XWA, THREADS_DATA
	LD DE, (XWA + PC_OFFSET) 	;	PC = current->PC;
	LD (VM_PC), DE
	RET


EXECUTE_INSTRUCTION:
	PUSH XIX
	PUSH XIY

	LD IX, (VM_PC)
	EXTZ XIX
	ADD XIX, (CUR_BYTECODE)

FETCH_OPCODE:
	LD A, (XIX)  ; opcode = fetch_byte();
	INC XIX

	BIT 7, A	; if (opcode & 0x80)
	JP Z, OPCODE_BIT_7_NOT_SET

	; ====  VIDEO instruction (0x80) ====
_OPCODE_0x80:
;		uint16_t offset = ((opcode << 8) | fetch_byte()) * 2;
	LD W, A
	LD A, (XIX)
	INC XIX
	PUSH WA				; save offset_raw = (opcode << 8) | low_byte

	; Read x from bytecode (XIX still points to bytecode stream)
	LD D, 0
	LD E, (XIX)			; x = fetch_byte()
	INC XIX
	PUSH DE				; save x

	; Read y from bytecode
	LD A, (XIX)			; y = fetch_byte()
	INC XIX
	LD H, 0
	LD L, A				; HL = y

	; Save bytecode position (past all 4 consumed bytes: opcode, offset_lo, x, y)
	PUSH HL				; save y
	LD XDE, XIX
	SUB XDE, (CUR_BYTECODE)
	LD (VM_PC), DE
	POP HL				; restore y

	; Restore x
	POP DE				; DE = x

	; Compute offset and set up video data pointer
	; Opcodes >= 0x80 always use CUR_VIDEO_1 (cinematic segment)
	; Reference: vid_opcd_0x80 calls setDataBuffer(CINEMATIC, offset)
	; Note: Fabien's "segVideo2" = cinematic data = our CUR_VIDEO_1 (naming inverted)
	POP WA				; WA = offset_raw
	SLA 1, WA			; offset *= 2 (uint16_t wraps, e.g. 0x883E*2 → 0x107C)
	EXTZ XWA
	LD XIX, (CUR_VIDEO_1)
	ADD XIX, XWA

;		if (y > 199)
;		{
;			x += (y - 199);
;			y = 199;
;		}
	CP HL, 199
	JP ULE, _0x80_y_ok	; if y <= 199, skip (normal case)
	; y > 199: adjust coordinates
	ADD DE, HL
	SUB DE, 199			; x += (y - 199)
	LD HL, 199			; y = 199
_0x80_y_ok:

	LDW (CUR_ZOOM), 040h	; default zoom
	LD B, 0FFh				; color = BLACK
	CALL readAndDrawPolygon

	JP _after_PC_update

OPCODE_BIT_7_NOT_SET:
	BIT 6, A	; if (opcode & 0x40)
	JP Z, OPCODE_BIT_6_NOT_SET

	; ====  VIDEO instruction (0x40) ====
_OPCODE_0x40:
	; A = opcode (bit 6 set), save for bit testing
	LD B, A

	; offset = fetch_word() * 2 (big-endian)
	LD WA, (XIX)
	EX W, A				; byte-swap
	SLA 1, WA			; offset *= 2
	INC 2, XIX
	PUSH WA				; save offset [stack: offset]

	; x = fetch_byte()
	LD A, (XIX)
	INC XIX
	LD D, 0
	LD E, A				; DE = x (byte value)

	; X addressing mode based on opcode bits 5,4
	BIT 5, B
	JP NZ, _0x40_x_bit5set

	; bit 5 clear: extended x
	BIT 4, B
	JP NZ, _0x40_x_var
	; x = (x << 8) | fetch_byte() - 16-bit immediate
	LD D, E
	LD E, (XIX)
	INC XIX
	JP _0x40_x_done

_0x40_x_var:
	; x = read_vm_variable(x) - A still has x
	CALL _read_vm_var	; DE = vm_var[x]
	JP _0x40_x_done

_0x40_x_bit5set:
	; bit 5 set
	BIT 4, B
	JP Z, _0x40_x_done
	; x += 0x100
	ADD DE, 100h

_0x40_x_done:
	; DE = x
	PUSH DE				; save x [stack: x, offset]

	; y = fetch_byte()
	LD A, (XIX)
	INC XIX
	LD H, 0
	LD L, A				; HL = y (byte value)

	; Y addressing mode based on opcode bits 3,2
	BIT 3, B
	JP NZ, _0x40_y_done

	BIT 2, B
	JP NZ, _0x40_y_var
	; y = (y << 8) | fetch_byte() - 16-bit immediate
	LD H, L
	LD L, (XIX)
	INC XIX
	JP _0x40_y_done

_0x40_y_var:
	; y = read_vm_variable(y) - A still has y
	CALL _read_vm_var	; DE = vm_var[y]
	LD HL, DE			; HL = y

_0x40_y_done:
	; HL = y
	PUSH HL				; save y [stack: y, x, offset]

	; Zoom mode based on opcode bits 1,0
	LDW (CUR_ZOOM), 040h		; default zoom (16-bit)
	LD A, B
	AND A, 3

	CP A, 0
	JP EQ, _0x40_zoom_done

	CP A, 1
	JP NE, _0x40_zoom_not_1
	; zoom = read_vm_variable(fetch_byte())
	LD A, (XIX)
	INC XIX
	CALL _read_vm_var	; DE = vm_var[A]
	LD (CUR_ZOOM), DE	; zoom = full 16-bit variable value
	JP _0x40_zoom_done

_0x40_zoom_not_1:
	CP A, 2
	JP NE, _0x40_zoom_case3
	; case 2: zoom = fetch_byte() (literal zoom value)
	LD WA, 0
	LD A, (XIX)
	INC XIX
	LD (CUR_ZOOM), WA	; zoom = byte, zero-extended to 16-bit
	JP _0x40_zoom_done

_0x40_zoom_case3:
	; case 3: m_useVideo2 = true, zoom = 0x40
	PUSH XWA
	LD XWA, (CUR_VIDEO_2)
	LD (CUR_VIDEO_DATA), XWA
	POP XWA

_0x40_zoom_done:
	; CUR_ZOOM = 16-bit zoom value

	; Save bytecode position (all variable-length bytes consumed)
	LD XDE, XIX
	SUB XDE, (CUR_BYTECODE)
	LD (VM_PC), DE

	; Restore parameters from stack
	POP HL				; HL = y
	POP DE				; DE = x
	POP WA				; WA = offset

	; Set up polygon data pointer
	EXTZ XWA
	LD XIX, (CUR_VIDEO_DATA)
	ADD XIX, XWA

	; B = color (0xFF = BLACK), zoom in CUR_ZOOM
	LD B, 0FFh

	; DE = x, HL = y, B = color, XIX = data pointer, CUR_ZOOM = zoom
	CALL readAndDrawPolygon

	; Reset video data pointer to default (VIDEO_1)
	PUSH XWA
	LD XWA, (CUR_VIDEO_1)
	LD (CUR_VIDEO_DATA), XWA
	POP XWA

	JP _after_PC_update

OPCODE_BIT_6_NOT_SET:


	; ====  MOV CONST instruction  ====
	CP A, 0
	JP NE, INSTRUCTION_IS_NOT_MOVCONST
	LD WA, 0
	LD A, (XIX)		; uint8_t variableId = fetch_byte();
	INC XIX
	; Calculate destination pointer first
	LD XIY, VM_VARIABLES
	SLA 1, WA
	EXTZ XWA
	ADD XIY, XWA
	; Now fetch the 16-bit value (big-endian bytecode)
	LD WA, (XIX)	; int16_t value = fetch_word();
	EX W, A			; byte-swap: bytecode is big-endian
	INC 2, XIX
	LD (XIY), WA	; write_vm_variable(variableId, value);
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_MOVCONST:


	; ====  MOV instruction  ====
	CP A, 1
	JP NE, INSTRUCTION_IS_NOT_MOV
	LD WA, 0
	LD A, (XIX)		; uint8_t dstVariableId = fetch_byte();
	INC XIX
	PUSH WA			; save dstVariableId
	LD WA, 0
	LD A, (XIX)		; uint8_t srcVariableId = fetch_byte();
	INC XIX
	LD XIY, VM_VARIABLES
	SLA 1, WA
	EXTZ XWA
	ADD XIY, XWA
	LD DE, (XIY)	; value = read_vm_variable(srcVariableId);
	; Recalculate XIY for destination variable
	POP WA			; restore dstVariableId
	LD XIY, VM_VARIABLES
	SLA 1, WA
	EXTZ XWA
	ADD XIY, XWA
	LD (XIY), DE	; write_vm_variable(dstVariableId, value);
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_MOV:


	; ====  ADD instruction  ====
	CP A, 2
	JP NE, INSTRUCTION_IS_NOT_ADD
	LD WA, 0
	LD A, (XIX)		; uint8_t dstVariableId = fetch_byte();
	INC XIX
	PUSH WA			; save dstVariableId
	LD WA, 0
	LD A, (XIX)		; uint8_t srcVariableId = fetch_byte();
	INC XIX
	LD XIY, VM_VARIABLES
	SLA 1, WA
	EXTZ XWA
	ADD XIY, XWA
	LD DE, (XIY)	; srcValue = read_vm_variable(srcVariableId);
	; Recalculate XIY for destination variable
	POP WA			; restore dstVariableId
	LD XIY, VM_VARIABLES
	SLA 1, WA
	EXTZ XWA
	ADD XIY, XWA
	ADDW (XIY), DE	; vm_variable[dst] += srcValue;
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_ADD:


	; ====  ADD CONST instruction  ====
	CP A, 3
	JP NE, INSTRUCTION_IS_NOT_ADD_CONST
	LD WA, 0
	LD A, (XIX)		; uint8_t variableId = fetch_byte();
	INC XIX
	; Calculate variable pointer first
	LD XIY, VM_VARIABLES
	SLA 1, WA
	EXTZ XWA
	ADD XIY, XWA
	; Fetch 16-bit constant (big-endian bytecode)
	LD WA, (XIX)	; int16_t value = fetch_word();
	EX W, A			; byte-swap: bytecode is big-endian
	INC 2, XIX
	ADDW (XIY), WA	; vm_variable += value;
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_ADD_CONST:


	; ====  CALL subroutine instruction  ====
	CP A, 4
	JP NE, INSTRUCTION_IS_NOT_CALL
	LD WA, (XIX)		; uint16_t address;
	EX W, A
	INC 2, XIX
	LD XIY, (VM_STACK_POINTER)
	LD DE, (VM_PC)
	ADD DE, 3			; return address = PC + 3 (INC only supports 1,2,4,8)
	LD (XIY), DE		; push current program counter to VM stack
	INC 2, XIY
	LD (VM_STACK_POINTER), XIY
	LD (VM_PC), WA
	JP _after_PC_update
INSTRUCTION_IS_NOT_CALL:


	; ====  RET instruction  ====
	CP A, 5
	JP NE, INSTRUCTION_IS_NOT_RET
	LD XIY, (VM_STACK_POINTER)
	DEC 2, XIY
	LD WA, (XIY)		; pop return address from VM stack
	LD (VM_STACK_POINTER), XIY
	LD (VM_PC), WA
	JP _after_PC_update
INSTRUCTION_IS_NOT_RET:


	; ====  PAUSE_THREAD instruction  ====
	CP A, 6
	JP NE, INSTRUCTION_IS_NOT_PAUSE_THREAD
	LD WA, 0
	LD A, (CURRENT_THREAD)
	SLA 2, WA
	EXTZ XWA
	ADD XWA, THREADS_DATA

	LD DE, (XWA + REQUESTED_PC_OFFSET)
	CP DE, NO_REQUEST
	JP NE, _pausethread_after_setting_request
	; When there's no other program counter request set
	; for this thread, we set the address of the
	; next instruction to resume execution
	; in the next VM frame.
	LD XDE, XIX
	SUB XDE, (CUR_BYTECODE)
	LD (XWA + REQUESTED_PC_OFFSET), DE
_pausethread_after_setting_request:
	CALL NEXT_THREAD
	JP _after_PC_update
INSTRUCTION_IS_NOT_PAUSE_THREAD:


	; ====  JUMP instruction  ====
	CP A, 7
	JP NE, INSTRUCTION_IS_NOT_JUMP
	LD WA, (XIX)	; word jump_address;
	EX W, A
	LD (VM_PC), WA
	JP _after_PC_update
INSTRUCTION_IS_NOT_JUMP:


	; ====  SET_VECT instruction  ====
	CP A, 8
	JP NE, INSTRUCTION_IS_NOT_SET_VECT
	LD B, 0
	LD C, (XIX)	; byte thread_id
	INC XIX
	AND C, 3Fh	; (6 bits = max 64 threads);
	LD WA, (XIX)	; word request;
	EX W, A
	INC 2, XIX
	LD XIY, THREADS_DATA
	SLA 2, BC
	EXTZ XBC
	ADD XIY, XBC
	LD (XIY + REQUESTED_PC_OFFSET), WA
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_SET_VECT:


	; ====  DJNZ instruction  ====
	CP A, 9
	JP NE, INSTRUCTION_IS_NOT_DJNZ
	LD WA, 0
	LD A, (XIX)	; byte variableId
	INC XIX
	; Calculate variable pointer first
	LD XIY, VM_VARIABLES
	SLA 1, WA
	EXTZ XWA
	ADD XIY, XWA
	; Fetch jump address (big-endian bytecode)
	LD WA, (XIX)	; word address
	EX W, A			; byte-swap: bytecode is big-endian
	LD BC, WA
	INC 2, XIX
	; Decrement variable and branch if non-zero
	LD DE, (XIY)
	DEC DE
	LD (XIY), DE	; write_vm_variable(variableId, --value);
	CP DE, 0
	JP Z, _end_of_EXECUTE_INSTRUCTION
	LD (VM_PC), BC
	JP _after_PC_update

INSTRUCTION_IS_NOT_DJNZ:


	; ====  COND_JUMP instruction  ====
	CP A, 0Ah
	JP NE, INSTRUCTION_IS_NOT_COND_JUMP

	LD B, (XIX)		; uint8_t subopcode = fetch_byte();
	INC XIX

	LD A, (XIX)		; uint8_t v = fetch_byte();
	INC XIX
	CALL _read_vm_var
	PUSH DE			; save b = read_vm_variable(v) on stack

	LD A, (XIX)		; uint8_t c = fetch_byte();
	INC XIX

	; Determine operand 'a' based on subopcode bits
	BIT 7, B
	JP Z, _condJmp_not_var
	; bit 7 set: a = read_vm_variable(c)
	CALL _read_vm_var	; A still has c; DE = vm_var[c]
	JP _condJmp_have_a
_condJmp_not_var:
	BIT 6, B
	JP Z, _condJmp_byte_literal
	; bit 6 set: a = (c << 8) | fetch_byte()  (16-bit immediate)
	LD D, A
	LD E, (XIX)		; fetch extra low byte
	INC XIX
	JP _condJmp_have_a
_condJmp_byte_literal:
	; neither bit set: a = c (zero-extended byte, per reference)
	LD E, A
	LD D, 0
_condJmp_have_a:
	; DE = a (RHS), (XSP) = b (LHS), B = subopcode
	POP HL			; HL = b (LHS)

	; Save comparison type (subopcode & 7) before clobbering B
	LD A, B
	AND A, 7
	PUSH WA			; save comparison type on stack

	; Fetch the jump target word (big-endian, always consumed)
	LD WA, (XIX)
	EX W, A			; byte-swap: bytecode is big-endian
	LD BC, WA		; BC = jump offset
	INC 2, XIX

	; Restore comparison type
	POP WA			; A = comparison type

	; Dispatch comparison: b (HL) vs a (DE)
	CP A, 0			; case 0: eq (b == a)
	JP NE, _condJmp_not_eq
	CP HL, DE
	JP EQ, _condJmp_taken
	JP _condJmp_not_taken
_condJmp_not_eq:
	CP A, 1			; case 1: ne (b != a)
	JP NE, _condJmp_not_ne
	CP HL, DE
	JP NE, _condJmp_taken
	JP _condJmp_not_taken
_condJmp_not_ne:
	CP A, 2			; case 2: gt (b > a)
	JP NE, _condJmp_not_gt
	CP HL, DE
	JP GT, _condJmp_taken
	JP _condJmp_not_taken
_condJmp_not_gt:
	CP A, 3			; case 3: ge (b >= a)
	JP NE, _condJmp_not_ge
	CP HL, DE
	JP GE, _condJmp_taken
	JP _condJmp_not_taken
_condJmp_not_ge:
	CP A, 4			; case 4: lt (b < a)
	JP NE, _condJmp_not_lt
	CP HL, DE
	JP LT, _condJmp_taken
	JP _condJmp_not_taken
_condJmp_not_lt:
	; case 5: le (b <= a) - default for any remaining
	CP HL, DE
	JP LE, _condJmp_taken

_condJmp_not_taken:
	JP _end_of_EXECUTE_INSTRUCTION

_condJmp_taken:
	LD (VM_PC), BC
	JP _after_PC_update

INSTRUCTION_IS_NOT_COND_JUMP:


	; ====  SET_PALETTE instruction  ====
	CP A, 0Bh
	JP NE, INSTRUCTION_IS_NOT_SET_PALETTE
	; Reference: m_currentPaletteId = fetchWord() >> 8
	; The palette index is the first byte of the big-endian word
	LD WA, 0
	LD A, (XIX)		; palette index = first byte of word
	INC 2, XIX		; skip 2-byte word
	EXTZ XWA
	CALL SETUP_PALETTE
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_SET_PALETTE:


	; ====  RESET_THREAD instruction  ====
	CP A, 0Ch
	JP NE, INSTRUCTION_IS_NOT_RESET_THREAD
	LD B, (XIX)		; uint8_t first = fetch_byte();
	INC XIX
	LD C, (XIX)		; uint8_t last = fetch_byte();
	INC XIX
	LD D, (XIX)		; uint8_t type = fetch_byte();
	INC XIX
	; Clamp last to [0, 63]
	AND C, 3Fh

	CP D, 0			; type 0: unfreeze threads (make active)
	JP NE, _resetThread_not_unfreeze
_resetThread_unfreeze_loop:
	LD WA, 0
	LD A, B
	SLA 1, WA
	EXTZ XWA
	ADD XWA, VM_IS_CHANNEL_ACTIVE
	LD (XWA + REQUESTED_STATE), NOT_FROZEN
	INC B
	CP B, C
	JP ULE, _resetThread_unfreeze_loop
	JP _end_of_EXECUTE_INSTRUCTION

_resetThread_not_unfreeze:
	CP D, 1			; type 1: freeze threads (make inactive)
	JP NE, _resetThread_not_freeze
_resetThread_freeze_loop:
	LD WA, 0
	LD A, B
	SLA 1, WA
	EXTZ XWA
	ADD XWA, VM_IS_CHANNEL_ACTIVE
	LD (XWA + REQUESTED_STATE), FROZEN
	INC B
	CP B, C
	JP ULE, _resetThread_freeze_loop
	JP _end_of_EXECUTE_INSTRUCTION

_resetThread_not_freeze:
	; type 2: delete threads (set requested_PC = DELETE_THIS_THREAD)
_resetThread_delete_loop:
	LD WA, 0
	LD A, B
	SLA 2, WA
	EXTZ XWA
	ADD XWA, THREADS_DATA
	LDW (XWA + REQUESTED_PC_OFFSET), DELETE_THIS_THREAD
	INC B
	CP B, C
	JP ULE, _resetThread_delete_loop
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_RESET_THREAD:


	; ====  SELECT_VIDEO_PAGE instruction  ====
	CP A, 0Dh
	JP NE, INSTRUCTION_IS_NOT_SELECT_VIDEO_PAGE
	LD A, (XIX)		; byte frameBufferId
	INC XIX
	CALL GET_PAGE_PTR
	LD (CUR_PAGE_PTR_1), XWA
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_SELECT_VIDEO_PAGE:


	; ====  FILL_VIDEO_PAGE instruction  ====
	CP A, 0Eh
	JP NE, INSTRUCTION_IS_NOT_FILL_VIDEO_PAGE
	LD A, (XIX)		; uint8_t pageId = fetch_byte();
	INC XIX
	LD B, (XIX)		; uint8_t color = fetch_byte();
	INC XIX
	CALL GET_PAGE_PTR
	LD XDE, XWA
	LD A, B
	SLA 8, WA
	LD A, B
	LD BC, 320 * 200 / 2
_fill_videopage_loop:
	LD (XDE), WA
	INC 2, XDE
	DJNZ BC, _fill_videopage_loop
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_FILL_VIDEO_PAGE:


	; ====  COPY_VIDEO_PAGE instruction  ====
	CP A, 0Fh
	JP NE, INSTRUCTION_IS_NOT_COPY_VIDEO_PAGE
	LD B, (XIX)		; byte srcPageId
	INC XIX
	LD C, (XIX)		; byte dstPageId
	INC XIX

	; Get destination page pointer
	LD A, C
	CALL GET_PAGE_PTR
	PUSH XWA		; save dst pointer on stack

	; Check for simple copy: srcPageId >= 0xFE
	CP B, 0FEh
	JP UGE, _copypage_simple

	; Check scroll mode: (srcPageId & 0xBF) has bit 7 set?
	LD A, B
	AND A, 0BFh
	BIT 7, A
	JP Z, _copypage_simple_masked

	; === Scroll mode ===
	; Actual source page = srcPageId & 3
	AND A, 3
	CALL GET_PAGE_PTR
	LD XDE, XWA		; XDE = src page base

	; Read vscroll from VM_VARIABLE_SCROLL_Y
	PUSH XDE		; save src base
	LD A, VM_VARIABLE_SCROLL_Y
	CALL _read_vm_var	; DE = vscroll (16-bit signed)
	LD HL, DE		; HL = vscroll
	POP XDE			; restore src base

	; Validate: -199 <= vscroll <= 199
	CP HL, -199
	JP LT, _copypage_scroll_skip
	CP HL, 199
	JP GT, _copypage_scroll_skip

	; Compute h, src_y0, dest_y0
	LD BC, 200		; h = screen height
	POP XWA			; XWA = dst base
	PUSH XWA		; re-push for later pop

	CP HL, 0
	JP GE, _copypage_vscroll_positive

	; vscroll < 0: h += vscroll, src_y0 = -vscroll
	ADD BC, HL		; h += vscroll (vscroll is negative)
	LD WA, 0
	SUB WA, HL		; WA = -vscroll = src_y0
	; Advance src pointer by src_y0 * 320
	PUSH BC
	LD BC, 320
	EXTZ XWA
	MUL XWA, BC
	ADD XDE, XWA	; src += src_y0 * 320
	POP BC
	JP _copypage_do_scroll

_copypage_vscroll_positive:
	; vscroll >= 0: h -= vscroll, dest_y0 = vscroll
	SUB BC, HL		; h -= vscroll
	LD WA, HL		; WA = vscroll = dest_y0
	; Advance dst pointer by dest_y0 * 320
	POP XHL			; XHL = dst base (from stack)
	PUSH BC
	LD BC, 320
	EXTZ XWA
	MUL XWA, BC
	ADD XHL, XWA	; dst += dest_y0 * 320
	POP BC
	PUSH XHL		; re-push adjusted dst

_copypage_do_scroll:
	; Copy h scanlines (BC = h, XDE = src, stack top = dst)
	POP XHL			; XHL = dst pointer
	; Convert h scanlines to dword count: h * 320 / 4 = h * 80
	LD WA, BC		; WA = h
	EXTZ XWA
	LD BC, 80
	MUL XWA, BC		; XWA = h * 80
	LD BC, WA		; BC = dword count
_copypage_scroll_loop:
	LD XWA, (XDE)
	LD (XHL), XWA
	INC 4, XDE
	INC 4, XHL
	DJNZ BC, _copypage_scroll_loop
	JP _end_of_EXECUTE_INSTRUCTION

_copypage_scroll_skip:
	POP XWA			; clean up stack (dst pointer)
	JP _end_of_EXECUTE_INSTRUCTION

_copypage_simple_masked:
	; srcPageId after masking still doesn't have bit 7 set - use masked value
	CALL GET_PAGE_PTR
	LD XDE, XWA
	JP _copypage_do_simple

_copypage_simple:
	; Simple copy: get src page from original srcPageId
	LD A, B
	CALL GET_PAGE_PTR
	LD XDE, XWA

_copypage_do_simple:
	POP XHL			; XHL = dst page pointer (from stack)
	LD BC, 320 * 200 / 4
_copy_videopage_loop:
	LD XWA, (XDE)
	LD (XHL), XWA
	INC 4, XDE
	INC 4, XHL
	DJNZ BC, _copy_videopage_loop
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_COPY_VIDEO_PAGE:


	; ====  BLIT_FRAMEBUFFER instruction  ====
	CP A, 10h
	JP NE, INSTRUCTION_IS_NOT_BLIT_FRAMEBUFFER
	LD A, (XIX)		; byte pageId
	INC XIX

	; VM_HACK_SWITCH_FROM_INTRO_TO_LAKE:
	; If currentPart == PROTECTION and vm_var[0x67] == 1, set vm_var[0xDC] = 0x21
	; (The protection bytecode sets var[0x67]=1 when correct answer is entered;
	; this hack then sets var[0xDC]=0x21 which subsequent parts check.)
	; Note: Since we skip protection and set var[0xDC] directly in GAME_RESET,
	; this hack is currently redundant, but kept for correctness.
	PUSH WA			; save pageId
	LD WA, (CURRENT_PART_ID)
	CP WA, GAME_PART_PROTECTION
	JP NE, _blit_no_hack
	LD A, 067h
	CALL _read_vm_var	; DE = vm_var[0x67]
	CP DE, 1
	JP NE, _blit_no_hack
	LD A, 0DCh
	LD DE, 021h
	CALL _write_vm_var
_blit_no_hack:
	POP WA			; restore pageId (A = pageId)
	CALL UPDATE_DISPLAY
	CALL PAUSE			; Frame timing delay

	; Overrun visual indicator: white pixel at top-right for overrun, black otherwise
	LD A, (FRAME_OVERRAN)
	CP A, 0
	JP EQ, _no_overrun_indicator
	LDB (001a0000h + 20*320 + 319), 0Fh	; color 15 (white in most palettes)
	JP _end_overrun_indicator
_no_overrun_indicator:
	LDB (001a0000h + 20*320 + 319), 00h	; color 0 (background)
_end_overrun_indicator:

	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_BLIT_FRAMEBUFFER:


	; ====  KILL_THREAD instruction  ====
	CP A, 11h
	JP NE, INSTRUCTION_IS_NOT_KILL_THREAD
	LD WA, 0
	LD A, (CURRENT_THREAD)
	SLA 2, WA
	EXTZ XWA
	ADD XWA, THREADS_DATA
	LDW (XWA + PC_OFFSET), INACTIVE_THREAD
	CALL NEXT_THREAD
	JP _after_PC_update
INSTRUCTION_IS_NOT_KILL_THREAD:


	; ====  DRAW_STRING instruction  ====
	CP A, 12h
	JP NE, INSTRUCTION_IS_NOT_DRAW_STRING
	; word stringId, byte x, byte y, byte color
	LD WA, (XIX)	; stringId (big-endian)
	EX W, A
	INC 2, XIX
	LD D, 0
	LD E, (XIX)		; x
	INC XIX
	LD H, 0
	LD L, (XIX)		; y
	INC XIX
	LD B, (XIX)		; color
	INC XIX
	PUSH XIX		; save bytecode position (DRAW_STRING clobbers XIX)
	CALL DRAW_STRING
	POP XIX			; restore bytecode position
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_DRAW_STRING:


	; ====  SUB instruction  ====
	CP A, 13h
	JP NE, INSTRUCTION_IS_NOT_SUB
	; vm_variable[dst] -= vm_variable[src]
	LD WA, 0
	LD A, (XIX)		; uint8_t dstVariableId = fetch_byte();
	INC XIX
	PUSH WA			; save dstVariableId
	LD A, (XIX)		; uint8_t srcVariableId = fetch_byte();
	INC XIX
	CALL _read_vm_var	; DE = vm_variable[src]
	POP WA			; restore dstVariableId
	LD XIY, VM_VARIABLES
	SLA 1, WA
	EXTZ XWA
	ADD XIY, XWA
	SUBW (XIY), DE	; vm_variable[dst] -= srcValue;
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_SUB:


	; ====  AND instruction  ====
	CP A, 14h
	JP NE, INSTRUCTION_IS_NOT_AND
	; vm_variable[id] &= value
	LD WA, 0
	LD A, (XIX)		; uint8_t variableId = fetch_byte();
	INC XIX
	LD XIY, VM_VARIABLES
	SLA 1, WA
	EXTZ XWA
	ADD XIY, XWA
	LD WA, (XIX)	; int16_t value = fetch_word();
	EX W, A			; byte-swap: bytecode is big-endian
	INC 2, XIX
	AND (XIY), WA	; vm_variable[id] &= value;
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_AND:


	; ====  OR instruction  ====
	CP A, 15h
	JP NE, INSTRUCTION_IS_NOT_OR
	; vm_variable[id] |= value
	LD WA, 0
	LD A, (XIX)		; uint8_t variableId = fetch_byte();
	INC XIX
	LD XIY, VM_VARIABLES
	SLA 1, WA
	EXTZ XWA
	ADD XIY, XWA
	LD WA, (XIX)	; int16_t value = fetch_word();
	EX W, A			; byte-swap: bytecode is big-endian
	INC 2, XIX
	OR (XIY), WA	; vm_variable[id] |= value;
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_OR:


	; ====  SHL instruction  ====
	CP A, 16h
	JP NE, INSTRUCTION_IS_NOT_SHL
	; vm_variable[id] <<= amount
	LD WA, 0
	LD A, (XIX)		; uint8_t variableId = fetch_byte();
	INC XIX
	LD XIY, VM_VARIABLES
	SLA 1, WA
	EXTZ XWA
	ADD XIY, XWA
	LD WA, (XIX)	; uint16_t shiftAmount = fetch_word();
	EX W, A			; byte-swap: bytecode is big-endian
	INC 2, XIX
	LD DE, (XIY)
	; Shift DE left by A positions (shift amount in low byte)
	CP A, 0
	JP Z, _shl_done
_shl_loop:
	SLA 1, DE
	DEC A
	JP NZ, _shl_loop
_shl_done:
	LD (XIY), DE
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_SHL:


	; ====  SHR instruction  ====
	CP A, 17h
	JP NE, INSTRUCTION_IS_NOT_SHR
	; vm_variable[id] >>= amount
	LD WA, 0
	LD A, (XIX)		; uint8_t variableId = fetch_byte();
	INC XIX
	LD XIY, VM_VARIABLES
	SLA 1, WA
	EXTZ XWA
	ADD XIY, XWA
	LD WA, (XIX)	; uint16_t shiftAmount = fetch_word();
	EX W, A			; byte-swap: bytecode is big-endian
	INC 2, XIX
	LD DE, (XIY)
	; Shift DE right by A positions (shift amount in low byte)
	CP A, 0
	JP Z, _shr_done
_shr_loop:
	SRA 1, DE
	DEC A
	JP NZ, _shr_loop
_shr_done:
	LD (XIY), DE
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_SHR:


	; ====  PLAY_SOUND instruction  ====
	CP A, 18h
	JP NE, INSTRUCTION_IS_NOT_PLAY_SOUND
	; Implement-me!
	; Note: We currently do not understand the Technics KN5000 sound hardware.
	ADD XIX, 5		; word resourceId; byte freq; byte vol; byte channel (INC only supports 1,2,4,8)
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_PLAY_SOUND:


	; ====  LOAD instruction  ====
	CP A, 19h
	JP NE, INSTRUCTION_IS_NOT_LOAD
	LD WA, (XIX)	; uint16_t resourceId = fetch_word()
	EX W, A			; byte-swap: bytecode is big-endian
	INC 2, XIX

	; resourceId == 0: stop sound (no-op, we don't have sound)
	CP WA, 0
	JP EQ, _end_of_EXECUTE_INSTRUCTION

	; resourceId > 0x91: part switch request
	CP WA, NUM_MEM_LIST
	JP ULE, _load_check_screen
	LD (REQUESTED_NEXT_PART), WA
	JP _end_of_EXECUTE_INSTRUCTION

_load_check_screen:
	; Check if resourceId matches a known screen bitmap resource.
	; Screen resources serve dual purpose:
	;   1. 4bpp planar bitmap copied to PAGE_BITMAP_0 (for direct display)
	;   2. Raw data replaces CUR_VIDEO_1 (cinematic segment, used by VIDEO 0x80)
	; Reference: aw_hle.cpp screen_resource_indexes[] =
	;   {0x12,0x13,0x43,0x44,0x45,0x46,0x47,0x48,0x49,0x53,0x90,0x91}
	CP WA, 012h
	JP NE, _load_not_0x12
	LD XHL, SCREEN_BITMAP_0x12
	JP _load_screen_common
_load_not_0x12:
	CP WA, 013h
	JP NE, _load_not_0x13
	LD XHL, SCREEN_BITMAP_0x13
	JP _load_screen_common
_load_not_0x13:
	CP WA, 043h
	JP NE, _load_not_0x43
	LD XHL, SCREEN_BITMAP_0x43
	JP _load_screen_common
_load_not_0x43:
	CP WA, 044h
	JP NE, _load_not_0x44
	LD XHL, SCREEN_BITMAP_0x44
	JP _load_screen_common
_load_not_0x44:
	CP WA, 045h
	JP NE, _load_not_0x45
	LD XHL, SCREEN_BITMAP_0x45
	JP _load_screen_common
_load_not_0x45:
	CP WA, 046h
	JP NE, _load_not_0x46
	LD XHL, SCREEN_BITMAP_0x46
	JP _load_screen_common
_load_not_0x46:
	CP WA, 047h
	JP NE, _load_not_0x47
	LD XHL, SCREEN_BITMAP_0x47
	JP _load_screen_common
_load_not_0x47:
	CP WA, 048h
	JP NE, _load_not_0x48
	LD XHL, SCREEN_BITMAP_0x48
	JP _load_screen_common
_load_not_0x48:
	CP WA, 049h
	JP NE, _load_not_0x49
	LD XHL, SCREEN_BITMAP_0x49
	JP _load_screen_common
_load_not_0x49:
	CP WA, 053h
	JP NE, _load_not_0x53
	LD XHL, SCREEN_BITMAP_0x53
	JP _load_screen_common
_load_not_0x53:
	CP WA, 090h
	JP NE, _load_not_0x90
	LD XHL, SCREEN_BITMAP_0x90
	JP _load_screen_common
_load_not_0x90:
	CP WA, 091h
	JP NE, _load_unknown
	LD XHL, SCREEN_BITMAP_0x91
	JP _load_screen_common
_load_unknown:
	; Unknown resource - ignore
	JP _end_of_EXECUTE_INSTRUCTION

_load_screen_common:
	; XHL = pointer to 32000-byte screen resource data
	; 1. Set CUR_VIDEO_1 so VIDEO 0x80 opcodes can read polygon data from it
	;    (screen bitmaps replace the cinematic segment; Fabien's "segVideo2")
	LD (CUR_VIDEO_1), XHL
	LD (CUR_VIDEO_DATA), XHL
	; 2. Convert 4bpp planar to 8bpp chunky and copy to PAGE_BITMAP_0
	CALL LOAD_SCREEN
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_LOAD:


	; ====  PLAY_MUSIC instruction  ====
	CP A, 1Ah
	JP NE, INSTRUCTION_IS_NOT_PLAY_MUSIC
	; Implement-me!
	; Note: We currently do not understand the Technics KN5000 sound hardware.
	ADD XIX, 5		; word resNum; word delay; byte pos (INC only supports 1,2,4,8)
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_PLAY_MUSIC:

		
_end_of_EXECUTE_INSTRUCTION:
	SUB XIX, (CUR_BYTECODE)
	LD (VM_PC), IX
_after_PC_update:
	POP XIY
	POP XIX
	RET


BITMAP_FONT:
	binclude "hardcoded_data/anotherworld_chargen.rom"

STRING_INDEX:
	binclude "hardcoded_data/str_index.rom"

STRING_DATA:
	binclude "hardcoded_data/str_data.rom"

; =============================================================================
; Game Resources — Part data (palette, bytecode, video1, video2)
; =============================================================================
; Each part has up to 4 resources. Video2=0x11 is shared across gameplay parts.
; Resources are extracted from the original game by tools/extract_resources.py.
;
; Part 0: Protection
PART0_PALETTES:	binclude "resources/resource-0x14.bin"
PART0_BYTECODE:	binclude "resources/resource-0x15.bin"
PART0_VIDEO_1:	binclude "resources/resource-0x16.bin"

; Part 1: Intro
PART1_PALETTES:	binclude "resources/resource-0x17.bin"
PART1_BYTECODE:	binclude "resources/resource-0x18.bin"
PART1_VIDEO_1:	binclude "resources/resource-0x19.bin"

; Part 2: Water
PART2_PALETTES:	binclude "resources/resource-0x1a.bin"
PART2_BYTECODE:	binclude "resources/resource-0x1b.bin"
PART2_VIDEO_1:	binclude "resources/resource-0x1c.bin"

; Part 3: Jail
PART3_PALETTES:	binclude "resources/resource-0x1d.bin"
PART3_BYTECODE:	binclude "resources/resource-0x1e.bin"
PART3_VIDEO_1:	binclude "resources/resource-0x1f.bin"

; Part 4: Citadel
PART4_PALETTES:	binclude "resources/resource-0x20.bin"
PART4_BYTECODE:	binclude "resources/resource-0x21.bin"
PART4_VIDEO_1:	binclude "resources/resource-0x22.bin"

; Part 5: Battlechar
PART5_PALETTES:	binclude "resources/resource-0x23.bin"
PART5_BYTECODE:	binclude "resources/resource-0x24.bin"
PART5_VIDEO_1:	binclude "resources/resource-0x25.bin"

; Part 6: Arena
PART6_PALETTES:	binclude "resources/resource-0x26.bin"
PART6_BYTECODE:	binclude "resources/resource-0x27.bin"
PART6_VIDEO_1:	binclude "resources/resource-0x28.bin"

; Part 7: Final
PART7_PALETTES:	binclude "resources/resource-0x29.bin"
PART7_BYTECODE:	binclude "resources/resource-0x2a.bin"
PART7_VIDEO_1:	binclude "resources/resource-0x2b.bin"

; Part 8-9: Password (shared resources)
PART8_PALETTES:	binclude "resources/resource-0x7d.bin"
PART8_BYTECODE:	binclude "resources/resource-0x7e.bin"
PART8_VIDEO_1:	binclude "resources/resource-0x7f.bin"

; Shared video2 (gameplay parts 2-4, 6-7)
SHARED_VIDEO_2:	binclude "resources/resource-0x11.bin"

; =============================================================================
; Resource lookup table — 4 x 32-bit pointers per part (palette, bytecode, video1, video2)
; =============================================================================
PART_RESOURCE_TABLE:
	; Part 0: Protection
	dd PART0_PALETTES, PART0_BYTECODE, PART0_VIDEO_1, 0
	; Part 1: Intro
	dd PART1_PALETTES, PART1_BYTECODE, PART1_VIDEO_1, 0
	; Part 2: Water
	dd PART2_PALETTES, PART2_BYTECODE, PART2_VIDEO_1, SHARED_VIDEO_2
	; Part 3: Jail
	dd PART3_PALETTES, PART3_BYTECODE, PART3_VIDEO_1, SHARED_VIDEO_2
	; Part 4: Citadel
	dd PART4_PALETTES, PART4_BYTECODE, PART4_VIDEO_1, SHARED_VIDEO_2
	; Part 5: Battlechar
	dd PART5_PALETTES, PART5_BYTECODE, PART5_VIDEO_1, 0
	; Part 6: Arena
	dd PART6_PALETTES, PART6_BYTECODE, PART6_VIDEO_1, SHARED_VIDEO_2
	; Part 7: Final
	dd PART7_PALETTES, PART7_BYTECODE, PART7_VIDEO_1, SHARED_VIDEO_2
	; Part 8: Password
	dd PART8_PALETTES, PART8_BYTECODE, PART8_VIDEO_1, 0
	; Part 9: Password (same)
	dd PART8_PALETTES, PART8_BYTECODE, PART8_VIDEO_1, 0

; Screen bitmap resources (dual-purpose: 4bpp planar bitmap + polygon data for VIDEO 0x80)
SCREEN_BITMAP_0x12:
	binclude "resources/resource-0x12.bin"

SCREEN_BITMAP_0x13:
	binclude "resources/resource-0x13.bin"

SCREEN_BITMAP_0x43:
	binclude "resources/resource-0x43.bin"

SCREEN_BITMAP_0x44:
	binclude "resources/resource-0x44.bin"

SCREEN_BITMAP_0x45:
	binclude "resources/resource-0x45.bin"

SCREEN_BITMAP_0x46:
	binclude "resources/resource-0x46.bin"

SCREEN_BITMAP_0x47:
	binclude "resources/resource-0x47.bin"

SCREEN_BITMAP_0x48:
	binclude "resources/resource-0x48.bin"

SCREEN_BITMAP_0x49:
	binclude "resources/resource-0x49.bin"

SCREEN_BITMAP_0x53:
	binclude "resources/resource-0x53.bin"

SCREEN_BITMAP_0x90:
	binclude "resources/resource-0x90.bin"

SCREEN_BITMAP_0x91:
	binclude "resources/resource-0x91.bin"

