# Another World for the KN7000. Two builds:
#   make sdcard              build/sdcard/: KN7APP.BIN and the game's files, everything for the SD card's
#                            root folder (README-CNV.md). The build for a real instrument: an application
#                            of the loader KN7LOAD.CNV, which the instrument runs from the owner's existing
#                            floppy through DISK MENU > STYLE CONVERT; stays out of IC23, the user pools
#                            and the loader.
#   make MAME_ONLY=1 sp7001  BASEEXT.XAP, the SP7001 ride-along build (README.md): MAME ONLY. It keeps
#                            the game in the 0x44000000 window, which on a real KN7000 is IC23 (the
#                            battery-backed panel memories); the build refuses to run without MAME_ONLY=1.
# (The floppy-only AW.CNV route is retired: README-CNV.md, "History".)
# Needs the KN7000 toolchain (technics-roms-disasm/kn7000: assembler + XAP/SD tools, and the loader's
# tools/cnv_romdump) beside this repo, and for the SP7001 build its extracted vendor BASEEXT.XAP.

DISASM_REPO ?= ../../technics-roms-disasm/kn7000
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

all: sdcard

sp7001: build/BASEEXT.XAP

$(RES_OUT)/awres.inc: tools/aw_extract.py $(AW_DATA)/MEMLIST.BIN
	@mkdir -p $(RES_OUT)
	$(PYTHON) tools/aw_extract.py $(AW_DATA) $(RES_OUT) --inc $(RES_OUT)/awres.inc

# The SP7001 build lives in CS1 (IC23) and the TPAD pool: tools/ic23_guard.py must FIND that (were it
# ever to call this build clean, the check itself would be broken), and the build goes on only with
# MAME_ONLY=1.
build/another.bin: src/main.s src/display.s src/platform.inc src/vm.s src/vm.inc src/interp.s src/help.s $(RES_OUT)/awres.inc $(DISASM_REPO)/tools/xapasm.py tools/ic23_guard.py
	@mkdir -p build
	@if $(PYTHON) -I tools/ic23_guard.py $(DISASM_REPO)/tools src/main.s -I src -I $(RES_OUT) > build/another.guard; then \
	  echo "ic23_guard calls the SP7001 build clean, which it is not: the guard is broken"; exit 1; fi
	@tail -1 build/another.guard
	@if [ "$(MAME_ONLY)" != 1 ]; then \
	  echo "The SP7001 build writes the 0x44000000 window: IC23, the panel memories, on a real KN7000."; \
	  echo "It is for MAME only. Build it with: make MAME_ONLY=1 ...   (for an instrument: make floppy)"; exit 1; fi
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

# ---- the KN7APP.BIN build: a stock KN7000 (any program build), no SP7001 -- README-CNV.md ----
# DISK MENU > STYLE CONVERT runs KN7LOAD.CNV from the owner's floppy; the loader reads KN7APP.BIN from the SD
# card's root folder and calls it on every converter call. KN7APP.BIN runs the same VM and reads the game's
# files part by part from the card's root (AWRxx.AW: each resource the game draws or runs, as MEMLIST.BIN finds it
# in BANKxx; the font and the strings).
LOADER_DIR  ?= $(DISASM_REPO)/tools/cnv_romdump
# The loader on the owner's write-protected floppy, unchanged since its release: these exact files.
LOADER_CNV    ?= $(LOADER_DIR)/releases/2026-10-19/floppy/KN7LOAD.CNV
LOADER_FLOPPY ?= $(LOADER_DIR)/releases/2026-10-19/floppy/kn7load_floppy.img
LOADER_SHA1   := 6b81f382fd29b9bc5a025854af0e20a194e68bec
FLOPPY_SHA1   := b7a67de602694fd2257d59ce4509ca154b0b3064
# The published overlay build (program 941 is its default KN7000 BIOS; -bios v13 is program 893, the owner's).
MAME941     ?= ../../kn7000-emulator/run.sh
SD941       ?= ../../kn7000-emulator/sdcard_from_real_kn7000.img
APP_SRC     := src/cnv_main.s src/fwfind.s src/display.s src/vm.s src/interp.s src/help.s
BIOS        ?= v13

app: build/KN7APP.BIN
sdcard: build/sdcard/KN7APP.BIN

$(RES_OUT)/awpart.inc: tools/aw_extract.py tools/aw_partinfo.py src/platformcnv.inc $(AW_DATA)/MEMLIST.BIN
	@mkdir -p $(RES_OUT)
	$(PYTHON) -I tools/aw_extract.py $(AW_DATA) $(RES_OUT) --parts $@ src/platformcnv.inc $(FONT_DIR)

# Is the loader the owner's? (its SHA-1 and its floppy image's, as released on 2026-10-19)
build/loader.ok: $(LOADER_CNV) $(LOADER_FLOPPY)
	@mkdir -p build
	echo "$(LOADER_SHA1)  $(LOADER_CNV)" | sha1sum -c --quiet
	echo "$(FLOPPY_SHA1)  $(LOADER_FLOPPY)" | sha1sum -c --quiet
	@touch $@

# Before KN7APP.BIN is written, three checks must pass (each stops the build otherwise):
#   tools/leafcheck.py   a routine entered with `call X, 0, 0` must not call anything before it makes
#                        a frame (the nested call overwrites its return address; that hung the first
#                        unpacker);
#   tools/ic23_guard.py  no address the build names may lie in CS1 (IC23) or the user pools, and none in
#                        the loader's resident area 0x502B8000-0x502B9FFF but loads from its service
#                        table (--loader): "clean";
#   tools/cnv_layout.py  the memory map (src/platformcnv.inc) stays in the converter's RAM, off the
#                        mailbox page and the loader's resident area (kn7cnv.inc, and the loader's own
#                        image), without overlaps; the image starts at APP_BASE with its header and fits
#                        below the font.
# Then the loader's mkapp.py fills in the header's size and CRC-32, which the loader checks.
build/KN7APP.BIN: $(APP_SRC) src/platformcnv.inc src/vm.inc $(RES_OUT)/awpart.inc $(LOADER_DIR)/kn7cnv.inc $(LOADER_DIR)/mkapp.py $(DISASM_REPO)/tools/xapasm.py tools/leafcheck.py tools/ic23_guard.py tools/cnv_layout.py build/loader.ok
	@mkdir -p build
	$(PYTHON) -I tools/leafcheck.py $(APP_SRC)
	$(PYTHON) -I tools/ic23_guard.py $(DISASM_REPO)/tools src/cnv_main.s -I src -I $(RES_OUT) -I $(LOADER_DIR) --loader $(LOADER_DIR)/kn7cnv.inc
	$(XAPASM) src/cnv_main.s -I src -I $(RES_OUT) -I $(LOADER_DIR) -o build/kn7app.bin -m build/kn7app.map
	$(PYTHON) -I tools/cnv_layout.py $(LOADER_DIR)/kn7cnv.inc src/platformcnv.inc src/vm.inc build/kn7app.map build/kn7app.bin $(LOADER_CNV)
	$(PYTHON) -I $(LOADER_DIR)/mkapp.py build/kn7app.bin $@.tmp
	mv -f $@.tmp $@

# Everything for the SD card's root folder, and nothing else: build/sdcard/ (list: build/sdcard.txt).
build/sdcard/KN7APP.BIN: build/KN7APP.BIN tools/make_sdcard.py $(RES_OUT)/awpart.inc
	$(PYTHON) -I tools/make_sdcard.py build/sdcard build/KN7APP.BIN $(RES_OUT)

# Boot the stock KN7000 with the owner's loader floppy and a copy of the real KN7000's SD card with
# build/sdcard/ added to its root; then DISK MENU, STYLE CONVERT, OK. BIOS=v13 (the default) runs program
# 893 (the owner's), v16 program 941.
kn7run: build/sdcard/KN7APP.BIN build/loader.ok
	cp $(SD941) build/kn7run_sd.img && chmod u+w build/kn7run_sd.img
	$(SD_ADDFILE) build/kn7run_sd.img $$(cd build/sdcard && for f in *; do printf '%s build/sdcard/%s ' "$$f" "$$f"; done) > /dev/null
	cp $(LOADER_FLOPPY) build/kn7run_floppy.img && chmod u+w build/kn7run_floppy.img
	$(MAME941) kn7000 -bios $(BIOS) -window -flop $(abspath build/kn7run_floppy.img) -harddisk $(abspath build/kn7run_sd.img)

# Does the run-time firmware search find everything in every program build we have? (tools/aw_find_fw.py)
fwfind:
	$(PYTHON) -I tools/aw_find_fw.py

clean:
	rm -rf -- build

.PHONY: all sp7001 card run test clean app sdcard kn7run fwfind
