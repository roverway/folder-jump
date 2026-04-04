; ============================================================
; 路径跳转模块 - FolderJump
; 负责根据当前窗口类型执行路径跳转
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
    if (TryNavigateFileDialogByControl(hwnd, targetPath))
        return true

    if (TryNavigateFileDialogByShortcut(hwnd, targetPath))
        return true

    return SwitchFileDialogFallback(hwnd, targetPath)
}

TryNavigateFileDialogByControl(hwnd, targetPath) {
    LogDebug("Try file dialog control-level navigation")

    try {
        if (!ActivateTargetWindow(hwnd))
            return false

        targetControl := FindFileDialogEditableControl(hwnd)
        if (!targetControl) {
            LogDebug("No suitable file dialog control found for direct input")
            return false
        }

        if (!SetDialogControlText(hwnd, targetControl, targetPath))
            return false

        if (!SubmitDialogControl(hwnd, targetControl))
            return false

        if (WaitForFileDialogPath(hwnd, targetPath)) {
            LogInfo("File dialog control-level navigation succeeded: control=" targetControl ", path=" targetPath)
            return true
        }

        LogWarn("File dialog control-level navigation could not verify result")
        return false
    } catch as err {
        LogWarn("File dialog control-level navigation failed: " err.Message)
        return false
    }
}

TryNavigateFileDialogByShortcut(hwnd, targetPath) {
    LogDebug("Try file dialog shortcut-level navigation")

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

        targetControl := FindPreferredDialogControlAfterShortcut(hwnd)
        if (!targetControl)
            targetControl := GetFocusedControlSafe(hwnd)

        LogDebug("File dialog shortcut attempted: " shortcut ", before=" focusedControlBefore ", target=" targetControl)

        if (!SetDialogControlText(hwnd, targetControl, targetPath)) {
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
            LogInfo("File dialog shortcut navigation succeeded: shortcut=" shortcut ", path=" targetPath)
            RestoreClipboard(savedClipboard)
            return true
        }
    } catch as err {
        LogWarn("File dialog shortcut navigation failed: shortcut=" shortcut ", error=" err.Message)
    }

    RestoreClipboard(savedClipboard)
    return false
}

SwitchFileDialogFallback(hwnd, targetPath) {
    LogDebug("Start file dialog generic fallback: hwnd=" hwnd ", path=" targetPath)

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
            LogInfo("File dialog generic fallback succeeded: " targetPath)
            RestoreClipboard(savedClipboard)
            return true
        }

        LogWarn("File dialog generic fallback could not verify navigation result")
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

FindFileDialogEditableControl(hwnd) {
    controls := GetDialogControlsSafe(hwnd)
    if (controls.Length = 0)
        return ""

    bestAddressEdit := ""
    bestGenericEdit := ""

    for control in controls {
        className := GetFileDialogControlClassSafe(control, hwnd)
        text := GetFileDialogControlTextSafe(control, hwnd)
        loweredText := StrLower(text)
        loweredClass := StrLower(className)

        if (InStr(loweredClass, "edit")) {
            if (LooksLikeAddressBarControl(control, className, loweredText)) {
                if (!bestAddressEdit)
                    bestAddressEdit := control
            } else if (!bestGenericEdit) {
                bestGenericEdit := control
            }
        }
    }

    if (bestAddressEdit)
        return bestAddressEdit

    return bestGenericEdit
}

FindPreferredDialogControlAfterShortcut(hwnd) {
    focusedControl := GetFocusedControlSafe(hwnd)
    if (focusedControl && IsEditableDialogControl(hwnd, focusedControl))
        return focusedControl

    return FindFileDialogEditableControl(hwnd)
}

LooksLikeAddressBarControl(control, className, loweredText) {
    loweredControl := StrLower(control)
    loweredClass := StrLower(className)

    if (InStr(loweredControl, "breadcrumb") || InStr(loweredClass, "breadcrumb"))
        return true
    if (InStr(loweredControl, "toolbarwindow32") || InStr(loweredClass, "toolbarwindow32"))
        return true
    if (InStr(loweredText, "address") || InStr(loweredText, "location"))
        return true

    return false
}

IsEditableDialogControl(hwnd, control) {
    className := GetFileDialogControlClassSafe(control, hwnd)
    return InStr(StrLower(className), "edit")
}

SetDialogControlText(hwnd, control, targetPath) {
    if (!control)
        return false

    try {
        ControlFocus(control, "ahk_id " hwnd)
        Sleep(50)
        ControlSetText(targetPath, control, "ahk_id " hwnd)
        LogDebug("Set file dialog control text: " control)
        return true
    } catch as err {
        LogWarn("Failed to set file dialog control text: " control ", error=" err.Message)
        return false
    }
}

SubmitDialogControl(hwnd, control) {
    try {
        ControlFocus(control, "ahk_id " hwnd)
        Sleep(50)
        ControlSend("{Enter}", control, "ahk_id " hwnd)
        return true
    } catch as err {
        LogWarn("Failed to submit dialog control: " control ", error=" err.Message)
        return false
    }
}

GetDialogControlsSafe(hwnd) {
    try {
        return WinGetControls("ahk_id " hwnd)
    } catch as err {
        LogWarn("Failed to enumerate dialog controls: " err.Message)
        return []
    }
}

GetFocusedControlSafe(hwnd) {
    try {
        return ControlGetFocus("ahk_id " hwnd)
    } catch {
        return ""
    }
}

GetFileDialogControlClassSafe(control, hwnd) {
    try {
        return ControlGetClassNN(control, "ahk_id " hwnd)
    } catch {
        return control
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
    controls := GetDialogControlsSafe(hwnd)
    if (controls.Length = 0)
        return false

    for control in controls {
        text := GetFileDialogControlTextSafe(control, hwnd)
        if (!text)
            continue

        normalizedText := NormalizeFileDialogPath(text)
        if (InStr(normalizedText, normalizedTarget))
            return true
    }

    return false
}

GetFileDialogControlTextSafe(control, hwnd) {
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
