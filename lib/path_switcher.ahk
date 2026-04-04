; ============================================================
; Path Switcher - FolderJump
; Execute path switching based on the current window type
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\utils.ahk"
#Include "%A_ScriptDir%\adapters\explorer.ahk"
#Include "%A_ScriptDir%\adapters\totalcmd.ahk"
#Include "%A_ScriptDir%\adapters\dopus.ahk"

; Execute path switch
; Params:
;   entry - PathEntry object with target path and source metadata
;   targetHwnd - target window handle, defaults to active window
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

    ; Route by the current target window type only.
    ; The source adapter provides the path, but must not hijack the target window.
    if (activeClass = "#32770") {
        SwitchFileDialog(targetHwnd, entry.path)
    }
    else if (activeClass = "CabinetWClass" || activeClass = "ExploreWClass") {
        NavigateExplorer(targetHwnd, entry.path)
    }
    else if (activeClass = "TTOTAL_CMD") {
        panel := entry.HasOwnProp("panel") ? entry.panel : "active"
        NavigateTotalCmd(targetHwnd, entry.path, panel)
    }
    else if (activeClass = "dopus.lister" || activeClass = "dopus.tab") {
        NavigateDOpus(targetHwnd, entry.path)
    }
    else {
        LogWarn("Unknown window type, using fallback: " activeClass)
        SwitchFileDialogFallback(targetHwnd, entry.path)
    }
}

; File dialog path switch
SwitchFileDialog(hwnd, targetPath) {
    SwitchFileDialogFallback(hwnd, targetPath)
}

; File dialog fallback: type into address bar
SwitchFileDialogFallback(hwnd, targetPath) {
    LogDebug("Start dialog switch: hwnd=" hwnd ", path=" targetPath)

    savedClipboard := SaveClipboard()

    try {
        WinActivate("ahk_id " hwnd)
        if (!WinWaitActive("ahk_id " hwnd, , 2000)) {
            LogError("Failed to activate target window: ahk_id " hwnd)
            RestoreClipboard(savedClipboard)
            return false
        }
        LogDebug("Target window activated")

        Send("^l")
        Sleep(200)

        Send("^a")
        Sleep(50)

        A_Clipboard := targetPath
        if (!ClipWait(1)) {
            LogWarn("Clipboard write timed out")
        }
        Sleep(100)

        Send("^v")
        Sleep(200)
        Send("{Enter}")
        Sleep(200)

        LogDebug("Dialog switch succeeded: " targetPath)

        Sleep(300)
        RestoreClipboard(savedClipboard)
        return true
    } catch as err {
        LogError("Dialog switch failed: " err.Message)
        TrayTip("FolderJump", "跳转失败: " err.Message, 3000)
        RestoreClipboard(savedClipboard)
        return false
    }
}
