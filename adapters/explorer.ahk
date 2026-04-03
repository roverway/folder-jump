; ============================================================
; Explorer Adapter — FolderJump
; Windows Explorer 路径获取与跳转适配器
; ============================================================

#IncludeOnce "%A_ScriptDir%\lib\log_manager.ahk"
#IncludeOnce "%A_ScriptDir%\lib\utils.ahk"

; 收集所有 Explorer 窗口路径
CollectExplorerPaths() {
    paths := []
    try {
        shell := ComObject("Shell.Application")
    } catch as err {
        LogError("Shell.Application COM 对象获取失败: " err.Message)
        return paths
    }

    for window in shell.Windows {
        try {
            ; 跳过非 Explorer 窗口（如 IE）
            if (window.LocationName = "")
                continue

            ; 获取文件夹路径
            folder := window.Document.Folder
            if (!IsSet(folder) || !folder)
                continue

            path := folder.Self.Path
            if (!path || path = "")
                continue

            ; 跳过虚拟文件夹
            if (IsVirtualFolder(path))
                continue

            paths.Push({
                path: path,
                source: "explorer",
                label: "Explorer",
                hwnd: window.hwnd,
                timestamp: A_TickCount
            })
        }
    }

    LogDebug("Explorer 路径收集: " paths.Length " 个窗口")
    return paths
}

; 判断是否为虚拟文件夹
IsVirtualFolder(path) {
    static virtualPrefixes := [
        "::{20D04FE0-3AEA-1069-A2D8-08002B30309D}",  ; 此电脑
        "::{031E4825-7B94-4DC3-B131-E946B44C8DD5}",  ; 库
        "::{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}",  ; 网络
        "::{645FF040-5081-101B-9F08-00AA002F954E}"   ; 回收站
    ]
    for vp in virtualPrefixes {
        if (InStr(path, vp) = 1)
            return true
    }
    return false
}

; 导航到目标路径（COM 方法，优先）
NavigateExplorer(hwnd, targetPath) {
    try {
        shell := ComObject("Shell.Application")
    } catch as err {
        LogError("Shell.Application COM 获取失败，降级为键盘模拟: " err.Message)
        NavigateExplorerFallback(hwnd, targetPath)
        return
    }

    for window in shell.Windows {
        try {
            if (window.hwnd = hwnd) {
                window.Navigate(targetPath)
                LogDebug("Explorer COM 导航成功: " targetPath)
                return true
            }
        }
    }

    ; 未找到对应窗口，降级
    LogWarn("未找到匹配的 Explorer 窗口，降级为键盘模拟")
    NavigateExplorerFallback(hwnd, targetPath)
}

; 导航降级方案：模拟地址栏输入
NavigateExplorerFallback(hwnd, targetPath) {
    ; 保存当前剪贴板内容
    savedClipboard := SaveClipboard()
    
    try {
        WinActivate("ahk_id " hwnd)
        if (!WinWaitActive("ahk_id " hwnd, , 1000)) {
            LogError("无法激活 Explorer 窗口: ahk_id " hwnd)
            RestoreClipboard(savedClipboard)
            return false
        }

        ; Alt+D 聚焦地址栏
        Send("!d")
        Sleep(50)

        ; 粘贴路径
        A_Clipboard := targetPath
        Sleep(50)
        Send("^v")
        Sleep(50)
        Send("{Enter}")

        LogDebug("Explorer 键盘模拟导航: " targetPath)
        
        ; 恢复剪贴板
        RestoreClipboard(savedClipboard)
        return true
    } catch as err {
        LogError("Explorer 导航失败: " err.Message)
        RestoreClipboard(savedClipboard)
        return false
    }
}
