; ============================================================
; FolderJump — 轻量级 Windows 文件管理器路径快速切换工具
; 复刻 Listary Ctrl+G 功能
;
; 版本: 0.1.0
; 要求: AutoHotkey v2.0+
; 平台: Windows 10/11 (x64)
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent  ; 保持脚本常驻运行

; ============================================================
; 模块加载
; ============================================================
#IncludeOnce "%A_ScriptDir%\lib\log_manager.ahk"
#IncludeOnce "%A_ScriptDir%\lib\config_manager.ahk"
#IncludeOnce "%A_ScriptDir%\lib\tray_manager.ahk"
#IncludeOnce "%A_ScriptDir%\lib\hotkey_manager.ahk"
#IncludeOnce "%A_ScriptDir%\lib\window_monitor.ahk"
#IncludeOnce "%A_ScriptDir%\lib\selection_ui.ahk"

; ============================================================
; 全局状态
; ============================================================
g_Config := {}
g_PathCache := []
g_CurrentGui := ""
g_IsRefreshing := false

; ============================================================
; 初始化
; ============================================================

; 1. 初始化日志
InitLogs()
LogInfo("FolderJump v0.1.0 初始化开始")

; 2. 加载配置
g_Config := LoadConfig()

; 3. 初始化托盘
TrayInit()

; 4. 注册热键
ReloadHotkey()

; 5. 启动窗口监控定时器
InitWindowMonitor()

LogInfo("FolderJump 初始化完成，等待热键触发...")

; ============================================================
; 主循环（AHK 消息循环，无需显式代码）
; 脚本通过 Persistent 指令保持运行，等待热键和定时器事件
; ============================================================
