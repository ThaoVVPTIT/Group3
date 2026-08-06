ENTRY(start)

/* Fixed PicoSoC memory map: 8192 words x 4 bytes = 32 KiB. */
MEMORY
{
    RAM (xrw) : ORIGIN = 0x00000000, LENGTH = 0x8000
}

_stack_top = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
    .text :
    {
        . = ALIGN(4);
        *(.text*)
        *(.rodata*)
        *(.srodata*)
        . = ALIGN(4);
        _etext = .;
    } > RAM

    .data :
    {
        . = ALIGN(4);
        _sdata = .;
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
        _edata = .;
    } > RAM

    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    . = ALIGN(4);
    _heap_start = .;

    ASSERT(_heap_start <= _stack_top,
           "Firmware exceeds the 32 KiB PicoSoC RAM")
}