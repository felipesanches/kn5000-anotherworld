; =============================================================================
; font_8x8.asm - Simple 8x8 bitmap font (ASCII 32-127)
; =============================================================================
; Each character is 8 bytes (8 rows of 8 pixels).
; Characters are stored in ASCII order starting from space (32).
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
