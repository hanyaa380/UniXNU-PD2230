# iQOO Z7i UniXNU / MT6833 bring-up

面向 vivo/iQOO Z7i（MediaTek MT6833）的 UniXNU、UEFI Stage0、
fastboot 临时启动和 WOAPE/Linux 启动链研究仓库。

> 这是实验性 bring-up 项目，不是普通用户可刷写的 ROM。修改 LK、vbmeta
> 或 boot 分区可能导致设备无法启动。必须在已解锁 bootloader 并完成完整
> 备份的设备上测试。

## 当前状态

| 阶段 | 状态 |
| --- | --- |
| 原厂 LK 分析 | 已定位 fastboot 注册点和可用代码洞 |
| `fastboot boot` 命令注入 | 已实现，并通过 Unicorn 指令级测试 |
| `RAWBOOT!` 临时载荷 | 已实现原始二进制和 Android boot image 两种路径 |
| UEFI coldboot / Stage0 | 已能构建并在 MT6833 真机进入实验启动阶段 |
| UniXNU EFI/FAT payload | 菜单和 payload 加载路径已打通 |
| WOAPE / Windows PE 链 | 有历史测试镜像和脚本，仍属实验状态 |
| mainline Linux 6.8 | 已做过启动诊断，仍存在黑屏、震动和自动重启等兼容问题 |
| XNU / iOS 用户态 | 未完成；当前仓库保留启动入口和诊断基础 |

详细硬件与日志记录见 [docs/STATUS.md](docs/STATUS.md)。

## 项目内容

| 路径 | 用途 |
| --- | --- |
| `payload/` | UniXNU FAT payload 配置和 LK fastboot 注入桩源码 |
| `payload-minimal/` | 最小 UniXNU 菜单配置 |
| `scripts/patch_lk_boot.py` | 向 MT6833 原厂 LK 注入 `fastboot boot` 命令 |
| `scripts/verify_fastboot_boot.py` | Unicorn 指令级验证 fastboot、RAWBOOT 和 boot image 路径 |
| `scripts/make_rawboot.py` | 生成 `RAWBOOT!` 包装载荷 |
| `tests/uefi_stage0_loader.S` | UEFI coldboot Stage0 加载器 |
| `tests/build-unixnu-image.sh` | 将 UEFI、Stage0 和 UniXNU payload 打包为 boot image |
| `tests/arm64_env_probe.c` | ARM64 环境、Watchdog 和早期启动探针 |
| `docs/STATUS.md` | MT6833 真机启动状态和已知限制 |
| `docs/UPSTREAM.md` | 上游项目、工具和致谢 |

## 不包含的二进制

仓库忽略并禁止提交：

- 原厂或修改后的 `boot.img`、`lk.img`、`vbmeta*.img`、`vendor_boot.img`；
- Linux `Image`、DTB/DTBO、initramfs 和 WOAPE 镜像；
- UEFI FD、ELF、`.bin`、`.o` 和任何设备私钥；
- `build/`、`dist/`、`downloads/` 中的本机构建产物。

使用者必须自行从合法来源提取原厂镜像和测试系统。

## LK fastboot 注入

依赖：

- Python 3；
- `unicorn`；
- `liblk`：<https://github.com/R0rt1z2/liblk>；
- `lkpatcher`：<https://github.com/R0rt1z2/lkpatcher>；
- 本机匹配的原厂 `lk.img`。

默认工具链位于仓库相邻目录：

```text
../toolchain/python-tools
../toolchain/liblk
../toolchain/lkpatcher
```

可用变量覆盖：

```sh
make TOOLCHAIN=/path/to/toolchain payload
make TOOLCHAIN=/path/to/toolchain image
make TOOLCHAIN=/path/to/toolchain verify
```

构建前请确认 `lk.img` 的 SHA-256 与设备原厂分区一致。

## UEFI / UniXNU 镜像

默认 UEFI 工程位置：

```text
../toolchain/uefi-camellia
```

生成测试 boot image：

```sh
UEFI=/path/to/uefi-camellia \
  tests/build-unixnu-image.sh
```

默认输出：

```text
dist/iqooz7i-uefi-unixnu-ramdisk-boot.img
```

优先通过 fastboot 临时启动：

```sh
fastboot boot dist/iqooz7i-uefi-unixnu-ramdisk-boot.img
```

在确认启动链和恢复方式前，不要直接刷写 boot 或 LK。

## 安全与恢复

- 先备份 GPT、boot、vendor_boot、dtbo、lk、lk2、vbmeta 和 vbmeta_oem；
- 保存原厂固件与全量字库；
- 确保 fastboot、TWRP/recovery 和恢复分区可用；
- 修改 vbmeta 后必须同时处理 `vbmeta_oem` 链；
- MTK 原厂 LK 对分区、AVB、显示和电源管理存在大量定制，不能套用其他
  MT6833 设备的偏移；
- 本项目不保证充电、触摸、显示或摄像头在实验启动环境中可用。

## 上游与致谢

本项目使用或参考：

- UniXNU 与 Project-Silicium/Mu-Silicium；
- `stanveyjiang/uefi-camellia`；
- `R0rt1z2/liblk` 和 `R0rt1z2/lkpatcher`；
- AOSP MTK boot image、AVB 和设备树工具；
- MediaTek 原厂 LK、内核和分区别名，仅用于研究本机兼容性。

完整列表见 [docs/UPSTREAM.md](docs/UPSTREAM.md)。
