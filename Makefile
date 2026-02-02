# =============================================================================
# Makefile - Custom KN5000 ROM Build System
# =============================================================================
# Build custom ROMs for the Technics KN5000 keyboard.
#
# Targets:
#   make          - Build all ROMs
#   make clean    - Remove build artifacts
#   make test     - Run in MAME emulator (requires mame in PATH)
#
# Requirements:
#   - ASL Macro Assembler (asl) and p2bin in ../tools/asl/
#   - MAME with kn5000 driver (for testing)
# =============================================================================

# Tool paths (relative to project root)
ASL_PATH := ../tools/asl
ASL := $(ASL_PATH)/asl
P2BIN := $(ASL_PATH)/p2bin

# Assembler flags
ASL_FLAGS := -w -q

# Output directory
BUILD_DIR := build

# Source files
MAIN_SRC := src/main.asm
INCLUDE_DIR := src/includes

# Output files
MAIN_ROM := $(BUILD_DIR)/custom_program.rom

# ROM size (2MB for program ROM)
ROM_SIZE := 2097152

# =============================================================================
# Default target
# =============================================================================
.PHONY: all
all: $(BUILD_DIR) $(MAIN_ROM)
	@echo "Build complete: $(MAIN_ROM)"

# =============================================================================
# Create build directory
# =============================================================================
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# =============================================================================
# Build main program ROM
# =============================================================================
$(BUILD_DIR)/main.p: $(MAIN_SRC) $(wildcard $(INCLUDE_DIR)/*.inc) | $(BUILD_DIR)
	$(ASL) $(ASL_FLAGS) -i $(INCLUDE_DIR) $(MAIN_SRC) -o $@

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
# Clean build artifacts
# =============================================================================
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
	@echo "Clean complete"

# =============================================================================
# Test in MAME (requires MAME with kn5000 driver)
# =============================================================================
.PHONY: test
test: $(MAIN_ROM)
	@echo "To test in MAME, copy $(MAIN_ROM) to your MAME roms/kn5000 directory"
	@echo "and rename appropriately, or use MAME's -rompath option."
	@echo ""
	@echo "Example: mame kn5000 -rompath $(BUILD_DIR)"

# =============================================================================
# Development helpers
# =============================================================================

# Show disassembly (requires objdump or similar)
.PHONY: disasm
disasm: $(MAIN_ROM)
	hexdump -C $(MAIN_ROM) | head -100

# List symbols from the .p file
.PHONY: symbols
symbols: $(BUILD_DIR)/main.p
	@echo "Symbols in $(BUILD_DIR)/main.p:"
	@$(P2BIN) -l 0xFF $(BUILD_DIR)/main.p /dev/null 2>&1 | head -50

# Verify assembler is available
.PHONY: check
check:
	@if [ -x "$(ASL)" ]; then \
		echo "ASL found: $(ASL)"; \
		$(ASL) -version 2>&1 | head -1; \
	else \
		echo "ERROR: ASL not found at $(ASL)"; \
		exit 1; \
	fi
	@if [ -x "$(P2BIN)" ]; then \
		echo "P2BIN found: $(P2BIN)"; \
	else \
		echo "ERROR: P2BIN not found at $(P2BIN)"; \
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
	@echo "  make        - Build all ROMs"
	@echo "  make clean  - Remove build artifacts"
	@echo "  make test   - Show instructions for testing in MAME"
	@echo "  make check  - Verify build tools are available"
	@echo "  make disasm - Show hex dump of ROM"
	@echo "  make help   - Show this help"
	@echo ""
	@echo "Output:"
	@echo "  $(MAIN_ROM)"
