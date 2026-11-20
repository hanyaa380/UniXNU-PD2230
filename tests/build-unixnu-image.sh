#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UEFI="${UEFI:-$ROOT/../toolchain/uefi-camellia}"
PAYLOAD="${PAYLOAD:-$ROOT/build/unixnu-payload.img}"
OUT="${OUT:-$ROOT/dist/iqooz7i-uefi-unixnu-ramdisk-boot.img}"
STAGE0_COMPRESSION="${STAGE0_COMPRESSION:-raw}"
PAYLOAD_MODE="${PAYLOAD_MODE:-ramdisk}"

if [[ "${SKIP_UEFI_BUILD:-0}" != 1 ]]; then
  "$UEFI/build-camellia-coldboot.sh"
fi
if [[ "${SKIP_PAYLOAD_BUILD:-0}" != 1 ]]; then
  "$ROOT/tests/make-unixnu-payload.sh"
fi

cd "$ROOT"

if [[ ! -f "$PAYLOAD" ]]; then
  echo "missing payload image: $PAYLOAD" >&2
  exit 1
fi

payload_size=$(stat -c %s "$PAYLOAD")
if (( payload_size == 0 || payload_size % 512 != 0 || payload_size > 0x04000000 )); then
  echo "invalid ramdisk payload size: $payload_size" >&2
  exit 1
fi
payload_size_hex=$(printf '0x%x' "$payload_size")

LINK_INPUTS=(
  build/uefi_stage0_loader.o
  build/uefi-coldboot-50000000.o
)
STAGE0_MODE_CFLAGS=()
BOOT_RAMDISK=tests/minimal_ramdisk

case "$PAYLOAD_MODE" in
  embedded)
    llvm-objcopy -I binary -O elf64-littleaarch64 -B aarch64 \
      --rename-section .data=.payload2,alloc,load,readonly,data,contents \
      "$PAYLOAD" build/unixnu-payload.o
    LINK_INPUTS+=(build/unixnu-payload.o)
    STAGE0_MODE_CFLAGS+=(-DEMBEDDED_PAYLOAD)
    ;;
  ramdisk)
    if [[ "${VALIDATE_RAMDISK:-1}" == 1 ]]; then
      STAGE0_MODE_CFLAGS+=(-DVALIDATE_RAMDISK)
    fi
    BOOT_RAMDISK="$PAYLOAD"
    ;;
  *)
    echo "invalid PAYLOAD_MODE: $PAYLOAD_MODE" >&2
    exit 1
    ;;
esac

aarch64-linux-gnu-gcc -c -DPAYLOAD_SIZE="$payload_size_hex" \
  "${STAGE0_MODE_CFLAGS[@]}" \
  ${STAGE0_EXTRA_CFLAGS:-} \
  tests/uefi_stage0_loader.S -o build/uefi_stage0_loader.o
cp "$UEFI/dist/SILICIUM_UEFI-coldboot.fd" build/uefi-coldboot-50000000.fd

llvm-objcopy -I binary -O elf64-littleaarch64 -B aarch64 \
  --rename-section .data=.payload,alloc,load,readonly,data,contents \
  build/uefi-coldboot-50000000.fd build/uefi-coldboot-50000000.o

aarch64-linux-gnu-ld -T tests/uefi_stage0_loader.ld \
  "${LINK_INPUTS[@]}" \
  -o build/uefi_stage0_loader-unixnu.elf

aarch64-linux-gnu-objcopy -O binary \
  build/uefi_stage0_loader-unixnu.elf build/uefi_stage0_loader-unixnu.bin

case "$STAGE0_COMPRESSION" in
  raw)
    KERNEL=build/uefi_stage0_loader-unixnu.bin
    MAX_KERNEL_SIZE=$((4 * 1024 * 1024))
    ;;
  gzip)
    gzip -n -9 -c build/uefi_stage0_loader-unixnu.bin \
      > build/uefi_stage0_loader-unixnu.bin.gz
    KERNEL=build/uefi_stage0_loader-unixnu.bin.gz
    MAX_KERNEL_SIZE=$((2 * 1024 * 1024))
    ;;
  *)
    echo "invalid STAGE0_COMPRESSION: $STAGE0_COMPRESSION" >&2
    exit 1
    ;;
esac

kernel_size=$(stat -c %s "$KERNEL")
if (( kernel_size > MAX_KERNEL_SIZE )); then
  echo "stage0 kernel grew beyond limit: $kernel_size" >&2
  exit 1
fi

python3 "$UEFI/Resources/Scripts/mkbootimg-camellia.py" \
  --kernel "$KERNEL" \
  --ramdisk "$BOOT_RAMDISK" \
  --dtb build/device-boot.dtb \
  --output "$OUT" \
  --verify

printf 'stage0 kernel: %s bytes\npayload ramdisk: %s bytes\n' \
  "$kernel_size" "$payload_size"
sha256sum "$OUT"
