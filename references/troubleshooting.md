# OpenHarmony QEMU ARM64 构建问题速查

## 快速问题索引

| 错误关键字 | Release | 问题类型 | 解决方案 |
|-----------|---------|---------|---------|
| `recipe commences before first target` | OH 4.0 | Makefile 语法错误 | kernel.mk 中 export 需在目标规则内缩进 |
| `source tree not clean` | OH 4.0 | 构建状态问题 | mrproper 前设置 `KBUILD_OUTPUT=` |
| `cannot stat.*Image` | OH 4.0 | 路径错误 | 标准构建使用 src_tmp 而非 OBJ 目录 |
| `startup_l2.*not found` | OH 4.0 | 配置错误 | 移除不存在的 startup_l2 组件 |
| `thirdparty_bounds_checking_function.*not found` | OH 4.0 | 配置错误 | 移除不存在的组件 |
| `device_arm_virt.*not found` | OH 4.0 | 子系统名称不匹配 | 改为 device_qemu-arm-linux |
| `libstd.dylib.so not found` | OH 4.0 | Rust 动态库缺失 | 创建 libstd*.so 符号链接 |
| `cannot satisfy dependencies so 'std' only shows up once` | OH 4.0+ | Rust 库格式冲突 | 见 rust-knowledge.md |
| `user_idm_client.h not found` | - | HUKS 深层依赖 | 移除 huks 或添加 stub |
| `common_event_manager.h not found` | - | 深层依赖 | 同上 |
| `token_sync_manager_client.h not found` | - | 测试条件编译 | 添加 #ifdef 或排除测试 |
| `permission_state_change_callback.h not found` | - | fuzztest include | 添加 access_token/src 到 include_dirs |
| `hisysevent not found` | - | 组件未配置 | 在 config.json 添加 hiviewdfx/hisysevent |
| `GN phase failed` | - | 依赖缺失 | 添加缺失组件或检查循环依赖 |
| `find subsystem device_arm_virt failed` | - | board 名称不匹配 | 将 config.json 中 board 改为 `arm_virt` |
| `find component product_qemu-arm64-linux-min failed` | - | 缺少 product 子系统 | 创建 ohos.build 和 BUILD.gn |
| `vgettimeofday.*Error: junk at end of line` | - | VDSO 汇编错误 | kernel.mk 添加 `LLVM_IAS=1` |
| `format specifies type.*but the argument has type` | - | benchmark/fuzztest 格式错误 | 移除测试或修复格式字符串 |
| `lnn_net_builder_mock_test.cpp` | - | dsoftbus 测试编译错误 | 移除 dsoftbus 组件 |
| `collections.Mapping` | - | Python 3.10+ 兼容性问题 | 见本节第11条 |

---

## 0. 内核构建问题 (OH 4.0)

### 0.1 kernel.mk Makefile 语法错误

**错误信息**
```
recipe commences before first target
make[2]: *** No rule to make target 'build kernel...'
```

**根因**
`export KBUILD_OUTPUT=$(KERNEL_OBJ_TMP_PATH)` 放在了目标规则之外，导致后续命令无法正确执行。

**解决方案**
将 `KBUILD_OUTPUT` 的设置移到目标规则内部，确保所有命令都在正确的缩进层级。

**修改文件**: `kernel/linux/build/kernel.mk`

```makefile
# 修改前
$(KERNEL_IMAGE_FILE):
	$(hide) echo "build kernel..."
	# ... 复制源码和 mrproper 命令 ...
export KBUILD_OUTPUT=$(KERNEL_OBJ_TMP_PATH)
	$(hide) $(OHOS_BUILD_HOME)/drivers/hdf_core/...

# 修改后
$(KERNEL_IMAGE_FILE):
	$(hide) echo "build kernel..."
	# ... 复制源码和 mrproper 命令 ...
	$(hide) export KBUILD_OUTPUT=$(KERNEL_OBJ_TMP_PATH)
	$(hide) $(OHOS_BUILD_HOME)/drivers/hdf_core/...
```

---

### 0.2 源代码树不干净

**错误信息**
```
The source tree is not clean, please run 'make ARCH=arm64 mrproper'
```

**根因**
KBUILD_OUTPUT 在 mrproper 之前被设置，导致清理不彻底。

**解决方案**
在执行 mrproper 时明确设置 `KBUILD_OUTPUT=`

**修改文件**: `kernel/linux/build/kernel.mk`

```makefile
# 修改前
$(hide) cd $(KERNEL_SRC_TMP_PATH) && make ARCH=$(KERNEL_ARCH) mrproper

# 修改后
$(hide) cd $(KERNEL_SRC_TMP_PATH) && KBUILD_OUTPUT= make ARCH=$(KERNEL_ARCH) mrproper
```

---

### 0.3 内核镜像路径错误

**错误信息**
```
cannot stat '/workspace/out/KERNEL_OBJ/kernel/OBJ/linux-5.10/arch/arm64/boot/Image'
```

**根因**
标准构建模式下，内核镜像实际生成在 `src_tmp` 目录而非 `OBJ` 目录。

**解决方案**
1. 修复 `kernel_module_build.sh`，根据 BUILD_TYPE 选择正确的检查路径
2. 修复 `build_kernel.sh`，根据 BUILD_TYPE 选择正确的复制源路径

**修改文件**: `kernel/linux/build/kernel_module_build.sh`

```bash
# For standard build, check the source directory instead of OBJ directory
if [ "$BUILD_TYPE" == "standard" ];then
    LINUX_KERNEL_IMAGE_FILE=${LINUX_KERNEL_OUT}/arch/${KERNEL_ARCH}/boot/${kernel_image}
else
    LINUX_KERNEL_IMAGE_FILE=${LINUX_KERNEL_OBJ_OUT}/arch/${KERNEL_ARCH}/boot/${kernel_image}
fi
```

**修改文件**: `kernel/linux/build/build_kernel.sh`

```bash
if [ "$4" == "standard" ];then
    # For standard build, image is in src_tmp directory
    if [ "$5" == "arm64" ];then
        cp ${2}/kernel/src_tmp/${8}/arch/arm64/boot/Image ${3}/Image
    fi
else
    # For non-standard build, image is in OBJ directory
    if [ "$5" == "arm64" ];then
        cp ${2}/kernel/OBJ/${8}/arch/arm64/boot/Image ${3}/Image
    fi
fi
```

---

### 0.4 config.json 不存在的组件 (OH 4.0)

**错误信息**
```
Cannot find component: startup_l2
Cannot find component: thirdparty_bounds_checking_function
```

**根因**
config.json 中包含了不存在的组件。

**解决方案**
移除不存在的组件。

**修改文件**: `vendor/ohemu/qemu_arm64_linux_min/config.json`

```json
// 移除以下不存在的组件
// "startup_l2",
// "thirdparty_bounds_checking_function"
```

---

### 0.5 子系统名称不匹配 (OH 4.0)

**错误信息**
```
find subsystem device_arm_virt failed
```

**根因**
config.json 中的 subsystem 名称与实际文件不匹配。

**解决方案**
修正 subsystem 名称。

**修改文件**: `vendor/ohemu/qemu_arm64_linux_min/config.json`

```json
// 修改前
"subsystem": "device_arm_virt"

// 修改后
"subsystem": "device_qemu-arm-linux"
```

---

### 0.6 Rust 动态库依赖缺失 (OH 4.0)

**错误信息**
```
libstd.dylib.so: cannot open shared object file: No such file or directory
libtest.dylib.so: cannot open shared object file: No such file or directory
```

**根因**
Rust 标准库的符号链接缺失。

**解决方案**
创建必要的符号链接。

```bash
cd prebuilts/rustc/linux-x86_64/current/lib
ln -s libstd-*.so libstd.dylib.so
ln -s libtest-*.so libtest.dylib.so
```

---

### 0.7 Rust 库格式冲突 (OH 4.0+)

**错误信息**
```
error: cannot satisfy dependencies so 'std' only shows up once
= help: having upstream crates all available in one format will likely make this go away
```

**根因**
混合使用了 rlib 和 dylib 格式的 Rust 库。

**解决方案**
将 `ylong_runtime` 从 dylib 改为 static library (rlib)。

**修改文件**: `commonlibrary/rust/ylong_runtime/ylong_runtime/BUILD.gn`

```gn
# 修改前
ohos_rust_shared_library("ylong_runtime") {

# 修改后
ohos_rust_static_library("ylong_runtime") {
```

详细说明见 [rust-knowledge.md](rust-knowledge.md)。

---

## 11. Python 3.10+ 兼容性问题 (collections.Mapping)

### 错误信息
```
ImportError: cannot import name 'Mapping' from 'collections'
```
或
```
ModuleNotFoundError: No module named 'prompt_toolkit'
```

### 根因
在 Python 3.10+ 中，`collections.Mapping` 被移除，需要从 `collections.abc.Mapping` 导入。OpenHarmony 构建系统使用的 `prompt_toolkit==1.0.14` 版本过旧，不兼容 Python 3.10+。

### 受影响组件
- `build/hb/main.py` (hb 工具)
- `prompt_toolkit==1.0.14`
- `prebuilts/python/linux-x86/3.10.2/` (预编译 Python 3.10)

### 解决方案

**方案 A**: 使用 Docker 容器内的 Python 3.8（推荐）
```bash
# 容器内已安装 Python 3.8，使用 pip3 安装 prompt_toolkit
docker run -it -v $(pwd):/home/openharmony swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2 \
  bash -c "pip3 install prompt_toolkit==1.0.14 && cd /home/openharmony && PYTHONPATH=/home/openharmony/build/hb python3 build/hb/main.py build -p qemu-arm64-linux-min"
```

**方案 B**: 避免使用 prebuilts 中的 Python 3.10
```bash
# 设置 PATH 优先使用系统 Python 3.8
export PATH=/usr/bin:$PATH
python3 --version  # 确认为 3.8.x
```

### 验证 Python 版本
```bash
# Docker 内检查
docker run --rm swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2 python3 --version
# 输出: Python 3.8.10

# prebuilts Python 版本（不兼容）
/path/to/prebuilts/python/linux-x86/3.10.2/bin/python3 --version
# 输出: Python 3.10.x (有 collections.Mapping 问题)
```

### 注意事项
- **不要使用** `prebuilts/python/linux-x86/3.10.2/` 中的 Python，该版本与 prompt_toolkit 1.0.14 不兼容
- **优先使用** Docker 镜像自带的 Python 3.8
- 如果必须使用 Python 3.10+，需要升级相关 Python 包的版本

---

## 1. HUKS 组件问题 (Build 2-3, 16, 25, 27-28)

### 错误信息
```
fatal error: 'user_idm_client.h' file not found
fatal error: 'common_event_manager.h' file not found
```

### 根因
HUKS 依赖 `user_auth_framework → user_idm → common_event_manager`，在 QEMU ARM64 环境下这些头文件不可用。

### 解决方案

**方案 A**: 移除 huks 组件（推荐）
```json
// vendor/ohemu/qemu_arm64_linux_min/config.json
{
  "subsystem": "security",
  "components": [
    { "component": "device_auth" },
    { "component": "access_token" }
    // 移除 huks
  ]
}
```

**方案 B**: 为 QEMU 创建 stub 实现（复杂，不推荐）

---

## 2. GN 阶段依赖缺失 (Build 9-24)

### 错误信息
```
Reason: GN phase failed
Cannot find dependency for target 'xxx'
```

### 依赖链扩展顺序
| 步骤 | 缺失模块 | 添加结果 |
|------|---------|---------|
| 1 | hisysevent | ✅ 解决 |
| 2 | dsoftbus | ✅ 解决 |
| 3 | hitrace | ✅ 解决 |
| 4 | access_token | ❌ 新依赖 safwk |
| 5 | safwk | ❌ 新依赖 eventhandler |
| 6 | eventhandler | ❌ 新依赖 |
| 7 | huks | ❌ 回到 HUKS 问题 |

### 解决方案
1. 先运行 `hb build --gn-only` 验证依赖
2. 识别依赖循环：当添加组件持续引发新依赖时，移除该组件
3. 使用最小化配置原则

---

## 3. 测试代码条件编译 (Build 29-30)

### 错误信息
```
fatal error: 'token_sync_manager_client.h' file not found
```

### 根因
`accesstoken_info_manager_test.cpp` 在 `TOKEN_SYNC_ENABLE=false` 时仍尝试 include。

### 解决方案

**方案 A**: 修改测试文件添加条件编译
```cpp
// base/security/access_token/services/accesstokenmanager/test/unittest/cpp/src/accesstoken_info_manager_test.cpp
#ifdef TOKEN_SYNC_ENABLE
#include "token_sync_manager_client.h"
...
#endif
```

**方案 B**: 在 BUILD.gn 中条件排除
```gn
if (token_sync_enable == true) {
  sources += [ "accesstoken_info_manager_test.cpp" ]
}
```

---

## 4. Fuzztest Include 路径缺失 (Build 32-33)

### 错误信息
```
fatal error: 'permission_state_change_callback.h' file not found
fatal error: 'accesstoken_manager_client.h' file not found
```

### 根因
32 个 fuzztest BUILD.gn 文件缺少 `${access_token_path}/interfaces/innerkits/accesstoken/src`

### 批量修复命令
```bash
cd /home/volcano/myws/ohos_standard

for dir in base/security/access_token/test/fuzztest/access_token_stub/*/; do
  if ! grep -q "interfaces/innerkits/accesstoken/src" "$dir/BUILD.gn" 2>/dev/null; then
    sed -i '/include_dirs = \[/a\    "${access_token_path}/interfaces/innerkits/accesstoken/src",' "$dir/BUILD.gn"
  fi
done
```

---

## 5. Product 子系统缺失 (ohos.build / BUILD.gn)

### 错误信息
```
find subsystem device_arm_virt failed, please check it in out/preloader/qemu-arm64-linux-min/parts.json
find component product_qemu-arm64-linux-min failed, please check it in out/preloader/qemu-arm64-linux-min/parts.json
```

### 根因
构建系统需要两个文件来注册 product 子系统：

| 文件 | 作用 | 缺失后果 |
|------|------|---------|
| `ohos.build` | 声明 subsystem 和 parts 映射 | subsystem 无法被注册，校验失败 |
| `BUILD.gn` | 定义 GN 构建目标 | module_list 引用的目标不存在 |

### 缺失文件示例
```
vendor/ohemu/qemu_arm64_linux_min/
├── config.json      ✅ 存在
├── ohos.build       ❌ 缺失
└── BUILD.gn        ❌ 缺失
```

### 解决方案

1. 创建缺失的 `ohos.build`:
```json
{
  "parts": {
    "product_qemu-arm64-linux-min": {
      "module_list": [
        "//vendor/ohemu/qemu_arm64_linux_min:qemu_arm64_linux_min"
      ]
    }
  },
  "subsystem": "product_qemu-arm64-linux-min"
}
```

2. 创建缺失的 `BUILD.gn`:
```gn
group("qemu_arm64_linux_min") {
}
```

3. 确认白名单中有对应条目 (`build/subsystem_compoents_whitelist.json`):
```json
"device_arm_virt": "device_arm_virt",
"product_qemu-arm64-linux-min": "product_qemu-arm64-linux-min"
```

### Subsystem 名称不匹配警告

```
warning: subsystem name config incorrect in 'device/qemu/arm_virt/linux/ohos.build',
build file subsystem name is device_arm_virt, configured subsystem name is device_qemu-arm-linux.
```

**根因**: `config.json` 中 `board` 字段是 `qemu-arm-linux`，构建系统会生成期望名称 `device_qemu-arm-linux`，但实际 ohos.build 中写的是 `device_arm_virt`。

**解决方案**:

| 方案 | 修改位置 | 说明 |
|------|---------|------|
| 方案A | `config.json` 中 `board` 改为 `arm_virt` | ✅ 推荐，与 ohos.build 一致 |
| 方案B | 修改 `ohos.build` 中的 subsystem 名为 `device_qemu-arm-linux` | 需同步修改白名单 |
| 方案C | 忽略警告 | 仅当 parts.json 能正确生成时才可忽略 |

**方案A 示例**:
```json
// vendor/ohemu/qemu_arm64_linux_min/config.json
{
  "board": "arm_virt",  // 从 "qemu-arm-linux" 改为 "arm_virt"
  ...
}
```

---

## 6. QEMU 启动问题

### 启动卡在 init 阶段

**症状**: 构建完成后，QEMU 启动卡在 init 阶段，无法进入 shell。

**原因**: OpenHarmony 标准系统使用特殊的分区挂载机制，需要通过内核参数指定分区挂载信息。

**解决方案**: 参考 `vendor/ohemu/qemu_arm64_linux_min/qemu_run.sh`

关键启动参数：
```bash
kernel_bootargs="console=ttyAMA0 init=/bin/init hardware=qemu.arm.linux root=/dev/ram0 rw \
ohos.required_mount.system=/dev/block/vdb@/usr@ext4@ro,barrier=1@wait,required \
ohos.required_mount.vendor=/dev/block/vdc@/vendor@ext4@ro,barrier=1@wait,required"
```

**分区挂载参数格式**:
```
ohos.required_mount.<挂载点>=<设备路径>@<挂载目录>@<文件系统类型>@<挂载选项>@<等待策略>,required
```

### 控制台无输出

**解决方案**: 添加 `earlycon` 参数启用早期控制台：
```bash
-append "console=ttyAMA0,115200 earlycon ..."
```

### QEMU 驱动配置

```bash
# 正确：使用 virtio-blk-device
-drive if=none,file=system.img,format=raw,id=system,index=1 -device virtio-blk-device,drive=system

# 错误：使用 virtio-blk-pci
-drive file=system.img,format=qcow2,if=virtio
```

---

## 7. 内核及组件编译问题

### 7.1 VDSO 汇编错误

**错误信息**
```
/tmp/vgettimeofday-xxx.s: Error: junk at end of line, first unrecognized character is `"'
clang-15: error: assembler command failed with exit code 1
make[2]: *** [arch/arm64/Makefile:186: vdso_prepare] Error 2
```

**根因**
内核使用 Clang 编译时，需要启用集成汇编器 (IAS)，但配置中未正确设置。

**解决方案**
修改 `kernel/linux/build/kernel.mk`，为 arm64 架构添加 `LLVM_IAS=1`：
```makefile
else ifeq ($(KERNEL_ARCH), arm64)
    KERNEL_TARGET_TOOLCHAIN := $(PREBUILTS_GCC_DIR)/linux-x86/aarch64/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu/bin
    KERNEL_TARGET_TOOLCHAIN_PREFIX := $(KERNEL_TARGET_TOOLCHAIN)/aarch64-linux-gnu-
    KERNEL_CROSS_COMPILE += LLVM_IAS=1
```

### 7.2 c_utils benchmark/fuzztest 测试编译错误

**错误信息**
```
error: format specifies type 'long long' but the argument has type 'time_t'
error: format specifies type 'int' but the argument has type 'size_t'
```

**根因**
测试代码中存在格式字符串类型不匹配问题，被 `-Werror` 作为错误处理。

**解决方案**
从 `commonlibrary/c_utils/bundle.json` 中移除 benchmarktest 和 fuzztest 测试：
```json
"test": [
  "//commonlibrary/c_utils/base/test:unittest"
]
```

### 7.3 dsoftbus 测试编译错误

**错误信息**
```
lnn_net_builder_mock_test.cpp 编译失败
```

**根因**
dsoftbus 组件的测试代码在编译时出现问题。

**解决方案**
从 `vendor/ohemu/qemu_arm64_linux_min/config.json` 中移除 dsoftbus 组件：
```json
{
  "subsystem": "communication",
  "components": [
    { "component": "ipc", "features":[] }
  ]
}
```

---

## 8. 产品配置文件

### 路径
`vendor/ohemu/qemu_arm64_linux_min/config.json`

### 最小可用配置
```json
{
  "product_name": "qemu-arm64-linux-min",
  "type": "standard",
  "version": "3.0",
  "device_company": "qemu",
  "board": "arm_virt",
  "target_cpu": "arm64",
  "target_os": "ohos",
  "enable_ramdisk": true,
  "support_jsapi": false,
  "subsystems": [
    { "subsystem": "common", "components": [{ "component": "common" }] },
    { "subsystem": "startup", "components": [{ "component": "init" }] },
    { "subsystem": "hiviewdfx", "components": [
      { "component": "hilog" },
      { "component": "hisysevent" }
    ]},
    { "subsystem": "security", "components": [
      { "component": "device_auth" },
      { "component": "access_token" }
    ]},
    { "subsystem": "commonlibrary", "components": [{ "component": "c_utils" }] },
    { "subsystem": "communication", "components": [{ "component": "ipc" }] },
    { "subsystem": "systemabilitymgr", "components": [
      { "component": "samgr" },
      { "component": "safwk" }
    ]},
    { "subsystem": "thirdparty", "components": [{ "component": "bounds_checking_function" }] },
    { "subsystem": "device_arm_virt", "components": [{ "component": "qemu_arm_linux_chipset" }] }
  ]
}
```

---

## 9. 构建命令

### 标准构建流程
```bash
cd /path/to/ohos_standard

# 1. 清理旧构建
rm -rf out

# 2. 下载预编译工具
bash build/prebuilts_download.sh

# 3. 设置产品并构建
docker run --rm -v $(pwd):/workspace -w /workspace \
  swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2 \
  bash -c "
    python3 -m pip install --user build/hb > /dev/null 2>&1 && \
    hb set --product-name qemu-arm64-linux-min@ohemu && \
    hb build -f
  "
```

### 验证 GN 依赖（不编译）
```bash
hb build --gn-only
```

---

## 10. 构建产物

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
