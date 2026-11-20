/*
 * Positive-control payload for the iQOO Z7i boot-partition path.
 *
 * If the stock LK actually transfers control here, TOPRGU software reset
 * should reboot the phone within seconds instead of the ~30 second timeout.
 */

    .arch armv8-a
    .section .text.start, "ax"
    .align 12
    .global _start
    .type _start, %function
_start:
    movz    x0, #0x7000
    movk    x0, #0x1000, lsl #16

    movz    w1, #0x1971
    str     w1, [x0, #8]

    movz    w1, #0x0014
    movk    w1, #0x2200, lsl #16
    str     w1, [x0]

    movz    w1, #0x1209
    str     w1, [x0, #0x14]

    dsb     sy
1:
    wfi
    b       1b
    .size _start, .-_start

    .section .note.GNU-stack, "", %progbits
