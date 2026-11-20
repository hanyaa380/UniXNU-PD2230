#!/usr/bin/env python3
"""Verify fastboot boot registration, image loading, and handoff."""

from __future__ import annotations

import os
import struct
from pathlib import Path

from liblk.image import LkImage
from unicorn import (
    Uc,
    UC_ARCH_ARM,
    UC_HOOK_CODE,
    UC_MODE_LITTLE_ENDIAN,
    UC_MODE_THUMB,
    UC_PROT_ALL,
)
from unicorn.arm_const import (
    UC_ARM_REG_LR,
    UC_ARM_REG_R0,
    UC_ARM_REG_R1,
    UC_ARM_REG_R2,
    UC_ARM_REG_R3,
    UC_ARM_REG_SP,
)


REPO = Path(__file__).resolve().parent.parent
IMAGE = Path(os.environ.get("LK_IMAGE", REPO / "dist" / "lk-bootcmd-v1.img"))
PAYLOAD = REPO / "build" / "fastboot_boot_stub.bin"
STOCK_BOOT = REPO / "boot.img"

LK_BASE = 0x48200000
PATCH_CALL = 0x4822C57E
STUB_ADDRESS = 0x4829A07C
FASTBOOT_REGISTER = 0x4822B96C
LK_PRINTF = 0x48239100
LK_CLEAN_CACHE_RANGE = 0x48223010
LK_JUMP64 = 0x48227CF8
WDT_MODE = 0x10007000

KERNEL_LOAD = 0x40000000
RAMDISK_LOAD = 0x41000000
DTB_LOAD = 0x47C80000
DOWNLOAD = 0x48910000
SCRATCH = 0x48900000
STACK = 0x48980000
SENTINEL = 0x48990000


def read_cstr(uc: Uc, address: int) -> str:
    data = bytes(uc.mem_read(address, 160))
    return data.split(b"\0", 1)[0].decode("ascii", "replace")


def make_emulator(code: bytes) -> Uc:
    uc = Uc(UC_ARCH_ARM, UC_MODE_THUMB | UC_MODE_LITTLE_ENDIAN)
    uc.mem_map(0x40000000, 0x02000000, UC_PROT_ALL)
    uc.mem_map(0x47C00000, 0x00100000, UC_PROT_ALL)
    uc.mem_map(LK_BASE, 0x00600000, UC_PROT_ALL)
    uc.mem_map(SCRATCH, 0x00200000, UC_PROT_ALL)
    uc.mem_map(WDT_MODE & ~0xFFF, 0x1000, UC_PROT_ALL)
    uc.mem_write(WDT_MODE, struct.pack("<I", 1))
    uc.mem_write(LK_BASE, code)

    # The production code intentionally uses three calling conventions here:
    # Thumb LK helpers, and LK's ARM cache-maintenance routine.
    uc.mem_write(FASTBOOT_REGISTER, b"\x70\x47")  # Thumb: bx lr
    uc.mem_write(LK_PRINTF, b"\x70\x47")  # Thumb: bx lr
    uc.mem_write(LK_CLEAN_CACHE_RANGE, b"\x1e\xff\x2f\xe1")  # ARM: bx lr
    uc.mem_write(LK_JUMP64, b"\x70\x47")  # Thumb: bx lr
    return uc


def main() -> int:
    image = LkImage(IMAGE)
    lk = image.partitions["lk"]
    code = bytes(lk.data)
    payload = PAYLOAD.read_bytes()

    cave_off = STUB_ADDRESS - LK_BASE
    if code[cave_off:cave_off + len(payload)] != payload:
        raise SystemExit("stub payload mismatch")

    registrations: list[tuple[str, int, int, int]] = []
    logs: list[str] = []
    cache_calls: list[tuple[int, int]] = []
    jumps: list[tuple[int, int, int, int]] = []

    def hook_register(uc: Uc, address: int, size: int, _: object) -> None:
        registrations.append(
            (
                read_cstr(uc, uc.reg_read(UC_ARM_REG_R0)),
                uc.reg_read(UC_ARM_REG_R1),
                uc.reg_read(UC_ARM_REG_R2),
                uc.reg_read(UC_ARM_REG_R3),
            )
        )

    def hook_printf(uc: Uc, address: int, size: int, _: object) -> None:
        logs.append(read_cstr(uc, uc.reg_read(UC_ARM_REG_R0)))

    def hook_cache(uc: Uc, address: int, size: int, _: object) -> None:
        cache_calls.append(
            (uc.reg_read(UC_ARM_REG_R0), uc.reg_read(UC_ARM_REG_R1))
        )

    def hook_jump(uc: Uc, address: int, size: int, _: object) -> None:
        jumps.append(
            tuple(
                uc.reg_read(reg)
                for reg in (
                    UC_ARM_REG_R0,
                    UC_ARM_REG_R1,
                    UC_ARM_REG_R2,
                    UC_ARM_REG_R3,
                )
            )
        )

    def stop(uc: Uc, address: int, size: int, _: object) -> None:
        uc.emu_stop()

    def new_emulator() -> Uc:
        uc = make_emulator(code)
        uc.hook_add(
            UC_HOOK_CODE,
            hook_register,
            begin=FASTBOOT_REGISTER,
            end=FASTBOOT_REGISTER,
        )
        uc.hook_add(UC_HOOK_CODE, hook_printf, begin=LK_PRINTF, end=LK_PRINTF)
        uc.hook_add(
            UC_HOOK_CODE,
            hook_cache,
            begin=LK_CLEAN_CACHE_RANGE,
            end=LK_CLEAN_CACHE_RANGE,
        )
        uc.hook_add(UC_HOOK_CODE, hook_jump, begin=LK_JUMP64, end=LK_JUMP64)
        uc.hook_add(UC_HOOK_CODE, stop, begin=SENTINEL, end=SENTINEL)
        return uc

    uc = new_emulator()
    uc.hook_add(UC_HOOK_CODE, stop, begin=PATCH_CALL + 4, end=PATCH_CALL + 4)
    uc.reg_write(UC_ARM_REG_SP, STACK)
    uc.reg_write(UC_ARM_REG_LR, SENTINEL)

    # Execute the displaced ultraflash: registration through the injected stub.
    uc.reg_write(UC_ARM_REG_R0, 0x482A08D4)
    uc.reg_write(UC_ARM_REG_R1, 0x48236055)
    uc.reg_write(UC_ARM_REG_R2, 1)
    uc.reg_write(UC_ARM_REG_R3, 1)
    uc.emu_start(PATCH_CALL | 1, SENTINEL, count=10000)

    if len(registrations) != 2:
        raise SystemExit(f"expected two registrations, got {registrations!r}")
    if registrations[0] != ("ultraflash:", 0x48236055, 1, 1):
        raise SystemExit(f"displaced registration changed: {registrations[0]!r}")
    if registrations[1][0] != "boot":
        raise SystemExit(f"boot command not registered: {registrations[1]!r}")
    if registrations[1][2:] != (1, 0):
        raise SystemExit(f"unexpected boot flags: {registrations[1]!r}")

    boot_handler = registrations[1][1]

    # RAWBOOT!: copy to the requested physical address and invoke lk_jump64.
    raw_payload = bytes((i * 37 + 11) & 0xFF for i in range(0x123))
    raw = struct.pack(
        "<8sIIII",
        b"RAWBOOT!",
        KERNEL_LOAD,
        KERNEL_LOAD + 0x40,
        DTB_LOAD,
        len(raw_payload),
    ) + raw_payload
    uc.mem_write(DOWNLOAD, raw)
    logs.clear()
    cache_calls.clear()
    jumps.clear()
    uc.reg_write(UC_ARM_REG_SP, STACK)
    uc.reg_write(UC_ARM_REG_LR, SENTINEL)
    uc.reg_write(UC_ARM_REG_R0, 0)
    uc.reg_write(UC_ARM_REG_R1, DOWNLOAD)
    uc.reg_write(UC_ARM_REG_R2, len(raw))
    uc.emu_start(boot_handler, SENTINEL, count=100000)
    if bytes(uc.mem_read(KERNEL_LOAD, len(raw_payload))) != raw_payload:
        raise SystemExit("RAWBOOT payload was not copied")
    if cache_calls != [(KERNEL_LOAD, len(raw_payload))]:
        raise SystemExit(
            f"unexpected RAWBOOT cache call: {cache_calls!r}; logs={logs!r}"
        )
    if jumps != [(KERNEL_LOAD + 0x40, DTB_LOAD, 0, 1)]:
        raise SystemExit(f"unexpected RAWBOOT jump: {jumps!r}; logs={logs!r}")
    if struct.unpack("<I", uc.mem_read(WDT_MODE, 4))[0] != 0x22000000:
        raise SystemExit("watchdog was not disabled before RAWBOOT handoff")
    if not any("RAWBOOT" in message for message in logs):
        raise SystemExit(f"RAWBOOT handler did not log: {logs!r}")

    # Minimal v2 Android boot image with an uncompressed kernel, ramdisk and DTB.
    page = 0x800
    kernel = bytes((i * 13 + 7) & 0xFF for i in range(0x101))
    ramdisk = bytes((i * 29 + 3) & 0xFF for i in range(0x345))
    fdt_size = 0x80
    fdt = bytearray(fdt_size)
    struct.pack_into(">II", fdt, 0, 0xD00DFEED, fdt_size)
    fdt[8:16] = b"TESTFDT!"
    image_data = bytearray(0x2000)
    image_data[0:8] = b"ANDROID!"
    struct.pack_into("<I", image_data, 0x08, len(kernel))
    struct.pack_into("<I", image_data, 0x0C, KERNEL_LOAD)
    struct.pack_into("<I", image_data, 0x10, len(ramdisk))
    struct.pack_into("<I", image_data, 0x14, RAMDISK_LOAD)
    struct.pack_into("<I", image_data, 0x20, DTB_LOAD)
    struct.pack_into("<I", image_data, 0x24, page)
    struct.pack_into("<I", image_data, 0x28, 2)
    struct.pack_into("<I", image_data, 0x670, len(fdt))
    struct.pack_into("<Q", image_data, 0x674, DTB_LOAD)
    image_data[page:page + len(kernel)] = kernel
    ramdisk_off = page + ((len(kernel) + page - 1) // page) * page
    image_data[ramdisk_off:ramdisk_off + len(ramdisk)] = ramdisk
    fdt_off = ramdisk_off + ((len(ramdisk) + page - 1) // page) * page
    image_data[fdt_off:fdt_off + len(fdt)] = fdt

    uc.mem_write(DOWNLOAD, bytes(image_data))
    logs.clear()
    cache_calls.clear()
    jumps.clear()
    uc.reg_write(UC_ARM_REG_SP, STACK)
    uc.reg_write(UC_ARM_REG_LR, SENTINEL)
    uc.reg_write(UC_ARM_REG_R0, 0)
    uc.reg_write(UC_ARM_REG_R1, DOWNLOAD)
    uc.reg_write(UC_ARM_REG_R2, len(image_data))
    uc.emu_start(boot_handler, SENTINEL, count=200000)
    if bytes(uc.mem_read(KERNEL_LOAD, len(kernel))) != kernel:
        raise SystemExit("Android kernel was not copied")
    if bytes(uc.mem_read(RAMDISK_LOAD, len(ramdisk))) != ramdisk:
        raise SystemExit("Android ramdisk was not copied")
    if bytes(uc.mem_read(DTB_LOAD, len(fdt))) != bytes(fdt):
        raise SystemExit("Android DTB was not copied")
    if cache_calls != [
        (KERNEL_LOAD, len(kernel)),
        (RAMDISK_LOAD, len(ramdisk)),
        (DTB_LOAD, len(fdt)),
    ]:
        raise SystemExit(f"unexpected Android cache calls: {cache_calls!r}")
    if jumps != [(KERNEL_LOAD, DTB_LOAD, 0, 1)]:
        raise SystemExit(f"unexpected Android jump: {jumps!r}")
    if not any("Android" in message for message in logs):
        raise SystemExit(f"Android handler did not log: {logs!r}")

    # A compressed stock kernel must fail instead of being executed as garbage.
    image_data[page:page + 2] = b"\x1f\x8b"
    uc.mem_write(DOWNLOAD, bytes(image_data))
    logs.clear()
    cache_calls.clear()
    jumps.clear()
    uc.reg_write(UC_ARM_REG_SP, STACK)
    uc.reg_write(UC_ARM_REG_LR, SENTINEL)
    uc.reg_write(UC_ARM_REG_R0, 0)
    uc.reg_write(UC_ARM_REG_R1, DOWNLOAD)
    uc.reg_write(UC_ARM_REG_R2, len(image_data))
    uc.emu_start(boot_handler, SENTINEL, count=200000)
    if jumps or cache_calls:
        raise SystemExit("compressed kernel unexpectedly reached handoff")
    if not any("compressed kernel" in message for message in logs):
        raise SystemExit(f"compressed kernel was not rejected: {logs!r}")

    # The actual PD2230 boot.img has a gzip kernel and ramdisk. It must be
    # rejected before LK attempts to execute compressed bytes.
    if STOCK_BOOT.is_file():
        stock_size = STOCK_BOOT.stat().st_size
        stock_header = STOCK_BOOT.read_bytes()[:0x800]
        uc.mem_write(DOWNLOAD, stock_header)
        logs.clear()
        cache_calls.clear()
        jumps.clear()
        uc.reg_write(UC_ARM_REG_SP, STACK)
        uc.reg_write(UC_ARM_REG_LR, SENTINEL)
        uc.reg_write(UC_ARM_REG_R0, 0)
        uc.reg_write(UC_ARM_REG_R1, DOWNLOAD)
        uc.reg_write(UC_ARM_REG_R2, stock_size)
        uc.emu_start(boot_handler, SENTINEL, count=200000)
        if jumps or cache_calls:
            raise SystemExit("stock compressed boot.img unexpectedly reached handoff")
        if not any("compressed kernel" in message for message in logs):
            raise SystemExit(f"stock boot.img was not rejected safely: {logs!r}")

    print("boot registration: OK")
    print("  displaced:", registrations[0])
    print(f"  new command: boot, handler={boot_handler:#x}, flags=(1,0)")
    print("RAWBOOT handoff: OK")
    print("Android boot-image handoff: OK (kernel + ramdisk + DTB)")
    print("compressed kernel rejection: OK")
    if STOCK_BOOT.is_file():
        print("stock PD2230 boot.img rejection: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
