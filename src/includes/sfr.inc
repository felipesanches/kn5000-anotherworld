; =============================================================================
; sfr.inc - TMP94C241 Special Function Register Definitions
; =============================================================================
; Special Function Registers for the Toshiba TMP94C241F (TLCS-900/H2)
; used in the Technics KN5000 keyboard.
;
; Reference: ../kn5000-docs/cpu-subsystem.md
; =============================================================================

; -----------------------------------------------------------------------------
; I/O Ports
; -----------------------------------------------------------------------------
P0		EQU 000h
P0CR		EQU 002h
P0FC		EQU 003h
P1		EQU 004h
P1CR		EQU 006h
P1FC		EQU 007h
P2		EQU 008h
P2CR		EQU 00Ah
P2FC		EQU 00Bh
P3		EQU 00Ch
P3CR		EQU 00Eh
P3FC		EQU 00Fh
P7		EQU 01Ch
P7CR		EQU 01Eh
P7FC		EQU 01Fh
P8		EQU 020h
P8CR		EQU 022h
P8FC		EQU 023h
PA		EQU 028h
PAFC		EQU 02Bh
PB		EQU 02Ch
PBFC		EQU 02Fh
PC		EQU 030h
PCCR		EQU 032h
PCFC		EQU 033h
PD		EQU 034h
PDCR		EQU 036h
PDFC		EQU 037h
PE		EQU 038h
PECR		EQU 03Ah
PEFC		EQU 03Bh
PF		EQU 03Ch
PFCR		EQU 03Eh
PFFC		EQU 03Fh
PG		EQU 040h
PH		EQU 044h
PHCR		EQU 046h
PHFC		EQU 047h
PZ		EQU 068h
PZCR		EQU 06Ah

; -----------------------------------------------------------------------------
; 8-bit Timers
; -----------------------------------------------------------------------------
T8RUN		EQU 080h
TRDC		EQU 081h
T02FFCR		EQU 082h
T01MOD		EQU 084h
T23MOD		EQU 085h
TREG0		EQU 088h
TREG1		EQU 089h
TREG2		EQU 08Ah
TREG3		EQU 08Bh

; -----------------------------------------------------------------------------
; 16-bit Timers
; -----------------------------------------------------------------------------
T4MOD		EQU 098h
T4FFCR		EQU 099h
T16RUN		EQU 09Eh
T16CR		EQU 09Fh

; -----------------------------------------------------------------------------
; Serial Channels (SC0, SC1)
; SC0 is used for MIDI and Computer Interface
; -----------------------------------------------------------------------------
SC0BUF		EQU 0D0h	; Serial Channel 0 Buffer (read/write data)
SC0CR		EQU 0D1h	; Serial Channel 0 Control
SC0MOD		EQU 0D2h	; Serial Channel 0 Mode
BR0CR		EQU 0D3h	; Baud Rate 0 Control
SC1BUF		EQU 0D4h	; Serial Channel 1 Buffer
SC1CR		EQU 0D5h	; Serial Channel 1 Control
SC1MOD		EQU 0D6h	; Serial Channel 1 Mode
BR1CR		EQU 0D7h	; Baud Rate 1 Control

; SC0MOD bit definitions:
;   Bits 7-6: Clock source (00=T0, 01=baud rate generator, 10=external, 11=T2)
;   Bit 5: Receive enable
;   Bits 4-3: Stop bits (00=1, 01=1.5, 10=2)
;   Bit 2: Parity enable
;   Bit 1: Parity type (0=even, 1=odd)
;   Bit 0: 8-bit mode (1=8-bit, 0=7-bit)
SC0MOD_8N1	EQU 029h	; 8-bit, no parity, 1 stop, baud gen, RX enable

; SC0CR bit definitions:
;   Bit 7: TX interrupt enable
;   Bit 6: RX interrupt enable
;   Bits 5-2: Error flags (read only)
;   Bit 1: TX buffer empty (read only)
;   Bit 0: RX buffer full (read only)
SC0CR_TXEN	EQU 080h	; TX interrupt enable
SC0CR_RXEN	EQU 040h	; RX interrupt enable

; BR0CR baud rate values (assuming 25 MHz system clock, fc/4):
;   0x00 = 31250 (MIDI standard)
;   0x06 = 38400
;   0x08 = 19200
;   0x10 = 9600
BR0CR_38400	EQU 006h
BR0CR_19200	EQU 008h
BR0CR_9600	EQU 010h
BR0CR_MIDI	EQU 000h

; -----------------------------------------------------------------------------
; Interrupt Control
; -----------------------------------------------------------------------------
INTE45		EQU 0E0h
INTE67		EQU 0E1h
INTE89		EQU 0E2h
INTEAB		EQU 0E3h
INTET01		EQU 0E4h
INTET23		EQU 0E5h
INTET45		EQU 0E6h
INTET67		EQU 0E7h
INTET89		EQU 0E8h
INTETAB		EQU 0E9h
INTES0		EQU 0EAh	; SC0 interrupt enable
INTES1		EQU 0EBh	; SC1 interrupt enable
INTETC01	EQU 0ECh
INTETC23	EQU 0EDh
INTETC45	EQU 0EEh
INTETC67	EQU 0EFh
INTE0AD		EQU 0F0h
IIMC		EQU 0F6h
INTNMWDT	EQU 0F7h
INTCLR		EQU 0F8h

; -----------------------------------------------------------------------------
; DMA Controller
; -----------------------------------------------------------------------------
DMA0V		EQU 0100h
DMA1V		EQU 0101h
DMA2V		EQU 0102h
DMA3V		EQU 0103h
DMAB		EQU 0108h
DMAR		EQU 0109h

; -----------------------------------------------------------------------------
; System Control
; -----------------------------------------------------------------------------
CLKMOD		EQU 010Ah	; Clock Mode
WDMOD		EQU 0110h	; Watchdog Mode
WDCR		EQU 0111h	; Watchdog Control

; Watchdog control values:
WDMOD_DISABLE	EQU 000h	; Disable watchdog
WDCR_DISABLE	EQU 0B1h	; Watchdog control to disable

; -----------------------------------------------------------------------------
; Memory Controller - Block Chip Select
; -----------------------------------------------------------------------------
B0CSL		EQU 0140h
B0CSH		EQU 0141h
MAMR0		EQU 0142h
MSAR0		EQU 0143h
B1CSL		EQU 0144h
B1CSH		EQU 0145h
MAMR1		EQU 0146h
MSAR1		EQU 0147h
B2CSL		EQU 0148h
B2CSH		EQU 0149h
MAMR2		EQU 014Ah
MSAR2		EQU 014Bh
B3CSL		EQU 014Ch
B3CSH		EQU 014Dh
MAMR3		EQU 014Eh
MSAR3		EQU 014Fh
B4CSL		EQU 0150h
B4CSH		EQU 0151h
MAMR4		EQU 0152h
MSAR4		EQU 0153h
B5CSL		EQU 0154h
B5CSH		EQU 0155h
MAMR5		EQU 0156h
MSAR5		EQU 0157h

; -----------------------------------------------------------------------------
; DRAM Controller
; -----------------------------------------------------------------------------
DRAM0CRL	EQU 0160h
DRAM0CRH	EQU 0161h
DRAM1CRL	EQU 0162h
DRAM1CRH	EQU 0163h
DRAM0REF	EQU 0164h
DRAM1REF	EQU 0165h
PMEMCR		EQU 0166h
