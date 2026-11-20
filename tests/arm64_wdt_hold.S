/*
 * Minimal iQOO Z7i (MT6833) post-LK hold test.
 *
 * This deliberately performs no stack, memory, cache, or framebuffer access.
 * It only disables the MT6833 top watchdog and parks the boot CPU.  If the
 * device still resets, the failure is before or outside our payload.
 */

    .arch armv8-a
    .section .text.start, "ax"
    .align 12
    .global _start
    .type _start, %function
_start:
    movz    x0, #0x7000
    movk    x0, #0x1000, lsl #16
    movz    w1, #0x0000
    movk    w1, #0x2200, lsl #16
    str     w1, [x0]
    dsb     sy
1:
    wfi
    b       1b
    .size _start, .-_start

    .section .note.GNU-stack, "", %progbits
