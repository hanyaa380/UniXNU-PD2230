#!/usr/bin/env python3
"""Inject the minimal fastboot boot-command registration stub."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path

from liblk.image import LkImage
from lkpatcher.cert_bypass import CertBypassMode, apply_cert_bypass


REPO = Path(__file__).resolve().parent.parent
DEFAULT_INPUT = REPO / "lk.img"
DEFAULT_PAYLOAD = REPO / "build" / "fastboot_boot_stub.bin"
DEFAULT_OUTPUT = REPO / "dist" / "lk-bootcmd-v1.img"

LK_LOAD_ADDRESS = 0x48200000
FASTBOOT_REGISTER = 0x4822B96C
PATCH_CALL = 0x4822C57E
ORIGINAL_BL = bytes.fromhex("fff7f5f9")
STUB_ADDRESS = 0x4829A07C
STUB_CAVE_END = 0x4829A580
ORANGE_STATE_FUNCTION = 0x4824ED88
ORIGINAL_ORANGE_STATE = bytes.fromhex("1b4b10b5")
ORANGE_STATE_RETURN = bytes.fromhex("00207047")  # movs r0, #0; bx lr
PARTITION_SIZE = 0x1000000


def thumb_bl(src: int, dst: int) -> bytes:
    """Encode an ARMv7 Thumb-2 BL instruction."""
    offset = dst - (src + 4)
    if not -(1 << 24) <= offset < (1 << 24):
        raise ValueError(f"Thumb BL out of range: {src:#x} -> {dst:#x}")
    if offset & 1:
        raise ValueError("Thumb BL target must be halfword aligned")

    s = (offset >> 24) & 1
    i1 = (offset >> 23) & 1
    i2 = (offset >> 22) & 1
    imm10 = (offset >> 12) & 0x3FF
    imm11 = (offset >> 1) & 0x7FF
    j1 = ((~i1) ^ s) & 1
    j2 = ((~i2) ^ s) & 1

    first = 0xF000 | (s << 10) | imm10
    second = 0xD000 | (j1 << 13) | (j2 << 11) | imm11
    return struct.pack("<HH", first, second)


def decode_thumb_bl(word: bytes, src: int) -> int:
    first, second = struct.unpack("<HH", word)
    if (first & 0xF800) != 0xF000 or (second & 0xD000) != 0xD000:
        raise ValueError("not a Thumb BL")
    s = (first >> 10) & 1
    j1 = (second >> 13) & 1
    j2 = (second >> 11) & 1
    i1 = ((~j1) & 1) ^ s
    i2 = ((~j2) & 1) ^ s
    imm10 = first & 0x3FF
    imm11 = second & 0x7FF
    offset = (s << 24) | (i1 << 23) | (i2 << 22) | (imm10 << 12) | (imm11 << 1)
    if s:
        offset |= ~0x1FFFFFF
    return src + 4 + offset


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--payload", type=Path, default=DEFAULT_PAYLOAD)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    source_sha = hashlib.sha256(args.input.read_bytes()).hexdigest()
    image = LkImage(args.input)
    lk = image.partitions.get("lk")
    if lk is None or lk.lk_address != LK_LOAD_ADDRESS:
        raise SystemExit("unexpected LK partition or load address")

    original_lk_data = bytes(lk.data)
    data = bytearray(original_lk_data)
    patch_off = PATCH_CALL - LK_LOAD_ADDRESS
    orange_off = ORANGE_STATE_FUNCTION - LK_LOAD_ADDRESS
    cave_off = STUB_ADDRESS - LK_LOAD_ADDRESS
    cave_end_off = STUB_CAVE_END - LK_LOAD_ADDRESS
    payload = args.payload.read_bytes()

    if bytes(data[patch_off:patch_off + 4]) != ORIGINAL_BL:
        raise SystemExit("unexpected original instruction at fastboot registration")
    if bytes(data[orange_off:orange_off + 4]) != ORIGINAL_ORANGE_STATE:
        raise SystemExit("unexpected original Orange State function prologue")
    if decode_thumb_bl(ORIGINAL_BL, PATCH_CALL) != FASTBOOT_REGISTER:
        raise SystemExit("original registration target mismatch")
    if cave_off + len(payload) > cave_end_off:
        raise SystemExit("payload does not fit selected code cave")
    if any(data[cave_off:cave_off + len(payload)]):
        raise SystemExit("selected code cave is not empty")

    data[cave_off:cave_off + len(payload)] = payload
    data[orange_off:orange_off + 4] = ORANGE_STATE_RETURN
    patched_call = thumb_bl(PATCH_CALL, STUB_ADDRESS)
    if decode_thumb_bl(patched_call, PATCH_CALL) != STUB_ADDRESS:
        raise SystemExit("failed to encode patched registration call")
    data[patch_off:patch_off + 4] = patched_call
    original_cert2 = bytes(lk.cert2.data)
    lk.data = bytes(data)

    image._rebuild_contents()
    signed = apply_cert_bypass(image, mode=CertBypassMode.OVERRIDE)
    if "lk" not in signed:
        raise SystemExit(f"LK partition was not re-signed: {signed}")

    output = bytes(image.contents)
    if len(output) > PARTITION_SIZE:
        if any(output[PARTITION_SIZE:]):
            raise SystemExit("signed image exceeds 16 MiB")
        output = output[:PARTITION_SIZE]
    else:
        output += b"\0" * (PARTITION_SIZE - len(output))

    check = LkImage(output)
    check_lk = check.partitions["lk"]
    check_data = check_lk.data
    if check_data[cave_off:cave_off + len(payload)] != payload:
        raise SystemExit("payload not present in final LK")
    if check_data[patch_off:patch_off + 4] != patched_call:
        raise SystemExit("patched call not present in final LK")
    if check_data[orange_off:orange_off + 4] != ORANGE_STATE_RETURN:
        raise SystemExit("Orange State bypass is not present in final LK")
    if not bytes(check_lk.cert2.data).endswith(original_cert2):
        raise SystemExit("CERT2 override did not preserve the original certificate")

    allowed = set(range(orange_off, orange_off + 4))
    allowed.update(range(patch_off, patch_off + 4))
    allowed.update(range(cave_off, cave_off + len(payload)))
    changed = [
        offset
        for offset, (before, after) in enumerate(
            zip(original_lk_data, check_data)
        )
        if before != after
    ]
    unexpected = [offset for offset in changed if offset not in allowed]
    if unexpected:
        raise SystemExit(f"unexpected LK data changes: {unexpected[:16]!r}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(output)
    output_sha = hashlib.sha256(output).hexdigest()

    manifest = {
        "input": str(args.input),
        "input_sha256": source_sha,
        "output": str(args.output),
        "output_sha256": output_sha,
        "lk_load_address": f"0x{LK_LOAD_ADDRESS:x}",
        "patch_call": f"0x{PATCH_CALL:x}",
        "original_bl": ORIGINAL_BL.hex(),
        "patched_bl": patched_call.hex(),
        "orange_state_function": f"0x{ORANGE_STATE_FUNCTION:x}",
        "orange_state_original": ORIGINAL_ORANGE_STATE.hex(),
        "orange_state_patch": ORANGE_STATE_RETURN.hex(),
        "stub_address": f"0x{STUB_ADDRESS:x}",
        "stub_size": len(payload),
        "cert2_resigned": signed,
        "cert2_size": len(check_lk.cert2.data),
        "cert2_override": True,
        "lk_data_changes": len(changed),
    }
    args.output.with_suffix(args.output.suffix + ".json").write_text(
        json.dumps(manifest, indent=2) + "\n"
    )
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
