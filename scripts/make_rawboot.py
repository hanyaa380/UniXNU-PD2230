#!/usr/bin/env python3
"""Wrap an in-memory UEFI/BootShim payload for the patched boot command."""

from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path


MAGIC = b"RAWBOOT!"
HEADER_SIZE = 24


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("payload", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--load-addr", type=lambda value: int(value, 0), default=0x40080000)
    parser.add_argument("--entry", type=lambda value: int(value, 0), default=0)
    parser.add_argument("--dtb-addr", type=lambda value: int(value, 0), default=0)
    args = parser.parse_args()

    payload = args.payload.read_bytes()
    if not payload:
        raise SystemExit("payload is empty")
    if len(payload) > 0xFFFFFFFF:
        raise SystemExit("payload is larger than the 32-bit RAWBOOT format")

    entry = args.entry or args.load_addr
    for name, value in (
        ("load-addr", args.load_addr),
        ("entry", entry),
        ("dtb-addr", args.dtb_addr),
    ):
        if not 0 <= value <= 0xFFFFFFFF:
            raise SystemExit(f"{name} does not fit in 32 bits: {value:#x}")

    header = struct.pack(
        "<8sIIII",
        MAGIC,
        args.load_addr,
        entry,
        args.dtb_addr,
        len(payload),
    )
    output = header + payload
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(output)

    print(f"payload: {args.payload} ({len(payload):#x} bytes)")
    print(f"load:    {args.load_addr:#010x}")
    print(f"entry:   {entry:#010x}")
    print(f"dtb:     {args.dtb_addr:#010x}")
    print(f"output:  {args.output} ({len(output):#x} bytes)")
    print(f"sha256:  {hashlib.sha256(output).hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
