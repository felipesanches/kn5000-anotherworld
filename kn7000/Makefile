# Another World for the KN7000 (ride-along module in the SP7001 SD plug-in).
# See README.md. Needs kn7000_disassembly beside this repo (assembler + XAP/SD tools)
# and its extracted vendor BASEEXT.XAP.

DISASM_REPO ?= ../../kn7000_disassembly
PYTHON      ?= python3
XAPASM      := $(PYTHON) $(DISASM_REPO)/tools/xapasm.py
BASE_XAP    ?= $(DISASM_REPO)/baserom/sp7001_baseext.xap
MODULE_AT   := 0x502B6000
SD_IMAGE    ?= ../../technics_roms/media/sp7001_activated_sdcard.img
MAME        ?= mame
ROMPATH     ?= ../../technics_romsets

all: build/BASEEXT.XAP

build/another.bin: src/main.s src/platform.inc $(DISASM_REPO)/tools/xapasm.py
	@mkdir -p build
	$(XAPASM) src/main.s -I src -o $@ -m build/another.map

build/BASEEXT.XAP: build/another.bin $(BASE_XAP) $(DISASM_REPO)/tools/xap_addon.py
	$(PYTHON) $(DISASM_REPO)/tools/xap_addon.py $(BASE_XAP) build/another.bin $@ --at $(MODULE_AT)

card: build/BASEEXT.XAP
	cp $(SD_IMAGE) build/another_sd.img
	chmod u+w build/another_sd.img
	$(PYTHON) $(DISASM_REPO)/tools/sd_splice.py build/another_sd.img 'C:\TECHNICS\DATA\BASEEXT.XAP' build/BASEEXT.XAP

run: card
	$(MAME) -rompath $(ROMPATH) kn7000 -bios sp7001 -harddisk build/another_sd.img -window

clean:
	rm -rf -- build

.PHONY: all card run clean
