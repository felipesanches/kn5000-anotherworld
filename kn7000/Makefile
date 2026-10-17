# Another World for the KN7000 (ride-along module in the SP7001 SD plug-in).
# See README.md. Needs kn7000_disassembly beside this repo (assembler + XAP/SD tools)
# and its extracted vendor BASEEXT.XAP.

DISASM_REPO ?= ../../kn7000_disassembly
PYTHON      ?= python3
XAPASM      := $(PYTHON) $(DISASM_REPO)/tools/xapasm.py
BASE_XAP    ?= $(DISASM_REPO)/baserom/sp7001_baseext.xap
# The start of BASEEXT.XAP's free tail (xap_addon.py): room for a 12,928-byte module.
MODULE_AT   := 0x502B4D80
SD_IMAGE    ?= ../../technics_roms/media/sp7001_activated_sdcard.img
# The ONLY build with the sp7001 BIOS (driver: src/mame/matsushita/kn7000.cpp).
# The overlay ../../kn7000-emulator/kn7000 does NOT have it.
MAME        ?= ../../mame-pr/kn7000
ROMPATH     ?= ../../technics_romsets
# The original MS-DOS release (MEMLIST.BIN + BANK01..BANK0D) -- the same files the reference VM
# (rustyworld) reads. tools/aw_extract.py unpacks all 146 resources into build/res/; each goes on
# the card as its own file (C:\TECHNICS\DATA\AWRxx.AW) because the firmware's fread has a 16-bit
# count and no sequential reads, and every resource is <= 65535 bytes.
AW_DATA     ?= ../../MSDOS
RES_OUT     := build/res
# The 8x8 font and the string index/data tables (DRAW_STRING). These are the exact
# blobs the KN5000 build binclude's; shared verbatim so the two renderers agree.
FONT_DIR    ?= ../../custom-kn5000-roms/anotherworld/src/hardcoded_data
SD_ADDFILE  := $(PYTHON) $(DISASM_REPO)/tools/sd_addfile.py

all: build/BASEEXT.XAP

$(RES_OUT)/awres.inc: tools/aw_extract.py $(AW_DATA)/MEMLIST.BIN
	@mkdir -p $(RES_OUT)
	$(PYTHON) tools/aw_extract.py $(AW_DATA) $(RES_OUT) --inc $@

build/another.bin: src/main.s src/platform.inc src/vm.s src/vm.inc src/interp.s src/help.s $(RES_OUT)/awres.inc $(DISASM_REPO)/tools/xapasm.py
	@mkdir -p build
	$(XAPASM) src/main.s -I src -I $(RES_OUT) -o $@ -m build/another.map

build/BASEEXT.XAP: build/another.bin $(BASE_XAP) $(DISASM_REPO)/tools/xap_addon.py
	$(PYTHON) $(DISASM_REPO)/tools/xap_addon.py $(BASE_XAP) build/another.bin $@ --at $(MODULE_AT)

card: build/BASEEXT.XAP
	cp $(SD_IMAGE) build/another_sd.img
	chmod u+w build/another_sd.img
	$(PYTHON) $(DISASM_REPO)/tools/sd_splice.py build/another_sd.img 'C:\TECHNICS\DATA\BASEEXT.XAP' build/BASEEXT.XAP
	$(SD_ADDFILE) build/another_sd.img $$(cat $(RES_OUT)/card.args) > build/card.log
	$(SD_ADDFILE) build/another_sd.img 'C:\TECHNICS\DATA\AWFONT.AW'   $(FONT_DIR)/anotherworld_chargen.rom
	$(SD_ADDFILE) build/another_sd.img 'C:\TECHNICS\DATA\AWSTRIDX.AW' $(FONT_DIR)/str_index.rom
	$(SD_ADDFILE) build/another_sd.img 'C:\TECHNICS\DATA\AWSTRDAT.AW' $(FONT_DIR)/str_data.rom

run: card
	$(MAME) kn7000 -bios sp7001 -rompath $(ROMPATH) -harddisk build/another_sd.img -window
	# mame-pr is an UNPATCHED tree: dismiss the red "known problems" warning with a
	# keypress. For a scripted (headless) run use `make test`, which clears it with -str.

# Reproduce the verification: run probes/render.lua, which presses SD CARD LOAD, lets
# the game task draw, and dumps page-0 (+ a snapshot) to build/. -str <1..299> clears
# the warning screen so the autoboot script runs (this tree lacks the -skip_gameinfo patch).
# Scripted check: press SD CARD LOAD, let the VM run the intro, then dump the loaded
# resources, VM state and page fills (and a snapshot) to build/. -str clears the warning
# screen so the autoboot script runs (this tree lacks the -skip_gameinfo patch).
test: card
	RENDER_LOG=build/awrun.log $(MAME) kn7000 -bios sp7001 -rompath $(ROMPATH) \
	  -harddisk build/another_sd.img -autoboot_script probes/awrun.lua \
	  -snapshot_directory build -str 50 -window -nothrottle
	@echo "---- build/awrun.log ----"; cat build/awrun.log

clean:
	rm -rf -- build

.PHONY: all card run test clean
