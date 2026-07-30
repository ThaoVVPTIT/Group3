RISCV_TOOLCHAIN_DIR = /opt/riscv/bin
GCC = $(RISCV_TOOLCHAIN_DIR)/riscv32-unknown-elf-gcc
OBJ_DUMP = $(RISCV_TOOLCHAIN_DIR)/riscv32-unknown-elf-objdump
OBJ_COPY = $(RISCV_TOOLCHAIN_DIR)/riscv32-unknown-elf-objcopy

MEM_SIZE = 8192
COMMON_FLAGS = -mabi=ilp32 -march=rv32i -ffreestanding -nostdlib

.PHONY: all clean

all: firmware.hex dumpfile

firmware.hex: firmware.bin makehex.py
	python3 makehex.py $< $(MEM_SIZE) > $@

firmware.bin: firmware.elf
	$(OBJ_COPY) -O binary $< $@

dumpfile: firmware.elf
	$(OBJ_DUMP) -d $< > $@

firmware.elf: start.o main.o sections.lds Makefile
	$(GCC) -Og $(COMMON_FLAGS) -o $@ -Wl,--build-id=none,-Bstatic,-T,sections.lds,-Map,firmware.map,--strip-debug start.o main.o -lgcc

main.o: main.c
	$(GCC) -c -I. -Iinc/ $(COMMON_FLAGS) -Og --std=c99 -o $@ $<

start.o: start.S
	$(GCC) -c $(COMMON_FLAGS) -o $@ $<

clean:
	rm -f *.o dumpfile *.elf *.hex *.bin *.map