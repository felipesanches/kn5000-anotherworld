# Another World for the KN7000 (ride-along module in the SP7001 SD plug-in).
# See README.md. Needs kn7000_disassembly beside this repo (assembler + XAP/SD tools)
# and its extracted vendor BASEEXT.XAP.

DISASM_REPO ?= ../../kn7000_disassembly
PYTHON      ?= python3
XAPASM      := $(PYTHON) $(DISASM_REPO)/tools/xapasm.py
BASE_XAP    ?= $(DISASM_REPO)/baserom/sp7001_baseext.xap
MODULE_AT   := 0x502B6000
SD_IMAGE    ?= ../../technics_roms/media/sp7001_activated_sdcard.img
# The ONLY build with the sp7001 BIOS (driver: src/mame/matsushita/kn7000.cpp).
# The overlay ../../kn7000-emulator/kn7000 does NOT have it.
MAME        ?= ../../mame-pr/kn7000
ROMPATH     ?= ../../technics_romsets

all: build/BASEEXT.XAP

build/another.bin: src/main.s src/platform.inc src/vm.s src/vm.inc $(DISASM_REPO)/tools/xapasm.py
	@mkdir -p build
	$(XAPASM) src/main.s -I src -o $@ -m build/another.map

build/BASEEXT.XAP: build/another.bin $(BASE_XAP) $(DISASM_REPO)/tools/xap_addon.py
	$(PYTHON) $(DISASM_REPO)/tools/xap_addon.py $(BASE_XAP) build/another.bin $@ --at $(MODULE_AT)

card: build/BASEEXT.XAP
	cp $(SD_IMAGE) build/another_sd.img
	chmod u+w build/another_sd.img
	$(PYTHON) $(DISASM_REPO)/tools/sd_splice.py build/another_sd.img 'C:\TECHNICS\DATA\BASEEXT.XAP' build/BASEEXT.XAP

run: card
	$(MAME) kn7000 -bios sp7001 -rompath $(ROMPATH) -harddisk build/another_sd.img -window
	# mame-pr is an UNPATCHED tree: dismiss the red "known problems" warning with a
	# keypress. For a scripted (headless) run use `make test`, which clears it with -str.

# Reproduce the verification: run probes/render.lua, which presses SD CARD LOAD, lets
# the game task draw, and dumps page-0 (+ a snapshot) to build/. -str <1..299> clears
# the warning screen so the autoboot script runs (this tree lacks the -skip_gameinfo patch).
test: card
	RENDER_LOG=build/render.log $(MAME) kn7000 -bios sp7001 -rompath $(ROMPATH) \
	  -harddisk build/another_sd.img -autoboot_script probes/render.lua \
	  -snapshot_directory build -str 40 -window -nothrottle
	@echo "---- build/render.log ----"; cat build/render.log

clean:
	rm -rf -- build

.PHONY: all card run test clean
