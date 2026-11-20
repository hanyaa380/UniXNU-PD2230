/*
 * Minimal AArch64 entry glue for the iQOO Z7i environment probe.
 * ATF enters here with MMU/caches disabled and a device-tree argument in x0.
 */

    .arch armv8-a
    .section .text.start, "ax"
    .align 12
    .global _start
    .type _start, %function
_start:
    mov     x19, x0
    movz    x0, #0x0000
    movk    x0, #0x4010, lsl #16  /* private probe stack */
    mov     sp, x0
    mov     x0, x19
    bl      probe_main
1:
    wfe
    b       1b
    .size _start, .-_start

    .section .note.GNU-stack, "", %progbits
