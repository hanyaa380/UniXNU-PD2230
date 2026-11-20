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

    .payload : ALIGN(16) {
        _payload = .;
        *(.payload)
    }

    .payload2 : ALIGN(16) {
        _fat_payload = .;
        *(.payload2)
    }

    /DISCARD/ : {
        *(.note.GNU-stack)
        *(.comment)
        *(.ARM.attributes)
    }
}
