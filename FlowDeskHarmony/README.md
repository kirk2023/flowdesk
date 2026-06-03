# FlowDesk HarmonyOS Client

鸿蒙手机端 - FlowDesk 远程桌面控制软件

## 平台
- HarmonyOS 6 (API 12+)
- Stage 模型 + ArkTS + ArkUI

## MVP 范围
- 局域网 P2P 远程控制 Windows PC
- 零服务器、零账户
- 仅做屏幕镜像 + 触控控制
- 不含文件传输

## 工程结构
```
FlowDeskHarmony/
├── AppScope/                    # 应用全局配置
│   ├── app.json5                # bundleName 等
│   └── resources/
├── entry/                       # 主模块
│   ├── build-profile.json5
│   ├── oh-package.json5
│   └── src/main/
│       ├── ets/
│       │   ├── entryability/    # UIAbility 入口
│       │   └── pages/           # UI 页面
│       ├── module.json5         # 模块清单（权限/Ability）
│       └── resources/           # 资源（字符串/颜色/图标）
├── build-profile.json5          # 顶层构建配置
├── hvigorfile.ts                # 构建脚本
└── oh-package.json5             # 顶层依赖
```

## 在 DevEco Studio 中打开
1. 启动 DevEco Studio
2. File → Open → 选中 `D:\AI\opencode\FlowDeskHarmony` 目录
3. 等待 hvigor 同步依赖（首次约 1-2 分钟）
4. 连接真机（HarmonyOS 6 设备）
5. Run → Run 'entry'

## 当前状态
- ✅ 工程脚手架就绪
- ✅ 设备列表主页面（UI 完整）
- ✅ 添加设备弹窗（扫码/ID/PIN 三种模式）
- ✅ 本地数据存储（Preferences）
- ✅ 网络信息获取
- 🚧 局域网发现协议（mDNS/UDP 探测）
- 🚧 P2P 连接建立（ECDH + AES-GCM）
- 🚧 屏幕流接收（AVPlayer）
- 🚧 远程控制页面

## 需要的图标资源
工程依赖 `app_icon` 媒体资源，在 DevEco Studio 中：
1. 右键 `entry/src/main/resources/base/media` → New → Image Asset
2. 选择 Foreground/Background 颜色或图片
3. 点击 OK 自动生成 5 种分辨率图标

## 开发路线
参见 `D:\AI\opencode\docs\prd\FlowDesk_PRD.md`
