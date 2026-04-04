---
name: build_oh_standard
description: |
  OpenHarmony Standard System QEMU Build Skill - 构建可运行在 QEMU ARM64 的 OpenHarmony 标准系统镜像。

  **触发场景**:
  - 用户请求构建 OpenHarmony QEMU 镜像
  - 用户请求解决 OpenHarmony 编译错误
  - 用户询问 OpenHarmony 依赖关系
  - 用户需要配置 OpenHarmony 产品

  **核心能力**:
  - 完整构建流程 (34 次构建验证)
  - 问题诊断与解决 (HUKS/测试/fuzztest)
  - 依赖关系分析
  - Docker 环境配置
---

# OpenHarmony QEMU ARM64 构建技能

## 快速开始

### 标准构建流程 (17分钟)

```bash
cd /path/to/ohos_standard

# 1. 清理旧构建
rm -rf out

# 2. 下载预编译工具
bash build/prebuilts_download.sh

# 3. Docker 构建
docker run --rm -v $(pwd):/workspace -w /workspace \
  swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2 \
  bash -c "
    python3 -m pip install --user build/hb && \
    hb set --product-name qemu-arm64-linux-min@ohemu && \
    hb build -f
  "

# 4. 验证产物
ls -lh out/qemu-arm-linux/packages/phone/images/
```

### 使用构建脚本 (推荐)

```bash
cd /path/to/ohos_standard
chmod +x /path/to/skills/build_oh_standard/scripts/build_qemu.sh

# 标准构建
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

### 2. 常见问题解决

**HUKS 编译失败** (最常见)
```bash
# 症状: user_idm_client.h / common_event_manager.h not found
# 解决: 移除 huks 组件
sed -i '/"huks"/d' vendor/ohemu/qemu_arm64_linux_min/config.json
```

**Fuzztest 编译失败**
```bash
# 症状: permission_state_change_callback.h not found
# 解决: 运行修复脚本
./fix_fuzztest_include.sh
```

**测试代码编译失败**
```bash
# 症状: token_sync_manager_client.h not found
# 解决: 修改测试 BUILD.gn
# 参考 troubleshooting.md §3
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

### 关键配置项

| 配置项 | 值 | 说明 |
|-------|-----|------|
| `support_jsapi` | `false` | 避免深层 JS 依赖 |
| `enable_ramdisk` | `true` | QEMU 需要 |
| `target_cpu` | `arm64` | ARM64 架构 |

---

## Docker 环境

### 预构建镜像
```
swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2
```

### 自定义镜像 (可选)

如需固化配置，参考 [Dockerfile](assets/Dockerfile) 创建自定义镜像：

```bash
cd /path/to/skills/build_oh_standard/assets
docker build -t my-ohos-build:1.0 .
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

## 参考文档

- [troubleshooting.md](references/troubleshooting.md) - 详细问题诊断
- [dependencies.md](references/dependencies.md) - 完整依赖关系图
- [Dockerfile](assets/Dockerfile) - Docker 镜像配置

---

## 经验总结

1. **HUKS 是深水区**: 在 QEMU ARM64 下依赖链几乎无法简化，**建议默认禁用**
2. **先 GN 后 Ninja**: `hb build --gn-only` 可快速验证依赖 (~1分钟)
3. **测试隔离**: 测试代码与产品代码的条件编译必须一致
4. **Fuzztest 完整路径**: 不能假设所有平台 include 路径相同
5. **最小化原则**: 不需要的组件不要添加，避免引入复杂依赖

---

*构建验证: 34 次构建*
*最终状态: ✅ SUCCESS*
*产物: 可运行在 QEMU ARM64 的 OpenHarmony 标准系统*
