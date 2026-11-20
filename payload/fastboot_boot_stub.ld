OUTPUT_FORMAT("elf32-littlearm")
OUTPUT_ARCH(arm)
ENTRY(fastboot_boot_stub)

SECTIONS
{
    . = 0x4829a07c;
    .text : {
        *(.text*)
        *(.rodata*)
    }

    /DISCARD/ : {
        *(.note.GNU-stack)
        *(.comment)
        *(.ARM.attributes)
    }
}
