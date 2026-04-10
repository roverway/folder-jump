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
    ; 只要是保存类对话框，优先用它。如果是打开类对话框，它内部会自动返回 "skip"
    if (WinExist("ahk_id " hwnd)) {
        result := TryNavigateViaEdit1(hwnd, targetPath)
        if (result = "ok")
            return true
        if (result = "closed") {
            TrayTip("FolderJump", "跳转失败：对话框已关闭，请重新打开后再试", 3000)
            return false
        }
        ; 如果返回 "skip" (打开对话框) 或 "failed"，继续往下走
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

    ; 【最终层】：全局按键模拟兜底
    if (WinExist("ahk_id " hwnd))
        return SwitchFileDialogFallback(hwnd, targetPath)

    return false
}

; ============================================================
; 层0：纯 UIA 直接操作（最快，无键盘模拟）
; ============================================================
;
; 原理：通过 Windows 内置 IUIAutomation COM 接口直接定位
; 地址栏 Edit 控件，用 SetFocus 激活编辑模式，用 ValuePattern
; 设置路径文本，用 ControlSend 发 Enter 完成导航。
; 全程不使用 Send() 全局按键，无竞态风险。
;
; 返回值："ok" / "closed" / "failed"

TryNavigateViaUIA(hwnd, targetPath) {
    LogDebug("Try UIA direct navigation: " targetPath)
    try {
        ; 初始化 UI Automation（Windows 内置，无需外部库）
        UIA := ComObject("UIAutomationClient.CUIAutomation")
        if (!UIA)
            return "failed"

        rootEl := UIA.ElementFromHandle(hwnd)
        if (!rootEl)
            return "failed"

        ; UIA 常量定义
        UIA_ControlTypePropertyId := 30003
        UIA_ComboBoxControlTypeId := 50003
        UIA_EditControlTypeId := 50004
        TreeScope_Descendants := 4
        TreeScope_Children := 2

        ; 策略：找地址栏的 ComboBox（排除文件名和文件类型的 ComboBox）
        ; 标准文件对话框中地址栏是 "Previous Locations" / "以前的位置" ComboBox
        comboCond := UIA.CreatePropertyCondition(UIA_ControlTypePropertyId, UIA_ComboBoxControlTypeId)
        combos := rootEl.FindAll(TreeScope_Descendants, comboCond)

        if (!combos || combos.Length = 0) {
            LogDebug("UIA: no ComboBox found")
            return "failed"
        }

        addressCombo := ""
        editCond := UIA.CreatePropertyCondition(UIA_ControlTypePropertyId, UIA_EditControlTypeId)

        Loop combos.Length {
            el := combos.GetElement(A_Index - 1)
            comboName := ""
            try comboName := el.CurrentName
            lowerName := StrLower(comboName)

            ; 排除文件名输入框和文件类型筛选的 ComboBox
            if (InStr(lowerName, "file name") || InStr(lowerName, "文件名"))
                continue
            if (InStr(lowerName, "file type") || InStr(lowerName, "文件类型")
                || InStr(lowerName, "save as type") || InStr(lowerName, "保存类型"))
                continue

            ; 匹配地址栏关键词
            if (InStr(lowerName, "previous") || InStr(lowerName, "以前")
                || InStr(lowerName, "address") || InStr(lowerName, "地址")) {
                addressCombo := el
                break
            }

            ; 兜底：检查该 ComboBox 内是否有包含路径的 Edit 子元素
            try {
                childEdit := el.FindFirst(TreeScope_Children, editCond)
                if (childEdit) {
                    editVal := ""
                    try editVal := childEdit.GetCurrentPropertyValue(30045)
                    if (editVal && InStr(editVal, "\") && InStr(editVal, ":")) {
                        addressCombo := el
                        break
                    }
                }
            }
        }

        if (!addressCombo) {
            LogDebug("UIA: address bar ComboBox not found")
            return "failed"
        }

        ; 在地址栏 ComboBox 中找 Edit 子元素
        addressEdit := ""
        try addressEdit := addressCombo.FindFirst(TreeScope_Descendants, editCond)
        if (!addressEdit) {
            LogDebug("UIA: Edit not found in address bar")
            return "failed"
        }

        ; 聚焦地址栏 Edit（触发面包屑→编辑模式转换）
        try addressEdit.SetFocus()
        Sleep(50)

        if (!WinExist("ahk_id " hwnd))
            return "closed"

        ; 设置路径文本：优先用 ValuePattern，降级用 ControlSetText
        valueSet := false
        try {
            ; UIA_ValuePatternId = 10002
            valPattern := addressEdit.GetCurrentPattern(10002)
            if (valPattern) {
                ; IUIAutomationValuePattern::SetValue (vtable index 3)
                ComCall(3, valPattern, "WStr", targetPath)
                valueSet := true
                LogDebug("UIA: path set via ValuePattern")
            }
        }

        if (!valueSet) {
            ; 降级：通过控件句柄用 ControlSetText
            try {
                nativeHwnd := addressEdit.CurrentNativeWindowHandle
                if (nativeHwnd) {
                    ControlSetText(targetPath, "ahk_id " nativeHwnd)
                    valueSet := true
                    LogDebug("UIA: path set via ControlSetText fallback")
                }
            }
        }

        if (!valueSet) {
            ; 再降级：用当前焦点控件
            focusedCtrl := GetFocusedControlSafe(hwnd)
            if (focusedCtrl) {
                try {
                    ControlSetText(targetPath, focusedCtrl, "ahk_id " hwnd)
                    valueSet := true
                    LogDebug("UIA: path set via focused control fallback")
                }
            }
        }

        if (!valueSet) {
            LogDebug("UIA: failed to set path text")
            return "failed"
        }

        Sleep(30)

        ; 发送 Enter 触发导航
        focusedCtrl := GetFocusedControlSafe(hwnd)
        if (focusedCtrl)
            ControlSend("{Enter}", focusedCtrl, "ahk_id " hwnd)
        else
            Send("{Enter}")

        Sleep(80)
        if (!WinExist("ahk_id " hwnd)) {
            LogWarn("UIA: dialog closed after Enter")
            return "closed"
        }

        ; 验证导航结果
        if (WaitForFileDialogPath(hwnd, targetPath, 1.0)) {
            LogInfo("UIA direct navigation succeeded: " targetPath)
            return "ok"
        }

        LogDebug("UIA: navigation could not be verified")
        return "failed"
    } catch as err {
        LogDebug("UIA navigation failed: " err.Message)
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
