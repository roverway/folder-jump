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
RegisterMessageFilters()
LogInfo("FolderJump v0.1.0 startup begin")

g_Config := LoadConfig()

TrayInit()
ReloadHotkey()
InitWindowMonitor()

LogInfo("FolderJump startup complete")

RegisterMessageFilters() {
    static MSGFLT_ALLOW := 1
    messages := [0x0312, 0x000C, 0x0100, 0x0101, 0x0302]

    for msg in messages {
        try {
            DllCall("User32.dll\ChangeWindowMessageFilterEx", "Ptr", A_ScriptHwnd, "UInt", msg, "UInt", MSGFLT_ALLOW, "Ptr", 0)
            LogDebug("Allowed message through UIPI filter: " msg)
        } catch as err {
            LogWarn("ChangeWindowMessageFilterEx unavailable or failed for msg " msg ": " err.Message)
        }
    }
}

