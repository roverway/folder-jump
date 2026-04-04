# FolderJump

AutoHotkey v2 Windows 路径切换工具，核心体验参考 Listary 的 `Ctrl+G`。

## 当前行为

当前版本主要面向“打开 / 另存为”这类文件对话框。

在受支持的文件对话框中按下 `Ctrl+G` 后，会弹出路径选择面板，列出当前已收集到的路径来源：

- Windows Explorer
- Total Commander
- Directory Opus

用户选择目标路径后，FolderJump 会把该路径应用到当前文件对话框。

## 当前支持的路径来源

| 来源 | 路径获取方式 | 说明 |
|---|---|---|
| Windows Explorer | COM | 稳定 |
| Total Commander | 内部窗口消息 | 列表标签当前显示 `active` / `inactive` |
| Directory Opus | `DOpusRT /info ...,paths`，标题解析兜底 | 优先使用官方接口 |

## 当前支持的触发场景

运行时只在文件对话框中响应热键。

## 快速开始

1. 安装 AutoHotkey v2。
2. 复制 `config.ini.example` 为 `config.ini`。
3. 运行：

```cmd
AutoHotkey64.exe main.ahk
```

或者编译：

```cmd
build\build.bat
```

## 配置示例

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

## 当前限制

- 热键已刻意收紧为只在文件对话框中触发。
- Total Commander 的左右侧推断目前仍是启发式，因此没有在 UI 中展示 `left/right`。
- 某些较老或高度定制的文件对话框，仍可能退回到通用按键模拟。

## 日志

运行日志写入 `logs/folder-jump.log`。

## 许可

MIT
