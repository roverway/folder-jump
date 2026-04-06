#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ============================================================
; FolderJump
; 轻量级 Windows 路径切换工具，复刻 Listary Ctrl+G 核心体验
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\utils.ahk"
#Include "%A_ScriptDir%\lib\config_manager.ahk"
#Include "%A_ScriptDir%\lib\tray_manager.ahk"
; 所有适配器必须在 path_collector 之前
#Include "%A_ScriptDir%\adapters\explorer.ahk"
#Include "%A_ScriptDir%\adapters\totalcmd.ahk"
#Include "%A_ScriptDir%\adapters\dopus.ahk"
; path_collector 依赖所有适配器
#Include "%A_ScriptDir%\lib\path_collector.ahk"
; path_switcher 依赖适配器和 utils
#Include "%A_ScriptDir%\lib\path_switcher.ahk"
; window_monitor 依赖 path_collector
#Include "%A_ScriptDir%\lib\window_monitor.ahk"
; 热键管理器
#Include "%A_ScriptDir%\lib\hotkey_manager.ahk"
; 选择界面依赖 path_switcher
#Include "%A_ScriptDir%\lib\selection_ui.ahk"

g_Config := {}
g_PathCache := []
g_CurrentGui := ""
g_IsRefreshing := false

InitLogs()
LogInfo("FolderJump v0.1.0 startup begin")

g_Config := LoadConfig()

TrayInit()
ReloadHotkey()
InitWindowMonitor()

LogInfo("FolderJump startup complete")
