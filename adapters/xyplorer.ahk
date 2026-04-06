; ============================================================
; XYplorer 适配器 — FolderJump
; 负责获取 XYplorer 的路径 (支持单/双面板)
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\utils.ahk"

CollectXYplorerPaths() {
    paths := []
    
    ; 寻找所有的 ThunderRT6FormDC 窗口
    try {
        windows := WinGetList("ahk_class ThunderRT6FormDC")
    } catch as err {
        LogWarn("Failed to enumerate XYplorer windows: " err.Message)
        return paths
    }

    for hwnd in windows {
        try {
            ; 检查进程名，因为 ThunderRT6FormDC 可能是其他基于 VB6 的应用
            processName := WinGetProcessName("ahk_id " hwnd)
            if (!InStr(StrLower(processName), "xyplorer"))
                continue

            xyPaths := CollectPathsFromXYplorerInstance(hwnd)
            for entry in xyPaths {
                paths.Push(entry)
            }
        } catch as err {
            LogWarn("Failed to process XYplorer window " hwnd ": " err.Message)
        }
    }

    return paths
}

CollectPathsFromXYplorerInstance(hwnd) {
    paths := []
    tempFile := A_Temp "\folderjump_xy_" hwnd "_" A_TickCount ".txt"
    
    try {
        if (FileExist(tempFile))
            FileDelete(tempFile)
    }
    
    ; XYplorer script: 
    ; $dp 判断双面板 (基于命令状态 #800)
    ; $pane 获取当前活动面板 (1或2)
    ; $p_i 获取非活动面板当前标签路径 (仅在双窗格开启时，使用官方 'i' 参数)
    xyScript := '::$dp = get("#800"); $pane = get("pane"); $p_i = ""; if ($dp == 1) { $p_i = tab("get", "path", , "i"); } writefile("' tempFile '", <curpath> . "<crlf>" . $dp . "<crlf>" . $pane . "<crlf>" . $p_i, "o", "utf8");'
    
    if (!SendXYplorerScript(hwnd, xyScript)) {
        LogWarn("Failed to send WM_COPYDATA to XYplorer window " hwnd)
        return paths
    }
    
    ; 等待文件生成，最多等 1000 毫秒
    Loop 20 {
        if (FileExist(tempFile))
            break
        Sleep(50)
    }
    
    if (!FileExist(tempFile)) {
        LogWarn("XYplorer did not generate the temp file in time: " tempFile)
        return paths
    }
    
    ; 读取并解析临时文件
    try {
        content := FileRead(tempFile, "UTF-8")
        FileDelete(tempFile)
        
        lines := StrSplit(Trim(content, " `t`r`n"), "`n", "`r")
        if (lines.Length < 1 || lines[1] = "")
            return paths

        activePath := NormalizePathString(lines[1])
        isDualPane := (lines.Length >= 2 && lines[2] = "1")
        activePaneIndex := (lines.Length >= 3 ? lines[3] : "1")
        inactivePath := (lines.Length >= 4 ? NormalizePathString(lines[4]) : "")
        
        if (isDualPane && inactivePath) {
            path1 := (activePaneIndex = "1") ? activePath : inactivePath
            path2 := (activePaneIndex = "2") ? activePath : inactivePath
            
            if (path1 && DirExist(path1)) {
                label1 := (activePaneIndex = "1") ? "XYplorer (窗格 1/活动)" : "XYplorer (窗格 1)"
                paths.Push({
                    path: path1,
                    source: "xyplorer",
                    label: label1,
                    hwnd: hwnd,
                    panel: "1",
                    timestamp: (activePaneIndex = "1") ? A_TickCount : A_TickCount - 1
                })
            }
            
            if (path2 && DirExist(path2)) {
                label2 := (activePaneIndex = "2") ? "XYplorer (窗格 2/活动)" : "XYplorer (窗格 2)"
                paths.Push({
                    path: path2,
                    source: "xyplorer",
                    label: label2,
                    hwnd: hwnd,
                    panel: "2",
                    timestamp: (activePaneIndex = "2") ? A_TickCount : A_TickCount - 1
                })
            }
        } else {
            ; 单面板状态
            if (activePath && DirExist(activePath)) {
                paths.Push({
                    path: activePath,
                    source: "xyplorer",
                    label: "XYplorer",
                    hwnd: hwnd,
                    timestamp: A_TickCount
                })
            }
        }
    } catch as err {
        LogWarn("Failed to read XYplorer temp file: " err.Message)
    }

    LogDebug("XYplorer 路径收集: hwnd=" hwnd ", 数量=" paths.Length)
    return paths
}

SendXYplorerScript(hwnd, script) {
    size := StrLen(script) * 2  ; UTF-16 size
    
    COPYDATA := Buffer(A_PtrSize * 3)
    
    ; dwData = 4194305 (0x400001, 用于识别 XYplorer 消息)
    NumPut("Ptr", 4194305, COPYDATA, 0)
    ; cbData
    NumPut("UInt", size, COPYDATA, A_PtrSize)
    ; lpData
    NumPut("Ptr", StrPtr(script), COPYDATA, A_PtrSize * 2)
    
    ; 0x4A 是 WM_COPYDATA
    try {
        SendMessage(0x004A, 0, COPYDATA, , "ahk_id " hwnd)
        return true
    } catch as err {
        LogWarn("SendMessage to XYplorer failed: " err.Message)
        return false
    }
}
