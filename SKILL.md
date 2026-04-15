---
name: build_oh_standard
description: "OpenHarmony Standard System QEMU Build Skill - 构建可运行在 QEMU ARM64 的 OpenHarmony 标准系统镜像。

**触发场景**:
- 用户请求构建 OpenHarmony QEMU 镜像
- 用户请求解决 OpenHarmony 编译错误
- 用户询问 OpenHarmony 依赖关系
- 用户需要配置 OpenHarmony 产品

**核心能力**:
- 完整构建流程 (34 次构建验证)
- 问题诊断与解决 (HUKS/测试/Rust 格式冲突)
- 依赖关系分析
- Docker 环境配置"
---

# OpenHarmony QEMU ARM64 构建技能

## ⚠️ 重要说明

**Docker 镜像版本与源码版本无需匹配！**

| 组件 | 版本来源 | 说明 |
|------|----------|------|
| 基础工具 | Docker 镜像 | Python、bash 等基础工具 |
| 编译工具链 | 源码 prebuilts | gcc、rustc 等由 `build/prebuilts_download.sh` 下载 |

Docker 镜像仅提供基础运行环境，**编译工具链由源码自行提供**，因此：
- `docker_oh_standard:3.2` 可以用来构建 OpenHarmony 4.1 Release
- 版本不匹配**不会**导致编译链问题

| 源码版本 | Docker 镜像 | 说明 |
|---------|-------------|------|
| OpenHarmony 3.2 | `docker_oh_standard:3.2` | 官方稳定版 |
| OpenHarmony 4.0/4.1 | `docker_oh_standard:3.2` ✅ 可用 | 基础工具兼容 |

---

## 快速开始

### 标准构建流程 (17分钟)

```bash
cd /path/to/ohos_standard

# 1. 确认源码版本 (加速)
cat .repo/manifests/default.xml | grep revision

# 2. 确认并拉取对应版本的 Docker 镜像
docker pull swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2

# 3. 下载预编译工具
bash build/prebuilts_download.sh

# 4. Docker 构建 (增量编译，保留 out 目录)
#    - 首次构建: 完整编译
#    - 后续构建: 增量编译，只重新编译有变化的模块
docker run --rm -v $(pwd):/workspace -w /workspace \
  swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2 \
  bash -c "
    python3 -m pip install --user build/hb && \
    export PATH=/root/.local/bin:\$PATH && \
    hb set --product-name qemu-arm64-linux-min@ohemu && \
    hb build -f
  "

# 5. 验证产物 (确认有新的构建输出)
ls -lh out/qemu-arm-linux/packages/phone/images/ && \
  echo "--- Build Hash Check ---" && \
  sha256sum out/qemu-arm-linux/packages/phone/images/Image

# 6. 完全重编译 (如需清理旧构建)
#    在 Docker 容器内以 root 权限删除 out 目录
docker run --rm -v $(pwd):/workspace -w /workspace \
  swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2 \
  bash -c "
    rm -rf /workspace/out && \
    python3 -m pip install --user build/hb && \
    export PATH=/root/.local/bin:\$PATH && \
    hb set --product-name qemu-arm64-linux-min@ohemu && \
    hb build -f
  "
```

### 使用构建脚本 (推荐)

```bash
cd /path/to/ohos_standard
chmod +x /path/to/skills/build_oh_standard/scripts/build_qemu.sh

# 标准构建 (需确认脚本内镜像版本匹配)
./build_qemu.sh

# 仅验证 GN 依赖 (~1分钟)
./build_qemu.sh --gn-only

# 清理后构建
./build_qemu.sh --clean
```

---

## 问题诊断流程

遇到构建错误时，按顺序检查：

### 1. 确定错误类型

| 错误模式 | 问题类型 | 参考文档 |
|---------|---------|---------|
| `fatal error: 'xxx.h' not found` | 头文件缺失 | troubleshooting.md §1-4 |
| `GN phase failed` | GN 依赖缺失 | troubleshooting.md §2 |
| `FAILED: obj/...` | Ninja 编译失败 | troubleshooting.md §1 |
| `Ninja build...` 无输出 | 构建卡住 | 重新运行 |
| `cannot satisfy dependencies so 'std' only shows up once` | Rust 库格式冲突 | 见 §2.1 |

### 2. 常见问题解决

#### 2.1 Rust 库格式冲突 (std only shows up once) ⭐重要

```
症状: error: cannot satisfy dependencies so `std` only shows up once
     = help: having upstream crates all available in one format will likely make this go away
错误位置: RUST dylib communication/ipc/libipc_rust.dylib.so
```

**根因分析:**

| 组件 | 格式 | 来源 |
|------|------|------|
| 预编译库 (ylong_runtime 等) | rlib (静态库) | out/ 目录下提前编译好的库 |
| git 依赖 (ipc_rust 的依赖) | dylib (动态库) | Cargo.toml 从 git 拉取后编译 |
| ipc_rust 本身 | dylib | GN 模板 `ohos_rust_shared_library` 硬编码 `crate_type = "dylib"` |

Rust 编译器要求 `std` 只能以一种格式出现，混合 rlib 和 dylib 会导致冲突。

**关键发现: `-Cprefer-dynamic` 标志的影响**

`build/templates/rust/rust_template.gni` 中有这段代码：
```python
if (!defined(rust_static_link) || !rust_static_link) {
  rustflags += [ "-Cprefer-dynamic" ]
}
```

此标志告诉 rustc 优先使用动态链接，与预编译的 rlib 库格式冲突。

**解决方案 (已验证有效):**

修改 `build/templates/rust/rust_template.gni`，注释掉第 322-324 行：
```python
# if (!defined(rust_static_link) || !rust_static_link) {
#   rustflags += [ "-Cprefer-dynamic" ]
# }
```

**尝试过但无效的方案:**
- 删除预编译 .rlib 文件 (会被重新生成)
- 修改 Cargo.toml 移除依赖 (问题在编译配置，不在依赖本身)
- build_ohos_sdk=true (用于 SDK 构建，非产品构建)

#### 2.2 HUKS 编译失败 (最常见)
```bash
# 症状: user_idm_client.h / common_event_manager.h not found
# 解决: 移除 huks 组件
sed -i '/"huks"/d' vendor/ohemu/qemu_arm64_linux_min/config.json
```

#### 2.3 Fuzztest 编译失败
```bash
# 症状: permission_state_change_callback.h not found
# 解决: 运行修复脚本
./fix_fuzztest_include.sh
```

#### 2.4 测试代码编译失败
```bash
# 症状: token_sync_manager_client.h not found
# 解决: 修改测试 BUILD.gn
# 参考 troubleshooting.md §3
```

#### 2.5 Product 子系统缺失 (ohos.build / BUILD.gn)
```bash
# 症状:
#   - find subsystem device_arm_virt failed
#   - find component product_qemu-arm64-linux-min failed
# 解决: 创建缺失的 ohos.build 和 BUILD.gn 文件
# 参考 troubleshooting.md §5
```

#### 2.6 Subsystem 名称不匹配警告
```bash
# 症状: subsystem name config incorrect
# 解决: 将 config.json 中 board 改为 "arm_virt"
# 参考 troubleshooting.md §5
```

### 3. 验证修复

```bash
# 先验证 GN 依赖
hb build --gn-only

# 确认通过后再完整构建
hb build -f
```

---

## 依赖关系要点

### 高风险组件 (🔴 应避免或移除)

**HUKS** - 25+ 间接依赖
```
huks → user_auth_framework → user_idm → common_event_manager
                ↓
        (以上在 QEMU ARM64 不可用)
```

### 中风险组件 (🟡 谨慎添加)

- access_token: 6 直接依赖
- dsoftbus: 5 直接依赖

### 低风险组件 (🟢 通常可用)

- samgr, safwk
- eventhandler
- hilog, hisysevent

详细依赖图: [dependencies.md](references/dependencies.md)

---

## Docker 环境

### 预构建镜像
```
# Docker 镜像仅提供基础工具，版本灵活
OpenHarmony 3.2: swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2
OpenHarmony 4.x: swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2 ✅ 同样可用
```

### 镜像版本查询

```bash
# 查看本地已有的镜像
docker images | grep openharmony

# 拉取特定版本镜像
docker pull swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:<version>
```

---

## 产品配置

### 配置文件位置
- 产品配置: `vendor/ohemu/qemu_arm64_linux_min/config.json`
- 子系统配置: `build/subsystem_config.json`

### 最小可用配置 (无 HUKS)

如果遇到 HUKS 问题，使用此最小配置：

```json
{
  "subsystem": "security",
  "components": [
    { "component": "device_auth" },
    { "component": "access_token" }
  ]
}
```

---

## 构建产物

```
out/qemu-arm-linux/packages/phone/images/
├── Image           31M    Linux 内核
├── ramdisk.img     2.2M  初始化内存盘
├── system.img    100M    系统分区
├── vendor.img    100M    厂商分区
├── userdata.img  100M    用户数据
├── eng_system.img 12M    工程测试镜像
└── updater.img    6.9M   更新镜像
```

---

## 经验总结

1. **Docker 镜像版本灵活**: Docker 镜像仅提供基础工具，编译链由源码 prebuilts 提供，版本无需匹配
2. **Rust 格式冲突解决**: 注释掉 `build/templates/rust/rust_template.gni` 中的 `-Cprefer-dynamic` 标志
3. **HUKS 是深水区**: 在 QEMU ARM64 下依赖链几乎无法简化，**建议默认禁用**
4. **先 GN 后 Ninja**: `hb build --gn-only` 可快速验证依赖 (~1分钟)
5. **测试隔离**: 测试代码与产品代码的条件编译必须一致
6. **最小化原则**: 不需要的组件不要添加，避免引入复杂依赖

---

## 附录：Rust 编译知识

### crate-type 类型

| 类型 | 说明 | 适用场景 |
|------|------|----------|
| `rlib` | Rust 静态库 | 链接到其他 Rust crate |
| `dylib` | Rust 动态库 | 运行时加载 |
| `staticlib` | C 静态库 | 与 C 代码链接 |
| `cdylib` | C 兼容动态库 | FFI 调用 |

### OpenHarmony 中的 crate_type 指定

**注意**: OpenHarmony 的 crate type **不是**在 Cargo.toml 中指定的，而是由 GN 模板决定：

```python
# build/templates/rust/rust_template.gni 第 328-337 行
template("ohos_rust_shared_library") {
  rust_target("$_target_name") {
    target_type = "ohos_rust_library"
    crate_type = "dylib"   # <-- 这里是硬编码
```

### "std only shows up once" 错误原因

Rust 编译器在链接时要求：
- 同一个 crate (如 std) 只能以一种格式出现
- 混合 rlib 和 dylib 格式会导致歧义
- 必须统一所有上游 crate 的格式

---

*构建验证: 34 次构建 (使用 3.2 版本镜像)*
*最终状态: ✅ SUCCESS*
*产物: 可运行在 QEMU ARM64 的 OpenHarmony 标准系统*
