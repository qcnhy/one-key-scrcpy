# MI6 无头主机复活方案

## 问题

换电池时螺丝刀刮断了屏幕排线，导致 DSI 显示接口物理损坏。
内核不断尝试驱动物理坏屏，每秒刷出大量 `panel timeout` / `Panel has gone bad` 错误。
这个死循环阻塞了 SurfaceFlinger 渲染管线，导致投屏画面严重卡顿。

## 解决方案

核心就一行命令，让内核放弃驱动物理坏屏：

```bash
su -c 'echo 1 > /sys/class/graphics/fb0/msm_disable_panel'
```

已通过 Magisk 开机脚本（service.sh）自动执行，无需手动干预。
开机后面板自动禁用，投屏即流畅。

## 文件说明

```
MI6_HEADLESS_HEADSET/
├── README.md              ← 本说明文件
├── 一键启动投屏.bat        ← Windows: 双击运行（增强版）
└── 一键启动投屏.command    ← macOS: 双击运行（增强版）
```

## 一键启动投屏 说明（Windows / macOS 功能一致）

脚本自动完成两步：

1. **连接设备** — 自动检测 USB / WiFi
2. **启动 scrcpy** — 分辨率 1280 / 码率 4M / 帧率 30，保持手机屏幕原状态

> 面板禁用由手机端 Magisk 脚本开机自动完成，投屏脚本不再处理。

| 功能 | 说明 |
|------|------|
| 自动检测 USB | 无需手填设备序列号 |
| IP 记忆 | 连接成功的 WiFi IP 存入历史文件（macOS: `~/.scrcpy_hosts`，Windows: `%USERPROFILE%\.scrcpy_hosts`），下次直接选 |
| 在线探测 | 并行检查历史 IP，在线设备标记并优先显示 |
| 灵活输入 | 输入 **数字** 选序号，输入 **IP 地址** 直接连 |
| 自动找工具 | Windows 版自动查找 `scrcpy.exe` / `adb.exe`，无需再改脚本里的硬编码路径 |

输入示例：
```
请输入序号或 IP 地址: 1              ← 选列表第 1 个设备
请输入序号或 IP 地址: 192.168.1.100  ← 直接连接此 IP
```

### 依赖

- **Windows (.bat)**：`winget install Genymobile.scrcpy`，或到 [Genymobile/scrcpy Releases](https://github.com/Genymobile/scrcpy/releases) 下载 win64 压缩包解压。脚本会自动查找 `scrcpy.exe` / `adb.exe`（PATH / 脚本同目录 / `C:\scrcpy*` / scoop / chocolatey）；压缩包自带 adb.exe，保持解压目录完整即可
- **macOS (.command)**：`brew install scrcpy android-platform-tools`

## 手机端自动化

- **magisk-wifiadb**（Magisk 模块）— 开机自动维持 WiFi ADB 5555 端口
- **disable_bad_panel**（Magisk service.sh）— 开机自动禁用损坏面板，守护循环防止重置

## 日常使用

**Windows**：双击 `一键启动投屏.bat`

**macOS**：双击 `一键启动投屏.command`

> 首次运行 macOS 可能拦截：**系统设置 → 隐私与安全性 → 仍要打开**

## 注意事项

- 面板禁用后手机物理屏幕不会亮（本来就坏了，无所谓）
- 如果某天换了新屏幕，移除 Magisk 脚本不再禁用面板即可恢复
- WiFi 和电脑须在同一局域网
- scrcpy 参数可在脚本顶部按需调整（分辨率 / 码率 / 帧率）

## 更新记录

### v1.1.0（2026-08-16）

- Windows `.bat` 升级为功能完整增强版，与 macOS 版对齐：USB 自动检测、WiFi IP 历史记忆、序号 / IP 灵活输入
- Windows 版新增工具自动发现（PATH / 脚本同目录 / `C:\scrcpy*` / scoop / chocolatey），移除硬编码路径 `C:\scrcpy-win64-v3.3.4`
