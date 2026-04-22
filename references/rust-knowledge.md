# Rust 编译知识

## crate-type 类型

| 类型 | 说明 | 适用场景 |
|------|------|----------|
| `rlib` | Rust 静态库 | 链接到其他 Rust crate |
| `dylib` | Rust 动态库 | 运行时加载 |
| `staticlib` | C 静态库 | 与 C 代码链接 |
| `cdylib` | C 兼容动态库 | FFI 调用 |

## OpenHarmony 中的 crate_type 指定

**注意**: OpenHarmony 的 crate type **不是**在 Cargo.toml 中指定的，而是由 GN 模板决定：

```python
# build/templates/rust/rust_template.gni 第 328-337 行
template("ohos_rust_shared_library") {
  rust_target("$_target_name") {
    target_type = "ohos_rust_library"
    crate_type = "dylib"   # <-- 这里是硬编码
```

## "std only shows up once" 错误原因

Rust 编译器在链接时要求：
- 同一个 crate (如 std) 只能以一种格式出现
- 混合 rlib 和 dylib 格式会导致歧义
- 必须统一所有上游 crate 的格式

## 解决方案

### 方案 A：注释掉 -Cprefer-dynamic（适用于 staticlib）

注释掉 `build/templates/rust/rust_template.gni` 中的 `-Cprefer-dynamic` 标志：

```python
# if (!defined(rust_static_link) || !rust_static_link) {
#   rustflags += [ "-Cprefer-dynamic" ]
# }
```

### 方案 B：完全移除 gcc_toolchain.gni 中的 -Cprefer-dynamic（会破坏 dylib）

如需统一所有编译格式，可移除 `build/toolchain/gcc_toolchain.gni` 中所有 Rust 工具链的 `-C prefer-dynamic` 标志。

**注意**：这会导致 dylib 编译失败，因为预编译库是 rlib 格式。

---

## ⭐ samgr 依赖链与 Rust 库格式冲突详解

### 问题现象

```
error: cannot satisfy dependencies so `std` only shows up once
```

### 依赖关系图

```
samgr (可执行/共享库)
   │
   ▼ 依赖
ipc_rust.dylib.so ─────────────────────────────────────┐
   │                                                    │
   ▼ 依赖                                               │
ylong_runtime.dylib                                    │
   ├─ 编译类型: crate-type = dylib                      │
   └─ 需要 std 动态格式: std.dylib ◀────────────────────┤ 冲突爆发
                                                        │
   ▼ 依赖                                               │
ylong_io.rlib (预编译)                                 │
   ├─ 编译类型: crate-type = rlib                       │
   └─ 预编译时已绑定: std.rlib ─────────────────────────┘

🛑 约束求解器: "std 不能同时是 rlib 和 dylib → 无法生成合法依赖图 → 编译终止"
```

### 详细依赖链

| 组件 | 类型 | 需要的 std 格式 | 问题 |
|------|------|----------------|------|
| `samgr` | 可执行文件/共享库 | - | 最终产物 |
| `ipc:ipc_rust.dylib.so` | dylib | dylib | samgr 依赖它 |
| `ylong_runtime:ylong_runtime` | dylib | dylib | ipc_rust 依赖它 |
| `ylong_io` | **rlib** (预编译) | rlib | ylong_runtime 依赖它 |
| 预编译 `libstd.rlib` | rlib | - | ylong_io 预编译时绑定 |

### 根本矛盾

1. **预编译库是 rlib 格式**：`ylong_io` 等预编译库在下载时已编译为 `.rlib` 格式，绑定了 `libstd.rlib`

2. **ylong_runtime 是 dylib**：`ylong_runtime` 的 `BUILD.gn` 指定 `crate_type = "dylib"`，需要 `libstd.so` (dylib 格式)

3. **Rust 约束**：`std` 只能以一种格式存在，不能同时是 `rlib` 和 `dylib`

### gcc_toolchain.gni 中的 -C prefer-dynamic

这个标志控制 rustc 的默认链接行为：

| 标志 | rustc 行为 | 需要的 std 格式 |
|------|-----------|----------------|
| `-C prefer-dynamic` | 优先使用动态 std | `libstd.so` (dylib) |
| 无此标志 | 使用静态 std | `libstd.rlib` |

```python
# build/toolchain/gcc_toolchain.gni 中的工具定义
rust_cdylib = {
  command = "... --crate-name {{crate_name}} -C prefer-dynamic {{source}} ..."  # 默认有
  ...
}

rust_rlib = {
  command = "... --crate-name {{crate_name}} -C prefer-dynamic {{source}} ..."  # 默认有
  ...
}
```

### 为什么移除 -C prefer-dynamic 仍然失败？

1. **ylong_io 是预编译 rlib**：预编译时使用了 `-C prefer-dynamic`，所以它绑定了 `libstd.rlib`

2. **ylong_runtime 需要 dylib std**：当编译为 dylib 时，rustc 需要 `libstd.so`

3. **即使统一格式也不行**：因为预编译库已经固定了格式，无法重新编译

### 解决方案选项

| 方案 | 说明 | 可行性 |
|------|------|--------|
| 官方提供 dylib 格式预编译库 | 需要 OpenHarmony 更新预编译工具链 | 需等待官方 |
| 排除 ipc/samgr 组件 | 使用不含 Rust IPC 的配置 | ✅ 已验证可行 |
| 使用旧版本 OpenHarmony | 如 3.2 Release | 可能可行 |

### 已验证可用的精简配置

```json
// vendor/ohemu/qemu_arm_linux_min/config.json
{
  "subsystem": "security",
  "components": [
    { "component": "device_auth" },
    { "component": "access_token" }
    // 注意：移除了 huks
  ]
},
{
  "subsystem": "hiviewdfx",
  "components": [
    { "component": "hilog" },
    { "component": "hisysevent" },
    { "component": "hichecker" }
    // 注意：移除了 faultloggerd
  ]
},
{
  "subsystem": "communication",
  "components": [
    // 注意：移除了 ipc 和 dsoftbus（它们依赖 Rust IPC）
  ]
},
{
  "subsystem": "systemabilitymgr",
  "components": [
    // 注意：移除了 samgr 和 safwk（它们依赖 ipc）
  ]
}
```

### 相关文件

| 文件 | 作用 |
|------|------|
| `build/templates/rust/rust_template.gni` | 定义 Rust GN 模板（ohos_rust_shared_library 等） |
| `build/toolchain/gcc_toolchain.gni` | 定义 Rust 编译工具链命令 |
| `commonlibrary/rust/ylong_runtime/ylong_runtime/BUILD.gn` | ylong_runtime (dylib) 定义 |
| `commonlibrary/rust/ylong_runtime/ylong_io/BUILD.gn` | ylong_io (rlib) 预编译库 |
| `foundation/communication/ipc/interfaces/innerkits/rust/BUILD.gn` | ipc_rust.dylib 定义 |

---

## ⭐⭐⭐ 成功解决方案：ylong_runtime 改为静态库

### 核心思路

将 `ylong_runtime` 从 `dylib` 改为 `static library (rlib)`，使其与 `ylong_io.rlib` 的格式一致，避免 Rust 的 `std only shows up once` 冲突。

### 修改步骤

#### 1. 修改 ylong_runtime/BUILD.gn

将 `ohos_rust_shared_library` 改为 `ohos_rust_static_library`：

```python
import("//build/ohos.gni")

ohos_rust_static_library("ylong_runtime") {
  part_name = "ylong_runtime"
  subsystem_name = "commonlibrary"
  crate_name = "ylong_runtime"
  edition = "2021"
  features = [
    "fs",
    "macros",
    "net",
    "sync",
    "time",
  ]
  sources = [ "src/lib.rs" ]
  deps = [
    "../ylong_io:ylong_io",
    "../ylong_runtime_macros:ylong_runtime_macros(${host_toolchain})",
    "//third_party/rust/crates/libc:lib",
  ]
}
```

#### 2. 修改 SDK 生成脚本 build/scripts/gen_sdk_build_file.py

SDK 描述文件 type 仍为 "so"，但实际产物是 .rlib，需要添加例外处理（第 119-121 行附近）：

```python
# check sdk type consistency
suffix = module_type
if module_type == "none":
    continue
# Don't check suffix for maple sdk.
if module_type == "maple":
    pass
# Rust rlib files have .rlib suffix but type is "lib"
elif module_type == "lib" and source.endswith(".rlib"):
    pass
# Handle so->rlib conversion case (type says "so" but actual file is .rlib)
elif module_type == "so" and source.endswith(".rlib"):
    pass
elif not source.endswith(suffix):
    raise Exception(
        "sdk module [{}] type configuration is inconsistent.".format(
            module_name))
```

### 验证结果

- ✅ 单独编译 `ylong_runtime` 成功
- ✅ 完整镜像编译成功
- ✅ samgr、systemabilitymgr、ipc、dsoftbus 均包含在镜像中

### 关键文件位置

| 文件 | 路径 |
|------|------|
| ylong_runtime BUILD.gn | `/home/volcano/myws/tohst/commonlibrary/rust/ylong_runtime/ylong_runtime/BUILD.gn` |
| SDK 生成脚本 | `/home/volcano/myws/tohst/build/scripts/gen_sdk_build_file.py` |

### 最小化验证流程

1. 修改代码后，先单独编译目标模块：`hb build commonlibrary/rust/ylong_runtime/ylong_runtime:ylong_runtime`
2. 确认成功后，再编译整个镜像：`hb build -f`
3. 验证产物中包含 samgr：`find out -name "*samgr*" | head -10`
