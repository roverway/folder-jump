; ============================================================
; Path Switcher — FolderJump
; 路径跳转执行器
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\utils.ahk"
#Include "%A_ScriptDir%\adapters\explorer.ahk"
#Include "%A_ScriptDir%\adapters\totalcmd.ahk"
#Include "%A_ScriptDir%\adapters\dopus.ahk"

; 执行路径跳转
; 参数:
;   entry - PathEntry 对象，包含目标路径和来源信息
;   targetHwnd - 目标窗口句柄（可选，默认使用当前活动窗口）
; 行为:
;   根据当前焦点窗口类型选择合适的跳转方式
;   Explorer: COM 导航 → 键盘模拟
;   对话框: 键盘模拟 (Alt+D → 粘贴 → Enter)
;   Total Commander: Ctrl+D → 粘贴 → Enter
;   Directory Opus: DOpusRT 命令行 → Ctrl+L → 粘贴 → Enter
; 注意:
;   所有键盘模拟操作都会保存并恢复剪贴板内容
ExecutePathSwitch(entry, targetHwnd := 0) {
    ; 如果没有提供目标窗口句柄，使用当前活动窗口
    if (!targetHwnd)
        targetHwnd := WinExist("A")
    if (!targetHwnd) {
        LogError("无法获取前景窗口句柄")
        return
    }

    activeClass := WinGetClass(targetHwnd)

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
        SwitchFileDialog(targetHwnd, entry.path)
    }
    else if (activeClass = "CabinetWClass" || activeClass = "ExploreWClass") {
        ; Explorer 模式
        NavigateExplorer(targetHwnd, entry.path)
    }
    else if (activeClass = "TTOTAL_CMD") {
        ; Total Commander 模式
        NavigateTotalCmd(targetHwnd, entry.path)
    }
    else if (activeClass = "dopus.lister" || activeClass = "dopus.tab") {
        ; Directory Opus 模式
        NavigateDOpus(targetHwnd, entry.path)
    }
    else {
        ; 未知类型，尝试通用方法
        LogWarn("未知窗口类型: " activeClass "，使用通用跳转")
        SwitchFileDialogFallback(targetHwnd, entry.path)
    }
}

; 文件对话框跳转（优先尝试 COM，文件对话框通常不暴露给 COM）
SwitchFileDialog(hwnd, targetPath) {
    SwitchFileDialogFallback(hwnd, targetPath)
}

; 文件对话框降级方案：模拟地址栏输入
SwitchFileDialogFallback(hwnd, targetPath) {
    LogDebug("开始对话框跳转: hwnd=" hwnd ", path=" targetPath)
    
    ; 保存当前剪贴板内容
    savedClipboard := SaveClipboard()
    
    try {
        ; 激活目标窗口
        WinActivate("ahk_id " hwnd)
        if (!WinWaitActive("ahk_id " hwnd, , 2000)) {
            LogError("无法激活目标窗口: ahk_id " hwnd)
            RestoreClipboard(savedClipboard)
            return false
        }
        LogDebug("窗口已激活")

        ; 尝试 Ctrl+L 聚焦地址栏（现代对话框通用快捷键）
        Send("^l")
        Sleep(200)
        
        ; 如果 Ctrl+L 无效，尝试 Alt+D（传统快捷键）
        ; 直接选择所有文本准备覆盖
        Send("^a")
        Sleep(50)

        ; 设置剪贴板并等待写入完成
        A_Clipboard := targetPath
        if (!ClipWait(1)) {
            LogWarn("剪贴板写入超时")
        }
        Sleep(100)

        ; 粘贴路径
        Send("^v")
        Sleep(200)

        ; 确认
        Send("{Enter}")
        Sleep(200)

        LogDebug("对话框跳转成功: " targetPath)
        
        ; 恢复剪贴板（延迟恢复，避免影响粘贴操作）
        Sleep(300)
        RestoreClipboard(savedClipboard)
        return true
    } catch as err {
        LogError("对话框跳转失败: " err.Message)
        TrayTip("FolderJump", "跳转失败: " err.Message, 3000)
        RestoreClipboard(savedClipboard)
        return false
    }
}