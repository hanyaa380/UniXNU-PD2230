OUTPUT_FORMAT("elf64-littleaarch64")
OUTPUT_ARCH(aarch64)
ENTRY(_start)

SECTIONS
{
    . = 0x40080000;

    .text : {
        *(.text.start)
        *(.text*)
    }

    /DISCARD/ : {
        *(.note.GNU-stack)
        *(.comment)
        *(.ARM.attributes)
    }
}
