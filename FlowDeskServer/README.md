<# FlowDesk Server

Windows 端被控程序 - 鸿蒙手机远程控制 Windows PC

## 平台
- .NET 8 + WPF
- 目标 OS: Windows 10 1903+ / Windows 11
- MVP 范围: 局域网 P2P · 零服务器 · 端到端加密

## 项目结构
```
FlowDeskServer/
├── FlowDeskServer.sln
└── FlowDeskServer/
    ├── FlowDeskServer.csproj
    ├── App.xaml / App.xaml.cs           # 应用入口 + 服务注册
    ├── MainWindow.xaml / .cs            # 主窗口（显示 ID/PIN/二维码）
    ├── Services/
    │   ├── DeviceIdService.cs           # 设备ID 生成 + 本地存储
    │   ├── PinService.cs                # 动态 PIN (30秒刷新)
    │   ├── DiscoveryService.cs          # UDP 47800 设备发现
    │   ├── PairingService.cs            # UDP 47801 配对 + 数据通道
    │   ├── ScreenStreamService.cs       # 屏幕采集 + JPEG 编码
    │   ├── InputInjectionService.cs     # 鼠标/键盘注入
    │   └── FirewallService.cs           # 防火墙规则自动放行
    ├── Models/Protocol.cs               # 协议数据模型
    ├── Common/Constants.cs              # 常量 + Win32 P/Invoke
    └── assets/
        ├── app_icon.ico                 # 托盘/窗口图标
        └── app_icon.png
```

## 构建运行

```powershell
cd D:\AI\opencode\FlowDeskServer
dotnet restore
dotnet build -c Release
dotnet run --project FlowDeskServer
```

或用 Visual Studio 2022 / Rider 打开 `FlowDeskServer.sln`。

## MVP 关键技术决策

| 模块 | 方案 | 后续升级 |
|---|---|---|
| 屏幕采集 | GDI `CopyFromScreen` (15fps) | V1.5: DXGI Desktop Duplication |
| 视频编码 | JPEG 单帧流 (quality 65) | V1.5: H.264 硬编 (Media Foundation) |
| 输入注入 | P/Invoke `SendInput` | (已是最佳) |
| 加密 | .NET 8 `AesGcm` + `ECDiffieHellman` | (已是最佳) |
| 设备发现 | UDP 广播 (47800) | (已是最佳) |
| 配对/数据 | UDP (47801) + ECDH P-256 + HKDF-SHA256 | V1.5: 改 TCP 提升可靠性 |
| 托盘 | Hardcodet.NotifyIcon.Wpf | (已是最佳) |
| 二维码 | QRCoder | (已是最佳) |

## 协议

### 发现包 (JSON, 明文)
```json
{ "type": "iam", "id": "8K7M-3XQ2-NP5R", "alias": "PC-Name", "port": 47801, "proto": "flowdesk-v1", "ts": 1234567890 }
```

### 配对握手 (明文 JSON, 4字节魔数头)
- `PHEL` (pair-hello): 客户端发起，含 ECDH 公钥 + PIN
- `POK!` (pair-accept): 服务端接受，含服务端公钥
- `PREJ` (pair-reject): 服务端拒绝

### 数据包 (4字节魔数 `PCRY` + AES-256-GCM 加密负载)
- 内部 JSON: `{ "type": "input" | "frame", ... }`
- 加密格式: nonce(12) || ciphertext || tag(16)
- nonce 单调递增，防重放

## 安全模型
- ECDH P-256 密钥交换（即使无服务器也防中间人）
- HKDF-SHA256 派生 32 字节 AES 密钥
- AES-256-GCM 端到端加密
- nonce 单调递增防重放
- PIN 30 秒失效

## 已知限制
- 公网不可用（仅局域网 P2P）
- 屏幕采集用 GDI，CPU 占用较高（~30%@1080P@15fps）
- 没有文件传输（V1.0 不做）
- 没有多客户端支持（一对一连接）

## 后续优化
- V1.5: DXGI 屏幕采集 + H.264 硬编
- V1.5: TCP 数据通道（更可靠）
- V1.5: Windows Service 化（开机自启 + 后台运行）
- V2.0: 公网中转模式（订阅制）
