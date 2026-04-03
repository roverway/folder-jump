; ============================================================
; Path Switcher — FolderJump
; 路径跳转执行器
; ============================================================

#IncludeOnce "%A_ScriptDir%\lib\log_manager.ahk"
#IncludeOnce "%A_ScriptDir%\lib\utils.ahk"
#IncludeOnce "%A_ScriptDir%\adapters\explorer.ahk"
#IncludeOnce "%A_ScriptDir%\adapters\totalcmd.ahk"
#IncludeOnce "%A_ScriptDir%\adapters\dopus.ahk"

; 执行路径跳转
; 参数:
;   entry - PathEntry 对象，包含目标路径和来源信息
; 行为:
;   根据当前焦点窗口类型选择合适的跳转方式
;   Explorer: COM 导航 → 键盘模拟
;   对话框: 键盘模拟 (Alt+D → 粘贴 → Enter)
;   Total Commander: Ctrl+D → 粘贴 → Enter
;   Directory Opus: DOpusRT 命令行 → Ctrl+L → 粘贴 → Enter
; 注意:
;   所有键盘模拟操作都会保存并恢复剪贴板内容
ExecutePathSwitch(entry) {
    activeHwnd := WinExist("A")
    if (!activeHwnd) {
        LogError("无法获取前景窗口句柄")
        return
    }

    activeClass := WinGetClass(activeHwnd)

    ; 验证目标路径是否存在
    if (!DirExist(entry.path)) {
        LogWarn("目标路径不存在: " entry.path)
        TrayTip("FolderJump", "路径不存在: " entry.path, 3000)
        return
    }

    LogInfo("执行路径跳转: " entry.path " [" entry.label "]")

    ; 根据当前窗口类型选择跳转方式
    if (activeClass = "#32770") {
        ; 文件对话框模式
        SwitchFileDialog(activeHwnd, entry.path)
    }
    else if (activeClass = "CabinetWClass" || activeClass = "ExploreWClass") {
        ; Explorer 模式
        NavigateExplorer(activeHwnd, entry.path)
    }
    else if (activeClass = "TTOTAL_CMD") {
        ; Total Commander 模式
        NavigateTotalCmd(activeHwnd, entry.path)
    }
    else if (activeClass = "dopus.lister" || activeClass = "dopus.tab") {
        ; Directory Opus 模式
        NavigateDOpus(activeHwnd, entry.path)
    }
    else {
        ; 未知类型，尝试通用方法
        LogWarn("未知窗口类型: " activeClass "，使用通用跳转")
        SwitchFileDialogFallback(activeHwnd, entry.path)
    }
}

; 文件对话框跳转（优先尝试 COM，文件对话框通常不暴露给 COM）
SwitchFileDialog(hwnd, targetPath) {
    SwitchFileDialogFallback(hwnd, targetPath)
}

; 文件对话框降级方案：模拟地址栏输入
SwitchFileDialogFallback(hwnd, targetPath) {
    ; 保存当前剪贴板内容
    savedClipboard := SaveClipboard()
    
    try {
        WinActivate("ahk_id " hwnd)
        if (!WinWaitActive("ahk_id " hwnd, , 1000)) {
            LogError("无法激活目标窗口: ahk_id " hwnd)
            RestoreClipboard(savedClipboard)
            return false
        }

        ; Alt+D 聚焦地址栏
        Send("!d")
        Sleep(80)

        ; 粘贴路径
        A_Clipboard := targetPath
        Sleep(50)
        Send("^v")
        Sleep(80)

        ; 确认
        Send("{Enter}")
        Sleep(100)

        LogDebug("对话框跳转成功: " targetPath)
        
        ; 恢复剪贴板
        RestoreClipboard(savedClipboard)
        return true
    } catch as err {
        LogError("对话框跳转失败: " err.Message)
        TrayTip("FolderJump", "跳转失败: " err.Message, 3000)
        RestoreClipboard(savedClipboard)
        return false
    }
}