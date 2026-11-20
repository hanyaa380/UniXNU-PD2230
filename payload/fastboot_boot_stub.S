/*
 * iQOO Z7i (MT6833) fastboot boot command.
 *
 * The stock fastboot_init() registers "ultraflash:" with its final BL at
 * LK+0x2c57e. That call is redirected here. We perform the displaced call,
 * then register the missing "boot" command.
 *
 * The handler accepts either:
 *   - a standard Android v2 boot image with an uncompressed kernel; or
 *   - a small RAWBOOT! container for BootShim/UEFI payloads:
 *       "RAWBOOT!" (8 bytes)
 *       u32 load_addr
 *       u32 entry (0 = load_addr)
 *       u32 dtb_addr
 *       u32 payload_size
 *       payload bytes
 *
 * The payload is copied to its physical load address, cleaned from D-cache,
 * and handed to LK's own lk_jump64() path (SMC 0x82000115).
 */

    .syntax unified
    .cpu cortex-a53
    .thumb

    .section .text, "ax"
    .align 2
    .global fastboot_boot_stub
    .thumb_func
    .type fastboot_boot_stub, %function
fastboot_boot_stub:
    /* Preserve the displaced ultraflash: registration arguments and LR. */
    push    {r0-r4, lr}
    movw    r12, #0xb96d
    movt    r12, #0x4822
    blx     r12

    adr     r0, boot_name
    adr     r1, boot_handler
    movs    r2, #1              /* allowed when security is on */
    movs    r3, #0              /* allowed while locked */
    movw    r12, #0xb96d
    movt    r12, #0x4822
    blx     r12

    pop     {r0-r4, pc}
    .size fastboot_boot_stub, .-fastboot_boot_stub

    .global boot_handler
    .thumb_func
    .type boot_handler, %function
boot_handler:
    push    {r4-r11, lr}
    sub     sp, sp, #8
    mov     r4, r0
    mov     r5, r1
    mov     r6, r2

    cmp     r5, #0
    beq     no_data
    cmp     r6, #8
    blo     bad_size

    /* RAWBOOT! */
    ldr     r0, [r5]
    movw    r1, #0x4152
    movt    r1, #0x4257
    cmp     r0, r1
    bne     try_android
    ldr     r0, [r5, #4]
    movw    r1, #0x4f4f
    movt    r1, #0x2154
    cmp     r0, r1
    beq     rawboot

try_android:
    /* ANDROID! */
    ldr     r0, [r5]
    movw    r1, #0x4e41
    movt    r1, #0x5244
    cmp     r0, r1
    bne     bad_magic
    ldr     r0, [r5, #4]
    movw    r1, #0x494f
    movt    r1, #0x2144
    cmp     r0, r1
    bne     bad_magic
    b       android_boot

rawboot:
    cmp     r6, #24
    blo     bad_size

    ldr     r8, [r5, #8]        /* load address */
    ldr     r9, [r5, #12]       /* entry */
    ldr     r10, [r5, #16]      /* DTB */
    ldr     r11, [r5, #20]      /* payload size */

    cmp     r8, #0
    beq     bad_address
    cmp     r9, #0
    bne     1f
    mov     r9, r8
1:
    subs    r3, r6, #24
    cmp     r11, r3
    bhi     bad_size
    cmp     r11, #0
    beq     bad_size

    /* Never overwrite the running LK image. */
    ldr     r3, =0x48200000
    cmp     r8, r3
    blo     2f
    ldr     r3, =0x48700000
    cmp     r8, r3
    blo     bad_address
2:
    add     r7, r5, #24
    mov     r0, r8
    mov     r1, r7
    mov     r2, r11
    bl      copy_bytes

    mov     r0, r8
    mov     r1, r11
    bl      clean_cache_range
    bl      disable_watchdog

    adr     r0, raw_log
    mov     r1, r9
    mov     r2, r10
    mov     r3, r11
    bl      printf_lk

    mov     r0, r9
    mov     r1, r10
    movs    r2, #0
    movs    r3, #1
    bl      jump64
    b       jump_returned

android_boot:
    cmp     r6, #0x30
    blo     bad_size

    movw    r0, #0x28
    ldr     r0, [r5, r0]       /* header version */
    cmp     r0, #2
    bne     bad_size

    ldr     r10, [r5, #8]       /* kernel size */
    ldr     r8, [r5, #12]       /* kernel address */
    ldr     r0, [r5, #16]       /* ramdisk size */
    str     r0, [sp, #0]
    ldr     r4, [r5, #20]       /* ramdisk address */
    ldr     r11, [r5, #0x24]    /* page size */

    cmp     r0, #0
    beq     bad_size
    cmp     r10, #0
    beq     bad_size
    cmp     r8, #0
    beq     bad_address
    cmp     r4, #0
    beq     bad_address

    cmp     r11, #0x200
    blo     bad_page
    ldr     r3, =0x10000
    cmp     r11, r3
    bhi     bad_page
    sub     r3, r11, #1
    tst     r3, r11
    bne     bad_page

    /* page + kernel + ramdisk must be inside the download. */
    add     r3, r11, r10
    ldr     r0, [sp, #0]
    add     r3, r3, r0
    cmp     r3, r6
    bhi     bad_size

    /* Reject overlapping kernel and ramdisk destination ranges. */
    add     r0, r8, r10
    cmp     r0, r4
    bls     3f
    ldr     r0, [sp, #0]
    add     r0, r4, r0
    cmp     r0, r8
    bls     3f
    b       bad_address
3:
    add     r7, r5, r11
    ldrb    r0, [r7]
    cmp     r0, #0x1f
    bne     5f
    ldrb    r0, [r7, #1]
    cmp     r0, #0x8b
    beq     compressed_kernel
5:
    mov     r0, r8
    mov     r1, r7
    mov     r2, r10
    bl      copy_bytes

    mov     r0, r8
    mov     r1, r10
    bl      clean_cache_range

    /* Ramdisk starts after the page-aligned kernel segment. */
    sub     r0, r11, #1
    add     r7, r10, r0
    bic     r7, r7, r0
    add     r7, r7, r11
    add     r1, r5, r7
    ldr     r2, [sp, #0]
    mov     r0, r4
    bl      copy_bytes

    mov     r0, r4
    ldr     r1, [sp, #0]
    bl      clean_cache_range

    /* The tags address in an Android header is the DTB destination. */
    ldr     r9, [r5, #0x20]
    cmp     r9, #0
    bne     4f
    ldr     r9, =0x47c80000
4:
    /* DTB starts after the page-aligned ramdisk segment. */
    sub     r0, r11, #1
    ldr     r2, [sp, #0]
    add     r2, r2, r0
    bic     r2, r2, r0
    add     r7, r7, r2

    movw    r0, #0x670
    ldr     r2, [r5, r0]        /* v2 dtb_size */
    cmp     r2, #0
    beq     android_jump
    str     r2, [sp, #4]

    add     r1, r5, r7          /* DTB source */
    add     r0, r1, r2
    add     r3, r5, r6          /* download end */
    cmp     r0, r3
    bhi     android_jump

    mov     r0, r9
    bl      copy_bytes
    mov     r0, r9
    ldr     r1, [sp, #4]
    bl      clean_cache_range
    b       android_jump_dtb

android_jump:
    movs    r9, #0
android_jump_dtb:
    bl      disable_watchdog
    adr     r0, android_log
    mov     r1, r8
    mov     r2, r9
    mov     r3, r10
    bl      printf_lk

    mov     r0, r8
    mov     r1, r9
    movs    r2, #0
    movs    r3, #1
    bl      jump64

jump_returned:
    mov     r1, r0
    adr     r0, returned_log
    bl      printf_lk
    mov     r0, #-4
    b       out

no_data:
    adr     r0, no_data_log
    b       print_and_fail
bad_magic:
    adr     r0, bad_magic_log
    b       print_and_fail
bad_size:
    adr     r0, bad_size_log
    b       print_and_fail
bad_page:
    adr     r0, bad_page_log
    b       print_and_fail
bad_address:
    adr     r0, bad_address_log
    b       print_and_fail
compressed_kernel:
    adr     r0, compressed_log
print_and_fail:
    bl      printf_lk
    mov     r0, #-3
out:
    add     sp, sp, #8
    pop     {r4-r11, pc}
    .size boot_handler, .-boot_handler

    .thumb_func
    .type copy_bytes, %function
copy_bytes:
    /* r0=dst, r1=src, r2=len */
1:
    cmp     r2, #4
    blo     2f
    ldr     r3, [r1], #4
    str     r3, [r0], #4
    subs    r2, r2, #4
    b       1b
2:
    cbz     r2, 4f
3:
    ldrb    r3, [r1], #1
    strb    r3, [r0], #1
    subs    r2, r2, #1
    bne     3b
4:
    bx      lr
    .size copy_bytes, .-copy_bytes

    .thumb_func
    .type clean_cache_range, %function
clean_cache_range:
    /* LK+0x23010: clean D-cache for a range, then invalidate I-cache. */
    push    {r4, lr}
    movw    r12, #0x3010
    movt    r12, #0x4822
    blx     r12
    pop     {r4, pc}
    .size clean_cache_range, .-clean_cache_range

    .thumb_func
    .type disable_watchdog, %function
disable_watchdog:
    /*
     * MT6833 TOPRGU watchdog.  Kick it once and clear the enable bit while
     * preserving the rest of MODE.  The AArch64 payload repeats this after
     * entry, but doing it in LK also covers firmware that trips the watchdog
     * while entering the non-secure 64-bit image.
     */
    movw    r12, #0x7000
    movt    r12, #0x1000
    movw    r3, #0x1971
    str     r3, [r12, #8]
    ldr     r3, [r12]
    bic     r3, r3, #1
    movw    r2, #0x0000
    movt    r2, #0x2200
    orr     r3, r3, r2
    str     r3, [r12]
    dsb     sy
    isb     sy
    bx      lr
    .size disable_watchdog, .-disable_watchdog

    .thumb_func
    .type printf_lk, %function
printf_lk:
    push    {r4, lr}
    movw    r12, #0x9101
    movt    r12, #0x4823
    blx     r12
    pop     {r4, pc}
    .size printf_lk, .-printf_lk

    .thumb_func
    .type jump64, %function
jump64:
    /* LK+0x27cf8: lk_jump64(entry, dtb, 0, 1), via SMC 0x82000115. */
    push    {r4, lr}
    movw    r12, #0x7cf9
    movt    r12, #0x4822
    blx     r12
    pop     {r4, pc}
    .size jump64, .-jump64

    .align 2
boot_name:
    .asciz "boot"

no_data_log:
    .asciz "kaeru: boot: no downloaded image\n"
bad_magic_log:
    .asciz "kaeru: boot: expected ANDROID! or RAWBOOT!\n"
bad_size_log:
    .asciz "kaeru: boot: invalid image size\n"
bad_page_log:
    .asciz "kaeru: boot: invalid boot-image page size\n"
bad_address_log:
    .asciz "kaeru: boot: unsafe load address\n"
compressed_log:
    .asciz "kaeru: boot: compressed kernel is unsupported\n"
raw_log:
    .asciz "kaeru: RAWBOOT entry=0x%x dtb=0x%x size=0x%x\n"
android_log:
    .asciz "kaeru: Android entry=0x%x dtb=0x%x kernel=0x%x\n"
returned_log:
    .asciz "kaeru: lk_jump64 returned %d\n"

    .section .note.GNU-stack, "", %progbits
