# =============================================================================
# Makefile - Custom KN5000 ROM Build System
# =============================================================================
# Build custom ROMs for the Technics KN5000 keyboard.
#
# Targets:
#   make          - Build ROM and create MAME ROM set
#   make build    - Build custom ROM only
#   make romset   - Create complete MAME ROM set with custom program ROM
#   make clean    - Remove build artifacts
#   make test     - Run in MAME emulator
#
# Requirements:
#   - ASL Macro Assembler (asl) and p2bin in ../tools/asl/
#   - MAME unidasm disassembler in ../tools/unidasm
#   - Original KN5000 ROMs in /mnt/shared/kn5000_original_roms/kn5000/
#   - MAME with kn5000 driver (for testing)
# =============================================================================

# Tool paths (relative to project root)
ASL_PATH := ../../tools/asl
ASL := $(ASL_PATH)/asl
P2BIN := $(ASL_PATH)/p2bin
UNIDASM := ../../tools/unidasm
EXTRACT_RESOURCES := python3 tools/extract_resources.py

# Game data directory (original Another World files)
GAME_DATA_DIR := game_data/MSDOS

# Assembler flags
# -L generates listing file, -olist specifies listing filename
ASL_FLAGS := -w -q -L

# Build output directory
BUILD_DIR := out

# Source files
MAIN_SRC := src/main.asm
INCLUDE_DIR := src/includes

# Shared code from disasm repository
DISASM_REPO := ../../kn5000-roms-disasm

# Output files
MAIN_ROM := $(BUILD_DIR)/custom_program.rom
MAIN_DISASM := $(BUILD_DIR)/custom_program.disasm

# =============================================================================
# Target selection: maincpu (default) or extension
# =============================================================================
TARGET ?= maincpu

ifeq ($(TARGET),maincpu)
  ASL_EXTRA := -D TARGET_MAINCPU
  P2BIN_RANGE := -r 0xE00000-0xFFFFFF
  ROM_SIZE := 2097152
else ifeq ($(TARGET),extension)
  ASL_EXTRA := -D TARGET_EXTENSION
  P2BIN_RANGE := -r 0x280000-0x2FFFFF
  ROM_SIZE := 524288
endif

# =============================================================================
# MAME ROM Set Configuration
# =============================================================================
# Original ROM location
ORIGINAL_ROMS := /mnt/shared/kn5000_original_roms/kn5000

# Output ROM set location (MAME-ready)
ROMSET_BASE := /mnt/shared/custom_kn5000_roms/anotherworld
ROMSET_DIR := $(ROMSET_BASE)/kn5000

# Files to copy from original ROM set (all required for MAME kn5000 driver)
ORIGINAL_ROM_FILES := \
	kn5000_subcpu_boot.ic30 \
	kn5000_subprogram_v142.rom \
	kn5000_table_data_rom_even.ic3 \
	kn5000_table_data_rom_odd.ic1 \
	kn5000_rhythm_data_rom.ic14 \
	kn5000_waveform_rom.ic307 \
	kn5000_custom_data_rom.ic19

# The program ROM that gets replaced with our custom build
PROGRAM_ROM_NAME := kn5000_v10_program.rom

# =============================================================================
# Default target - build everything including ROM set
# =============================================================================
.PHONY: all
all: romset
	@echo ""
	@echo "Build complete! (TARGET=$(TARGET))"
	@echo "ROM set ready at: $(ROMSET_DIR)/"
	@echo "Test with: make test"

# =============================================================================
# Convenience targets for specific build modes
# =============================================================================
.PHONY: maincpu extension
maincpu:
	$(MAKE) all TARGET=maincpu

extension:
	$(MAKE) all TARGET=extension

# =============================================================================
# Build custom ROM only (no ROM set creation)
# =============================================================================
.PHONY: build
build: $(BUILD_DIR) $(MAIN_ROM) $(MAIN_DISASM)
	@echo "Build complete: $(MAIN_ROM)"
	@echo "Symbols used:   $(SYMBOLS_USED)"
	@echo "Symbols unused: $(SYMBOLS_UNUSED)"
	@echo "Disassembly:    $(MAIN_DISASM)"

# =============================================================================
# Create build directory
# =============================================================================
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# =============================================================================
# Extract game resources from original data files
# =============================================================================
# Resource files needed by the build (all parts + screen bitmaps)
RESOURCE_DIR := src/resources
RESOURCE_STAMP := $(RESOURCE_DIR)/.extracted

.PHONY: resources
resources: $(RESOURCE_STAMP)

$(RESOURCE_STAMP): tools/extract_resources.py $(wildcard $(GAME_DATA_DIR)/memlist.bin $(GAME_DATA_DIR)/MEMLIST.BIN $(GAME_DATA_DIR)/bank* $(GAME_DATA_DIR)/BANK* $(GAME_DATA_DIR)/resource-*.bin)
	$(EXTRACT_RESOURCES) $(GAME_DATA_DIR) $(RESOURCE_DIR)
	@touch $@

# =============================================================================
# Generate bitmap assets from game resources
# =============================================================================
ASSET_FILES := src/another_world_logo.bin src/other_bitmap.bin

.PHONY: assets
assets: $(RESOURCE_STAMP)
	touch src/another_world_logo.bin
	touch src/other_bitmap.bin
	python src/resources_to_images.py src/resources/resource-0x53.bin src/another_world_logo.bin
	python src/resources_to_images.py src/resources/resource-0x49.bin src/other_bitmap.bin

src/another_world_logo.bin: $(RESOURCE_STAMP) src/resources_to_images.py
	touch src/another_world_logo.bin
	python src/resources_to_images.py src/resources/resource-0x53.bin src/another_world_logo.bin

src/other_bitmap.bin: $(RESOURCE_STAMP) src/resources_to_images.py
	touch src/other_bitmap.bin
	python src/resources_to_images.py src/resources/resource-0x49.bin src/other_bitmap.bin

# =============================================================================
# Build main program ROM
# =============================================================================
# Symbol/listing file output (ASL listing with symbol table)
LISTING_FILE := $(BUILD_DIR)/main.listing
SYMBOLS_USED := $(BUILD_DIR)/symbols.used
SYMBOLS_UNUSED := $(BUILD_DIR)/symbols.unused

$(BUILD_DIR)/main.p: $(MAIN_SRC) $(wildcard $(INCLUDE_DIR)/*.inc) $(wildcard src/*.asm) $(ASSET_FILES) | $(BUILD_DIR)
	$(ASL) $(ASL_FLAGS) $(ASL_EXTRA) -olist $(LISTING_FILE) -i $(INCLUDE_DIR) -i src -i $(DISASM_REPO) -i $(DISASM_REPO)/shared $(MAIN_SRC) -o $@
	@# Extract symbol table from listing, split into used and unused
	@grep -E "^[ *]?[A-Za-z_][A-Za-z0-9_.]* :" $(LISTING_FILE) | \
		sed 's/ *| */\n/g' | \
		grep -E " :" | \
		grep -v "^$$" | \
		sed 's/^ *//' | \
		grep -v "^\*" | \
		sort > $(SYMBOLS_USED)
	@grep -E "^[ *]?[A-Za-z_][A-Za-z0-9_.]* :" $(LISTING_FILE) | \
		sed 's/ *| */\n/g' | \
		grep -E " :" | \
		grep -v "^$$" | \
		sed 's/^ *//' | \
		grep "^\*" | \
		sed 's/^\*//' | \
		sort > $(SYMBOLS_UNUSED)
	@echo "Symbols: $$(wc -l < $(SYMBOLS_USED)) used, $$(wc -l < $(SYMBOLS_UNUSED)) unused"

$(MAIN_ROM): $(BUILD_DIR)/main.p
	$(P2BIN) $< $@ $(P2BIN_RANGE) -l 0xFF
	@# Verify ROM size
	@SIZE=$$(stat -c%s "$@" 2>/dev/null || stat -f%z "$@" 2>/dev/null); \
	if [ "$$SIZE" -lt $(ROM_SIZE) ]; then \
		echo "Padding ROM to $(ROM_SIZE) bytes..."; \
		dd if=/dev/zero bs=1 count=$$(($(ROM_SIZE) - $$SIZE)) 2>/dev/null | tr '\0' '\377' >> $@; \
	fi
	@echo "ROM size: $$(stat -c%s "$@" 2>/dev/null || stat -f%z "$@" 2>/dev/null) bytes"

# =============================================================================
# Generate reference disassembly using MAME's unidasm
# =============================================================================
$(MAIN_DISASM): $(MAIN_ROM)
	@echo "Generating reference disassembly..."
	$(UNIDASM) $< -arch tlcs900 -basepc 0xE00000 > $@

# =============================================================================
# Create complete MAME ROM set
# =============================================================================
.PHONY: romset
romset: $(MAIN_ROM)
	@echo "Creating MAME ROM set at $(ROMSET_DIR)/"
	@# Create ROM set directory
	mkdir -p $(ROMSET_DIR)
	@# Copy original ROM files
	@for rom in $(ORIGINAL_ROM_FILES); do \
		if [ -f "$(ORIGINAL_ROMS)/$$rom" ]; then \
			cp "$(ORIGINAL_ROMS)/$$rom" "$(ROMSET_DIR)/"; \
			echo "  Copied: $$rom"; \
		else \
			echo "  WARNING: Missing original ROM: $$rom"; \
		fi; \
	done
	@# Copy our custom ROM as the program ROM
	cp $(MAIN_ROM) $(ROMSET_DIR)/$(PROGRAM_ROM_NAME)
	@echo "  Installed: $(PROGRAM_ROM_NAME) (custom build)"
	@# Show ROM set contents
	@echo ""
	@echo "ROM set contents:"
	@ls -la $(ROMSET_DIR)/

# =============================================================================
# Clean build artifacts
# =============================================================================
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
	rm -f $(ASSET_FILES)
	rm -f $(RESOURCE_STAMP)
	@echo "Clean complete (ROM set at $(ROMSET_DIR) preserved, resources kept)"

# Full clean including ROM set
.PHONY: distclean
distclean: clean
	rm -rf $(ROMSET_BASE)
	@echo "ROM set removed"

# =============================================================================
# Test in MAME
# =============================================================================
.PHONY: test
test: romset
	@echo ""
	@echo "Running MAME with custom ROM set..."
	@echo "ROM path: $(ROMSET_BASE)"
	@echo ""
	mame kn5000 -rompath $(ROMSET_BASE)

# Non-interactive test (just verify ROM loads)
.PHONY: test-verify
test-verify: romset
	@echo "Verifying ROM set with MAME..."
	mame kn5000 -rompath $(ROMSET_BASE) -verifyroms

# =============================================================================
# Development helpers
# =============================================================================

# Show hex dump of ROM
.PHONY: hexdump
hexdump: $(MAIN_ROM)
	hexdump -C $(MAIN_ROM) | head -100

# Show reset vector area
.PHONY: showvector
showvector: $(MAIN_ROM)
	@echo "Reset vector area (0xFFFEE0 = offset 0x1FFEE0):"
	hexdump -C $(MAIN_ROM) -s 0x1FFEE0 -n 32

# Verify assembler is available
.PHONY: check
check:
	@echo "Checking build tools..."
	@if [ -x "$(ASL)" ]; then \
		echo "  ASL: $(ASL)"; \
		$(ASL) -version 2>&1 | head -1 | sed 's/^/    /'; \
	else \
		echo "  ERROR: ASL not found at $(ASL)"; \
		exit 1; \
	fi
	@if [ -x "$(P2BIN)" ]; then \
		echo "  P2BIN: $(P2BIN)"; \
	else \
		echo "  ERROR: P2BIN not found at $(P2BIN)"; \
		exit 1; \
	fi
	@echo ""
	@echo "Checking original ROMs..."
	@if [ -d "$(ORIGINAL_ROMS)" ]; then \
		echo "  Original ROM directory: $(ORIGINAL_ROMS)"; \
		for rom in $(ORIGINAL_ROM_FILES); do \
			if [ -f "$(ORIGINAL_ROMS)/$$rom" ]; then \
				echo "    OK: $$rom"; \
			else \
				echo "    MISSING: $$rom"; \
			fi; \
		done; \
	else \
		echo "  ERROR: Original ROM directory not found: $(ORIGINAL_ROMS)"; \
		exit 1; \
	fi

# =============================================================================
# Help
# =============================================================================
.PHONY: help
help:
	@echo "KN5000 Custom ROM Build System (Another World VM)"
	@echo ""
	@echo "Build targets:"
	@echo "  make          - Build maincpu ROM and create MAME ROM set (default)"
	@echo "  make maincpu  - Build as standalone main CPU ROM (2MB, for MAME)"
	@echo "  make extension- Build as HDAE5000 extension board ROM (512KB)"
	@echo "  make build    - Build custom ROM only (current TARGET)"
	@echo ""
	@echo "Other targets:"
	@echo "  make resources- Extract game resources from $(GAME_DATA_DIR)"
	@echo "  make romset   - Create complete MAME ROM set"
	@echo "  make test     - Run in MAME emulator"
	@echo "  make clean    - Remove build artifacts (preserves ROM set and resources)"
	@echo "  make distclean- Remove everything including ROM set"
	@echo "  make check    - Verify build tools and original ROMs"
	@echo "  make help     - Show this help"
	@echo ""
	@echo "Current TARGET: $(TARGET)"
	@echo ""
	@echo "Output locations:"
	@echo "  Build:   $(BUILD_DIR)/"
	@echo "  ROM set: $(ROMSET_DIR)/"
	@echo ""
	@echo "The ROM set can be used with MAME:"
	@echo "  mame kn5000 -rompath $(ROMSET_BASE)"
