<div align="center">

# GKI KernelSU SUSFS
### 专为ReSukiSU打造的自动构建仓库

**自动化构建 GKI 内核 | 集成 KernelSU + SUSFS**

[![Release](https://img.shields.io/github/v/release/coolzyd9107/GKI_KernelSU_SUSFS?label=Release&style=flat-square&logo=github&logoColor=white&color=2ea44f)](https://github.com/coolzyd9107/GKI_KernelSU_SUSFS/releases)
[![Telegram](https://img.shields.io/static/v1?label=Telegram&message=Channel&color=0088cc)](https://t.me/ReSukiSUKernelBuilds)
[![KernelSU](https://img.shields.io/badge/KernelSU-Supported-5AA300?style=flat-square)](https://kernelsu.org/)
[![SUSFS](https://img.shields.io/badge/SUSFS-Integrated-E67E22?style=flat-square)](https://gitlab.com/simonpunk/susfs4ksu)

---

# 重要公告
### 2026高考在即，仓库作者需要备考+参考，因此近期维护暂停直至高考结束，如果你有能力可以发起pr帮助我们进行修复，见谅！同时祝其他本届考生高考顺利！

</div>

## ⚠️ 仓库须知

① 本仓库分叉自 [zzh20188/GKI_KernelSU_SUSFS](https://github.com/zzh20188/GKI_KernelSU_SUSFS/) 本人只进行了部分修改与问题修复，请各位使用者优先考虑分叉原始仓库。

② 本仓库只提供ReSukiSU的预构建内核，对于其它KernelSU分支，请分叉本仓库或 [zzh20188/GKI_KernelSU_SUSFS](https://github.com/zzh20188/GKI_KernelSU_SUSFS/) 然后自行构建。

## 💰 特别鸣谢

[coolzyd9107](https://github.com/coolzyd9107)：仓库的创建者和所有者，但他是一个大fèiwù，很多东西都不会。

[zzh20188](https://github.com/zzh20188)：他是本仓库的上游仓库作者。

[zhuzhuzihan](https://github.com/zhuzhuzihan)：协助进行了大量修复和修改，同时为我们的Telegram Bot提供服务器(仓库所有者真的太穷了，租不起)，我们的Telegram Bot的主要开发者。

[TanakaLun](https://github.com/TanakaLun)：协助进行了大量修复和修改。

[YC酱luyancib](https://github.com/luyanci): 协助开发Telegram Bot，提供部分构建工作流程修复思路和Bot开发思路。

[AlexLiuDev233](https://github.com/AlexLiuDev233): 协助修复构建工作流程存在的问题。

[cctv18](https://github.com/cctv18): 协助修复构建工作流程存在的问题，为添加6.12内核构建支持提供部分思路，为修复一些SUSFS导致的问题提供思路。

## 🚀 快速导航

<table>
<tr>
<td align="center" width="33%">📖 <b><a href="https://github.com/zzh20188/GKI_KernelSU_SUSFS/wiki">文档</a></b></td>
<td align="center" width="34%">📥 <b><a href="https://github.com/ReSukiSU-GKI/GKI_KernelSU_SUSFS/releases">下载</a></b></td>
<td align="center" width="33%">🔰 <b><a href="https://zzh20188.github.io/GKI_KernelSU_SUSFS/guide.html">新手教程</a></b></td>
</tr>
</table>

---

## ⚠️ 兼容性提醒

> **注意：** 目前不支持一加 ColorOS 14、15，刷入后可能需要清除数据开机。

> **ReSukiSU：ReSukiSU更新比SukiSU勤快，SukiSU报错就试试ReSukiSU**
>
> **默认变体已切换为 ReSukiSU**

> **Android 16：已支持 Android 16 - 6.12 内核版本**
>
> **自本仓库的提交#c17aae5起我们已彻底移除对除ReSukiSU以外的KernelSU变体的内核构建支持，如果你出于某种原因更喜欢使用其他KernelSU变体的管理器，你完全不必担心，我们启用了muti-manager (内核中的KernelSU驱动程序仍是ReSukiSU，但支持使用其它大部分KernelSU变体的管理器进行管理，例如KowSU和SukiSU-Ultra的管理器) ，这样你就可以直接使用其他KernelSU变体的管理器，但请务必记住，如果你要反馈问题，请使用ReSukiSU管理器提交日志信息**

> **rekernel功能（测试）：已支持 rekernel 功能（目前处于测试阶段）**

---

## 📚 文档与指南

详细说明请查阅 [**GitHub Wiki（中英双语）**](https://github.com/zzh20188/GKI_KernelSU_SUSFS/wiki)

Wiki 涵盖内容：
- [**🔰 新手必看**](https://github.com/zzh20188/GKI_KernelSU_SUSFS/wiki/Fork%E4%B8%8E%E8%87%AA%E5%AE%9A%E4%B9%89%E7%BC%96%E8%AF%91%E6%8C%87%E5%8D%97)
- 📥 下载/刷入内核
- 💡 使用技巧 Tips
- 🆘 救砖指南
- 📊 内核版本兼容性说明

---

## 🧪 Droidspaces 容器支持（实验性）

> **实验性功能：** 不保证所有 GKI 版本均能成功构建或启动，刷入前请务必备份 Boot 镜像。
>
> **TIPS：** 工作流使用的是 [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) 的 [官方补丁](https://github.com/ravindu644/Droidspaces-OSS/tree/main/Documentation/resources/kernel-patches/GKI) ，如有更好的补丁可以提个issues，此外由于存在三个补丁，或许需要反复试验以确保其中一个适配你的机型，请根据他人或实际经验来选择。

[Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) 是一个轻量级的 Linux 容器工具，可以在 Android 上运行完整的 Linux 环境（支持 systemd、OpenRC 等），用于搭建开发环境、运行服务器等场景。

**支持范围：** 5.10 / 5.15 / 6.1 / 6.6 / 6.12

**使用方式：** 在手动触发构建时，选择 `Droidspaces 容器支持` 选项：

| 选项 | 说明 |
|:---:|:---|
| `off` | 关闭（默认） |
| `678` | 使用 6_7_8 槽位补丁（推荐） |
| `123` | 使用 1_2_3 槽位补丁（备用） |
| `345` | 使用 3_4_5 槽位补丁（备用） |

> **提示：** 6.12 内核仅有一个补丁，选择任意非关闭选项即可。

**如果构建失败或刷入后 bootloop：** 可尝试切换到其他槽位补丁（如 678 → 123 或 345），不同内核子版本可能适用不同的补丁。

---

## ❗构建失败常见原因（SukiSU / SUSFS 更新不同步）

当以下两个分支的更新节奏不一致时，构建可能失败：

- SukiSU builtin 分支：<https://github.com/SukiSU-Ultra/SukiSU-Ultra/tree/builtin>
- SUSFS gki-android14-6.1 分支：<https://gitlab.com/simonpunk/susfs4ksu/-/tree/gki-android14-6.1?ref_type=heads>

例如：SUSFS 刚更新了新提交，但 SukiSU 的 `builtin` 分支还没跟进适配，这时打补丁/编译就容易失败。

如以下情况，只能等待SukiSU跟进，完成与SUSFS最新提交的适配。

<img src="assets/sukisu_eg1.png" alt="SukiSU builtin 更新记录" width="80%">
<img src="assets/susfs_eg1.png" alt="SUSFS gki-android14-6.1 更新记录" width="80%">

## 🔧 自定义提交配置
通过 [`config/config`](config/config) 文件可以指定 SUSFS 和 SukiSU 使用特定的 commit。

**什么是提交 (commit)？**

提交是一串哈希字符串，代表仓库在某个时间点的状态。例如将 sukisu 设为 `4b8644515fe6d87a109129e590ccd9d33a855dca`，即使用 1 月 30 日的 SukiSU 版本编译内核。

**为什么要指定提交？**

- 当上游仓库更新引入 bug 或兼容性问题时，可回退到稳定版本
- 当 SUSFS 与 SukiSU 版本不同步导致编译失败时，可手动指定兼容的版本

**如何获取提交哈希？**

- SUSFS: https://gitlab.com/simonpunk/susfs4ksu
- SukiSU: https://github.com/SukiSU-Ultra/SukiSU-Ultra/commits/builtin/

以 SUSFS 为例，先选择分支，再复制对应提交的哈希值：

![选择分支](assets/susfs_branch.png)
![复制提交](assets/susfs_commit.png)

```ini
# 启用自定义提交
custom=true

# SUSFS 各分支的 commit hash
gki-android12-5.10=
gki-android13-5.15=
gki-android14-6.1=
gki-android15-6.6=

# SukiSU 的 commit hash
sukisu=
```

> 留空则使用该分支的最新提交。

---

## 🧪 伪装 `/proc/config.gz`（Stock Config）

这是一个进阶技巧，不需要在工作流里手动开关。  
构建时会自动检测 `config/stock_defconfig` 是否存在：存在则应用，不存在则跳过。

使用方法：
1. 确保设备当前是官方 ROM + 官方内核。
2. 获取设备上的 `/proc/config.gz`（可在手机端或电脑端操作）。
3. 解压后重命名为 `stock_defconfig`，上传到仓库 [`config/`](config/) 目录并提交（可直接在手机端完成）。

构建流程会自动：
- 复制到内核源码：`$KERNEL_ROOT/common/arch/arm64/configs/stock_defconfig`
- 在 `$KERNEL_ROOT/common/kernel/Makefile` 中将 `$(obj)/config_data` 规则从 `$(KCONFIG_CONFIG)` 切换为 `arch/arm64/configs/stock_defconfig`
- 使编译产物中的 `/proc/config.gz` 更贴近你的官方内核配置
---

## 🛠️ 安装后推荐

### 📦 模块推荐

<table>
<tr>
<th>模块名称</th>
<th>仓库</th>
<th>频道</th>
</tr>
<tr>
<td><b>LSPosed-Irena</b></td>
<td><a href="https://github.com/re-zero001/LSPosed-Irena">GitHub</a></td>
<td><a href="https://t.me/lsposed_irena">Telegram</a></td>
</tr>
<tr>
<td><b>Zygisk Next</b></td>
<td><a href="https://github.com/Dr-TSNG/ZygiskNext">GitHub</a></td>
<td rowspan="2"><a href="https://t.me/real5ec1cff">Telegram</a></td>
</tr>
<tr>
<td><b>TrickyStore</b></td>
<td><a href="https://github.com/5ec1cff/TrickyStore">GitHub</a></td>
</tr>
</table>

### 🔧 Xposed 模块

| 模块 | 说明 |
|:---:|:---|
| **FuseFixer** | [Unicode零宽修复模块](https://t.me/real5ec1cff/268) |

### App

| 名称 | 说明 |
|:---:|:---|
| **Scene** | [官网](https://omarea.com/#/) |
---

<div align="center">

**更多内容持续更新中...**

⭐ 如果这个项目对你有帮助，请点个 Star 支持一下！

</div>
