# FolderJump

Windows 路径切换工具，使用 AutoHotkey v2 开发，复刻 Listary 的 `Ctrl+G` 功能。

## 当前行为

FolderJump 目前针对文件对话框（如"打开"和"另存为"对话框）进行了优化。
在支持的文件对话框中按 `Ctrl+G` 可打开选择器，其中列出从以下来源收集的路径：

- Windows Explorer
- Total Commander
- Directory Opus

选择路径后，会将其应用到当前文件对话框。

## 支持的来源

| 来源 | 路径收集方式 | 备注 |
|---|---|---|
| Windows Explorer | COM | 稳定 |
| Total Commander | 内部窗口消息 | 标签目前显示 `active` / `inactive` |
| Directory Opus | `DOpusRT /info ...,paths`，标题回退 | 优先使用官方接口 |

## 支持的触发上下文

运行时仅文件对话框会触发热键。

## 快速开始

1. 安装 AutoHotkey v2。
2. 将 `config.ini.example` 复制为 `config.ini`。
3. 运行：

```cmd
AutoHotkey64.exe main.ahk
```

或编译为独立程序：

```cmd
build\build.bat
```

## 配置

示例：

```ini
[general]
hotkey=^g
poll_interval=500
debounce_ms=300
auto_close_timeout=10
theme=dark

[adapters]
enable_explorer=1
enable_totalcmd=1
enable_dopus=1

[ui]
show_source_label=1
max_items=12
sort_by=recent
position=below_window

[log]
log_level=INFO
log_max_size=1048576
log_max_files=3
```

## 项目结构

```text
folder-jump/
├── main.ahk
├── config.ini.example
├── README.md
├── AGENTS.md
├── adapters/
│   ├── dopus.ahk
│   ├── explorer.ahk
│   └── totalcmd.ahk
├── build/
│   └── build.bat
├── docs/
│   ├── code-review-2026-04-04.md
│   └── todo.md
├── lib/
│   ├── config_manager.ahk
│   ├── hotkey_manager.ahk
│   ├── log_manager.ahk
│   ├── path_collector.ahk
│   ├── path_switcher.ahk
│   ├── selection_ui.ahk
│   ├── tray_manager.ahk
│   ├── utils.ahk
│   └── window_monitor.ahk
└── logs/
    └── folder-jump.log
```

## 已知限制

- 热键激活有意限制为文件对话框。
- Total Commander 左右面板推断未在 UI 中显示，因为当前启发式方法不够可靠。
- 部分旧版或高度定制的对话框可能仍需要通用键盘回退方案。

## 日志

运行时日志写入 `logs/folder-jump.log`。

## 许可证

MIT
