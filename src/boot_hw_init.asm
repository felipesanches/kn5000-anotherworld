; =============================================================================
; boot_hw_init.asm - Minimal Hardware Initialization (Local)
; =============================================================================
; Minimal version of the shared boot_hw_init.asm from kn5000-roms-disasm.
; Includes: display (VGA + VRAM), control panel serial (SC1 via Port F),
; 8-bit timer (T0/T1 cascade for system tick), and memory controller.
;
; Removed from original:
;   - 16-bit timer setup (T4, T5)
;   - Interrupt mode control (IIMC)
;
; Kept but potentially removable (marked with REVIEW):
;   - Data bus port setup (P2, P3, P7) - may be needed for external bus
;   - Address bus port setup (PA-PH, PZ) - may be needed for VRAM/VGA access
;   - Block chip select config (B0-B5) - may be needed for bus timing
;   These are safe to keep but could be tested for removal in MAME.
; =============================================================================

	; === Watchdog Timer Disable ===
	LD (WDMOD), 000h
	LD (WDCR), 0b1h

	; === System Clock Setup ===
	LD (CLKMOD), 004h			; High-speed (16 MHz)

	; === Port F Setup (SC1 for Control Panel) ===
	LD (PF), 000h
	LD (PFFC), 073h			; SC0: TXD+RXD func, SC1: TXD+RXD+SCLK func
	LD (PFCR), 015h			; SC0: TXD+CLK output, SC1: TXD output

	; === Data Bus Ports Setup (P2, P3, P7) ===
	; REVIEW: May be needed for external bus access to VGA/VRAM
	LD (P2FC), 0ffh
	LD (P3FC), 0ffh
	LD (P7), 0ffh
	LD (P7FC), 01fh
	LD (P7CR), 000h

	; === Address Bus Ports Setup (PA, PB, PC, PD, PE, PH, PZ) ===
	; REVIEW: May be needed for address lines to reach 0x170000 (VGA)
	; and 0x1A0000 (VRAM). Safe to keep; test removal in MAME.
	LD (PA), 0feh
	LD (PAFC), 008h
	LD (PB), 0ffh
	LD (PBFC), 01fh
	LD (PC), 003h
	LD (PCFC), 000h
	LD (PCCR), 002h
	LD (PD), 000h
	LD (PDFC), 006h
	LD (PDCR), 011h
	LD (PE), 000h
	LD (PEFC), 042h
	LD (PECR), 020h
	LD (PH), 000h
	LD (PHFC), 01eh
	LD (PHCR), 009h
	LD (PZ), 0ffh
	LD (PZCR), 003h

	; === Memory Controller: Start Address Registers ===
	LD (MSAR0), 01eh			; Block 0 @ 0x1E0000
	LD (MSAR1), 010h			; Block 1 @ 0x100000 (VGA at 0x170000)
	LD (MSAR2), 0c0h			; Block 2 @ 0xC00000
	LD (MSAR3), 000h			; Block 3 @ 0x000000 (DRAM)
	LD (MSAR4), 080h			; Block 4 @ 0x800000
	LD (MSAR5), 000h			; Block 5 @ 0x000000

	; === Memory Controller: Address Mask Registers ===
	LD (MAMR0), 00fh
	LD (MAMR1), 03fh
	LD (MAMR2), 07fh
	LD (MAMR3), 01fh
	LD (MAMR4), 0ffh
	LD (MAMR5), 0ffh

	; === Port 8 Setup (Chip Select Pins) ===
	LD (P8), 03bh
	LD (P8FC), 07fh
	LD (P8CR), 03fh

	; === DRAM Initialization ===
	LD BC, 0400h
.pause1:
	DJNZ BC, .pause1
	LD (DRAM1REF), 081h			; Enable DRAM refresh

	LD BC, 2000h
.pause2:
	DJNZ BC, .pause2
	LD (DRAM1REF), 071h
	LD (DRAM1CRL), 08bh
	LD (DRAM1CRH), 058h
	RES 4, (PMEMCR)

	; === Block Chip Select Configuration ===
	; REVIEW: Bus timing per memory block. Likely needed for VRAM/VGA
	; on block 1, but could test removal of unused blocks.
	LD (B0CSL), 011h
	LD (B1CSL), 033h
	LD (B2CSL), 011h
	LD (B3CSL), 022h
	LD (B4CSL), 011h
	LD (B5CSL), 022h

	LD (B0CSH), 080h
	LD (B1CSH), 081h
	LD (B2CSH), 0c2h
	LD (B3CSH), 08ah
	LD (B4CSH), 082h
	LD (B5CSH), 081h

	; === 8-bit Timer Setup (T0/T1 cascade for system tick) ===
	; T0 clock: prescaler T1 output = fCPU/8
	; MAME KN5000: fCPU = 16 MHz → T0 input = 2 MHz
	; T0 ÷10 (TREG0) → 200 kHz, T1 cascade ÷16 (TREG1) → 12500 Hz (80 µs/tick)
	LD (T01MOD), 01dh		; T0CLK=01(T1/÷8), T01M=00(8bit cascade), PRRUN=1
	LD (T02FFCR), 000h		; No flip-flop output
	LD (TREG0), 00ah		; T0 divides by 10
	LD (TREG1), 010h		; T1 divides by 16
	LD (TRDC), 000h			; No double-buffer
	LD (T16RUN), 080h		; Enable prescaler (bit 7 = PRRUN)
	LD (T8RUN), 003h		; Start T0 (bit 0) + T1 (bit 1)

	; Enable INTT1 interrupt at priority level 6
	LD (INTET01), 0C0h		; bits [7:5] = 110 = level 6, INTT0 disabled

	; === SC1 Serial Setup (Control Panel, 250 kHz) ===
	LD (SC1MOD), 000h		; Synchronous I/O mode, clock source = TO2 trigger
	LD (BR1CR), 014h		; 250 kHz baud rate (16 MHz / 16 / 4)
	LD (SC1CR), 001h		; IOC=0: internal clock, SCLKS=0: rising edge, RXE=1
	LD (INTES1), 000h		; Clear TX complete flag set by SC1MOD write (polled mode)
