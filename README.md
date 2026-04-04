# FolderJump

AutoHotkey v2 path switcher for Windows, inspired by Listary `Ctrl+G`.

## Current Behavior

FolderJump is currently optimized for file dialogs such as Open and Save As dialogs.
Press `Ctrl+G` in a supported file dialog to open a selector that lists paths collected from:

- Windows Explorer
- Total Commander
- Directory Opus

The selected path is then applied to the current file dialog.

## Supported Sources

| Source | Path collection | Notes |
|---|---|---|
| Windows Explorer | COM | stable |
| Total Commander | internal window messages | labels currently show `active` / `inactive` |
| Directory Opus | `DOpusRT /info ...,paths`, title fallback | official interface preferred |

## Supported Trigger Context

Only file dialogs are intended to trigger the hotkey at runtime.

## Quick Start

1. Install AutoHotkey v2.
2. Copy `config.ini.example` to `config.ini`.
3. Run:

```cmd
AutoHotkey64.exe main.ahk
```

Or compile with:

```cmd
build\build.bat
```

## Configuration

Example:

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

## Project Structure

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

## Known Limits

- Hotkey activation is intentionally restricted to file dialogs.
- Total Commander left/right side inference is not exposed in the UI because the current heuristic is not reliable enough.
- Some legacy or heavily customized dialogs may still require the generic keyboard fallback.

## Logs

Runtime logs are written to `logs/folder-jump.log`.

## License

MIT
