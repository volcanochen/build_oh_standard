# OpenHarmony QEMU ARM64 依赖关系图

## 组件风险等级速查

| 等级 | 组件 | 说明 |
|------|------|------|
| 🔴 高 | huks | 25+ 间接依赖，QEMU ARM64 不可用，**建议默认禁用** |
| 🟡 中 | access_token | 6 直接依赖 |
| 🟡 中 | dsoftbus | 5 直接依赖 |
| 🟢 低 | samgr, safwk | 通常可用 |
| 🟢 低 | eventhandler | 通常可用 |
| 🟢 低 | hilog, hisysevent | 通常可用 |

---

## 产品配置组件

```
qemu-arm64-linux-min@ohemu
├── common
├── startup (init)
├── hiviewdfx (hilog, hitrace, faultloggerd, hisysevent, hichecker)
├── security (device_auth, access_token, huks) ⚠️
├── commonlibrary (c_utils)
├── communication (ipc, dsoftbus)
├── notification (eventhandler)
├── systemabilitymgr (samgr, safwk)
├── developtools (bytrace, hdc)
├── thirdparty (bounds_checking_function)
└── device_arm_virt (qemu_arm_linux_chipset)
```

---

## HUKS 深层依赖链 (问题核心)

```
huks
│
├── [基础依赖 - 安全]
│   ├── hilog
│   ├── ipc (ipc_single)
│   ├── safwk (system_ability_fwk)
│   ├── samgr (samgr_proxy)
│   └── c_utils
│
├── [条件编译: device_cert_manager = true]
│   └── bundle_framework (device_cert_manager)
│       └── bundle_manager (bundle_discovery)
│           └── bundle_framework
│               └── app_control (appexecfwk_core)
│
├── [条件编译: enable_user_auth_framework = true]
│   └── user_auth_framework (userauth_client)
│       ├── ability_base (want)
│       ├── napi
│       ├── os_account (os_account_innerkits)
│       └── user_idm (user_idm_client) ❌
│           └── common_event_manager ❌
│               (这两个在 QEMU ARM64 不可用)
│
└── [条件编译: support_jsapi = true]
    ├── ability_base ───────────────────────┐
    ├── os_account                         │
    ├── common_event_service                │ (重复依赖)
    └── ipc (ipc_single) ──────────────────┘
```

---

## access_token 依赖链

```
access_token
│
├── [基础依赖]
│   ├── hilog
│   ├── ipc (ipc_core)
│   ├── safwk
│   ├── samgr
│   └── c_utils
│
├── [eventhandler 触发]
│   └── notification (eventhandler)
│       └── hilog (复用)
│
└── [测试依赖]
    ├── googletest (单元测试框架)
    └── sqlite (数据库)
```

---

## dsoftbus 依赖链

```
dsoftbus
│
├── [基础依赖]
│   ├── ipc (ipc_core)
│   ├── hilog
│   └── c_utils
│
├── [通信模块]
│   ├── bus_center (设备发现) → ipc
│   ├── discovery (服务发现) → ipc
│   └── transport (数据传输)
│       ├── tcp
│       └── udp
│
└── [配置选项]
    └── dsoftbus_get_devicename = false
        (简化网络配置)
```

---

## 系统能力管理 (samgr + safwk)

```
systemabilitymgr
│
├── samgr (系统能力管理器)
│   ├── hilog
│   ├── ipc (samgr_proxy)
│   ├── safwk
│   └── init (services)
│
└── safwk (系统能力框架)
    ├── hilog
    ├── ipc
    ├── samgr_proxy
    └── sa_mgr
```

---

## 依赖循环问题

### 问题 1: access_token ↔ eventhandler
```
access_token → notification (eventhandler) → access_token (回调)
```
**解决**: eventhandler 作为独立服务，不直接依赖 access_token

### 问题 2: ipc 版本冲突
```
HUKS:     ipc_single
dsoftbus: ipc_core
```
**解决**: 统一使用 ipc_core

### 问题 3: samgr ↔ safwk 潜在循环
```
samgr → safwk → samgr_proxy → samgr
```
**解决**: 通过代理层解耦

---

## 依赖深度统计

| 组件 | 直接依赖 | 间接依赖 | 风险 |
|------|---------|---------|------|
| huks | 8 | 25+ | 🔴 高 |
| access_token | 6 | 12 | 🟡 中 |
| dsoftbus | 5 | 10 | 🟡 中 |
| samgr | 4 | 8 | 🟢 低 |
| eventhandler | 3 | 6 | 🟢 低 |

---

## 配置文件位置

| 文件 | 路径 |
|------|------|
| 产品配置 | `vendor/ohemu/qemu_arm64_linux_min/config.json` |
| 子系统配置 | `build/subsystem_config.json` |
| 设备配置 | `device/qemu/arm_virt/linux/` |
