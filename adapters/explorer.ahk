; ============================================================
; Explorer Adapter — FolderJump
; Windows Explorer 路径获取与跳转适配器
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\utils.ahk"

; 收集所有 Explorer 窗口路径
CollectExplorerPaths() {
    paths := []
    try {
        shell := ComObject("Shell.Application")
    } catch as err {
        LogError("Shell.Application COM 对象获取失败: " err.Message)
        return paths
    }

    try {
        for window in shell.Windows {
        try {
            ; 跳过非 Explorer 窗口（如 IE）
            if (window.LocationName = "")
                continue

            ; 获取文件夹路径
            try {
                folder := window.Document.Folder
            } catch {
                folder := ""
            }

            path := ""
            if (IsSet(folder) && folder)
                try path := folder.Self.Path
                catch
                    path := ""

            if (!path || path = "")
                path := GetExplorerPathFromHwnd(window.hwnd)

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
    } catch as err {
        LogWarn("Shell.Windows 枚举中断: " err.Message)
    }

    LogDebug("Explorer 路径收集: " paths.Length " 个窗口")
    return paths
}

GetExplorerPathFromHwnd(hwnd) {
    try {
        shell := ComObject("Shell.Application")
        for window in shell.Windows {
            try {
                if (window.hwnd = hwnd) {
                    try {
                        path := window.Document.Folder.Self.Path
                        if (path && path != "")
                            return path
                    } catch {
                        continue
                    }
                }
            } catch {
                continue
            }
        }
    } catch {
    }

    return ""
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


