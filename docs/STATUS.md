# MT6833 真机状态记录

## 设备

| 项目 | 值 |
| --- | --- |
| 设备 | vivo / iQOO Z7i |
| SoC | MediaTek MT6833 |
| Android 基线 | Android 13 |
| 启动方式 | 已解锁 bootloader，通过 `fastboot boot`/`fastboot flash boot` 临时实验 |
| 原厂 LK 基址 | `0x48200000` |
| LK fastboot 注册函数 | `0x4822b96c` |
| 注入调用点 | `0x4822c57e` |
| 注入代码洞 | `0x4829a07c` |

这些地址只适用于当前保存的原厂 LK，不能套用到其他固件版本。

## 已验证的 fastboot 链

`scripts/patch_lk_boot.py` 保留并重签原厂 CERT2，修改范围限定为：

- fastboot 注册调用的 Thumb BL；
- Orange State 函数入口；
- 位于空洞中的 fastboot 注入桩；
- 必要的 CERT2 覆盖。

`scripts/verify_fastboot_boot.py` 使用 Unicorn 验证：

- fastboot `boot` 命令注册；
- 既有 `ultraflash:` 注册未被破坏；
- RAWBOOT 头、复制地址、缓存清理和 64 位跳转；
- Android v2 boot image 的 kernel、ramdisk、DTB 地址；
- 压缩内核会被拒绝，而不是当作原始 ARM64 入口执行；
- Watchdog 在跳转前关闭。

## UniXNU / UEFI

历史真机记录已确认：

- Mu-Silicium/Camellia coldboot UEFI 能够加载；
- UniXNU 菜单可显示并执行 payload；
- EFI FAT payload 可以读取；
- Stage0 loader 可把 UEFI FD 和 UniXNU payload 装入内存并跳转；
- 部分测试版本在菜单选择后出现整屏滚动、颜色条、黑屏但背光仍亮或自动
  重启。

## WOAPE / Linux

历史构建包含：

- Windows PE / WOAPE 启动项；
- mainline Linux 6.8 实验启动；
- 多种 UFS、TTBR1、DTB 和 Stage0 诊断组合。

观察到的问题：

- 个别载荷进入后持续震动；
- 菜单或日志被刷掉后黑屏；
- Linux 早期输出存在，但显示、供电或存储路径没有稳定完成；
- MTK 原厂 LK 的 AVB、DTBO overlay、display 和 UFS 行为与通用 MT6833
  平台不同。

仓库不包含这些实验镜像。需要从源码重新构建或使用本机保留的私有备份。

## 已知 LK 日志

最后保存的 expdb 日志显示：

```text
fastboot: processing commands
download_base:0x49100000
avb_slot_verify: boot: Hash of data does not match digest in descriptor
vbmeta: HASH_MISMATCH
booting linux @ 0x40080000, ramdisk @ 0x51100000
LK finished --> jump to linux kernel 64Bit
```

同时出现：

```text
[LK_DDP/DSI]error:polling SLEEPIN_DONE
[LK_DDP/DSI]error:polling SLEEPOUT_DONE
"/dsi/panel1/fake_heigh" is empty
"/dsi/panel1/fake_width" is empty
```

这些说明原厂 LK 已经进入 Linux 跳转路径，但 AVB 状态和显示时序仍需
分别处理。

## 分区观察

当前日志中可见：

```text
dtbo  start_sect=0x56980  nr_sects=0x800
woape start_sect=0x1d48ff8 nr_sects=0x80000
```

`woape` 的 LBA 超过 32 位范围，相关工具和脚本不得用 32 位分区号假设。

## 下一步

1. 固定原厂固件版本和所有镜像哈希；
2. 为 UEFI/UniXNU 添加不依赖屏幕的串口/内存日志；
3. 分离 AVB、DTBO overlay、显示供电和 UFS 驱动问题；
4. 将 Linux/WOAPE 测试从 `boot` 分区迁移到独立测试分区；
5. 在 MT6833 UniXNU 菜单稳定的基础上再接入 XNU。
