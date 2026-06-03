# FlowDesk 应用图标

## 文件清单

| 文件 | 用途 | 尺寸 |
|---|---|---|
| `icon_foreground.png` | **前景层**（透明背景） | 1024x1024 |
| `icon_background.png` | **背景层**（纯蓝 #0A59F7） | 1024x1024 |
| `previews/icon_*.png` | 预览图（48/96/144/192/256/512） | - |

## 设计说明

- **配色**：`#0A59F7` 蓝（与 `color.json` 中 `primary` 一致）
- **形状**：圆角矩形 (rx=200，鸿蒙标准图标)
- **图形语义**：左 PC 显示器 → 中箭头 → 右手机，表达"手机远程控制电脑"
- **白色描边宽度**：36px（1024 画布），缩放到小尺寸仍清晰

## 在 DevEco Studio 中使用

**方式 A：自动生成 5 种分辨率（推荐）**

1. 打开项目后，右键 `entry/src/main/resources/base/media`
2. 选择 `New` → `Image Asset`
3. **Foreground Source**: Image
4. **Path**: 选 `assets/icon_foreground.png`
5. **Background Source**: Color
6. **Color**: `#0A59F7`（或选 `assets/icon_background.png`）
7. 点击 `Next` → `Finish`
8. DevEco 自动生成 `app_icon.png` + 5 种分辨率的 `app_icon_foreground.png` 等

**方式 B：手动复制**

1. 把 `icon_foreground.png` 复制到 `entry/src/main/resources/base/media/app_icon.png`
2. 后续 DevEco 编译时自动缩放到其他分辨率

## 重新生成

```powershell
# Windows PowerShell
.\assets\generate_icon.ps1
```

## 调整设计

如需修改（例如改色、加文字、换图形），编辑 `generate_icon.ps1` 后重新运行即可——脚本是参数化的，改完一行立刻重出。
