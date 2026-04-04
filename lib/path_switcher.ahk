; ============================================================
; Path Switcher - FolderJump
; Execute path switching based on the current window type
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\utils.ahk"
#Include "%A_ScriptDir%\adapters\explorer.ahk"
#Include "%A_ScriptDir%\adapters\totalcmd.ahk"
#Include "%A_ScriptDir%\adapters\dopus.ahk"

ExecutePathSwitch(entry, targetHwnd := 0) {
    if (!targetHwnd)
        targetHwnd := WinExist("A")
    if (!targetHwnd) {
        LogError("Failed to get foreground window handle")
        return
    }

    activeClass := WinGetClass(targetHwnd)

    if (!DirExist(entry.path)) {
        LogWarn("Target path does not exist: " entry.path)
        TrayTip("FolderJump", "路径不存在: " entry.path, 3000)
        return
    }

    LogInfo("Execute path switch: targetPath=" entry.path ", targetClass=" activeClass ", source=" entry.source)

    if (activeClass = "#32770") {
        SwitchFileDialog(targetHwnd, entry.path)
    }
    else if (activeClass = "CabinetWClass" || activeClass = "ExploreWClass") {
        NavigateExplorer(targetHwnd, entry.path)
    }
    else if (activeClass = "TTOTAL_CMD") {
        panelSide := entry.HasOwnProp("panelSide") ? entry.panelSide : (entry.HasOwnProp("panel") ? entry.panel : "")
        panelRole := entry.HasOwnProp("panelRole") ? entry.panelRole : "active"
        NavigateTotalCmd(targetHwnd, entry.path, panelSide, panelRole)
    }
    else if (activeClass = "dopus.lister" || activeClass = "dopus.tab") {
        NavigateDOpus(targetHwnd, entry.path)
    }
    else {
        LogWarn("Unknown window type, using fallback: " activeClass)
        SwitchFileDialogFallback(targetHwnd, entry.path)
    }
}

SwitchFileDialog(hwnd, targetPath) {
    if (TryNavigateFileDialog(hwnd, targetPath))
        return true

    return SwitchFileDialogFallback(hwnd, targetPath)
}

TryNavigateFileDialog(hwnd, targetPath) {
    if (!ActivateTargetWindow(hwnd))
        return false

    for shortcut in ["^l", "!d"] {
        if (TryNavigateFileDialogWithShortcut(hwnd, targetPath, shortcut))
            return true
    }

    return false
}

TryNavigateFileDialogWithShortcut(hwnd, targetPath, shortcut) {
    savedClipboard := SaveClipboard()

    try {
        focusedControlBefore := GetFocusedControlSafe(hwnd)

        Send(shortcut)
        Sleep(200)

        focusedControlAfter := GetFocusedControlSafe(hwnd)
        LogDebug("File dialog shortcut attempted: " shortcut ", before=" focusedControlBefore ", after=" focusedControlAfter)

        if (!SetFocusedControlText(hwnd, focusedControlAfter, targetPath)) {
            A_Clipboard := targetPath
            if (!ClipWait(1))
                LogWarn("Clipboard write timed out while targeting file dialog")
            Sleep(100)
            Send("^a")
            Sleep(50)
            Send("^v")
        }

        Sleep(150)
        Send("{Enter}")

        if (WaitForFileDialogPath(hwnd, targetPath)) {
            LogInfo("File dialog navigation succeeded via shortcut: " shortcut ", path=" targetPath)
            RestoreClipboard(savedClipboard)
            return true
        }
    } catch as err {
        LogWarn("File dialog shortcut navigation failed: " shortcut ", error=" err.Message)
    }

    RestoreClipboard(savedClipboard)
    return false
}

SwitchFileDialogFallback(hwnd, targetPath) {
    LogDebug("Start file dialog fallback: hwnd=" hwnd ", path=" targetPath)

    savedClipboard := SaveClipboard()

    try {
        if (!ActivateTargetWindow(hwnd)) {
            RestoreClipboard(savedClipboard)
            return false
        }

        Send("!d")
        Sleep(200)
        Send("^a")
        Sleep(50)

        A_Clipboard := targetPath
        if (!ClipWait(1))
            LogWarn("Clipboard write timed out during dialog fallback")
        Sleep(100)

        Send("^v")
        Sleep(150)
        Send("{Enter}")

        if (WaitForFileDialogPath(hwnd, targetPath)) {
            LogInfo("File dialog fallback succeeded: " targetPath)
            RestoreClipboard(savedClipboard)
            return true
        }

        LogWarn("File dialog fallback could not verify navigation result")
        RestoreClipboard(savedClipboard)
        return false
    } catch as err {
        LogError("Dialog switch failed: " err.Message)
        TrayTip("FolderJump", "跳转失败: " err.Message, 3000)
        RestoreClipboard(savedClipboard)
        return false
    }
}

ActivateTargetWindow(hwnd) {
    WinActivate("ahk_id " hwnd)
    if (!WinWaitActive("ahk_id " hwnd, , 2000)) {
        LogError("Failed to activate target window: ahk_id " hwnd)
        return false
    }

    LogDebug("Target window activated")
    return true
}

GetFocusedControlSafe(hwnd) {
    try {
        return ControlGetFocus("ahk_id " hwnd)
    } catch {
        return ""
    }
}

SetFocusedControlText(hwnd, focusedControl, targetPath) {
    if (!focusedControl)
        return false

    try {
        ControlFocus(focusedControl, "ahk_id " hwnd)
        ControlSetText(targetPath, focusedControl, "ahk_id " hwnd)
        LogDebug("Set file dialog control text: " focusedControl)
        return true
    } catch as err {
        LogWarn("Failed to set file dialog control text: " focusedControl ", error=" err.Message)
        return false
    }
}

WaitForFileDialogPath(hwnd, targetPath) {
    normalizedTarget := NormalizeFileDialogPath(targetPath)

    Loop 10 {
        Sleep(150)

        if (!WinExist("ahk_id " hwnd)) {
            LogWarn("File dialog closed before navigation could be verified")
            return false
        }

        if (FileDialogContainsPath(hwnd, normalizedTarget))
            return true
    }

    return false
}

FileDialogContainsPath(hwnd, normalizedTarget) {
    try {
        controls := WinGetControls("ahk_id " hwnd)
    } catch as err {
        LogWarn("Failed to enumerate file dialog controls: " err.Message)
        return false
    }

    for control in controls {
        text := GetControlTextSafe(control, hwnd)
        if (!text)
            continue

        normalizedText := NormalizeFileDialogPath(text)
        if (InStr(normalizedText, normalizedTarget))
            return true
    }

    return false
}

GetControlTextSafe(control, hwnd) {
    try {
        return ControlGetText(control, "ahk_id " hwnd)
    } catch {
        return ""
    }
}

NormalizeFileDialogPath(pathText) {
    pathText := StrReplace(pathText, "/", "\")
    pathText := Trim(pathText, " `t`r`n")

    if (StrLen(pathText) > 3 && SubStr(pathText, -1) = "\")
        pathText := SubStr(pathText, 1, -1)

    return StrLower(pathText)
}
