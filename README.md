# FolderJump

> 轻量级 Windows 文件管理器路径快速切换工具 — 复刻 Listary Ctrl+G 功能

[![AutoHotkey v2](https://img.shields.io/badge/AutoHotkey-v2.0+-blue.svg)](https://www.autohotkey.com/)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-lightgrey.svg)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 功能特性

按下 `Ctrl+G`，弹出浮动菜单列出所有已打开的文件夹，选择即可跳转。

- ✅ **Windows Explorer** — 自动检测所有打开的文件夹窗口（含 Win11 多标签）
- ✅ **文件对话框** — 在任意应用的打开/保存对话框中跳转路径
- ✅ **Total Commander** — 支持双面板路径获取与跳转（P1）
- ✅ **Directory Opus** — 支持多标签页路径获取与跳转（P1）
- ✅ **键盘导航** — ↑↓ 选择、Enter 确认、Esc 取消
- ✅ **自定义热键** — 修改配置文件即可，无需重启
- ✅ **深色/浅色主题** — 可切换 UI 主题
- ✅ **超低资源占用** — 空闲 ≤ 5MB 内存，CPU ≤ 0.5%

## 快速开始

### 方式一：直接运行（推荐开发/测试）

1. 安装 [AutoHotkey v2.0+](https://www.autohotkey.com/download/)
2. 复制配置文件：
   ```cmd
   copy config.ini.example config.ini
   ```
3. 双击 `main.ahk` 或运行：
   ```cmd
   AutoHotkey64.exe main.ahk
   ```
4. 系统托盘出现图标，程序就绪
5. 在任意文件管理器或文件对话框中按 `Ctrl+G`

### 方式二：编译为独立 .exe

1. 确保已安装 AutoHotkey（自带 Ahk2Exe 编译器）
2. 运行编译脚本：
   ```cmd
   build\build.bat
   ```
3. 生成 `FolderJump.exe`，可独立运行（无需安装 AHK）

## 配置

编辑 `config.ini`（修改后通过托盘菜单"重新加载配置"即时生效，无需重启）：

```ini
[general]
hotkey=^g                  ; 触发热键（^=Ctrl, !=Alt, +=Shift, #=Win）
poll_interval=500          ; 路径刷新间隔（毫秒）
auto_close_timeout=10      ; 菜单自动关闭时间（秒）
theme=dark                 ; UI 主题（dark / light）

[adapters]
enable_explorer=1          ; Windows Explorer
enable_totalcmd=1          ; Total Commander
enable_dopus=1             ; Directory Opus
enable_xyplorer=0          ; XYplorer

[ui]
show_source_label=1        ; 显示来源标签
max_items=12               ; 列表最大显示项数
sort_by=recent             ; 排序方式（recent / alphabetical）
position=below_window      ; 菜单位置

[log]
log_level=INFO             ; 日志级别（DEBUG / INFO / WARN / ERROR）
log_max_size=1048576       ; 单文件最大字节数（1MB）
log_max_files=3            ; 保留的历史日志文件数
```

## 使用说明

### 基本操作

| 操作 | 效果 |
|------|------|
| `Ctrl+G` | 弹出路径选择菜单 |
| `↑` / `↓` | 在路径列表中导航 |
| `Enter` | 确认选择并跳转 |
| `Esc` | 取消菜单 |
| 鼠标双击 | 确认选择并跳转 |

### 支持的窗口类型

| 窗口类型 | 路径获取 | 路径跳转 | 状态 |
|----------|---------|---------|------|
| Windows Explorer | COM 枚举 | COM 导航 / 键盘模拟 | ✅ P0 |
| 文件对话框 (#32770) | — | 键盘模拟 | ✅ P0 |
| Total Commander | 读取 wincmd.ini | Ctrl+D 键盘模拟 | ⚠️ P1 |
| Directory Opus | 窗口标题解析 | DOpusRT / 键盘模拟 | ⚠️ P1 |

### 托盘菜单

右键点击系统托盘图标：

| 菜单项 | 功能 |
|--------|------|
| 显示提示 | 显示运行状态 |
| 重新加载配置 | 热重载 config.ini |
| 退出 | 关闭程序 |

## 项目结构

```
folder-jump/
├── main.ahk                    # 入口文件
├── config.ini.example          # 配置模板
├── AGENTS.md                   # AI 代理开发指南
├── lib/
│   ├── log_manager.ahk         # 日志记录与轮转
│   ├── config_manager.ahk      # INI 配置管理
│   ├── tray_manager.ahk        # 系统托盘管理
│   ├── hotkey_manager.ahk      # 热键注册与上下文检测
│   ├── window_monitor.ahk      # 定时窗口轮询
│   ├── path_collector.ahk      # 路径收集调度器
│   ├── selection_ui.ahk        # 浮动菜单 GUI
│   └── path_switcher.ahk       # 路径跳转执行
├── adapters/
│   └── explorer.ahk            # Windows Explorer 适配器
├── build/
│   └── build.bat               # 编译脚本
└── logs/
    └── folder-jump.log         # 运行时日志
```

## 开发

### 环境要求

- **AutoHotkey**: v2.0+
- **Windows**: 10/11 (x64)
- **运行时依赖**: 无（纯 AHK 标准库）

### 添加新的文件管理器适配器

1. 在 `adapters/` 下创建 `<name>.ahk`
2. 实现两个函数：
   - `Collect<Name>Paths()` — 返回 `PathEntry[]` 数组
   - `Navigate<Name>(hwnd, targetPath)` — 执行跳转
3. 在 `lib/path_collector.ahk` 的 `CollectAllPaths()` 中注册
4. 在 `lib/path_switcher.ahk` 的 `ExecutePathSwitch()` 中添加跳转逻辑
5. 在 `lib/hotkey_manager.ahk` 的 `DetectContext()` 中添加窗口检测
6. 在 `config.ini.example` 的 `[adapters]` 中添加开关

### PathEntry 对象格式

```autohotkey
{
    path: string,        ; 完整路径，如 "C:\Users\ZuoQi\Projects"
    source: string,      ; 来源: "explorer" | "totalcmd" | "dopus"
    label: string,       ; 显示标签: "Explorer", "TC (左)", "DOpus"
    hwnd: integer,       ; 窗口句柄
    panel: string,       ; 面板标识（仅 TC）: "left" | "right"
    timestamp: integer   ; A_TickCount 时间戳
}
```

### 日志

运行日志位于 `logs/folder-jump.log`，支持自动轮转（最多 3 个备份，每个 1MB）。

## 常见问题

**Q: 按 Ctrl+G 没有反应？**
- 检查热键是否被其他程序占用
- 查看托盘是否有 FolderJump 图标
- 检查 `config.ini` 中的 `hotkey` 配置

**Q: 路径列表为空？**
- 确保至少打开了一个文件夹窗口
- 检查 `config.ini` 中对应 adapter 是否启用（enable_xxx=1）
- 查看 `logs/folder-jump.log` 排查错误

**Q: 杀毒软件拦截？**
- 编译为 .exe 可降低误报率
- 添加数字签名后可彻底解决

**Q: 文件对话框跳转失败？**
- 确保目标路径存在且有访问权限
- 某些特殊对话框（如旧版 Common Dialog）可能不兼容

## 许可证

MIT License
