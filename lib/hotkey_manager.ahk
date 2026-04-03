; ============================================================
; Hotkey Manager — FolderJump
; 热键注册、上下文检测、防抖
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"

; 上下文检测
DetectContext(activeClass, activeTitle) {
    ; Windows Explorer 文件夹窗口
    if (activeClass = "CabinetWClass" || activeClass = "ExploreWClass")
        return "explorer"

    ; 通用对话框（文件打开/保存）
    if (activeClass = "#32770") {
        if (IsFileDialog(activeTitle))
            return "dialog"
        return "none"
    }

    ; Total Commander
    if (activeClass = "TTOTAL_CMD")
        return "totalcmd"

    ; Directory Opus
    if (activeClass = "dopus.lister" || activeClass = "dopus.tab")
        return "dopus"

    ; XYplorer
    if (activeClass = "XYplorer")
        return "xyplorer"

    ; 其他窗口 — 忽略
    return "none"
}

; 判断是否为文件对话框
IsFileDialog(title) {
    static keywords := ["打开", "保存", "另存为", "Open", "Save", "Save As", "浏览", "Browse", "选择文件夹", "Select Folder", "选择文件", "Select File"]
    for kw in keywords {
        if (InStr(title, kw))
            return true
    }
    return false
}

; 热键触发入口
OnCtrlG(*) {
    global g_Config, g_PathCache, g_CurrentGui

    ; 1. 获取前景窗口
    activeHwnd := WinExist("A")
    if (!activeHwnd)
        return

    activeClass := WinGetClass(activeHwnd)
    activeTitle := WinGetTitle(activeHwnd)

    ; 2. 上下文判断
    context := DetectContext(activeClass, activeTitle)
    if (context = "none") {
        LogDebug("非目标窗口，忽略热键触发. Class: " activeClass)
        return
    }

    ; 3. 防抖：配置时间内不重复触发
    static lastTrigger := 0
    debounceMs := g_Config.debounce_ms
    if (A_TickCount - lastTrigger < debounceMs)
        return
    lastTrigger := A_TickCount

    ; 4. 如果已有 GUI 打开，先关闭
    if (IsSet(g_CurrentGui) && g_CurrentGui && g_CurrentGui.Hwnd) {
        try g_CurrentGui.Destroy()
        g_CurrentGui := ""
    }

    ; 5. 立即刷新路径缓存
    RefreshPaths()

    ; 6. 显示路径选择器
    LogDebug("热键触发: context=" context ", 缓存路径数=" g_PathCache.Length)
    ShowPathSelector(context, activeHwnd)
}

; 动态热键重载
ReloadHotkey() {
    global g_Config

    ; 清除旧热键
    try {
        Hotkey(g_Config.hotkey, , "Off")
    }

    ; 注册新热键
    try {
        Hotkey(g_Config.hotkey, OnCtrlG)
        LogInfo("热键已注册: " g_Config.hotkey)
        return true
    } catch as err {
        LogWarn("热键注册失败: " g_Config.hotkey " — " err.Message)
        TrayTip("FolderJump", "热键冲突: " g_Config.hotkey, 3000)
        return false
    }
}
