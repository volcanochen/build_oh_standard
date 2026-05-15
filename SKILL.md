---
name: build_oh_standard
description: "OpenHarmony Standard System QEMU Build Skill - 构建可运行在 QEMU ARM64 的 OpenHarmony 标准系统镜像。触发场景：用户请求构建 OpenHarmony QEMU 镜像、解决 OpenHarmony 编译错误、询问 OpenHarmony 依赖关系、需要配置 OpenHarmony 产品。核心能力：问题诊断与解决 (HUKS/测试/Rust 格式冲突)、依赖关系分析、Docker 环境配置"
---

# OpenHarmony QEMU ARM64 构建技能

## ⚠️ 重要说明

1. **Docker 镜像版本与源码版本无需匹配**：Docker 镜像仅提供基础工具（Python、bash），编译工具链由源码 `prebuilts` 自行提供。`docker_oh_standard:3.2` 可构建 OpenHarmony 3.2/4.0/4.1。

2. **删除编译产物需管理员权限时**：进入 Docker 容器以 root 删除：
   ```bash
   docker run --rm -v $(pwd):/workspace -w /workspace \
     swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2 \
     rm -rf out/
   ```

3. **问题分析必须具体**：不要猜测原因，通过增加日志或打开日志等级收集更多信息。

4. **记录决策过程**：选择方案后记录到 markdown 文档，记录决策原因和过程。

5. **先最小化验证**：先验证单模块改动，确认有效后再回到完整构建流程。

6. **增量编译使用 `--fast-rebuild`**：`hb build --fast-rebuild` 跳过 preloader 和 GN gen，只运行 ninja。

7. **⚠️ `hb set` 和 `hb build -f` 会导致增量失效**：`hb set xxx` 重新生成产品配置，`hb build -f` 强制全量编译，请谨慎选择。

***

## 快速开始

### 首次完整构建

```bash
cd /path/to/ohos_standard

# 1. 下载预编译工具
bash build/prebuilts_download.sh

# 2. Docker 构建
docker run --rm -v $(pwd):/workspace -w /workspace \
  swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2 \
  bash -c "
    cp /workspace/prebuilts/rustc/linux-x86_64/current/lib/libstd*.so /usr/lib/ && \
    python3 -m pip install --user build/hb > /dev/null 2>&1 && \
    export PATH=/root/.local/bin:\$PATH && \
    hb set --product-name qemu-arm64-linux-min@ohemu && \
    hb build -f --load-test-config false
  "
```

步骤说明：

| Step | 命令 | 说明 |
|------|------|------|
| 1 | `bash build/prebuilts_download.sh` | 下载预编译工具链 |
| 2 | `cp libstd*.so /usr/lib/` | 解决 Rust 动态库依赖 |
| 3 | `pip install build/hb` | 安装 hb 工具 |
| 4 | `hb set --product-name` | 设置产品名 |
| 5 | `hb build -f` | 执行编译 |

### 增量构建

```bash
docker run --rm -v $(pwd):/workspace -w /workspace \
  swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2 \
  bash -c "
    python3 -m pip install --user build/hb > /dev/null 2>&1 && \
    export PATH=/root/.local/bin:\$PATH && \
    hb build --fast-rebuild
  "
```

### 清理后重建

```bash
docker run --rm -v $(pwd):/workspace -w /workspace \
  swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2 \
  bash -c "
    rm -rf /workspace/out && \
    python3 -m pip install --user build/hb > /dev/null 2>&1 && \
    export PATH=/root/.local/bin:\$PATH && \
    hb set --product-name qemu-arm64-linux-min@ohemu && \
    hb build -f --load-test-config false
  "
```

### 使用构建脚本

```bash
cd /path/to/ohos_standard
chmod +x /path/to/skills/build_oh_standard/scripts/build_qemu.sh

./build_qemu.sh              # 标准构建
./build_qemu.sh --gn-only    # 仅验证 GN 依赖 (~1分钟)
./build_qemu.sh --clean      # 清理后构建
```

### 最小化验证

```bash
# 单独编译某个模块
hb build commonlibrary/rust/ylong_runtime/ylong_runtime:ylong_runtime
```

### 关键参数

| 参数 | 含义 |
|------|------|
| `-f` | 强制全量编译 |
| `--fast-rebuild` | 跳过 preloader 和 GN gen，只运行 ninja 增量编译 |
| `--load-test-config false` | 禁用测试配置加载 |
| `--gn-only` | 仅运行 GN 依赖检查 |

***

## 增量编译指南

`hb build` 默认执行完整流程：`preloader → loader → GN gen → ninja`

| 构建方式 | 命令 | preloader | GN gen | ninja | 时间 |
|---------|------|-----------|--------|-------|------|
| 全量编译 | `hb build -f` | ✅ | ✅ | ✅ 全量 | ~17 分钟 |
| 增量编译 | `hb build --fast-rebuild` | ❌ | ❌ | ✅ 增量 | ~1-5 分钟 |

**✅ 适合增量编译**: 修改源码 (.c, .cpp, .h)、小范围代码调整

**❌ 不适合增量编译**: 修改 BUILD.gn、修改 config.json、切换产品、更新源码后首次构建

**Docker 持久化**: 使用 `-v $(pwd):/workspace` 挂载工作目录，确保 `out/` 在容器删除后不丢失。

***

## 问题诊断流程

### 确定错误类型

| 错误模式 | 问题类型 | 参考 |
|---------|---------|------|
| `fatal error: 'xxx.h' not found` | 头文件缺失 | [troubleshooting.md](references/troubleshooting.md) §1-4 |
| `GN phase failed` | GN 依赖缺失 | [troubleshooting.md](references/troubleshooting.md) §2 |
| `FAILED: obj/...` | Ninja 编译失败 | [troubleshooting.md](references/troubleshooting.md) §1 |
| `cannot satisfy dependencies so 'std' only shows up once` | Rust 库格式冲突 | 见下方 §2.1 |

### 常见问题解决

#### 2.1 Rust 库格式冲突 ⭐重要

**根因**：预编译库为 rlib 格式，ylong_runtime 为 dylib 格式，Rust 编译器要求 std 只能以一种格式出现。

**解决方案**：将 `ylong_runtime` 从 dylib 改为 rlib：
1. `commonlibrary/rust/ylong_runtime/ylong_runtime/BUILD.gn`：`ohos_rust_shared_library` → `ohos_rust_static_library`
2. `build/scripts/gen_sdk_build_file.py` 添加 rlib 支持

详细步骤见 [rust-knowledge.md](references/rust-knowledge.md)

#### 2.2 HUKS 编译失败（最常见）

```bash
# 症状: user_idm_client.h / common_event_manager.h not found
# 解决: 移除 huks 组件
sed -i '/"huks"/d' vendor/ohemu/qemu_arm64_linux_min/config.json
```

#### 2.3 其他问题

详见 [troubleshooting.md](references/troubleshooting.md)

### 验证修复

```bash
hb build --gn-only        # 先验证 GN 依赖 (~1分钟)
hb build --fast-rebuild   # 确认通过后增量构建
```

***

## 依赖关系要点

| 风险等级 | 组件 | 说明 |
|---------|------|------|
| 🔴 高 | HUKS | 25+ 间接依赖，QEMU ARM64 下建议默认禁用 |
| 🟡 中 | accesstoken, dsoftbus | 谨慎添加 |
| 🟢 低 | samgr, safwk, eventhandler, hilog | 通常可用 |

详细依赖图: [dependencies.md](references/dependencies.md)

***

## 产品配置

配置文件：`vendor/ohemu/qemu_arm_linux_min/config.json`

当前配置含 samgr + Rust IPC，详见 [rust-knowledge.md](references/rust-knowledge.md)

***

## 构建产物

```
out/qemu-arm-linux/packages/phone/images/
├── Image           31M    Linux 内核
├── ramdisk.img     2.2M   初始化内存盘
├── system.img      100M   系统分区
├── vendor.img      100M   厂商分区
├── userdata.img    100M   用户数据
├── eng_system.img  12M    工程测试镜像
└── updater.img     6.9M   更新镜像
```

***

## 经验总结

1. **HUKS 是深水区**：在 QEMU ARM64 下依赖链几乎无法简化，建议默认禁用
2. **先 GN 后 Ninja**：`hb build --gn-only` 可快速验证依赖 (~1分钟)
3. **测试隔离**：测试代码与产品代码的条件编译必须一致
4. **最小化原则**：不需要的组件不要添加，避免引入复杂依赖
5. **Docker 持久化 out 目录**：使用 `docker run -v $(pwd):/workspace` 挂载工作目录

***

*构建验证: 34 次构建 (使用 3.2 版本镜像)*
*最终状态: ✅ SUCCESS*
