/* ============================================================================
 * Linker script for RV32I SystemVerilog Computer
 * Target: Unprivileged RV32I Base Integer Architecture
 * Memory layout matches rv32i_pkg.sv:
 *   ROM: 0x00000000 - 0x00003FFF (16 KB)
 *   RAM: 0x10000000 - 0x1000FFFF (64 KB)
 * ============================================================================ */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 16K
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 64K
}

/* Stack top at the very end of 64KB RAM (grows downwards) */
_stack_top = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
    /* Reset vector and startup entry point placed strictly at address 0x0 */
    .text.init :
    {
        KEEP(*(.text.init))
    } > ROM

    /* General application code */
    .text :
    {
        . = ALIGN(4);
        *(.text)
        *(.text.*)
        _etext = .;
    } > ROM

    /* Read-only data stays in ROM */
    .rodata :
    {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)
        . = ALIGN(4);
        _erodata = .;
    } > ROM

    /* Initialized data: VMA in RAM, LMA in ROM */
    _sidata = LOADADDR(.data);

    .data : AT(_sidata)
    {
        . = ALIGN(4);
        _sdata = .;
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        . = ALIGN(4);
        _edata = .;
    } > RAM

    /* Uninitialized data (BSS): zeroed by crt0 at boot */
    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    /* Heap start pointer directly following BSS */
    . = ALIGN(4);
    _heap_start = .;

    /* Discard unused sections */
    /DISCARD/ :
    {
        *(.comment)
        *(.note*)
        *(.eh_frame)
    }
}
