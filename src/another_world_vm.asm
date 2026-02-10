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

CURRENT_STATE	EQU 0  ; boolean stored as a byte
REQUESTED_STATE	EQU 1  ; boolean stored as a byte

FROZEN	EQU 0
NOT_FROZEN EQU 1
NO_STATE_REQUEST EQU 0FFh

; These off-screen video pages are stored in external RAM:
PAGE_BITMAP_0 EQU 240000h
PAGE_BITMAP_1 EQU 250000h
PAGE_BITMAP_2 EQU 260000h
PAGE_BITMAP_3 EQU 270000h

; VM variable indices (used by the game engine)
VM_VARIABLE_RANDOM_SEED		EQU 03Ch
VM_VARIABLE_LAST_KEYCHAR	EQU 0C5h
VM_VARIABLE_HERO_POS_UP_DOWN	EQU 0E5h
VM_VARIABLE_HERO_POS_JUMP_DOWN	EQU 0DCh
VM_VARIABLE_HERO_POS_LEFT_RIGHT	EQU 0E9h
VM_VARIABLE_HERO_POS_MASK	EQU 0FAh
VM_VARIABLE_HERO_ACTION		EQU 0FBh
VM_VARIABLE_HERO_ACTION_POS_MASK EQU 0FBh
VM_VARIABLE_SCROLL_Y		EQU 0F9h

; Game part IDs
GAME_PART_INTRO			EQU 03E80h
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
	ADDW (CUR_LINE_LOW), 320
	ADCW (CUR_LINE_HIGH), 0
	LD HL, (LINE_XMIN)
	EXTS XHL
	ADD XIX, XHL
	LD HL, (LINE_XMAX)
	SUB HL, (LINE_XMIN)

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
	ADDW (CUR_LINE_LOW), 320
	ADCW (CUR_LINE_HIGH), 0
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
	ADDW (CUR_LINE_LOW), 320
	ADCW (CUR_LINE_HIGH), 0
	LD HL, (LINE_XMIN)
	EXTS XHL
	ADD XIX, XHL
	LD HL, (LINE_XMAX)
	SUB HL, (LINE_XMIN)

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
	LD WA, 0
	LD WA, HL
	MUL XWA, 320
	; FIXME: do we need to zero the upper 16 bits of XDE here?
	ADD XWA, XDE
	LD XIX, 01a0000h
	ADD XIX, XWA
	LD (XIX), BC
	POP XIX
	RET

video MACRO type,data,x,y
	LD XIX, INTRO_VIDEO_type
	ADD XIX, data
	LD DE, x
	LD HL, y
	LD BC, 0FF40h
	CALL readAndDrawPolygon
	ENDM


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
	LD (XIX + REQUESTED_STATE), NO_STATE_REQUEST
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

	; Note: Full part switching would require bank-switching bytecode,
	; palettes, and video data. Only intro resources are available.
	RET


GAME_RESET:
	CALL VIDEO_START
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
	LD (XIX + REQUESTED_STATE), NO_STATE_REQUEST
	POP IX

	INC IX
	CP IX, 64
	JP NE, _setup_threads__loop

	; Initialize VM_VARIABLE_RANDOM_SEED with a fixed seed (no RTC available)
	LD A, VM_VARIABLE_RANDOM_SEED
	LD DE, 1234h			; Fixed seed value
	CALL _write_vm_var

	; VM_HACK_INIT_VAR_54_WITH_81: Required for Interplay logo display
	LD A, 054h
	LD DE, 0081h
	CALL _write_vm_var

	; Initialize part tracking
	LDW (REQUESTED_NEXT_PART), 0
	LDW (CURRENT_PART_ID), GAME_PART_INTRO

	RET

ENTRY:
	EI 06 ; DISABLE INTERRUPTS
	CALL GAME_RESET

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
	LD BC, 0
PAUSE_LOOP1:
	LD DE, 01h
PAUSE_LOOP2:
	DJNZ DE, PAUSE_LOOP2
	DJNZ BC, PAUSE_LOOP1
	RET

readAndDrawPolygon:
	; Inputs:
	; XIX: polygon data pointer
	; DE: x
	; HL: y
	; B: color (Black = FFh)
	; C: zoom (default = 40h)
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
	;(zoom, pt)

	PUSH XIX
	PUSH BC ; C=zoom
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

	LD WA, 0
	LD A, (XIX)
	INC XIX
	LD DE, 0
	LD E, C
	MUL XWA, DE			; *= ZOOM
	SRAW 6, WA			; /= default_zoom (40h)
	LD (POLYGON_BBOX_W), WA

	LD WA, 0
	LD A, (XIX)
	INC XIX
	LD DE, 0
	LD E, C
	MUL XWA, DE			; *= ZOOM
	SRAW 6, WA			; /= default_zoom (40h)
	LD (POLYGON_BBOX_H), WA

	LD B, (XIX)
	INC XIX
	LD (POLYGON_NUM_POINTS), B

	LD XIY, POLYGON_POINTS
	LD DE, 0
	LD E, C

READ_THE_COORDINATES:

	LD WA, 0
	LD A, (XIX)
	INC XIX
	MUL XWA, DE			; *= ZOOM
	SRAW 6, WA			; /= default_zoom (40h)
	LD (XIY), WA
	INC 2, XIY

	LD WA, 0
	LD A, (XIX)
	INC XIX
	MUL XWA, DE			; *= ZOOM
	SRAW 6, WA			; /= default_zoom (40h)
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

	LD XIX, (CUR_PAGE_PTR_1)
	LD XHL, 0
	LD HL, (HLINEY)
	MUL XHL, 320
	ADD XIX, XHL
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
	CPW (HLINEY), 199
	JP UGT, POLYGON_RASTER_LOOP	; if (m_hliney > 199) return;

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
	LD D, 0
	LD E, C ; zoom
	;	pt.x -= m_polygonData[m_data_offset++] * zoom / DEFAULT_ZOOM;
	LD WA, 0
	LD A, (XIX)
	INC XIX
	LD HL, (XSP + 6)
	MUL XWA, DE			; PT.X *= ZOOM
	SRA 6, WA			; PT.X /= default_zoom (40h)
	SUB HL, WA
	LD (XSP + 6), HL

	;	pt.y -= m_polygonData[m_data_offset++] * zoom / DEFAULT_ZOOM;
	LD WA, 0
	LD A, (XIX)
	INC XIX
	LD HL, (XSP + 4)
	MUL XWA, DE			; PT.Y *= ZOOM
	SRA 6, WA			; PT.Y /= default_zoom (40h)
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
	SRA 6, WA			; PO.X /= default_zoom (40h)
	ADD HL, WA
	LD (XSP + 2), HL
	
	; po.y += m_polygonData[m_data_offset++] * zoom / DEFAULT_ZOOM;
	LD WA, 0
	LD A, (XIX)
	INC XIX
	LD HL, (XSP)
	MUL XWA, DE			; PO.Y *= ZOOM
	SRA 6, WA			; PO.Y /= default_zoom (40h)
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
	LD XIX, 0
	LD IX, (XSP + 0Ah) ;offset
	SLA 1, IX		 ; m_data_offset = (offset & 0x7FFF) * 2;
	ADD XIX, INTRO_VIDEO_1
	
	LD HL, DE
	; here L is the computer new color
	; and BC is the children loop counter

	; BC needs to become color | zoom params and
	; DE needs to become x param
	; to the readAndDrawPolygon routine
	
	LD DE, (XSP + 4)	; restore zoom

	PUSH BC
	LD B, L		; color
	LD C, E		; zoom
	LD DE, (XSP + 0ah)		; PO.x
	LD HL, (XSP + 08h)		; PO.y
	; (color, zoom, po)
	CALL readAndDrawPolygon
	POP BC
	POP XIX				; m_data_offset = backup;
	POP DE		; restore zoom

	INC 6, XSP ; local vars offset, po.x, po.y
	DJNZ BC, children_loop
	RET


LOAD_SCREEN:
; Input: XHL = pointer to screen bitmap data (320x200 pixels)
; Copies bitmap data to PAGE_BITMAP_0
	LD XDE, PAGE_BITMAP_0
	LD XBC, 320 * 200 / 2		; bitmap data length in 16-bit words (320x200 pixels)
	LDIRW
	RET

SETUP_PALETTE:
	; XWA: paletteID
	LD BC,0
	LD XDE, 01703c8h		; VGA 3c8 port (select color palette index
	LD (XDE), C

	LD BC, 2*16							; data length: 16 colors, 4 bits per component
	LD XDE, 01703c9h					; VGA 3c9 port (for setting the color palette values: r, g and b)
	LD XHL, INTRO_PALETTES
	SLA 5, XWA
	ADD XHL, XWA

PALETTE_LOOP:
	; red
	LD A, (XHL)
	ANDB A, 0Fh
	LD (XDE), A
	INC XHL

	; green
	LD A, (XHL)
	ANDB A, 0Fh
	LD (XDE), A

	; blue
	LD A, (XHL)
	SRA 4, A
	LD (XDE), A
	INC XHL

	DJNZ BC, PALETTE_LOOP
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
	CP A, 3
	JP UGT, PAGEID_OTHER_VALUE
	AND WA, 3   ; 10000h bytes per page = enough for 320x200 pixels
	LD QWA, WA
	LD WA, 0
	ADD XWA, PAGE_BITMAP_0
	RET

PAGEID_OTHER_VALUE:
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


INPUT_UPDATE_PLAYER:
	; Stub: initialize input-related VM variables to neutral values
	; Full input via control panel serial is a future enhancement
	RET


CHECK_THREAD_REQUESTS:

	; Check if a part switch has been requested
	LD WA, (REQUESTED_NEXT_PART)
	CP WA, 0
	JP EQ, _no_part_switch
	; Part switch requested - call initForPart
	CALL initForPart
	LDW (REQUESTED_NEXT_PART), 0
_no_part_switch:

	LD A, 0
_check_thread_reqs__loop:

	; thread->state = thread->requested_state;
	PUSH WA
	SLA 1, WA
	EXTZ XWA
	ADD XWA, VM_IS_CHANNEL_ACTIVE
	LD E, (XWA + REQUESTED_STATE)
	CP E, NO_STATE_REQUEST
	JP EQ, _no_state_request
	LD (XWA + CURRENT_STATE), E
_no_state_request:
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
	CALL INPUT_UPDATE_PLAYER

	LD WA, 0
	LD A, (CURRENT_THREAD)

_next_thread__do_loop:
	INC A
	CP A, 64
	JP NE, _not_end_of_frame
	; == END OF FRAME ==
	LDB (CURRENT_THREAD), 0
	CALL CHECK_THREAD_REQUESTS
	LD A, 0FEh
	CALL UPDATE_DISPLAY
	LD A, 0
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
	ADD XIX, INTRO_BYTECODE			; FIXME

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

	; Save bytecode position before replacing XIX with video data pointer
	LD XDE, XIX
	SUB XDE, INTRO_BYTECODE
	LD (VM_PC), DE

	SLA 1, WA
	EXTZ XWA
	LD XIX, INTRO_VIDEO_1
	ADD XIX, XWA

	LD E, (XIX)
	INC XIX
	EXTZ DE		; x-coord

	LD B, (XIX)
	INC XIX
	EXTZ BC
	LD HL, BC	; y-coord

;		if (y > 199)
;		{
;			x += (y - 199);
;			y = 199;
;		}
	CP HL, 199
	JP UGE, _0x80_y_ok
	ADD DE, HL
	SUB DE, 199
	ADD HL, 199
_0x80_y_ok:

	LD BC, 0FF40h
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
	LD C, 40h			; default zoom
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
	LD C, E				; zoom = low byte of variable
	JP _0x40_zoom_done

_0x40_zoom_not_1:
	CP A, 2
	JP NE, _0x40_zoom_case3
	; fetch_byte() and discard
	INC XIX
	JP _0x40_zoom_done

_0x40_zoom_case3:
	; case 3: m_useVideo2 = true, zoom = 0x40
	; TODO: select INTRO_VIDEO_2 when available

_0x40_zoom_done:
	; C = zoom

	; Save bytecode position (all variable-length bytes consumed)
	LD XDE, XIX
	SUB XDE, INTRO_BYTECODE
	LD (VM_PC), DE

	; Restore parameters from stack
	POP HL				; HL = y
	POP DE				; DE = x
	POP WA				; WA = offset

	; Set up polygon data pointer
	EXTZ XWA
	LD XIX, INTRO_VIDEO_1
	ADD XIX, XWA

	; B = color (0xFF = BLACK), C = zoom (already set)
	LD B, 0FFh

	; DE = x, HL = y, BC = color|zoom, XIX = data pointer
	CALL readAndDrawPolygon

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
	INC 3, DE
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

    LD DE, 0FFFFh ; HACK!!!!!!
	LD (XWA + PC_OFFSET), DE ; HACK!!!!!!

	LD DE, (XWA + REQUESTED_PC_OFFSET)
	CP DE, NO_REQUEST
	JP NE, _pausethread_after_setting_request
	; When there's no other program counter request set
	; for this thread, we set the address of the
	; next instruction to resume execution
	; in the next VM frame.
	LD XDE, XIX
	SUB XDE, INTRO_BYTECODE		; FIXME
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
	; neither bit set: a = c (sign-extended byte)
	LD E, A
	LD D, 0
	; Sign-extend: if bit 7 of E is set, D = 0xFF
	BIT 7, E
	JP Z, _condJmp_have_a
	LD D, 0FFh
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
	LD WA, (XIX)	; word paletteId = fetch_word()
	EX W, A			; byte-swap: bytecode is big-endian
	INC 2, XIX
	SRA 8, WA		; paletteId >>= 8
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

	CP D, 0			; type 0: freeze threads
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
	CP D, 1			; type 1: unfreeze threads
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
	; If currentPart == INTRO and vm_var[0x67] == 1, set vm_var[0xDC] = 0x21
	PUSH WA			; save pageId
	LD WA, (CURRENT_PART_ID)
	CP WA, GAME_PART_INTRO
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
	CALL DRAW_STRING
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
	INC 5, XIX		; word resourceId; byte freq; byte vol; byte channel;	
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
	; Check if resourceId matches a known screen bitmap resource
	; screen_resource_indexes = {0x49, 0x53} (available resources)
	CP WA, 049h
	JP NE, _load_not_0x49
	LD XHL, SCREEN_BITMAP_0x49
	CALL LOAD_SCREEN
	JP _end_of_EXECUTE_INSTRUCTION
_load_not_0x49:
	CP WA, 053h
	JP NE, _load_unknown
	LD XHL, SCREEN_BITMAP_0x53
	CALL LOAD_SCREEN
	JP _end_of_EXECUTE_INSTRUCTION
_load_unknown:
	; Unknown resource - ignore
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_LOAD:


	; ====  PLAY_MUSIC instruction  ====
	CP A, 1Ah
	JP NE, INSTRUCTION_IS_NOT_PLAY_MUSIC
	; Implement-me!
	; Note: We currently do not understand the Technics KN5000 sound hardware.
	INC 5, XIX		; word resNum; word delay; byte pos;
	JP _end_of_EXECUTE_INSTRUCTION
INSTRUCTION_IS_NOT_PLAY_MUSIC:

		
_end_of_EXECUTE_INSTRUCTION:
	SUB XIX, INTRO_BYTECODE
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

INTRO_BYTECODE:
	binclude "resources/resource-0x18.bin"

INTRO_PALETTES:
	binclude "resources/resource-0x17.bin"  ; intro

INTRO_VIDEO_1:
	binclude "resources/resource-0x19.bin"

INTRO_VIDEO_2:
	binclude "resources/resource-0x1a.bin"

; Screen bitmap resources
SCREEN_BITMAP_0x49:
	binclude "resources/resource-0x49.bin"

SCREEN_BITMAP_0x53:
	binclude "resources/resource-0x53.bin"

BITMAP_1:
	binclude "another_world_logo.bin"
BITMAP_2:
	binclude "other_bitmap.bin"
