RISCV        ?= /opt/riscv
CROSS        ?= $(RISCV)/bin/riscv64-unknown-elf-
CC           := $(CROSS)gcc
OBJDUMP      := $(CROSS)objdump

TARGET := skiptrap
SRC    := $(TARGET).S

# Ibex Simple System runs from 0x100080 and expects writes to 0x20008.
# Use the same memory map as examples/sw/simple_system by linking their script.
LDSCRIPT := $(abspath ../../examples/sw/simple_system/common/link.ld)

# RV32IMCF + Zicsr to let us assemble FP ops; if core lacks F, they trap.
ARCH    := -march=rv32imcf_zicsr_zaamo -mabi=ilp32 -mcmodel=medany
CFLAGS  := $(ARCH) -nostdlib -nostartfiles -ffreestanding -static -Os -g
LDFLAGS := -T $(LDSCRIPT) -Wl,--no-gc-sections -Wl,--build-id=none

.PHONY: all clean

all: $(TARGET).elf $(TARGET).dump

$(TARGET).elf: $(SRC)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

$(TARGET).dump: $(TARGET).elf
	$(OBJDUMP) -d -S -x -M no-aliases $< > $@

clean:
	$(RM) $(TARGET).elf $(TARGET).dump
