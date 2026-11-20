CLANG ?= clang
LD_LLD ?= ld.lld
LLVM_OBJCOPY ?= llvm-objcopy

TOOLCHAIN ?= ../toolchain
PYTHON_TOOLS ?= $(TOOLCHAIN)/python-tools
LIBLK ?= $(TOOLCHAIN)/liblk
LKPATCHER ?= $(TOOLCHAIN)/lkpatcher

BUILD := build
DIST := dist
PAYLOAD_ELF := $(BUILD)/fastboot_boot_stub.elf
PAYLOAD_BIN := $(BUILD)/fastboot_boot_stub.bin
RAWBOOT_PAYLOAD ?=
RAWBOOT_OUTPUT ?= $(DIST)/rawboot.img
RAWBOOT_LOAD ?= 0x40080000
RAWBOOT_ENTRY ?= 0
RAWBOOT_DTB ?= 0

.PHONY: all payload image verify rawboot clean

all: image

payload: $(PAYLOAD_BIN)

$(PAYLOAD_BIN): payload/fastboot_boot_stub.S payload/fastboot_boot_stub.ld
	@mkdir -p $(BUILD)
	$(CLANG) --target=armv7a-none-eabi -march=armv7-a -mthumb \
		-mfloat-abi=soft -c payload/fastboot_boot_stub.S -o $(BUILD)/fastboot_boot_stub.o
	$(LD_LLD) -T payload/fastboot_boot_stub.ld -o $(PAYLOAD_ELF) \
		$(BUILD)/fastboot_boot_stub.o
	$(LLVM_OBJCOPY) -O binary $(PAYLOAD_ELF) $(PAYLOAD_BIN)
	llvm-nm -n $(PAYLOAD_ELF)

image: payload
	PYTHONPATH=$(PYTHON_TOOLS):$(LKPATCHER):$(LIBLK) \
		python3 scripts/patch_lk_boot.py \
		--input lk.img \
		--payload $(PAYLOAD_BIN) \
		--output $(DIST)/lk-bootcmd-v1.img

verify:
	PYTHONPATH=$(PYTHON_TOOLS):$(LKPATCHER):$(LIBLK) \
		python3 scripts/verify_fastboot_boot.py

rawboot:
	@test -n "$(RAWBOOT_PAYLOAD)" || \
		{ echo "usage: make rawboot RAWBOOT_PAYLOAD=path/to/bootshim.bin"; exit 2; }
	python3 scripts/make_rawboot.py "$(RAWBOOT_PAYLOAD)" "$(RAWBOOT_OUTPUT)" \
		--load-addr "$(RAWBOOT_LOAD)" \
		--entry "$(RAWBOOT_ENTRY)" \
		--dtb-addr "$(RAWBOOT_DTB)"

clean:
	rm -rf $(BUILD)
