; ============================================================
; Utils — FolderJump
; 通用工具函数
; ============================================================

; 保存剪贴板内容（完整内容，包括文件/图片）
; 返回: 剪贴板备份对象
SaveClipboard() {
    saved := ClipboardAll()
    return saved
}

; 恢复剪贴板内容
; 参数:
;   saved - 之前保存的剪贴板备份对象
RestoreClipboard(saved) {
    A_Clipboard := saved
}

; 获取对话框或常用控件的类名（安全封装）
GetControlClassSafe(control, hwnd) {
    try {
        return ControlGetClassNN(control, "ahk_id " hwnd)
    } catch {
        return control
    }
}

; 获取对话框或常用控件的文本（安全封装）
GetControlTextSafe(control, hwnd) {
    try {
        return ControlGetText(control, "ahk_id " hwnd)
    } catch {
        return ""
    }
}

; 归一化路径（转换为小写、统一斜杠、去除末尾斜杠）
NormalizePathString(pathStr) {
    pathStr := StrReplace(pathStr, "/", "\")
    pathStr := Trim(pathStr, " `t`r`n")
    if (StrLen(pathStr) > 3 && SubStr(pathStr, -1) = "\")
        pathStr := SubStr(pathStr, 1, -1)
    return StrLower(pathStr)
}