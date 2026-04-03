; ============================================================
; Directory Opus Adapter — FolderJump
; Directory Opus 多标签页路径获取与跳转
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\utils.ahk"

; 收集 Directory Opus 所有标签页路径
; 返回: PathEntry[] 数组
; 方法: 窗口枚举 + 标题解析
CollectDOpusPaths() {
    paths := []

    ; 方法：窗口枚举 + 标题解析
    try {
        for hwnd in WinGetList("ahk_class dopus.lister") {
            try {
                title := WinGetTitle(hwnd)
                path := ExtractPathFromDOpusTitle(title)
                if (path && DirExist(path)) {
                    paths.Push({
                        path: path,
                        source: "dopus",
                        label: "DOpus",
                        hwnd: hwnd,
                        timestamp: A_TickCount
                    })
                }
            }
        }
    } catch as err {
        LogWarn("Directory Opus 路径收集失败: " err.Message)
    }

    ; 也检查 dopus.tab 类（多标签页）
    try {
        for hwnd in WinGetList("ahk_class dopus.tab") {
            try {
                title := WinGetTitle(hwnd)
                path := ExtractPathFromDOpusTitle(title)
                if (path && DirExist(path)) {
                    paths.Push({
                        path: path,
                        source: "dopus",
                        label: "DOpus",
                        hwnd: hwnd,
                        timestamp: A_TickCount
                    })
                }
            }
        }
    } catch as err {
        LogWarn("Directory Opus tab 类路径收集失败: " err.Message)
    }

    LogDebug("Directory Opus 路径收集: " paths.Length " 个标签")
    return paths
}

; 从 DOpus 窗口标题提取路径
; 参数:
;   title - 窗口标题，如 "C:\Users\ZuoQi - Directory Opus"
; 返回: 提取的路径字符串
ExtractPathFromDOpusTitle(title) {
    ; DOpus 标题格式通常是 "路径 - Directory Opus" 或仅 "路径"
    path := RegExReplace(title, " - Directory Opus$")
    path := RegExReplace(path, " - Opus$")
    path := Trim(path)
    return path
}

; Directory Opus 路径跳转
; 参数:
;   hwnd - DOpus 窗口句柄
;   targetPath - 目标路径
; 返回: 跳转成功返回 true，失败返回 false
; 方法: DOpusRT 命令行（优先） → Ctrl+L 键盘模拟（降级）
NavigateDOpus(hwnd, targetPath) {
    try {
        ; 尝试使用 DOpusRT 命令行（不需要剪贴板）
        dopusrtPath := FindDOpusRT()
        if (dopusrtPath) {
            Run('"' dopusrtPath '" /cmd Go "' targetPath '"', , "Hide")
            LogDebug("DOpusRT 跳转成功: " targetPath)
            return true
        }
    } catch as err {
        LogWarn("DOpusRT 跳转失败，降级为键盘模拟: " err.Message)
    }

    ; 降级：键盘模拟（需要保存剪贴板）
    savedClipboard := SaveClipboard()

    try {
        WinActivate("ahk_id " hwnd)
        WinWaitActive("ahk_id " hwnd, , 1000)

        ; Ctrl+L 聚焦路径栏（DOpus 默认快捷键）
        Send("^l")
        Sleep(50)

        A_Clipboard := targetPath
        Sleep(50)
        Send("^v")
        Sleep(50)
        Send("{Enter}")

        LogDebug("DOpus 键盘模拟跳转: " targetPath)

        ; 恢复剪贴板
        RestoreClipboard(savedClipboard)
        return true
    } catch as err {
        LogError("DOpus 跳转失败: " err.Message)
        RestoreClipboard(savedClipboard)
        return false
    }
}

; 查找 DOpusRT.exe 路径
; 返回: dopusrt.exe 完整路径，未找到返回空字符串
FindDOpusRT() {
    static candidates := [
        "C:\Program Files\GPSoftware\Directory Opus\dopusrt.exe",
        "C:\Program Files (x86)\GPSoftware\Directory Opus\dopusrt.exe"
    ]
    for path in candidates {
        if (FileExist(path))
            return path
    }
    return ""
}