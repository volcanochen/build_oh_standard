# OpenHarmony QEMU ARM64 构建问题速查

## 快速问题索引

| 错误关键字 | 问题类型 | 解决方案 |
|-----------|---------|---------|
| `user_idm_client.h not found` | HUKS 深层依赖 | 移除 huks 或添加 stub |
| `common_event_manager.h not found` | 深层依赖 | 同上 |
| `token_sync_manager_client.h not found` | 测试条件编译 | 添加 #ifdef 或排除测试 |
| `permission_state_change_callback.h not found` | fuzztest include | 添加 access_token/src 到 include_dirs |
| `hisysevent not found` | 组件未配置 | 在 config.json 添加 hiviewdfx/hisysevent |
| `GN phase failed` | 依赖缺失 | 添加缺失组件或检查循环依赖 |

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

## 5. 产品配置文件

### 路径
`vendor/ohemu/qemu_arm64_linux_min/config.json`

### 最小可用配置
```json
{
  "product_name": "qemu-arm64-linux-min",
  "type": "standard",
  "version": "3.0",
  "device_company": "qemu",
  "board": "qemu-arm-linux",
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

## 6. 构建命令

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

## 7. 构建产物

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
