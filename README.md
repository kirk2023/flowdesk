# FlowDesk

**无账号、零依赖的局域网远程桌面** — 手机控电脑，扫码即连。

[English](README.en.md)

<p align="center">
  <img src="FlowDeskServer/FlowDeskServer/assets/app_icon.png" width="128" />
</p>

## 功能

- **扫码配对** — 手机扫 PC 端二维码，输入 6 位 PIN 即可连接
- **E2E 加密** — ECDH P-256 密钥交换 + AES-256-GCM 端到端加密，数据不经服务器
- **实时屏幕** — PC 屏幕画面通过 UDP 实时传输到手机，支持 ~30fps
- **触控操作** — 手机触屏映射为鼠标操作（左键/右键/滚轮）
- **中文输入** — 手机系统键盘直接输入中文，远程同步显示
- **截图保存** — 一键保存当前屏幕画面到手机相册

## 架构

```
┌──────────────┐     UDP (加密)     ┌──────────────┐
│  HarmonyOS   │◄─────────────────►│  Windows PC  │
│   手机 APP   │   ECDH+AES-GCM   │   Server     │
└──────────────┘                   └──────────────┘
      扫码配对，无需注册账号，无需联网
```

- **传输协议：** UDP（端口 47800 发现 / 47801 数据）
- **加密：** ECDH P-256 密钥协商 → AES-256-GCM 加密所有数据
- **无服务器：** 完全局域网 P2P，不依赖任何云服务

## 快速开始

### PC 端（Windows）

1. 下载 [最新 Release](https://github.com/kirk2023/flowdesk/releases) 中的 `FlowDesk.exe`
2. 双击运行，系统托盘出现图标
3. 界面显示设备 ID 和二维码

### 手机端（HarmonyOS 6）

1. 用 DevEco Studio 打开 `FlowDeskHarmony/` 目录
2. Build & Install 到手机
3. 打开 APP → 点击 `+` → 扫描 PC 端二维码
4. 输入 PC 端显示的 6 位 PIN

## 项目结构

```
flowdesk/
├── FlowDeskHarmony/          # 鸿蒙 6 手机端（ArkTS）
│   └── entry/src/main/ets/
│       ├── pages/
│       │   ├── Index.ets         # 设备列表页
│       │   └── RemoteScreen.ets  # 远程桌面页
│       ├── services/
│       │   ├── ConnectionService.ets  # UDP 连接 + 加密
│       │   ├── CryptoService.ets      # ECDH + AES-GCM
│       │   ├── DiscoveryService.ets   # UDP 局域网发现
│       │   └── InputService.ets       # 触控/键盘事件
│       └── models/
│           └── Protocol.ets      # 协议定义
├── FlowDeskServer/           # Windows PC 端（C# .NET 8）
│   └── FlowDeskServer/
│       ├── Services/
│       │   ├── PairingService.cs       # 配对 + 数据传输
│       │   ├── ScreenStreamService.cs  # 屏幕采集 + JPEG 编码
│       │   ├── InputInjectionService.cs # 输入模拟
│       │   ├── DiscoveryService.cs     # UDP 广播发现
│       │   └── FirewallService.cs      # 防火墙规则
│       ├── Common/
│       │   └── Constants.cs            # 配置常量
│       └── Models/
│           └── Protocol.cs             # 协议模型
└── docs/prd/
    └── FlowDesk_PRD.md       # 产品需求文档
```

## 技术细节

### 配对流程

```
手机                                    PC
  │                                      │
  │──── whoami (UDP 广播) ──────────────►│
  │◄─── iam (回复设备信息) ─────────────│
  │                                      │
  │  [扫码获取 PC 地址 + 设备 ID]        │
  │                                      │
  │──── PHEL (ECDH 公钥 + PIN) ────────►│
  │◄─── POK! (ECDH 公钥 + 屏幕尺寸) ───│
  │                                      │
  │  [双方 ECDH 派生共享密钥]            │
  │  [所有后续数据 AES-256-GCM 加密]     │
  │                                      │
  │◄──── PCRY (加密屏幕帧) ────────────│
  │──── PCRY (加密输入事件) ────────────►│
```

### 加密协议

- **密钥交换：** ECDH P-256，取原始共享密钥前 32 字节作为 AES key
- **数据加密：** AES-256-GCM，nonce(12) || ciphertext || authTag(16)
- **帧分片：** 屏幕帧超过 50KB 时自动分片，支持乱序重组

## 局限性

- ⚠️ **仅支持局域网** — 手机和 PC 必须在同一 WiFi 下
- ⚠️ **不支持国密算法** — 使用标准 AES-256-GCM
- ⚠️ **单向控制** — 仅支持手机控制 PC，不支持反向

## 开发环境

- **PC 端：** Windows 10+ / .NET 8 / C#
- **手机端：** HarmonyOS 6.0+ / DevEco Studio 5.0+ / ArkTS
- **构建：**
  - PC: `dotnet publish -c Release -r win-x64 --self-contained`
  - 手机: DevEco Studio → Build → Build Hap(s)

## Roadmap

- [x] v1.0 — 局域网 P2P 远程桌面
- [ ] v1.1 — 公网穿刺 (NAT Traversal)
- [ ] v1.2 — 文件传输
- [ ] v1.3 — 多设备支持

## License

MIT
