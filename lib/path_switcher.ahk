; ============================================================
; 路径跳转模块 - FolderJump
; 负责根据当前窗口类型执行路径跳转
; 四层降级策略：UIA直达 → 地址栏导航 → Edit1快速跳转 → 全局按键兜底
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\utils.ahk"
#Include "%A_ScriptDir%\adapters\explorer.ahk"
#Include "%A_ScriptDir%\adapters\totalcmd.ahk"
#Include "%A_ScriptDir%\adapters\dopus.ahk"
#Include "%A_ScriptDir%\adapters\xyplorer.ahk"

; ============================================================
; 入口函数
; ============================================================

ExecutePathSwitch(entry, targetHwnd := 0) {
    if (!targetHwnd)
        targetHwnd := WinExist("A")
    if (!targetHwnd) {
        LogError("Failed to get foreground window handle")
        return
    }

    ; 验证目标窗口仍然存在（模态对话框可能在 GUI 关闭后被父窗口销毁）
    if (!WinExist("ahk_id " targetHwnd)) {
        LogError("Target window no longer exists: ahk_id " targetHwnd)
        TrayTip("FolderJump", "目标窗口已关闭，跳转取消", 2000)
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
    else {
        LogWarn("Unknown or unsupported window type, using fallback: " activeClass)
        SwitchFileDialogFallback(targetHwnd, entry.path)
    }
}

; ============================================================
; 跳转编排器：动态路由策略
; ============================================================

SwitchFileDialog(hwnd, targetPath) {
    ; 【特权层】：Edit1 快速跳转（仅限另存为对话框，极致丝滑 0 闪烁）
    if (WinExist("ahk_id " hwnd)) {
        result := TryNavigateViaEdit1(hwnd, targetPath)
        if (result = "ok")
            return true
        if (result = "closed") {
            TrayTip("FolderJump", "跳转失败：对话框已关闭，请重新打开后再试", 3000)
            return false
        }
    }

    ; 【通用层 0】：纯 UIA 直接操作（打开/保存通用，会有一次地址栏展开视觉动画）
    if (WinExist("ahk_id " hwnd)) {
        result := TryNavigateViaUIA(hwnd, targetPath)
        if (result = "ok")
            return true
        if (result = "closed") {
            TrayTip("FolderJump", "跳转失败：对话框已关闭，请重新打开后再试", 3000)
            return false
        }
    }

    ; 【通用层 1】：地址栏导航（Alt+D 轮询兜底）
    if (WinExist("ahk_id " hwnd)) {
        result := TryNavigateViaAddressBar(hwnd, targetPath)
        if (result = "ok")
            return true
        if (result = "closed") {
            TrayTip("FolderJump", "跳转失败：对话框已关闭，请重新打开后再试", 3000)
            return false
        }
    }

    ; ======= 新增补丁：【绝境层】：老式“打开”对话框强行兜底 =======
    ; 当 UIA 和 Alt+D 都找不到地址栏时，说明这是 Ahk2Exe 这种远古风格对话框。
    ; 此时无视打开对话框的误关风险，强行向 Edit1 写入带反斜杠的路径并回车。
    if (WinExist("ahk_id " hwnd)) {
        result := TryNavigateLegacyOpenDialog(hwnd, targetPath)
        if (result = "ok")
            return true
        if (result = "closed") {
            TrayTip("FolderJump", "跳转失败：对话框已关闭，请重新打开后再试", 3000)
            return false
        }
    }
    ; ================================================================

    ; 【最终层】：全局按键模拟兜底
    if (WinExist("ahk_id " hwnd))
        return SwitchFileDialogFallback(hwnd, targetPath)

    return false
}

; ============================================================
; 层0：非 UIA 直接操作（绕过权限限制）
; ============================================================
TryNavigateViaUIA(hwnd, targetPath) {
    LogDebug("Try non-UIA direct navigation: " targetPath)
    try {
        ; 激活目标对话框
        if (!ActivateTargetWindow(hwnd))
            return "failed"

        ; 发送 Alt+D 激活地址栏编辑模式
        Send("!d")

        ; 等待地址栏 Edit 获得焦点（通常 40-80ms 即完成，最多等 300ms）
        addressEditCtrl := ""
        startTime := A_TickCount
        Loop {
            if (A_TickCount - startTime > 300)
                break
            if (!WinExist("ahk_id " hwnd))
                return "closed"
            focused := GetFocusedControlSafe(hwnd)
            if (focused && InStr(StrLower(GetControlClassSafe(focused, hwnd)), "edit")) {
                addressEditCtrl := focused
                break
            }
            Sleep(20)
        }

        if (!addressEditCtrl)
            return "failed"

        ; 获取地址栏 Edit 控件的句柄
        try {
            editHwnd := ControlGetHwnd(addressEditCtrl, "ahk_id " hwnd)
        } catch {
            return "failed"
        }

        ; 使用 SendMessage 设置文本（WM_SETTEXT = 0x000C）
        SendMessage(0x000C, 0, StrPtr(targetPath), editHwnd)

        Sleep(30)

        ; 使用 PostMessage 发送 Enter（WM_KEYDOWN = 0x0100, VK_RETURN = 0x0D）
        PostMessage(0x0100, 0x0D, 0, editHwnd)

        Sleep(100)
        if (!WinExist("ahk_id " hwnd)) {
            LogWarn("Non-UIA: dialog closed after Enter")
            return "closed"
        }

        if (WaitForFileDialogPath(hwnd, targetPath, 1.0)) {
            LogInfo("Non-UIA direct navigation succeeded: " targetPath)
            return "ok"
        }

        return "failed"
    } catch {
        return "failed"
    }
}

; ============================================================
; 层1：地址栏导航（自适应轮询优化版）
; ============================================================
;
; 返回值："ok" / "closed" / "failed"

TryNavigateViaAddressBar(hwnd, targetPath) {
    LogDebug("Try address bar navigation: " targetPath)
    try {
        if (!ActivateTargetWindow(hwnd))
            return "failed"

        ; 发送 Alt+D 激活地址栏编辑模式
        Send("!d")

        ; 自适应轮询：等待地址栏 Edit 获得焦点（替代固定 Sleep(150)）
        ; 通常 40-80ms 即完成，最多等 300ms
        addressEditCtrl := ""
        startTime := A_TickCount
        Loop {
            if (A_TickCount - startTime > 300)
                break
            if (!WinExist("ahk_id " hwnd))
                return "closed"
            focused := GetFocusedControlSafe(hwnd)
            if (focused && focused != "Edit1") {
                className := GetControlClassSafe(focused, hwnd)
                if (InStr(StrLower(className), "edit")) {
                    addressEditCtrl := focused
                    break
                }
            }
            Sleep(20)
        }

        if (!addressEditCtrl) {
            LogDebug("Address bar: Edit control not found after Alt+D")
            return "failed"
        }

        ; 填入目标路径
        try {
            ControlSetText(targetPath, addressEditCtrl, "ahk_id " hwnd)
        } catch as err {
            LogWarn("Address bar: failed to set text: " err.Message)
            return "failed"
        }

        ; 发送 Enter 触发导航（地址栏 Enter = 导航，不会确认文件选择）
        ControlSend("{Enter}", addressEditCtrl, "ahk_id " hwnd)

        Sleep(80)
        if (!WinExist("ahk_id " hwnd)) {
            LogWarn("Address bar: dialog closed after Enter")
            return "closed"
        }

        if (WaitForFileDialogPath(hwnd, targetPath, 1.0)) {
            LogInfo("Address bar navigation succeeded: " targetPath)
            return "ok"
        }

        LogDebug("Address bar: navigation could not be verified")
        return "failed"
    } catch as err {
        LogWarn("Address bar navigation failed: " err.Message)
        return "failed"
    }
}

; ============================================================
; 层2：Edit1 快速跳转（仅限另存为对话框）
; ============================================================
;
; 返回值："ok" / "closed" / "skip" / "failed"

TryNavigateViaEdit1(hwnd, targetPath) {
    LogDebug("Try Edit1 navigation")

    navPath := targetPath
    if (SubStr(navPath, -1) != "\")
        navPath .= "\"

    try {
        editControl := "Edit1"

        try {
            ControlGetStyle(editControl, "ahk_id " hwnd)
        } catch {
            LogWarn("Edit1 control not found")
            return "skip"
        }

        ; 通过 Button1 文字区分打开/保存对话框
        confirmBtnText := ""
        try {
            confirmBtnText := StrLower(ControlGetText("Button1", "ahk_id " hwnd))
        }
        isOpenDialog := (InStr(confirmBtnText, "open") || InStr(confirmBtnText, "打开"))
        LogDebug("Dialog confirm button: '" confirmBtnText "', isOpenDialog=" isOpenDialog)

        originalText := GetControlTextSafe(editControl, hwnd)

        ControlFocus(editControl, "ahk_id " hwnd)
        ControlSetText(navPath, editControl, "ahk_id " hwnd)
        Sleep(20)

        ControlSend("{Enter}", editControl, "ahk_id " hwnd)

        Sleep(80)
        if (!WinExist("ahk_id " hwnd)) {
            LogWarn("Dialog closed after Edit1 Enter: " targetPath)
            return "closed"
        }

        navigatesOk := WaitForFileDialogPath(hwnd, targetPath, 1.0)

        if (WinExist("ahk_id " hwnd)) {
            ControlSetText(originalText, editControl, "ahk_id " hwnd)
        }

        if (navigatesOk) {
            LogInfo("Edit1 navigation succeeded: " targetPath)
            return "ok"
        } else {
            LogWarn("Edit1 navigation couldn't be verified")
            return "failed"
        }
    } catch as err {
        LogWarn("Edit1 navigation failed: " err.Message)
        return "failed"
    }
}

; ============================================================
; 层3：全局按键模拟兜底
; ============================================================

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


; ============================================================
; 绝境层：老式“打开”对话框强制 Edit1 兜底
; ============================================================
TryNavigateLegacyOpenDialog(hwnd, targetPath) {
    LogDebug("Try Legacy Open Dialog Edit1 Fallback")
    
    ; 必须以反斜杠结尾，这是强迫老式对话框跳目录的秘诀
    navPath := targetPath
    if (SubStr(navPath, -1) != "\")
        navPath .= "\"

    try {
        if (!ActivateTargetWindow(hwnd))
            return "failed"

        editControl := "Edit1"
        try ControlGetStyle(editControl, "ahk_id " hwnd)
        catch 
            return "failed"

        originalText := GetControlTextSafe(editControl, hwnd)
        
        ControlFocus(editControl, "ahk_id " hwnd)
        ControlSetText(navPath, editControl, "ahk_id " hwnd)
        
        ; 老式对话框需要给 EN_CHANGE 事件一点反应时间
        Sleep(60) 
        
        ControlSend("{Enter}", editControl, "ahk_id " hwnd)
        
        Sleep(100)
        if (!WinExist("ahk_id " hwnd)) {
            LogWarn("Legacy fallback: dialog closed unexpectedly")
            return "closed"
        }

        if (WaitForFileDialogPath(hwnd, targetPath, 1.0)) {
            ControlSetText(originalText, editControl, "ahk_id " hwnd)
            LogInfo("Legacy Open Dialog navigation succeeded: " targetPath)
            return "ok"
        }
        
        return "failed"
    } catch {
        return "failed"
    }
}

; ============================================================
; 辅助函数
; ============================================================

ActivateTargetWindow(hwnd) {
    if (!WinExist("ahk_id " hwnd)) {
        LogError("Target window does not exist: ahk_id " hwnd)
        return false
    }

    WinActivate("ahk_id " hwnd)
    if (!WinWaitActive("ahk_id " hwnd, , 2)) {
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

GetDialogControlsSafe(hwnd) {
    try {
        return WinGetControls("ahk_id " hwnd)
    } catch as err {
        LogWarn("Failed to enumerate dialog controls: " err.Message)
        return []
    }
}

WaitForFileDialogPath(hwnd, targetPath, timeoutSec := 1.5) {
    normalizedTarget := NormalizePathString(targetPath)
    iterations := Ceil(timeoutSec * 1000 / 50)

    Loop iterations {
        Sleep(50)

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
        text := GetControlTextSafe(control, hwnd)
        if (!text)
            continue

        normalizedText := NormalizePathString(text)
        if (InStr(normalizedText, normalizedTarget))
            return true
    }

    return false
}
