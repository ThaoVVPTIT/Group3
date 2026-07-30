# Makefile tối giản để biên dịch main.c + start.S cho PicoRV32

CC = /opt/riscv/bin/riscv32-unknown-elf-gcc
LD = /opt/riscv/bin/riscv32-unknown-elf-ld
OBJCOPY = /opt/riscv/bin/riscv32-unknown-elf-objcopy
OBJDUMP = /opt/riscv/bin/riscv32-unknown-elf-objdump
PYTHON = python3

# Biên dịch tối ưu dung lượng (-Os), cho tập lệnh RV32I tiêu chuẩn
OPTS = -Os -march=rv32im -mabi=ilp32 -g

all: firmware.mif

firmware.mif: start.o main.o
	$(CC) $(OPTS) -ffreestanding -nostdlib -o firmware.elf -T sections.lds start.o main.o -lgcc
	$(OBJCOPY) -O binary firmware.elf firmware.bin
	$(OBJDUMP) -d firmware.elf > firmware.s.txt
	$(PYTHON) makehex.py firmware.bin 32768 . > firmware.mif
	@echo "=========================================================="
	@echo " Biên dịch thành công! Copy file firmware.mif ra thư mục"
	@echo " chứa file prv32_top.v của Quartus để nạp vào FPGA."
	@echo "=========================================================="

start.o: start.S custom_ops.S
	$(CC) $(OPTS) -c start.S -o start.o

main.o: main.c
	$(CC) $(OPTS) -c main.c -o main.o

clean:
	rm -f *.o *.elf *.bin *.s.txt *.mif *.hex
