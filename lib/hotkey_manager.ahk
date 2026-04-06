; ============================================================
; 热键管理模块 - FolderJump
; 负责热键注册、上下文检测与防抖
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"

DetectContext(activeHwnd, activeClass, activeTitle) {
    if (activeClass = "#32770") {
        if (IsFileDialog(activeHwnd, activeTitle))
            return "dialog"
        return "none"
    }

    return "none"
}

IsFileDialog(hwnd, title := "") {
    if (!hwnd)
        return false

    if (HasFileDialogControls(hwnd))
        return true

    return TitleLooksLikeFileDialog(title)
}

HasFileDialogControls(hwnd) {
    try {
        controls := WinGetControls("ahk_id " hwnd)
    } catch as err {
        LogWarn("Failed to inspect dialog controls: " err.Message)
        return false
    }

    if (controls.Length = 0)
        return false

    fileNameSignals := 0
    actionSignals := 0
    shellSignals := 0

    for control in controls {
        controlClass := GetControlClassSafe(control, hwnd)
        controlText := StrLower(GetControlTextSafe(control, hwnd))

        if (InStr(controlClass, "Edit"))
            fileNameSignals += 1

        if (InStr(controlClass, "ToolbarWindow32") || InStr(controlClass, "Breadcrumb Parent"))
            shellSignals += 1

        if (InStr(controlText, "open") || InStr(controlText, "save") || InStr(controlText, "browse") || InStr(controlText, "folder") || InStr(controlText, "file"))
            actionSignals += 1
    }

    if (shellSignals > 0 && fileNameSignals > 0)
        return true

    if (fileNameSignals >= 2 && actionSignals > 0)
        return true

    return false
}

TitleLooksLikeFileDialog(title) {
    static keywords := [
        "open",
        "save",
        "save as",
        "browse",
        "select folder",
        "select file"
    ]

    loweredTitle := StrLower(title)
    for keyword in keywords {
        if (InStr(loweredTitle, keyword))
            return true
    }

    return false
}

OnCtrlG(*) {
    global g_Config, g_PathCache, g_CurrentGui

    activeHwnd := WinExist("A")
    if (!activeHwnd)
        return

    activeClass := WinGetClass(activeHwnd)
    activeTitle := WinGetTitle(activeHwnd)

    context := DetectContext(activeHwnd, activeClass, activeTitle)
    if (context = "none") {
        LogDebug("Ignore hotkey outside supported context. Class: " activeClass ", Title: " activeTitle)
        return
    }

    static lastTrigger := 0
    debounceMs := g_Config.debounce_ms
    if (A_TickCount - lastTrigger < debounceMs)
        return
    lastTrigger := A_TickCount

    if (IsSet(g_CurrentGui) && g_CurrentGui && g_CurrentGui.Hwnd) {
        try g_CurrentGui.Destroy()
        g_CurrentGui := ""
    }

    RefreshPaths()

    LogDebug("Hotkey triggered: context=" context ", cachedPaths=" g_PathCache.Length)
    ShowPathSelector(context, activeHwnd)
}

ReloadHotkey() {
    global g_Config

    try {
        Hotkey(g_Config.hotkey, , "Off")
    }

    try {
        Hotkey(g_Config.hotkey, OnCtrlG)
        LogInfo("Hotkey registered: " g_Config.hotkey)
        return true
    } catch as err {
        LogWarn("Hotkey registration failed: " g_Config.hotkey ", error=" err.Message)
        TrayTip("FolderJump", "Hotkey conflict: " g_Config.hotkey, 3000)
        return false
    }
}
