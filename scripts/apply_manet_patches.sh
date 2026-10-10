#!/usr/bin/env bash
# ================================================================
# apply_manet_patches.sh
# ----------------------------------------------------------------
# 小米 manet (Android 14 / Linux 6.1) 内核补丁集成脚本
#
# 在已通过 AOSP manifest 同步的 common/ 目录以及克隆好的
# msm-kernel/ (Xiaomi bsp-manet-u-oss) 之上应用 ReSukiSU、SUSFS、
# Droidspaces SYSVIPC kABI、NTSync、CVE-2026-43499、ZRAM、BBG 等补丁，
# 并生成幂等的 Bazel defconfig fragment。
#
# 设计原则:
#   - 严格模式 (set -euo pipefail)，必需补丁失败即退出非零
#   - 必需补丁先 dry-run，失败则收集 .rej 并报错
#   - 不直接修改 common/arch/arm64/configs/gki_defconfig
#   - 不删除 KMI / protected_exports / kmi_symbol_list_strict_mode
#   - 所有配置项写入 common/arch/arm64/configs/ksu.fragment
#
# 用法:
#   bash scripts/apply_manet_patches.sh \
#     --workspace /path/to/kernel_workspace \
#     --droidspaces 678 \
#     --enable-susfs \
#     --ntsync \
#     --cve \
#     --use-zram \
#     --use-bbg \
#     --ksu-ref main
# ================================================================
set -euo pipefail

# ==================== 默认值 ====================
WORKSPACE=""
DROIDSPACES="off"
NTSYNC=false
SUSFS=true
CVE=false
USE_ZRAM=false
USE_BBG=false
# Gunyah SM8650 虚拟机启动修复：默认开启
# 只作用于 msm-kernel/ 平台层，与 GKI 侧补丁互不影响；关掉用 --no-gunyah-fix
GUNYAH_FIX=true
# Droidspaces 进阶能力：默认关闭，按需用 --droidspaces-extras 打开
DROIDSPACES_EXTRAS=false
KSU_REF="main"
ANDROID_VERSION="android14"
KERNEL_VERSION="6.1"
SUSFS_BRANCH="gki-${ANDROID_VERSION}-${KERNEL_VERSION}"

# ==================== 参数解析 ====================
usage() {
  cat <<'EOF'
用法: apply_manet_patches.sh [选项]
  --workspace PATH        内核工作区路径 (包含 common/ 和 msm-kernel/) [必需]
  --droidspaces SLOT      Droidspaces 槽位: off|678|123|345 (默认 off)
  --droidspaces-extras   追加 Droidspaces 可选配置 (USER_NS / NAT66 / UFW / Fail2ban 等)
  --ntsync                启用 NTSync 补丁 (需配合 --droidspaces)
  --enable-susfs           启用 SUSFS (默认)
  --disable-susfs         禁用 SUSFS
  --cve                   应用 CVE-2026-43499 rtmutex 修复链
  --gunyah-fix            应用 Gunyah SM8650 虚拟机启动修复 (默认开启)
  --no-gunyah-fix         跳过 Gunyah SM8650 虚拟机启动修复
  --use-zram              启用 ZRAM LZ4 增强补丁栈
  --use-bbg               启用 BBG 防格机
  --ksu-ref REF           ReSukiSU 分支/提交 (默认 main)
  --help                  显示此帮助
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      WORKSPACE="$2"; shift 2 ;;
    --droidspaces)
      DROIDSPACES="$2"; shift 2 ;;
    --ntsync)
      NTSYNC=true; shift ;;
    --droidspaces-extras)
      DROIDSPACES_EXTRAS=true; shift ;;
    --enable-susfs)
      SUSFS=true; shift ;;
    --disable-susfs)
      SUSFS=false; shift ;;
    --cve)
      CVE=true; shift ;;
    --gunyah-fix)
      GUNYAH_FIX=true; shift ;;
    --no-gunyah-fix)
      GUNYAH_FIX=false; shift ;;
    --use-zram)
      USE_ZRAM=true; shift ;;
    --use-bbg)
      USE_BBG=true; shift ;;
    --ksu-ref)
      KSU_REF="$2"; shift 2 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      echo "::error::未知参数: $1" >&2
      usage >&2
      exit 2 ;;
  esac
done

# ==================== 前置校验 ====================
die() {
  echo "::error::$*" >&2
  exit 1
}

log() {
  echo "[manet] $*"
}

warn() {
  echo "::warning::$*"
}

[[ -n "$WORKSPACE" ]] || die "--workspace 为必需参数"
[[ -d "$WORKSPACE" ]] || die "工作区不存在: $WORKSPACE"
[[ -d "$WORKSPACE/common" ]] || die "$WORKSPACE/common 不存在，请先执行 repo sync"
[[ -d "$WORKSPACE/common/drivers" ]] || die "$WORKSPACE/common/drivers 不存在"

case "$DROIDSPACES" in
  off|678|123|345) ;;
  *) die "--droidspaces 仅支持 off|678|123|345，当前: $DROIDSPACES" ;;
esac

if $NTSYNC && [[ "$DROIDSPACES" == "off" ]]; then
  die "--ntsync 需要配合 --droidspaces 使用"
fi

if $DROIDSPACES_EXTRAS && [[ "$DROIDSPACES" == "off" ]]; then
  die "--droidspaces-extras 需要配合 --droidspaces 使用"
fi

# ==================== 路径常量 ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMMON="$WORKSPACE/common"
FRAG="$COMMON/arch/arm64/configs/ksu.fragment"
FRAG_DIR="$(dirname "$FRAG")"

# 外部仓库克隆目录 (在工作区外，避免污染 Bazel 工作区)
CLONE_DIR="$WORKSPACE/.manet-clones"
mkdir -p "$CLONE_DIR"

SUSFS4KSU="$CLONE_DIR/susfs4ksu"
DROIDSPACES_REPO="$CLONE_DIR/Droidspaces-OSS"
SUKISU_PATCH="$CLONE_DIR/SukiSU_patch"

# ==================== 辅助函数 ====================

# 应用必需补丁: 先 dry-run，成功后 apply，失败则打印诊断并退出
# 参数: $1 = 补丁文件路径, $2 = strip 层级 (默认 1)
# 注意: dry-run 失败时绝不执行真实 apply，避免部分修改源码树
apply_required_patch() {
  local patch_file="$1"
  local strip="${2:-1}"

  [[ -f "$patch_file" ]] || die "必需补丁文件不存在: $patch_file"

  log "dry-run 补丁: $(basename "$patch_file")"
  if patch --forward --dry-run -p"$strip" < "$patch_file" >/dev/null 2>&1; then
    log "dry-run 通过，应用补丁: $(basename "$patch_file")"
    patch --forward -p"$strip" < "$patch_file"
    return 0
  fi

  # 检查是否已应用 (reverse dry-run 成功说明已应用)
  if patch --reverse --dry-run -p"$strip" < "$patch_file" >/dev/null 2>&1; then
    log "补丁已应用，跳过: $(basename "$patch_file")"
    return 0
  fi

  # dry-run 失败且未应用 — 打印完整诊断并退出，不执行真实 apply
  echo "::error::补丁 dry-run 失败: $patch_file" >&2
  echo "::error::dry-run 诊断输出:" >&2
  patch --forward --dry-run -p"$strip" < "$patch_file" >&2 || true

  die "必需补丁应用失败 (dry-run 未通过): $(basename "$patch_file")"
}

# 向 fragment 文件幂等追加配置行
frag_add() {
  local line="$1"
  mkdir -p "$FRAG_DIR"
  touch "$FRAG"
  if ! grep -qF "$line" "$FRAG" 2>/dev/null; then
    echo "$line" >> "$FRAG"
  fi
}

# 向 fragment 文件幂等追加多行配置
frag_add_block() {
  local block="$1"
  mkdir -p "$FRAG_DIR"
  touch "$FRAG"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! grep -qF "$line" "$FRAG" 2>/dev/null; then
      echo "$line" >> "$FRAG"
    fi
  done <<< "$block"
}

# 从 common/Makefile 提取 SUBLEVEL
extract_sublevel() {
  local sublevel=""
  if [[ -f "$COMMON/Makefile" ]]; then
    sublevel="$(grep '^SUBLEVEL = ' "$COMMON/Makefile" | awk '{print $3}')"
  fi
  echo "${sublevel:-0}"
}

# 判断配置符号是否在内核树的 Kconfig 中声明
# 参数: $1 = 符号名 (不含 CONFIG_ 前缀)
# 用途: 可选配置在换内核版本后可能不存在，直接写入 fragment 会让构建失败，
#       这里先确认符号存在再追加。
# 注意: GKI 构建由 common/(内核主体) 与 msm-kernel/(平台层) 合并而成，
#       符号可能任一侧声明，故两棵树都查。
sym_exists() {
  local sym="$1" dir
  for dir in "$COMMON" "$WORKSPACE/msm-kernel"; do
    [[ -d "$dir" ]] || continue
    if grep -rqE "^[[:space:]]*(menu)?config[[:space:]]+${sym}\$" \
         --include=Kconfig "$dir" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# 仅当符号存在时追加配置，否则打印告警并跳过
frag_add_if_exists() {
  local sym="$1"
  if sym_exists "$sym"; then
    frag_add "CONFIG_${sym}=y"
  else
    warn "内核树未声明 CONFIG_${sym}，已跳过 (可能该版本不支持)"
  fi
}

# ==================== 1. KernelSU (ReSukiSU) ====================
# manet 工作区是双树结构: common/ 是 repo sync 出来的 GKI 内核主体(承载 ksu.fragment
# 与 Bazel 的 //common: 包)，msm-kernel/ 是 Xiaomi BSP 平台层。
#
# ReSukiSU 的 setup.sh 用 GKI_ROOT=$(pwd) 推导路径，并检查 $GKI_ROOT/common/drivers，
# 因此必须在 $WORKSPACE(即 GKI_ROOT) 下执行 —— 它会:
#   - 把 KernelSU/ 源码放在 $WORKSPACE/KernelSU
#   - 在 common/drivers/ 建一个 symlink: kernelsu -> ../../KernelSU/kernel
#   - 往 common/drivers/Makefile 追加 obj-$(CONFIG_KSU) += kernelsu/
#   - 往 common/drivers/Kconfig 的「第一个 endmenu 之前」插入 source "drivers/kernelsu/Kconfig"
#
# 两个必须自己补的坑:
#
#  ① symlink 出树:Bazel 收包时不跟随指向包外的 symlink，common/drivers/kernelsu 会
#     被当成空目录，于是 CONFIG_KSU 无人声明。Bazel 配置校验随即报
#       CONFIG_KSU: actual '', expected 'CONFIG_KSU=y' from common/.../ksu.fragment
#       Are they declared in Kconfig?
#     这就是 kernel-manet.yml 一直失败的直接原因(纯 make 的 build.yml 不受影响，
#     因为 make 会正常跟随 symlink)。处置: 把 symlink 换成真实拷贝。
#
#  ② source 行位置:setup.sh 插在「第一个 endmenu」之前，若该 endmenu 处于某个
#     条件块内，source 会被跳过。这里统一改放到文件末尾(顶层、无条件生效)。
log "===== 1. 添加 ReSukiSU (ref: $KSU_REF) ====="
(
  cd "$WORKSPACE"
  curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s "$KSU_REF"
)

# KernelSU 源码由 setup.sh 放在 GKI_ROOT 下
KSU_SRC="$WORKSPACE/KernelSU"
[[ -d "$KSU_SRC" ]] || die "ReSukiSU 安装失败: $KSU_SRC 不存在"

# 把 KernelSU 驱动挂到「所有」内核树里。
#
# 为什么不是只挂 common/:
#   msm-kernel/ 本身就是一棵完整的 kernel 源码树(自带 drivers/、arch/、Kconfig)，
#   Bazel 目标 //msm-kernel:manet_gki_config 走的是 msm-kernel/ 的 Kconfig 解析。
#   设备的 /proc/kallsyms 也印证了这点:
#     gh_vm_mem_alloc               T            <- 内建进 vmlinux(来自 common/)
#     qcom_scm_gh_rm_pre_mem_share  T [gunyah_qcom] <- 厂商 .ko(来自 msm-kernel/)
#   即两棵树都会被真正编译。CONFIG_KSU 只挂到 common/ 时，msm-kernel 侧的配置
#   校验依然报 "CONFIG_KSU: actual ''"，构建中止。
#   因此在两棵树里都挂上，哪一侧解析都能命中。
#
# 另一个必须自己处理的点: setup.sh 建的是 symlink (drivers/kernelsu -> KernelSU/kernel)，
# 而 Bazel 收包不跟随指向包外的 symlink，会被当成空目录。这里统一换成真实拷贝。
KSU_TREES=("$COMMON" "$WORKSPACE/msm-kernel")
for TREE in "${KSU_TREES[@]}"; do
  KDIR="$TREE/drivers"
  if [[ ! -d "$KDIR" ]]; then
    warn "跳过 KernelSU 挂载(无 drivers 目录): $TREE"
    continue
  fi

  # symlink -> 真实目录 (Bazel 需要)
  if [[ -L "$KDIR/kernelsu" ]]; then
    log "  $TREE: symlink -> 真实拷贝"
    rm -f "$KDIR/kernelsu"
    cp -r "$KSU_SRC/kernel" "$KDIR/kernelsu"
  elif [[ ! -d "$KDIR/kernelsu" ]]; then
    cp -r "$KSU_SRC/kernel" "$KDIR/kernelsu"
  fi
  [[ -f "$KDIR/kernelsu/Kconfig" ]] || die "$TREE: kernelsu/Kconfig 缺失"

  # Makefile: obj-$(CONFIG_KSU) += kernelsu/
  grep -q 'kernelsu' "$KDIR/Makefile" 2>/dev/null \
    || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$KDIR/Makefile"

  # Kconfig: source 行确保在顶层(文件末尾)
  if ! grep -q 'drivers/kernelsu/Kconfig' "$KDIR/Kconfig" 2>/dev/null; then
    sed -i '/drivers\/kernelsu\/Kconfig/d' "$KDIR/Kconfig" 2>/dev/null || true
    printf '\nsource "drivers/kernelsu/Kconfig"\n' >> "$KDIR/Kconfig"
  fi

  # 校验 CONFIG_KSU 确实被声明
  grep -RqsE '^[[:space:]]*(menu)?config[[:space:]]+KSU$' "$KDIR/kernelsu" 2>/dev/null \
    || die "$TREE: kernelsu/Kconfig 中找不到 config KSU 声明"
  log "  $TREE: KernelSU 已挂载"
done
log "ReSukiSU 安装完成 (源码: $KSU_SRC)"

# ==================== 2. SUSFS ====================
if $SUSFS; then
  log "===== 2. 应用 SUSFS (分支: $SUSFS_BRANCH) ====="

  rm -rf "$SUSFS4KSU"
  git clone --depth 1 https://gitlab.com/simonpunk/susfs4ksu.git -b "$SUSFS_BRANCH" "$SUSFS4KSU"

  susfs_patch="$SUSFS4KSU/kernel_patches/50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch"
  [[ -f "$susfs_patch" ]] || die "SUSFS 主补丁不存在: $susfs_patch"

  # 复制 SUSFS 资源到 common (必需，缺失即失败)
  cd "$COMMON"
  cp "$susfs_patch" ./

  susfs_fs_dir="$SUSFS4KSU/kernel_patches/fs"
  susfs_inc_dir="$SUSFS4KSU/kernel_patches/include/linux"
  [[ -d "$susfs_fs_dir" ]] || die "SUSFS 资源目录不存在: $susfs_fs_dir"
  [[ -d "$susfs_inc_dir" ]] || die "SUSFS 资源目录不存在: $susfs_inc_dir"

  mkdir -p fs include/linux
  cp -r "$susfs_fs_dir/"* ./fs/
  cp -r "$susfs_inc_dir/"* ./include/linux/

  # ---------- SUSFS 补丁的前置兼容处理 ----------
  # SUSFS 主补丁是针对较新 AOSP common 编写的，其 fs/proc/base.c 的 hunk#1
  # 上下文要求 include 区存在 "#include <linux/dma-buf.h>"。
  # Xiaomi ACK 基线(ACK_SHA)下的 base.c 没有这一行（该 include 是后续
  # AOSP 提交才加的），导致 hunk#1 无法定位、整块补丁 dry-run 失败。
  # 这里按需补齐该 include，使补丁上下文成立；若已存在则不做任何改动。
  base_c="fs/proc/base.c"
  if [[ -f "$base_c" ]]; then
    if ! grep -q '#include <linux/dma-buf.h>' "$base_c"; then
      log "base.c 缺少 dma-buf.h include，按 SUSFS 补丁上下文补齐"
      if grep -q '#include <linux/cpufreq_times.h>' "$base_c"; then
        sed -i '/#include <linux\/cpufreq_times.h>/a #include <linux/dma-buf.h>' "$base_c"
      else
        # 退路: cpufreq_times.h 也不在时，插到 trace/events/oom.h 之前
        sed -i '0,/#include <trace\/events\/oom.h>/s//#include <linux\/dma-buf.h>\n#include <trace\/events\/oom.h>/' "$base_c"
      fi
      grep -n 'dma-buf.h' "$base_c" | head -3
    else
      log "base.c 已含 dma-buf.h include，跳过兼容处理"
    fi
  else
    warn "未找到 $base_c，跳过 SUSFS 前置兼容处理"
  fi

  # 应用 SUSFS 主补丁 (必需)
  apply_required_patch "50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch" 1

  # ---------- SUSFS 旧基线兼容: VMA_PAD_START ----------
  # manet ACK 基线是 6.1.25。新版 SUSFS 在 fs/proc/task_mmu.c 使用
  # VMA_PAD_START(vma)，但该宏是后续 stable 合入，6.1.25 还没有。
  # 未补时 clang 直接报:
  #   error: call to undeclared function 'VMA_PAD_START'
  # 语义上 SUSFS 需要的是虚拟 VMA 的末端地址，旧内核等价写法就是 vma->vm_end。
  task_mmu="$COMMON/fs/proc/task_mmu.c"
  if [[ -f "$task_mmu" ]] && grep -q 'VMA_PAD_START' "$task_mmu" \
     && ! grep -q 'define VMA_PAD_START' "$task_mmu"; then
    sed -i '0,/^#include /s//#ifndef VMA_PAD_START\n#define VMA_PAD_START(vma) ((vma)->vm_end)\n#endif\n&/' "$task_mmu"
    log "已为 6.1.$(extract_sublevel) 补 VMA_PAD_START 兼容定义"
  fi

  # ---------- SUSFS 宏声明兜底 ----------
  # 某些旧 ACK 的 task_mmu.c include 上下文与 SUSFS patch 预期不同，导致代码 hunk
  # 成功但 susfs_def.h 的 include hunk 漏掉。检测到 SUSFS 宏却没有头文件时补齐。
  if [[ -f "$task_mmu" ]] && \
     grep -qE 'SUSFS_IS_INODE_SUS_MAP|SUSFS_IS_INODE_OPEN_REDIRECT' "$task_mmu" && \
     ! grep -qF '#include <linux/susfs_def.h>' "$task_mmu"; then
    if grep -qF '#include <linux/pkeys.h>' "$task_mmu"; then
      sed -i '/#include <linux\/pkeys.h>/a #if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs_def.h>\n#endif' "$task_mmu"
    elif grep -qF '#include <linux/uaccess.h>' "$task_mmu"; then
      sed -i '/#include <linux\/uaccess.h>/a #if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs_def.h>\n#endif' "$task_mmu"
    else
      sed -i '0,/^#include /s//#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs_def.h>\n#endif\n&/' "$task_mmu"
    fi
    log "已补 task_mmu.c 的 susfs_def.h 条件 include"
  fi

  # SUSFS 配置写入 fragment
  frag_add_block "$(cat <<'EOF'
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
EOF
)"

  log "SUSFS 应用完成"

  # SUSFS 与 Droidspaces 的已知交互问题（内核侧无法自动修复，只能运行时规避）
  if [[ "$DROIDSPACES" != "off" ]]; then
    warn "已同时启用 SUSFS 与 Droidspaces —— 二者存在已知冲突"
    warn "  原因: SUSFS 的 sus_mount 会隐藏挂载点，容器启动时需要看到自己的挂载，"
    warn "        隐藏后容器会启动失败或行为异常。"
    warn "  处置: 刷入后在 SUSFS 设置中关闭"
    warn "        「HIDE SUS MOUNTS FOR ALL PROCESSES / 对所有进程隐藏 sus 挂载」"
    warn "        及「开机完成时关闭」选项，保持常驻关闭。"
    warn "  说明: 这是官方标注的已知限制，不是本脚本的缺陷，"
    warn "        内核编译层面无法规避，只能通过上述设置规避。"
  fi
fi

# ==================== 2.5 Gunyah SM8650 虚拟机启动修复 ====================
# 小米 manet (SM8650 / 8 Gen 3) 的 Gunyah 存在两个缺陷，会导致 DroidVM 等
# 基于 crosvm+Gunyah 的虚拟机管理器无法创建虚拟机：
#   1) gh_vm_mem_alloc() 用高阶 kcalloc 分配 pinned page 指针数组
#      (4 GiB 客机即需 8 MiB)，碎片化后失败 -> "Out of memory (os error 12)"
#   2) SCM VMID 映射错误 -> RM 拒绝 mem parcel -> "No such device (os error 19)"
# 补丁移植自 DroidVM 官方 FAQ 给出的两个上游修复。
#
# 两棵树都可能承载 Gunyah: common/ 里的 vm_mgr_mm.c 会内建进 vmlinux
# (设备 kallsyms 中 gh_vm_mem_alloc 无 [module] 标记)，而 msm-kernel/ 里的
# gunyah_qcom.c 编成厂商 .ko (qcom_scm_gh_rm_pre_mem_share T [gunyah_qcom])。
# 因此按文件粒度分别在每棵树里尝试应用，哪棵树存在该文件就修哪棵；
# 补丁已改为树内相对路径(patches/0003-gunyah-*.patch)，-p1 从树根即可。
if $GUNYAH_FIX; then
  log "===== 2.5 应用 Gunyah SM8650 启动修复 ====="

  GUNYAH_MAP=(
    "0003-gunyah-vm_mgr_mm.patch:vm_mgr_mm.c:kvcalloc(mapping->npages"
    "0003-gunyah-qcom.patch:gunyah_qcom.c:qcom_scm_map_vmid"
  )

  for ENTRY in "${GUNYAH_MAP[@]}"; do
    PNAME="${ENTRY%%:*}"
    REST="${ENTRY#*:}"
    FNAME="${REST%%:*}"
    MARK="${REST#*:}"
    PPATH="$REPO_ROOT/patches/$PNAME"

    if [[ ! -f "$PPATH" ]]; then
      warn "Gunyah 补丁不存在，跳过: $PPATH"
      continue
    fi

    applied=false
    for TREE in "${KSU_TREES[@]}"; do
      TARGET="$TREE/drivers/virt/gunyah/$FNAME"
      [[ -f "$TARGET" ]] || continue

      # 已修则跳过
      if grep -qF "$MARK" "$TARGET" 2>/dev/null; then
        log "  ${TREE#$WORKSPACE/}/drivers/virt/gunyah/$FNAME 已是修复后状态"
        applied=true
        continue
      fi

      # 允许逐树跳过: common/ 与 msm-kernel/ 的同一文件来自不同上游
      # (AOSP ACK vs Xiaomi BSP)，顶部上下文可能有细微差异。
      # 只要目标函数结构一致就修；不一致的那棵树跳过并告警，不中断整个构建。
      # 注意 common/ 的 gunyah_qcom.c 实际不参与编译 —— GKI defconfig 里
      # CONFIG_GUNYAH_QCOM_PLATFORM 未设置，设备上跑的是 msm-kernel 编出的
      # 厂商模块，因此真正必须修的是 msm-kernel 那棵。
      if ! ( cd "$TREE" && patch --forward --dry-run -p1 < "$PPATH" >/dev/null 2>&1 ); then
        if ( cd "$TREE" && patch --reverse --dry-run -p1 < "$PPATH" >/dev/null 2>&1 ); then
          log "  ${TREE#$WORKSPACE/}/$FNAME 已应用，跳过"
          applied=true
        else
          warn "  ${TREE#$WORKSPACE/}/$FNAME 上下文不匹配($PNAME)，跳过该树"
        fi
        continue
      fi

      ( cd "$TREE" && apply_required_patch "$PPATH" 1 )

      if grep -qF "$MARK" "$TARGET" 2>/dev/null; then
        log "  校验通过: ${TREE#$WORKSPACE/}/drivers/virt/gunyah/$FNAME ($MARK)"
        applied=true
      else
        warn "  校验未命中: $TARGET 未出现 $MARK"
      fi
    done

    if ! $applied; then
      die "Gunyah 补丁 $PNAME 在两棵树都未能应用，无法确认修复生效"
    fi
  done
fi

# ==================== 3. Droidspaces SYSVIPC kABI ====================
if [[ "$DROIDSPACES" != "off" ]]; then
  log "===== 3. 应用 Droidspaces SYSVIPC kABI (槽位: $DROIDSPACES) ====="

  rm -rf "$DROIDSPACES_REPO"
  git clone --depth 1 https://github.com/ravindu644/Droidspaces-OSS.git "$DROIDSPACES_REPO"

  # 槽位转换: 678 -> 6_7_8, 123 -> 1_2_3, 345 -> 3_4_5
  slot_name="$(echo "$DROIDSPACES" | sed 's/\(.\)/\1_/g; s/_$//')"
  patch_file="$DROIDSPACES_REPO/Documentation/resources/kernel-patches/GKI/below-kernel-6.12/001.GKI-below-6.12-fix_sysvipc_kabi_${slot_name}.patch"

  [[ -f "$patch_file" ]] || die "Droidspaces SYSVIPC 补丁不存在: $patch_file"

  cd "$COMMON"
  apply_required_patch "$patch_file" 1

  # Droidspaces 配置写入 fragment
  frag_add_block "$(cat <<'EOF'
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_IPC_NS=y
CONFIG_PID_NS=y
CONFIG_DEVTMPFS=y
EOF
)"

  log "Droidspaces SYSVIPC kABI 应用完成"

  # ---------- 可选进阶配置 ----------
  # 全部为官方 GKI 清单中标注 optional/recommended 的项。
  # 与上面 5 项不同，这些不是容器启动的硬性前提，缺失只影响对应能力。
  if $DROIDSPACES_EXTRAS; then
    log "----- 追加 Droidspaces 可选配置 -----"

    # 沙箱：Docker/Podman 的 "unsafe procfs" 报错需要它
    # 安全性说明: cred.user_ns 与 nsproxy 的字段在本树均为无条件声明，
    # 开启不会改变 struct cred / struct nsproxy 尺寸，kABI 安全。
    frag_add_if_exists "USER_NS"

    # NAT 增强：容器出网走 MASQUERADE，缺 ADDRTYPE 时部分上游地址无法匹配
    frag_add_if_exists "NETFILTER_XT_MATCH_ADDRTYPE"

    # IPv6 NAT (NAT66)：容器内 IPv6 出网
    frag_add_if_exists "IP6_NF_NAT"
    frag_add_if_exists "IP6_NF_TARGET_MASQUERADE"

    # UFW 支持
    # 注: 官方 GKI 清单写的是 NETFILTER_XT_TARGET_REJECT，但 6.1 树用的是
    #     IP_NF_TARGET_REJECT / IP6_NF_TARGET_REJECT；两者都试，存在才写入。
    frag_add_if_exists "NETFILTER_XT_TARGET_REJECT"
    frag_add_if_exists "IP_NF_TARGET_REJECT"
    frag_add_if_exists "IP6_NF_TARGET_REJECT"
    frag_add_if_exists "NETFILTER_XT_TARGET_LOG"
    frag_add_if_exists "NETFILTER_XT_MATCH_RECENT"

    # Fail2ban 支持
    frag_add_if_exists "IP_SET"
    frag_add_if_exists "IP_SET_HASH_IP"
    frag_add_if_exists "IP_SET_HASH_NET"
    frag_add_if_exists "NETFILTER_XT_SET"

    # tmpfs 的 xattr / posix acl (NixOS 等需要)
    frag_add_if_exists "TMPFS_POSIX_ACL"
    frag_add_if_exists "TMPFS_XATTR"

    log "Droidspaces 可选配置追加完成"
    log "注意: 未启用 CFS_BANDWIDTH / CGROUP_PIDS —— 二者会真实改变调度器与 cgroup"
    log "      结构体尺寸，导致大量导出符号 CRC 变化、厂商模块拒载，且无 kABI 补丁可救。"
    log "      代价是 --cpus 与 --pids-limit 两个资源限制参数不可用。"
  fi
fi

# ==================== 4. NTSync ====================
if $NTSYNC; then
  log "===== 4. 应用 NTSync 补丁 (android14-6.1) ====="

  ntsync_base="$CLONE_DIR/ntsync_base.patch"
  ntsync_variant="$CLONE_DIR/ntsync_compat_android14-6.1.patch"

  wget -q -O "$ntsync_base" \
    "https://raw.githubusercontent.com/Goldzxcbug/Droidspaces_Kernel_patch/refs/heads/main/NTsync/ntsync_base.patch"
  wget -q -O "$ntsync_variant" \
    "https://raw.githubusercontent.com/Goldzxcbug/Droidspaces_Kernel_patch/refs/heads/main/NTsync/ntsync_compat_android14-6.1.patch"

  [[ -f "$ntsync_base" ]] || die "NTSync base 补丁下载失败"
  [[ -f "$ntsync_variant" ]] || die "NTSync android14-6.1 补丁下载失败"

  cd "$COMMON"
  apply_required_patch "$ntsync_base" 1
  apply_required_patch "$ntsync_variant" 1

  frag_add "CONFIG_NTSYNC=y"
  log "NTSync 补丁应用完成"
fi

# ==================== 5. CVE-2026-43499 rtmutex 修复 ====================
if $CVE; then
  log "===== 5. 应用 CVE-2026-43499 rtmutex 修复链 ====="

  cve_script="$REPO_ROOT/security_patch/apply_cve_2026_43499.sh"
  [[ -f "$cve_script" ]] || die "CVE 修复脚本不存在: $cve_script"

  sublevel="$(extract_sublevel)"
  log "检测到 SUBLEVEL: $sublevel"

  cd "$COMMON"
  bash "$cve_script" "$KERNEL_VERSION" "$sublevel" "$REPO_ROOT/security_patch"

  log "CVE-2026-43499 修复链应用完成"
fi

# ==================== 6. ZRAM LZ4 增强 ====================
if $USE_ZRAM; then
  log "===== 6. 应用 ZRAM LZ4 增强补丁栈 ====="

  # 克隆 SukiSU_patch (提供 lz4k / lz4k_oplus 资源)
  rm -rf "$SUKISU_PATCH"
  git clone --depth 1 https://github.com/ShirkNeko/SukiSU_patch.git "$SUKISU_PATCH"

  cd "$COMMON"

  # 第一阶段: 升级 LZ4 到 1.10.0 并添加 ARM64 NEON 加速
  log "升级 LZ4 源码..."
  rm -f lib/lz4/lz4_compress.c lib/lz4/lz4_decompress.c lib/lz4/lz4defs.h lib/lz4/lz4hc_compress.c
  cp -r "$REPO_ROOT/zram/lz4/"* ./lib/lz4/
  cp -r "$REPO_ROOT/zram/include/linux/"* ./include/linux/
  bash "$REPO_ROOT/zram/apply_lz4_neon.sh"

  # f2fs iostat Makefile 修复 (幂等)
  if [[ -f "fs/f2fs/Makefile" ]] && ! grep -qF 'f2fs-$(CONFIG_F2FS_IOSTAT) += iostat.o' "fs/f2fs/Makefile"; then
    echo 'f2fs-$(CONFIG_F2FS_IOSTAT) += iostat.o' >> "fs/f2fs/Makefile"
  fi

  # 第二阶段: LZ4KD 和 LZ4K_OPLUS 补丁
  log "复制 LZ4K 资源..."
  cp -r "$SUKISU_PATCH/other/zram/lz4k/include/linux/"* ./include/linux/
  cp -r "$SUKISU_PATCH/other/zram/lz4k/lib/"* ./lib/
  cp -r "$SUKISU_PATCH/other/zram/lz4k/crypto/"* ./crypto/
  cp -r "$SUKISU_PATCH/other/zram/lz4k_oplus" ./lib/

  lz4kd_patch="$SUKISU_PATCH/other/zram/zram_patch/${KERNEL_VERSION}/lz4kd.patch"
  lz4k_oplus_patch="$SUKISU_PATCH/other/zram/zram_patch/${KERNEL_VERSION}/lz4k_oplus.patch"

  [[ -f "$lz4kd_patch" ]] || die "lz4kd.patch 不存在: $lz4kd_patch"
  [[ -f "$lz4k_oplus_patch" ]] || die "lz4k_oplus.patch 不存在: $lz4k_oplus_patch"

  cp "$lz4kd_patch" ./
  cp "$lz4k_oplus_patch" ./

  apply_required_patch "lz4kd.patch" 1
  apply_required_patch "lz4k_oplus.patch" 1

  # ZRAM 配置写入 fragment
  frag_add_block "$(cat <<'EOF'
CONFIG_ZSMALLOC=y
CONFIG_ZRAM=y
CONFIG_CRYPTO_LZ4HC=y
CONFIG_CRYPTO_LZ4K=y
CONFIG_CRYPTO_LZ4KD=y
CONFIG_CRYPTO_842=y
CONFIG_CRYPTO_LZ4K_OPLUS=y
EOF
)"

  # android14: 从 modules.bzl 移除 zram/zsmalloc 模块声明 (改为内建)
  modules_bzl="$COMMON/modules.bzl"
  if [[ -f "$modules_bzl" ]]; then
    log "从 modules.bzl 移除 zram/zsmalloc 模块声明..."
    sed -i 's/"drivers\/block\/zram\/zram\.ko",//g; s/"mm\/zsmalloc\.ko",//g' "$modules_bzl"
  fi

  log "ZRAM LZ4 增强补丁栈应用完成"
fi

# ==================== 7. BBG 防格机 ====================
if $USE_BBG; then
  log "===== 7. 应用 BBG 防格机 ====="

  (
    cd "$WORKSPACE"
    wget -O- https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash
  )

  # 修改 security/Kconfig 添加 baseband_guard 到 LSM 默认列表 (幂等)
  kconfig="$COMMON/security/Kconfig"
  if [[ -f "$kconfig" ]]; then
    if ! grep -q 'baseband_guard' "$kconfig"; then
      sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/selinux/selinux,baseband_guard/ } }' "$kconfig"
    fi
  fi

  frag_add "CONFIG_BBG=y"
  log "BBG 防格机应用完成"
fi

# ==================== 7.5 修复 glibc 2.38+ 链接错误 ====================
# 症状: 编译到链接阶段报
#   ld.lld: error: undefined symbol: __isoc23_strtol / __isoc23_strtoul / __isoc23_strtoull
#   clang-17: error: linker command failed with exit code 1
#
# 原因: glibc 2.38 起把 strtol/strtoul/strtoull 改成了 __isoc23_* 符号(ISO C23 语义)。
#   resolve_btfids 这个 host 工具由 tools/bpf/resolve_btfids/Makefile 通过子 make 编译，
#   子 make 没有继承主编译的 EXTRA_CFLAGS，于是仍按旧 ABI 链接，落在新 glibc 上就找不到符号。
#   上游修复(见 build.yml「修复 glibc 2.38 兼容性」)是给该子 make 传入 EXTRA_CFLAGS。
#
# 触发条件与上游一致: 6.1 且 SUBLEVEL <= 43 (manet 为 6.1.x 早期基线，命中)。
# glibc < 2.38 时无需处理，直接跳过。
log "===== 7.5 检查 glibc 2.38+ 兼容性 ====="
CURRENT_SUB="$(extract_sublevel)"
if [[ ! "$CURRENT_SUB" =~ ^[0-9]+$ ]]; then
  warn "无法解析 SUBLEVEL(得到 '$CURRENT_SUB')，按需要修复处理"
  CURRENT_SUB=99999
fi

NEEDS_GLIBC_FIX=false
if [[ "$ANDROID_VERSION" == "android14" && "$KERNEL_VERSION" == "6.1" && "$CURRENT_SUB" -le 43 ]]; then
  NEEDS_GLIBC_FIX=true
fi

if $NEEDS_GLIBC_FIX; then
  GLIBC_VERSION="$(ldd --version 2>/dev/null | head -n 1 | awk '{print $NF}')"
  if [[ -n "$GLIBC_VERSION" ]] && \
     [[ "$(printf '%s\n' "2.38" "$GLIBC_VERSION" | sort -V | head -n1)" == "2.38" ]]; then
    log "glibc $GLIBC_VERSION >= 2.38 且 SUBLEVEL=$CURRENT_SUB，应用 EXTRA_CFLAGS 修复"

    # 两棵树都要修: 构建日志显示真正被编译的 resolve_btfids 位于
    #   out/cache/<hash>/msm-kernel/tools/bpf/resolve_btfids/
    # 即 msm-kernel 那棵；只修 common/ 时错误照旧。
    for TREE in "${KSU_TREES[@]}"; do
      rbf="$TREE/tools/bpf/resolve_btfids/Makefile"
      if [[ ! -f "$rbf" ]]; then
        warn "未找到 $rbf，跳过"
        continue
      fi
      # 给子 make 传入 EXTRA_CFLAGS，使 host 工具按当前 glibc 的 ABI 链接
      sed -i '/\$(Q)\$(MAKE) -C \$(SUBCMD_SRC) OUTPUT=\$(abspath \$(dir \$@))\/ \$(abspath \$@)/s//$(Q)$(MAKE) -C $(SUBCMD_SRC) EXTRA_CFLAGS="$(CFLAGS)" OUTPUT=$(abspath $(dir $@))\/ $(abspath $@)/' "$rbf" 2>/dev/null || true
      if grep -q 'EXTRA_CFLAGS' "$rbf"; then
        log "  ${TREE#$WORKSPACE/}: resolve_btfids/Makefile 已注入 EXTRA_CFLAGS"
      else
        warn "  ${TREE#$WORKSPACE/}: 未匹配到目标行，链接错误可能仍会出现"
      fi
    done

    # 5.10/5.15 还需要改写 parse-options.c 的 for 循环声明(C99 声明位置问题)。
    # 6.1 已修正，这里仅对旧版内核生效，保持与上游一致。
    if [[ "$KERNEL_VERSION" == "5.10" || "$KERNEL_VERSION" == "5.15" ]]; then
      po="$COMMON/tools/lib/subcmd/parse-options.c"
      if [[ -f "$po" ]]; then
        sed -i '/char \*buf = NULL;/a int i;' "$po" 2>/dev/null || true
        sed -i 's/for (int i = 0; subcommands\[i\]; i++) {/for (i = 0; subcommands[i]; i++) {/' "$po" 2>/dev/null || true
        log "  parse-options.c 已改写(5.10/5.15)"
      fi
    fi
  else
    log "glibc ${GLIBC_VERSION:-未知} < 2.38，无需修复"
  fi
else
  log "SUBLEVEL=$CURRENT_SUB 不在需要 glibc 修复的范围内，跳过"
fi

# ==================== 8. 基础内核配置 fragment ====================
log "===== 8. 生成基础内核配置 fragment ====="

# KSU 基础配置 (始终写入，因为 ReSukiSU 已安装)
frag_add "CONFIG_KSU=y"
frag_add "CONFIG_TMPFS_XATTR=y"
frag_add "CONFIG_TMPFS_POSIX_ACL=y"

# ==================== 9. 输出 fragment 摘要 ====================
log "===== 9. fragment 文件摘要 ====="
if [[ -f "$FRAG" ]]; then
  echo "=== $FRAG ==="
  cat "$FRAG"
  echo "========================="
  log "fragment 文件已生成: $FRAG"
  log "Bazel 构建参数: --defconfig_fragment=//common:arch/arm64/configs/ksu.fragment"
else
  warn "fragment 文件未生成 (无配置项)"
fi

# ==================== 10. 收集 .rej 文件 ====================
rej_files="$(find "$COMMON" -type f -name '*.rej' 2>/dev/null || true)"
if [[ -n "$rej_files" ]]; then
  echo "::error::检测到 .rej 文件:" >&2
  echo "$rej_files" >&2
  die "存在未解决的补丁冲突"
fi

log "===== manet 补丁集成完成 ====="
