#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
IMAGE="$ROOT/build/unixnu-payload.img"
SIZE_MIB=8

rm -f "$IMAGE"
mformat -C -T "$((SIZE_MIB * 2048))" -v UNIXNU -N 534e5547 -i "$IMAGE" ::
mmd -i "$IMAGE" ::/EFI ::/EFI/UniXNU
MTOOLS_SKIP_CHECK=1 TZ=UTC mcopy -Q -m \
  -i "$IMAGE" \
  "$ROOT/payload/EFI/UniXNU/unixnu.toml" \
  ::/EFI/UniXNU/unixnu.toml

printf 'payload: %s (%s MiB)\n' "$IMAGE" "$SIZE_MIB"
