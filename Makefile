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

# ROM size (2MB for program ROM)
ROM_SIZE := 2097152

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
	@echo "Build complete!"
	@echo "ROM set ready at: $(ROMSET_DIR)/"
	@echo "Test with: make test"

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
# Build main program ROM
# =============================================================================
# Symbol/listing file output (ASL listing with symbol table)
LISTING_FILE := $(BUILD_DIR)/main.listing
SYMBOLS_USED := $(BUILD_DIR)/symbols.used
SYMBOLS_UNUSED := $(BUILD_DIR)/symbols.unused

$(BUILD_DIR)/main.p: $(MAIN_SRC) $(wildcard $(INCLUDE_DIR)/*.inc) $(wildcard src/*.asm) | $(BUILD_DIR)
	$(ASL) $(ASL_FLAGS) -olist $(LISTING_FILE) -i $(INCLUDE_DIR) -i src -i $(DISASM_REPO) -i $(DISASM_REPO)/shared $(MAIN_SRC) -o $@
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
	$(P2BIN) $< $@ -l 0xFF
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
	@echo "Clean complete (ROM set at $(ROMSET_DIR) preserved)"

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
	@echo "KN5000 Custom ROM Build System"
	@echo ""
	@echo "Targets:"
	@echo "  make          - Build ROM and create MAME ROM set (default)"
	@echo "  make build    - Build custom ROM only"
	@echo "  make romset   - Create complete MAME ROM set"
	@echo "  make test     - Run in MAME emulator"
	@echo "  make clean    - Remove build artifacts (preserves ROM set)"
	@echo "  make distclean- Remove everything including ROM set"
	@echo "  make check    - Verify build tools and original ROMs"
	@echo "  make help     - Show this help"
	@echo ""
	@echo "Output locations:"
	@echo "  Build:   $(BUILD_DIR)/"
	@echo "  ROM set: $(ROMSET_DIR)/"
	@echo ""
	@echo "The ROM set can be used with MAME:"
	@echo "  mame kn5000 -rompath $(ROMSET_BASE)"
