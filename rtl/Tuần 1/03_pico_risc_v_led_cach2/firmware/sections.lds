/*
sections.lds - Sơ đồ phân bổ bộ nhớ cho PicoRV32 DE10-Lite (128kB RAM)
Bắt đầu từ địa chỉ 0x00000000
*/

MEMORY {
	mem : ORIGIN = 0x00000000, LENGTH = 0x00020000 /* 128 kB RAM */
}

SECTIONS {
	.memory : {
		. = 0x000000;
		start*(.text);
		*(.text);
		*(.rodata);
		*(.rodata*);
		*(.data);
		*(.bss);
		end = .;
	} > mem
}
