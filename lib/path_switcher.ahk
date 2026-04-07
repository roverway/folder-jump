; ============================================================
; 路径跳转模块 - FolderJump
; 负责根据当前窗口类型执行路径跳转
; 三层降级策略：地址栏导航 → Edit1快速跳转 → 全局按键兜底
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
; 跳转编排器：3 层降级策略
; ============================================================

SwitchFileDialog(hwnd, targetPath) {
    ; 层1：地址栏导航（Alt+D → 编辑框填路径 → Enter）
    ;   对打开/保存对话框均安全，地址栏 Enter 语义永远是"导航"而非"确认文件选择"
    ;   这是 Listary 等工具使用的核心方法
    result := TryNavigateViaAddressBar(hwnd, targetPath)
    if (result = "ok")
        return true
    if (result = "closed") {
        LogWarn("Dialog closed during address bar navigation")
        TrayTip("FolderJump", "跳转失败：对话框已关闭，请重新打开后再试", 3000)
        return false
    }

    ; 层2：Edit1 快速跳转（仅限另存为对话框，打开对话框会返回 "skip"）
    ;   对另存为对话框效果最好：0闪烁，最丝滑
    if (WinExist("ahk_id " hwnd)) {
        result := TryNavigateViaEdit1(hwnd, targetPath)
        if (result = "ok")
            return true
        if (result = "closed") {
            LogWarn("Dialog closed during Edit1 navigation")
            TrayTip("FolderJump", "跳转失败：对话框已关闭，请重新打开后再试", 3000)
            return false
        }
    }

    ; 层3：全局按键模拟兜底（Alt+D → Ctrl+A → Ctrl+V → Enter）
    if (WinExist("ahk_id " hwnd))
        return SwitchFileDialogFallback(hwnd, targetPath)

    return false
}

; ============================================================
; 层1：地址栏导航（打开/保存通用，最安全）
; ============================================================
;
; 原理：Alt+D 将面包屑地址栏切换为可编辑文本框，填入路径后
; 按 Enter 触发"导航到该路径"。与 Edit1（文件名框）不同，
; 地址栏的 Enter 永远是导航语义，不会触发文件选择确认。
;
; 返回值："ok" / "closed" / "failed"

TryNavigateViaAddressBar(hwnd, targetPath) {
    LogDebug("Try address bar navigation: " targetPath)
    try {
        if (!ActivateTargetWindow(hwnd))
            return "failed"

        ; 发送 Alt+D 激活地址栏编辑模式
        Send("!d")
        Sleep(150)

        ; 检查窗口是否还存在
        if (!WinExist("ahk_id " hwnd))
            return "closed"

        ; 获取当前焦点控件（应该是地址栏编辑框）
        focusedControl := GetFocusedControlSafe(hwnd)
        if (!focusedControl) {
            LogWarn("Address bar: no focused control after Alt+D")
            return "failed"
        }

        ; 验证焦点控件是 Edit 类型（地址栏进入编辑模式后会变成 Edit 控件）
        className := GetControlClassSafe(focusedControl, hwnd)
        if (!InStr(StrLower(className), "edit")) {
            LogDebug("Address bar: focused control is not Edit type: " className)
            return "failed"
        }

        ; 确保焦点不在文件名输入框 (Edit1) 上
        ; 如果 Alt+D 后聚焦到 Edit1，说明该对话框没有标准地址栏
        if (focusedControl = "Edit1") {
            LogDebug("Address bar: Alt+D focused Edit1 (filename box), not address bar")
            return "failed"
        }

        ; 填入目标路径
        try {
            ControlSetText(targetPath, focusedControl, "ahk_id " hwnd)
        } catch as err {
            LogWarn("Address bar: failed to set text: " err.Message)
            return "failed"
        }

        Sleep(50)

        ; 发送 Enter 触发导航（地址栏的 Enter 不会确认文件选择）
        ControlSend("{Enter}", focusedControl, "ahk_id " hwnd)

        Sleep(100)
        if (!WinExist("ahk_id " hwnd)) {
            LogWarn("Address bar: dialog closed after Enter")
            return "closed"
        }

        ; 等待对话框完成跳转
        if (WaitForFileDialogPath(hwnd, targetPath, 1.0)) {
            LogInfo("Address bar navigation succeeded: " targetPath)
            return "ok"
        }

        LogDebug("Address bar: navigation could not be verified within timeout")
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
; 原理：在文件名输入框 (Edit1) 填入目录路径并发 Enter，
; 另存为对话框会导航到该目录。但打开文件对话框会把路径当
; 作"确认选择"而关闭对话框，因此必须跳过。
;
; 返回值："ok" / "closed" / "skip" / "failed"

TryNavigateViaEdit1(hwnd, targetPath) {
    LogDebug("Try Edit1 navigation")

    ; 路径必须以反斜杠结尾，否则对话框可能会尝试选中同名文件而不是跳转目录
    navPath := targetPath
    if (SubStr(navPath, -1) != "\")
        navPath .= "\"

    try {
        editControl := "Edit1"

        ; 检查 Edit1 是否真正存在
        try {
            ControlGetStyle(editControl, "ahk_id " hwnd)
        } catch {
            LogWarn("Edit1 control not found for fast navigation")
            return "skip"
        }

        ; 判断对话框类型：通过 Button1 的文字区分打开/保存
        ; "打开"类对话框在 Edit1 填入目录路径后按 Enter 会关闭对话框
        ; "保存"类对话框则会导航到目录
        confirmBtnText := ""
        try {
            confirmBtnText := StrLower(ControlGetText("Button1", "ahk_id " hwnd))
        }
        isOpenDialog := (InStr(confirmBtnText, "open") || InStr(confirmBtnText, "打开"))
        LogDebug("Dialog confirm button: '" confirmBtnText "', isOpenDialog=" isOpenDialog)

        ; 打开文件对话框必须跳过 Edit1 方案
        if (isOpenDialog) {
            LogDebug("Skipping Edit1 for open-file dialog to avoid accidental confirmation")
            return "skip"
        }

        ; 1. 备份原文件名（用户可能已在另存为对话框输入了要保存的文件名）
        originalText := GetControlTextSafe(editControl, hwnd)

        ; 2. 聚焦文件名输入框，设置为目标路径
        ControlFocus(editControl, "ahk_id " hwnd)
        ControlSetText(navPath, editControl, "ahk_id " hwnd)

        ; 短暂等待 Windows 内部应用控件变更事件
        Sleep(20)

        ; 3. 发送 Enter 执行路径跳转
        ControlSend("{Enter}", editControl, "ahk_id " hwnd)

        ; 3.5 立即检查窗口是否还存在
        ; 某些边缘情况下 Enter 可能导致对话框关闭
        Sleep(80)
        if (!WinExist("ahk_id " hwnd)) {
            LogWarn("Dialog closed after Edit1 Enter (unexpected): " targetPath)
            return "closed"
        }

        ; 4. 等待对话框完成跳转
        navigatesOk := WaitForFileDialogPath(hwnd, targetPath, 1.0)

        ; 5. 瞬间恢复用户原本输入的文件名
        if (WinExist("ahk_id " hwnd)) {
            ControlSetText(originalText, editControl, "ahk_id " hwnd)
        }

        if (navigatesOk) {
            LogInfo("Edit1 navigation succeeded: " targetPath)
            return "ok"
        } else {
            LogWarn("Edit1 navigation couldn't be verified within timeout")
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
; 辅助函数
; ============================================================

ActivateTargetWindow(hwnd) {
    ; 先检查窗口是否存在
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
