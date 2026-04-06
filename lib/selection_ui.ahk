; ============================================================
; Selection UI — FolderJump
; 浮动菜单 GUI（键盘导航、自动关闭）
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\path_switcher.ahk"

; 主题配色
g_Themes := {
    dark: {
        bg: "1E1E2E",
        text: "FFFFFF",
        hint: "888888",
        border: "333333"
    },
    light: {
        bg: "FFFFFF",
        text: "333333",
        hint: "999999",
        border: "CCCCCC"
    }
}

; 智能截断长路径
; 参数:
;   fullPath - 完整路径
;   maxLength - 显示的最大字符数（默认 60）
; 返回:
;   截断后的路径（保留末尾文件夹和开头部分）
TruncatePathForDisplay(fullPath, maxLength := 60) {
    if (StrLen(fullPath) <= maxLength)
        return fullPath
    
    ; 获取末尾文件夹名称
    lastBackslash := InStr(fullPath, "\", , 0)
    folderName := SubStr(fullPath, lastBackslash + 1)
    
    ; 如果末尾文件夹本身已经接近最大长度，直接返回
    if (StrLen(folderName) >= maxLength - 5)
        return "..." folderName
    
    ; 计算剩余空间用于显示开头路径
    remainingLength := maxLength - StrLen(folderName) - 4  ; 4 是"..."的长度
    prefixPath := SubStr(fullPath, 1, remainingLength)
    
    return prefixPath "..." folderName
}

; 显示路径选择器
; 参数:
;   context - 当前窗口类型（"explorer", "dialog", "totalcmd", "dopus"）
;   activeHwnd - 前景窗口句柄，用于定位弹出位置
; 行为:
;   创建浮动 ListBox 菜单，显示所有已打开的文件夹路径
;   支持键盘导航（↑↓选择、Enter确认、Esc取消）
;   自动关闭（失焦、超时）
;   用户选择后调用 ExecutePathSwitch 执行跳转
ShowPathSelector(context, activeHwnd) {
    global g_PathCache, g_Config, g_CurrentGui

    if (g_PathCache.Length = 0) {
        TrayTip("FolderJump", "没有打开的文件夹窗口", 2000)
        return
    }

    ; 如果只有一个可选路径，直接跳转，不再显示选择菜单
    if (g_PathCache.Length = 1) {
        entry := g_PathCache[1]
        LogInfo("仅存在一个可选路径，直接跳转: " entry.path " [" entry.label "]")
        ExecutePathSwitch(entry, activeHwnd)
        return
    }

    ; 获取前景窗口位置
    try {
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " activeHwnd)
    } catch {
        ; 如果获取失败，使用屏幕中心
        wx := A_ScreenWidth // 2 - 200
        wy := A_ScreenHeight // 2 - 150
        ww := 400
        wh := 300
    }

    ; 选择主题
    themeName := g_Config.theme
    theme := g_Themes.HasOwnProp(themeName) ? g_Themes.%themeName% : g_Themes.dark

    ; 创建 GUI
    pathGui := Gui("+AlwaysOnTop +ToolWindow -Caption +Border")
    pathGui.BackColor := theme.bg

    ; 标题栏
    titleColor := theme.text
    pathGui.Add("Text", "x5 y5 w390 Center c" titleColor, "FolderJump - 选择目标文件夹")

    ; 构建列表项（使用截断路径）
    ; 保存原始路径数据供后续使用
    items := []
    displayPaths := []
    maxItems := g_Config.max_items
    count := Min(g_PathCache.Length, maxItems)
    Loop count {
        entry := g_PathCache[A_Index]
        ; 截断路径用于显示（最多60字符）
        displayPath := TruncatePathForDisplay(entry.path, 60)
        if (g_Config.show_source_label)
            displayPath := displayPath "  [" entry.label "]"
        items.Push(displayPath)
        displayPaths.Push(entry.path)  ; 保存完整路径
    }

    ; 获取 DPI 缩放因子
    ; A_Dpi 变量在 AHK v2 中反映系统 DPI 设置（通常 100%, 125%, 150% 等）
    ; 如果未定义或低于 100，使用默认值 100
    dpiScale := IsSet(A_ScreenDPI) ? (A_ScreenDPI / 96) : 1
    
    ; 计算每项高度（基于 DPI）
    itemHeight := Round(25 * dpiScale)
    maxListHeight := Round(300 * dpiScale)
    previewHeight := Round(50 * dpiScale)  ; 底部预览区域高度
    headerHeight := Round(80 * dpiScale)  ; 标题 + 提示高度

    ; 路径列表（ListBox）
    listHeight := Min(count * itemHeight, maxListHeight)
    listBox := pathGui.Add("ListBox", "x5 y30 w390 h" listHeight " vPathList", items)
    listBox.Choose(1)

    ; 完整路径预览区域
    textColor := theme.text
    previewBox := pathGui.Add("Text", "x5 y+" 5 " w390 h30 c" textColor, displayPaths[1])
    previewBox.Value := displayPaths[1]

    ; 底部提示
    hintColor := theme.hint
    pathGui.Add("Text", "x5 y+" 3 " w390 Center c" hintColor, "↑↓ 选择  |  Enter 确认  |  Esc 取消")

    ; 计算弹出位置
    popupX := wx
    popupY := wy + wh + 5

    ; 确保不超出屏幕底部
    ; totalHeight 需要包含：标题 + listBox + 预览区 + 提示 + 间距
    totalHeight := listHeight + headerHeight + 30 + 6
    if (popupY + totalHeight > A_ScreenHeight) {
        popupY := wy - totalHeight - 10
        if (popupY < 0)
            popupY := 10
    }

    ; 显示窗口
    pathGui.Show("x" popupX " y" popupY)

    ; 保存 GUI 引用和原始活动窗口句柄（用于后续跳转）
    ; 同时保存完整路径列表用于预览
    g_CurrentGui := pathGui
    pathGui.targetHwnd := activeHwnd
    pathGui.displayPaths := displayPaths
    pathGui.previewBox := previewBox

    ; 绑定键盘事件
    pathGui.OnEvent("Escape", GuiEscape)

    ; 超时自动关闭
    timeout := g_Config.auto_close_timeout * 1000
    autoCloseFn := GuiAutoClose.Bind(pathGui)
    SetTimer(autoCloseFn, -timeout)
    pathGui.autoCloseTimer := autoCloseFn

    ; 失焦检测定时器（每 200ms 检查一次）
    focusCheckFn := CheckFocusClose.Bind(pathGui)
    SetTimer(focusCheckFn, 200)
    pathGui.focusCheckTimer := focusCheckFn

    ; 设置 ListBox 键盘事件
    listBox.OnEvent("DoubleClick", ListBoxConfirm)
    listBox.OnEvent("Change", ListBoxChange)

    ; 使用 AHK v2 的 InputHook 捕获 Enter 键
    enterHook := InputHook("V")
    enterHook.KeyOpt("{Enter}", "N")
    enterHook.OnKeyDown := ListBoxEnterPressed.Bind(listBox)
    enterHook.Start()

    ; 保存引用以便清理
    pathGui.enterHook := enterHook
    pathGui.selectedIndex := 0
}

; ListBox 确认事件（双击时触发）
; 执行路径跳转并关闭 GUI
ListBoxConfirm(GuiCtrlObj, *) {
    global g_CurrentGui, g_PathCache
    selectedIndex := GuiCtrlObj.Value
    if (selectedIndex > 0 && selectedIndex <= g_PathCache.Length) {
        entry := g_PathCache[selectedIndex]
        LogInfo("用户选择路径(双击): " entry.path " [" entry.label "]")
        ; 使用保存的目标窗口句柄，而不是当前活动窗口（因为当前是 FolderJump GUI）
        targetHwnd := g_CurrentGui.HasOwnProp("targetHwnd") ? g_CurrentGui.targetHwnd : 0
        ExecutePathSwitch(entry, targetHwnd)
    }
    CleanupGui(g_CurrentGui)
}

; ListBox 变更事件（用于键盘导航时记录当前选择）
; 保存当前选择到 GUI 对象以便 Enter 键处理，同时更新底部预览
ListBoxChange(GuiCtrlObj, *) {
    global g_CurrentGui
    if (IsSet(g_CurrentGui) && g_CurrentGui) {
        selectedIndex := GuiCtrlObj.Value
        g_CurrentGui.selectedIndex := selectedIndex
        
        ; 更新底部完整路径预览
        if (selectedIndex > 0 && 
            g_CurrentGui.HasOwnProp("displayPaths") && 
            selectedIndex <= g_CurrentGui.displayPaths.Length &&
            g_CurrentGui.HasOwnProp("previewBox")) {
            ; 显示完整路径
            fullPath := g_CurrentGui.displayPaths[selectedIndex]
            g_CurrentGui.previewBox.Value := fullPath
        }
    }
}

; Enter 键确认（通过 InputHook 捕获）
; 执行路径跳转并关闭 GUI
ListBoxEnterPressed(listBox, hook, vk, sc, *) {
    global g_CurrentGui, g_PathCache
    if (vk = 13) {
        try {
            selectedIndex := listBox.Value
            if (selectedIndex > 0 && selectedIndex <= g_PathCache.Length) {
                entry := g_PathCache[selectedIndex]
                LogInfo("用户选择路径(Enter): " entry.path " [" entry.label "]")
                ; 使用保存的目标窗口句柄，而不是当前活动窗口（因为当前是 FolderJump GUI）
                targetHwnd := g_CurrentGui.HasOwnProp("targetHwnd") ? g_CurrentGui.targetHwnd : 0
                ExecutePathSwitch(entry, targetHwnd)
                CleanupGui(g_CurrentGui)
            }
        }
    }
}

; Escape 键关闭（通过 gui.OnEvent("Escape") 绑定）
GuiEscape(*) {
    global g_CurrentGui
    LogDebug("用户按 Escape 取消选择")
    CleanupGui(g_CurrentGui)
}

; 失焦检测定时器回调
CheckFocusClose(pathGui) {
    global g_CurrentGui
    try {
        ; 检查 GUI 是否还存在
        if (!WinExist("ahk_id " pathGui.Hwnd)) {
            SetTimer(pathGui.focusCheckTimer, 0)
            return
        }
        ; 检查 GUI 是否失去焦点（不是活动窗口）
        if (WinActive("ahk_id " pathGui.Hwnd) != pathGui.Hwnd) {
            LogDebug("GUI 失焦，自动关闭")
            SetTimer(pathGui.focusCheckTimer, 0)
            CleanupGui(g_CurrentGui)
        }
    }
}

; 超时关闭（通过 SetTimer 一次性触发）
GuiAutoClose(pathGui) {
    global g_CurrentGui
    LogDebug("GUI 超时，自动关闭")
    CleanupGui(g_CurrentGui)
}

; 清理 GUI 资源（停止定时器、InputHook，销毁 GUI）
; 在所有关闭路径中统一调用，确保资源正确释放
CleanupGui(pathGui) {
    global g_CurrentGui
    if (!IsSet(g_CurrentGui) || !g_CurrentGui)
        return
    ; 停止超时定时器（如果存在）
    if (IsSet(pathGui) && pathGui && pathGui.HasOwnProp("autoCloseTimer")) {
        try SetTimer(pathGui.autoCloseTimer, 0)
    }
    ; 停止焦点检测定时器（如果存在）
    if (IsSet(pathGui) && pathGui && pathGui.HasOwnProp("focusCheckTimer")) {
        try SetTimer(pathGui.focusCheckTimer, 0)
    }
    ; 停止 InputHook（如果存在）
    if (IsSet(pathGui) && pathGui && pathGui.HasOwnProp("enterHook")) {
        try pathGui.enterHook.Stop()
    }
    ; 销毁 GUI
    try pathGui.Destroy()
    ; 清除全局引用
    g_CurrentGui := ""
}
