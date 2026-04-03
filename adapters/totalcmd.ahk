; ============================================================
; Total Commander Adapter — FolderJump
; Total Commander 双面板路径获取与跳转
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\utils.ahk"

; 收集 Total Commander 双面板路径
; 返回: PathEntry[] 数组，包含左/右面板路径
; 方法: 使用 TC 官方 API (SendMessage 1074, 17 获取路径控件句柄)
CollectTotalCmdPaths() {
    paths := []
    
    LogInfo("开始收集 Total Commander 路径...")

    try {
        ; 枚举所有 TC 窗口
        tcWindows := WinGetList("ahk_class TTOTAL_CMD")
        tcCount := tcWindows.Length
        LogInfo("找到 " tcCount " 个 TC 窗口")
        
        for hwnd in tcWindows {
            try {
                ; 使用 TC 官方 API 获取路径
                panelPaths := GetTCPathsViaAPI(hwnd)
                
                for panelPath in panelPaths {
                    LogInfo("检查路径: " panelPath.path " [" panelPath.panel "]")
                    if (panelPath.path && DirExist(panelPath.path)) {
                        paths.Push({
                            path: panelPath.path,
                            source: "totalcmd",
                            label: "TC (" panelPath.panel ")",
                            hwnd: hwnd,
                            panel: panelPath.panel,
                            timestamp: A_TickCount
                        })
                        LogInfo("添加 TC 路径: " panelPath.path)
                    } else {
                        LogInfo("路径无效或不存在: " panelPath.path)
                    }
                }
            } catch as innerErr {
                LogWarn("处理 TC 窗口失败: " innerErr.Message)
            }
        }
    } catch as err {
        LogWarn("Total Commander 路径收集失败: " err.Message)
    }

    LogInfo("Total Commander 路径收集完成: " paths.Length " 个面板")
    return paths
}

; 通过 TC 官方 API 获取双面板路径（不依赖标题栏设置、不依赖快捷键）
; 原理: SendMessage 1074 (WM_USER+74) 是 TC 的内部消息
;   wParam=17: 返回活动面板路径控件的 HWND
;   wParam=18: 返回非活动面板路径控件的 HWND
GetTCPathsViaAPI(hwnd) {
    paths := []
    
    try {
        ; 获取活动面板路径控件句柄
        activePathHwnd := SendMessage(1074, 17, , , "ahk_id " hwnd)
        LogInfo("TC 活动面板路径控件 HWND: " activePathHwnd)
        
        if (activePathHwnd && activePathHwnd > 0) {
            try {
                activePath := ControlGetText("ahk_id " activePathHwnd)
                ; TC 路径控件文本格式: "C:\path`r`n" 或 "C:\path>"
                activePath := RegExReplace(activePath, "[>\r\n]+$")
                activePath := Trim(activePath)
                LogInfo("TC 活动面板路径: '" activePath "'")
                
                if (activePath && RegExMatch(activePath, "^[A-Za-z]:")) {
                    paths.Push({path: activePath, panel: "active"})
                }
            } catch as err {
                LogWarn("读取活动面板路径失败: " err.Message)
            }
        }
        
        ; 获取非活动面板路径控件句柄
        inactivePathHwnd := SendMessage(1074, 18, , , "ahk_id " hwnd)
        LogInfo("TC 非活动面板路径控件 HWND: " inactivePathHwnd)
        
        if (inactivePathHwnd && inactivePathHwnd > 0) {
            try {
                inactivePath := ControlGetText("ahk_id " inactivePathHwnd)
                inactivePath := RegExReplace(inactivePath, "[>\r\n]+$")
                inactivePath := Trim(inactivePath)
                LogInfo("TC 非活动面板路径: '" inactivePath "'")
                
                if (inactivePath && RegExMatch(inactivePath, "^[A-Za-z]:")) {
                    ; 判断是左面板还是右面板
                    ; 如果活动面板是左面板，非活动就是右面板，反之亦然
                    ; 这里暂时标记为 inactive，跳转时再处理
                    panel := (paths.Length > 0 && paths[1].panel = "left") ? "right" : "left"
                    paths.Push({path: inactivePath, panel: panel})
                }
            } catch as err {
                LogWarn("读取非活动面板路径失败: " err.Message)
            }
        }
        
        ; 如果 API 方法失败，降级为 WinGetText 解析
        if (paths.Length = 0) {
            LogInfo("TC API 方法失败，尝试 WinGetText 解析...")
            return GetTCPathsViaWinGetText(hwnd)
        }
        
    } catch as err {
        LogWarn("TC API 路径获取失败: " err.Message)
        return GetTCPathsViaWinGetText(hwnd)
    }
    
    return paths
}

; 降级方案: 通过 WinGetText 获取 TC 窗口所有文本，解析路径
; TC 窗口文本中，路径行以 ">" 结尾
GetTCPathsViaWinGetText(hwnd) {
    paths := []
    
    try {
        ; 获取窗口所有文本（包括隐藏文本）
        oldSetting := A_DetectHiddenText
        DetectHiddenText(true)
        allText := WinGetText("ahk_id " hwnd)
        DetectHiddenText(oldSetting)
        
        LogInfo("TC WinGetText 文本长度: " StrLen(allText))
        
        ; 解析以 ">" 结尾的行（这些是路径行）
        for line in StrSplit(allText, "`n", "`r") {
            line := Trim(line)
            if (line && SubStr(line, -1) = ">") {
                ; 移除末尾的 ">"
                path := SubStr(line, 1, -1)
                path := Trim(path)
                LogInfo("WinGetText 解析到路径: '" path "'")
                
                if (path && RegExMatch(path, "^[A-Za-z]:")) {
                    panel := (paths.Length = 0) ? "left" : "right"
                    paths.Push({path: path, panel: panel})
                }
            }
        }
        
    } catch as err {
        LogWarn("WinGetText 路径获取失败: " err.Message)
    }
    
    return paths
}

; Total Commander 路径跳转
; 参数:
;   hwnd - TC 窗口句柄
;   targetPath - 目标路径
;   panel - 目标面板 ("left"/"right"/"active")
; 返回: 跳转成功返回 true，失败返回 false
; 方法: 通过 TC 命令行参数直接跳转，无需键盘模拟
NavigateTotalCmd(hwnd, targetPath, panel := "active") {
    LogInfo("TC 跳转: hwnd=" hwnd ", path=" targetPath ", panel=" panel)
    
    try {
        ; 方法1: 通过 TC 命令行参数跳转（最可靠）
        ; /O = 在已有实例中打开, /T = 在新标签中打开, /L = 左面板路径, /R = 右面板路径
        try {
            pid := WinGetPID("ahk_id " hwnd)
            if (pid) {
                ; 通过 WMI 获取 TC 可执行文件路径
                for process in ComObjGet("winmgmts:").ExecQuery("Select * From Win32_Process Where ProcessId = " pid) {
                    tcExe := process.ExecutablePath
                    break
                }
                
                if (tcExe && FileExist(tcExe)) {
                    LogInfo("找到 TC 可执行文件: " tcExe)
                    ; 构建命令行参数
                    if (panel = "left") {
                        Run('"' tcExe '" /O /T /L="' targetPath '"', , "Hide")
                    } else if (panel = "right") {
                        Run('"' tcExe '" /O /T /R="' targetPath '"', , "Hide")
                    } else {
                        ; 活动面板：使用左面板参数
                        Run('"' tcExe '" /O /T /L="' targetPath '"', , "Hide")
                    }
                    LogInfo("TC 跳转成功 (命令行): " targetPath)
                    return true
                }
            }
        } catch as err {
            LogWarn("TC 命令行跳转失败: " err.Message)
        }
        
        ; 方法2: 降级为键盘模拟（使用 ControlSend 直接发送到 TC 窗口）
        LogInfo("降级为键盘模拟跳转...")
        savedClipboard := SaveClipboard()
        
        ; 激活 TC 窗口
        WinActivate("ahk_id " hwnd)
        if (!WinWaitActive("ahk_id " hwnd, , 2000)) {
            LogError("无法激活 Total Commander 窗口")
            RestoreClipboard(savedClipboard)
            return false
        }
        Sleep(200)
        
        ; 如果指定了面板，先切换焦点
        if (panel = "left" || panel = "right") {
            Send("{Tab}")
            Sleep(150)
        }

        ; Ctrl+D 打开"改变文件夹"对话框
        Send("^d")
        Sleep(300)
        
        ; 输入路径
        A_Clipboard := targetPath
        if (!ClipWait(1)) {
            LogWarn("剪贴板写入超时")
        }
        Sleep(100)
        Send("^v")
        Sleep(200)
        
        ; 确认
        Send("{Enter}")
        Sleep(300)

        LogInfo("TC 跳转成功 (键盘): " targetPath)
        Sleep(200)
        RestoreClipboard(savedClipboard)
        return true
    } catch as err {
        LogError("Total Commander 跳转失败: " err.Message)
        return false
    }
}
