; ============================================================
; Total Commander Adapter — FolderJump
; Total Commander 双面板路径获取与跳转
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\utils.ahk"

; 收集 Total Commander 双面板路径
; 返回: PathEntry[] 数组，包含左/右面板路径
; 方法: 读取 wincmd.ini 配置文件
CollectTotalCmdPaths() {
    paths := []

    ; 方法：读取 TC 的 wincmd.ini 配置文件
    iniPath := FindTCIniPath()
    if (!iniPath) {
        LogDebug("未找到 Total Commander 配置文件")
        return paths
    }

    try {
        leftPath := IniRead(iniPath, "left", "path", "")
        rightPath := IniRead(iniPath, "right", "path", "")
        
        ; 获取 ini 文件所在目录作为相对路径的基准
        iniDir := SubStr(iniPath, 1, InStr(iniPath, "\", , -1) - 1)

        ; 处理左面板路径
        if (leftPath && leftPath != "") {
            leftPath := ResolveTCPath(leftPath, iniDir)
            if (leftPath && DirExist(leftPath)) {
                paths.Push({
                    path: leftPath,
                    source: "totalcmd",
                    label: "TC (左)",
                    hwnd: 0,
                    panel: "left",
                    timestamp: A_TickCount
                })
            }
        }

        ; 处理右面板路径
        if (rightPath && rightPath != "") {
            rightPath := ResolveTCPath(rightPath, iniDir)
            if (rightPath && DirExist(rightPath)) {
                paths.Push({
                    path: rightPath,
                    source: "totalcmd",
                    label: "TC (右)",
                    hwnd: 0,
                    panel: "right",
                    timestamp: A_TickCount
                })
            }
        }
    } catch as err {
        LogWarn("Total Commander 路径读取失败: " err.Message)
    }

    LogDebug("Total Commander 路径收集: " paths.Length " 个面板")
    return paths
}

; 解析 TC 路径（相对路径转为绝对路径）
; 参数:
;   path - 原始路径字符串
;   iniDir - wincmd.ini 所在目录
; 返回: 绝对路径
ResolveTCPath(path, iniDir) {
    ; 如果已经是绝对路径，直接返回
    if (InStr(path, ":\"))
        return path
    
    ; 如果是相对路径，基于 ini 文件目录解析
    if (SubStr(path, 1, 1) = "\") {
        ; 路径以反斜杠开头，可能是相对于驱动器根目录
        ; 获取驱动器字母
        driveLetter := SubStr(iniDir, 1, 2)
        return driveLetter path
    }
    
    ; 普通相对路径，基于 ini 目录
    fullPath := iniDir "\" path
    
    ; 标准化路径
    fullPath := StrReplace(fullPath, "/", "\")
    while InStr(fullPath, "\\")
        fullPath := StrReplace(fullPath, "\\", "\")
    
    return fullPath
}

; 查找 TC 配置文件路径
; 返回: wincmd.ini 完整路径，未找到则返回空字符串
FindTCIniPath() {
    static candidates := [
        A_AppData "\GHISLER\wincmd.ini",
        A_ProgramFiles "\Totalcmd\wincmd.ini",
        A_ProgramFiles "\totalcmd\wincmd.ini",
        "C:\Totalcmd\wincmd.ini"
    ]
    for path in candidates {
        if (FileExist(path))
            return path
    }
    return ""
}

; Total Commander 路径跳转
; 参数:
;   hwnd - TC 窗口句柄
;   targetPath - 目标路径
; 返回: 跳转成功返回 true，失败返回 false
; 方法: Ctrl+D → 粘贴 → Enter（键盘模拟）
NavigateTotalCmd(hwnd, targetPath) {
    ; 保存当前剪贴板内容（由 path_switcher 提供）
    savedClipboard := SaveClipboard()
    
    try {
        WinActivate("ahk_id " hwnd)
        if (!WinWaitActive("ahk_id " hwnd, , 1000)) {
            LogError("无法激活 Total Commander 窗口")
            RestoreClipboard(savedClipboard)
            return false
        }

        ; Ctrl+D 打开路径输入框（TC 默认快捷键）
        Send("^d")
        Sleep(50)

        A_Clipboard := targetPath
        Sleep(50)
        Send("^v")
        Sleep(50)
        Send("{Enter}")

        LogDebug("Total Commander 跳转成功: " targetPath)
        
        ; 恢复剪贴板
        RestoreClipboard(savedClipboard)
        return true
    } catch as err {
        LogError("Total Commander 跳转失败: " err.Message)
        RestoreClipboard(savedClipboard)
        return false
    }
}