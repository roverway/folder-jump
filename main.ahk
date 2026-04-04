#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ============================================================
; FolderJump
; 轻量级 Windows 路径切换工具，复刻 Listary Ctrl+G 核心体验
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\config_manager.ahk"
#Include "%A_ScriptDir%\lib\tray_manager.ahk"
#Include "%A_ScriptDir%\lib\hotkey_manager.ahk"
#Include "%A_ScriptDir%\lib\window_monitor.ahk"
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
