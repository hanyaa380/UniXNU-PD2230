/*
 * iQOO Z7i cold-boot UEFI loader.
 *
 * LK decompresses this stage0 at 0x40080000.  The loader clears the display
 * to black, copies the linked 2 MiB UEFI FD to 0x50000000, then enters the
 * FD.  The FAT payload is either embedded after the FD or loaded separately
 * by LK at the boot header's ramdisk address (0x51100000).
 */

#define FB_BASE        0x77780000
#define FB_PITCH       736
#define FB_HEIGHT      1600
#define FB_HANDOFF     0x47D00000
#define FB_PAGE_MAP    0x47D00100
#define FB_LOGICAL_SIZE 0x47E000
#define FB_PAGE_COUNT  0x47E
#define EMBEDDED_BASE  0x52000000
#define RAMDISK_BASE   0x51100000
#define FAT_OEM_OFFSET 3
#ifndef PAYLOAD_SIZE
#define PAYLOAD_SIZE   0x01000000
#endif
#define UEFI_BASE      0x50000000
#define UEFI_SIZE      0x00200000

    .arch armv8-a
    .section .text.start, "ax"
    .align 12
    .global _start
    .type _start, %function
_start:
    mov     x19, x0

    /* Disable the MT6833 TOPRGU watchdog. */
    movz    x0, #0x7000
    movk    x0, #0x1000, lsl #16
    movz    w1, #0x1971
    str     w1, [x0, #8]
    movz    w1, #0x0000
    movk    w1, #0x2200, lsl #16
    str     w1, [x0]

    /* Clear the display to black. */
    movz    x9, #0x0000
    movk    x9, #0x7778, lsl #16
    mov     w10, #0x0000
    movk    w10, #0xff00, lsl #16
    movz    x11, #0xf800
    movk    x11, #0x0011, lsl #16
1:
    str     w10, [x9], #4
    subs    x11, x11, #1
    b.ne    1b
    dsb     sy

#ifdef PAINT_AND_HALT
    /* Diagnostic: prove LK reached the decompressed stage0 entry point. */
    movz    x9, #0x0000
    movk    x9, #0x7778, lsl #16
    movz    w10, #0xff00
    movk    w10, #0xff00, lsl #16
    movz    x11, #0xf800
    movk    x11, #0x0011, lsl #16
8:
    str     w10, [x9], #4
    subs    x11, x11, #1
    b.ne    8b
    dsb     sy
9:
    wfe
    b       9b
#endif

#ifdef VALIDATE_RAMDISK
    /*
     * The payload generator writes "MTOO4043" as the FAT OEM name.  If this
     * signature is absent, LK did not copy the ramdisk to its advertised
     * address; paint the screen red and stop before publishing a bogus disk.
     */
    movz    x9, #0x0000
    movk    x9, #0x5110, lsl #16
    ldr     w11, [x9, #FAT_OEM_OFFSET]
    movz    w12, #0x544d
    movk    w12, #0x4f4f, lsl #16
    cmp     w11, w12
    b.eq    4f

    movz    x9, #0x0000
    movk    x9, #0x7778, lsl #16
    mov     w10, #0x001f
    movk    w10, #0xf8ff, lsl #16
    movz    x11, #0xf800
    movk    x11, #0x0011, lsl #16
6:
    str     w10, [x9], #4
    subs    x11, x11, #1
    b.ne    6b
    dsb     sy
7:
    wfe
    b       7b
4:
#endif

#ifdef HALT_AFTER_VALIDATE
    /* Diagnostic: ramdisk signature validation completed. */
    movz    x9, #0x0000
    movk    x9, #0x7778, lsl #16
    movz    w10, #0xff00
    movk    w10, #0xffff, lsl #16
    movz    x11, #0xf800
    movk    x11, #0x0011, lsl #16
13:
    str     w10, [x9], #4
    subs    x11, x11, #1
    b.ne    13b
    dsb     sy
14:
    wfe
    b       14b
#endif

    /*
     * Publish an early framebuffer handoff and identity run map so the UEFI
     * SerialPortLib can render DEBUG text before CamelliaBootMemoryDxe runs.
     */
    movz    x12, #0x0000
    movk    x12, #0x47d0, lsl #16

    movz    x13, #0x4555
    movk    x13, #0x4649, lsl #16
    movk    x13, #0x4246, lsl #32
    movk    x13, #0x3130, lsl #48
    str     x13, [x12, #0]
    movz    x13, #0x0000
    movk    x13, #0x7778, lsl #16
    str     x13, [x12, #8]
    mov     w13, #720
    str     w13, [x12, #16]
    mov     w13, #1600
    str     w13, [x12, #20]
    movz    w13, #0x0b80
    str     w13, [x12, #24]
    mov     w13, #32
    str     w13, [x12, #28]

    add     x14, x12, #0x100
    movz    x13, #0x5545
    movk    x13, #0x4946, lsl #16
    movk    x13, #0x5046, lsl #32
    movk    x13, #0x314d, lsl #48
    str     x13, [x14, #0]
    movz    x13, #0xe000
    movk    x13, #0x0047, lsl #16
    str     x13, [x14, #8]
    movz    w13, #0x1000
    str     w13, [x14, #16]
    mov     w13, #1
    str     w13, [x14, #20]
    movz    x13, #0x0000
    movk    x13, #0x7778, lsl #16
    str     x13, [x14, #24]
    movz    w13, #0x047e
    str     w13, [x14, #32]
    str     wzr, [x14, #36]
    dsb     sy

    /* Copy the FD out of the image without source/destination overlap. */
    adr     x4, _payload
    movz    x20, #0x0000
    movk    x20, #0x5000, lsl #16
    mov     x5, x20
    movz    x6, #0x0000
    movk    x6, #0x0020, lsl #16
2:
    ldp     x7, x8, [x4], #16
    stp     x7, x8, [x5], #16
    subs    x6, x6, #16
    b.ne    2b
    dsb     sy
    isb

#ifdef EMBEDDED_PAYLOAD
    /* Copy the embedded FAT payload to reserved DRAM. */
    adrp    x4, _fat_payload
    add     x4, x4, :lo12:_fat_payload
    movz    x5, #(EMBEDDED_BASE & 0xffff)
    movk    x5, #((EMBEDDED_BASE >> 16) & 0xffff), lsl #16
    movz    x6, #(PAYLOAD_SIZE & 0xffff)
    movk    x6, #((PAYLOAD_SIZE >> 16) & 0xffff), lsl #16
    movk    x6, #((PAYLOAD_SIZE >> 32) & 0xffff), lsl #32
    movk    x6, #((PAYLOAD_SIZE >> 48) & 0xffff), lsl #48
10:
    ldp     x7, x8, [x4], #16
    stp     x7, x8, [x5], #16
    subs    x6, x6, #16
    b.ne    10b
    dsb     sy
#endif

    /*
     * Publish the FAT payload handoff consumed by CamelliaUniXNULoaderDxe.
     */
    movz    x15, #0x0800
    movk    x15, #0x47d0, lsl #16
    movz    x13, #0x4555
    movk    x13, #0x4946, lsl #16
    movk    x13, #0x4152, lsl #32
    movk    x13, #0x314d, lsl #48
    str     x13, [x15, #0]
#ifdef EMBEDDED_PAYLOAD
    movz    x13, #(EMBEDDED_BASE & 0xffff)
    movk    x13, #((EMBEDDED_BASE >> 16) & 0xffff), lsl #16
#else
    movz    x13, #0x0000
    movk    x13, #0x5110, lsl #16
#endif
    str     x13, [x15, #8]
    movz    x13, #(PAYLOAD_SIZE & 0xffff)
    movk    x13, #((PAYLOAD_SIZE >> 16) & 0xffff), lsl #16
    movk    x13, #((PAYLOAD_SIZE >> 32) & 0xffff), lsl #32
    movk    x13, #((PAYLOAD_SIZE >> 48) & 0xffff), lsl #48
    str     x13, [x15, #16]
    movz    w13, #512
    str     w13, [x15, #24]
    str     wzr, [x15, #28]

#ifdef HALT_AFTER_FD_COPY
    /* Diagnostic: UEFI FD, ramdisk handoff and payload are now prepared. */
    movz    x9, #0x0000
    movk    x9, #0x7778, lsl #16
    movz    w10, #0xffff
    movk    w10, #0xff00, lsl #16
    movz    x11, #0xf800
    movk    x11, #0x0011, lsl #16
11:
    str     w10, [x9], #4
    subs    x11, x11, #1
    b.ne    11b
    dsb     sy
12:
    wfe
    b       12b
#endif

    ic      iallu
    dsb     sy
    isb

    mov     x0, x19
    br      x20
    .size _start, .-_start

    .section .note.GNU-stack, "", %progbits
