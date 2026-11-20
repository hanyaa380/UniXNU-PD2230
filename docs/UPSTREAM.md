# 上游项目与致谢

## 核心启动与 UEFI

| 项目 | 用途 |
| --- | --- |
| [UniXNU/UniXNU](https://github.com/UniXNU/UniXNU) | UniXNU boot menu、EFI payload 和 Darwin/XNU 启动框架 |
| [Project-Silicium/Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium) | Apple Silicon 风格的 ARM64 UEFI 和 BDS 框架 |
| [stanveyjiang/uefi-camellia](https://github.com/stanveyjiang/uefi-camellia) | MT6833 coldboot UEFI、mkbootimg 和 Stage0 输入 |

## LK 分析与注入

| 项目 | 用途 |
| --- | --- |
| [R0rt1z2/liblk](https://github.com/R0rt1z2/liblk) | LK image 分区、证书和镜像解析 |
| [R0rt1z2/lkpatcher](https://github.com/R0rt1z2/lkpatcher) | LK CERT2 重签和补丁工具 |
| [Unicorn Engine](https://github.com/unicorn-engine/unicorn) | 无设备 fastboot/RAWBOOT 指令级验证 |

## Android / MediaTek 参考

| 来源 | 用途 |
| --- | --- |
| AOSP `system/tools/mkbootimg` | Android v0/v2 boot image 格式 |
| AOSP `external/avb` | vbmeta、AVB descriptor 和解锁状态诊断 |
| MediaTek 原厂 LK 与 Android 13 固件 | 当前设备的真实分区、fastboot 和显示实现 |
| mainline Linux MT6833 DTS/驱动 | UFS、display、PMIC 和早期启动参考 |

原厂二进制和厂商镜像不随本仓库发布。使用者必须从自己的合法固件来源提取。

## 文档与实验工具

- Python 3、Clang/LLD、LLVM objcopy、mtools；
- AArch64 cross GCC；
- `dtc`、`lz4`、`gzip` 和解包/打包工具；
- fastboot、adb 和平台 recovery/TWRP。

## 贡献说明

提交硬件日志时请同时提供：

- 固件版本和原厂分区哈希；
- 设备代号、SoC 和存储类型；
- 使用的 payload SHA-256；
- fastboot 命令、屏幕状态和 pstore/expdb 文本；
- 是否修改过 `lk`、`vbmeta`、`vbmeta_oem` 或 GPT。

不要提交厂商完整镜像、用户数据、序列号、私钥或包含个人信息的日志。
