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