; ============================================================
; Selection UI — FolderJump
; 浮动菜单 GUI（键盘导航、自动关闭）
; ============================================================

#IncludeOnce "%A_ScriptDir%\lib\log_manager.ahk"
#IncludeOnce "%A_ScriptDir%\lib\path_switcher.ahk"

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
    theme := g_Themes.HasOwnProp(themeName) ? g_Themes[themeName] : g_Themes.dark

    ; 创建 GUI
    gui := Gui("+AlwaysOnTop +ToolWindow -Caption +Border")
    gui.BackColor := theme.bg

    ; 标题栏
    titleColor := theme.text
    gui.Add("Text", "x5 y5 w390 Center c" titleColor, "FolderJump - 选择目标文件夹")

    ; 构建列表项
    items := []
    maxItems := g_Config.max_items
    count := Min(g_PathCache.Length, maxItems)
    Loop count {
        entry := g_PathCache[A_Index]
        if (g_Config.show_source_label)
            items.Push(entry.path "  [" entry.label "]")
        else
            items.Push(entry.path)
    }

    ; 获取 DPI 缩放因子
    ; A_Dpi 变量在 AHK v2 中反映系统 DPI 设置（通常 100%, 125%, 150% 等）
    ; 如果未定义或低于 100，使用默认值 100
    dpiScale := IsSet(A_ScreenDPI) ? (A_ScreenDPI / 96) : 1
    
    ; 计算每项高度（基于 DPI）
    itemHeight := Round(25 * dpiScale)
    maxListHeight := Round(300 * dpiScale)
    headerHeight := Round(80 * dpiScale)  ; 标题 + 底部提示高度

    ; 路径列表（ListBox）
    listHeight := Min(count * itemHeight, maxListHeight)
    listBox := gui.Add("ListBox", "x5 y30 w390 h" listHeight " vPathList", items)
    listBox.Choose(1)

    ; 底部提示
    hintColor := theme.hint
    gui.Add("Text", "x5 y+" 5 " w390 Center c" hintColor, "↑↓ 选择  |  Enter 确认  |  Esc 取消")

    ; 计算弹出位置
    popupX := wx
    popupY := wy + wh + 5

    ; 确保不超出屏幕底部
    totalHeight := listHeight + headerHeight
    if (popupY + totalHeight > A_ScreenHeight) {
        popupY := wy - totalHeight - 10
        if (popupY < 0)
            popupY := 10
    }

    ; 显示窗口
    gui.Show("x" popupX " y" popupY)

    ; 保存 GUI 引用
    g_CurrentGui := gui

    ; 绑定键盘事件
    gui.OnEvent("Escape", GuiEscape)

    ; 失焦自动关闭
    gui.OnEvent("LoseFocus", GuiLoseFocus)

    ; 超时自动关闭
    timeout := g_Config.auto_close_timeout * 1000
    autoCloseFn := GuiAutoClose.Bind(gui)
    SetTimer(autoCloseFn, -timeout)
    gui.autoCloseTimer := autoCloseFn

    ; 设置 ListBox 键盘事件
    listBox.OnEvent("DoubleClick", ListBoxConfirm)
    listBox.OnEvent("Change", ListBoxChange)

    ; 使用 AHK v2 的 InputHook 捕获 Enter 键
    enterHook := InputHook("V")
    enterHook.OnEnter := ListBoxEnterPressed.Bind(listBox)
    enterHook.Start()

    ; 保存引用以便清理
    gui.enterHook := enterHook
    gui.selectedIndex := 0
}

; ListBox 确认事件（双击时触发）
; 执行路径跳转并关闭 GUI
ListBoxConfirm(GuiCtrlObj, *) {
    global g_CurrentGui, g_PathCache
    selectedIndex := GuiCtrlObj.Choice
    if (selectedIndex > 0 && selectedIndex <= g_PathCache.Length) {
        entry := g_PathCache[selectedIndex]
        LogInfo("用户选择路径(双击): " entry.path " [" entry.label "]")
        ExecutePathSwitch(entry)
    }
    CleanupGui(g_CurrentGui)
}

; ListBox 变更事件（用于键盘导航时记录当前选择）
; 保存当前选择到 GUI 对象以便 Enter 键处理
ListBoxChange(GuiCtrlObj, *) {
    global g_CurrentGui
    if (IsSet(g_CurrentGui) && g_CurrentGui)
        g_CurrentGui.selectedIndex := GuiCtrlObj.Choice
}

; Enter 键确认（通过 InputHook 捕获）
; 执行路径跳转并关闭 GUI
ListBoxEnterPressed(listBox, *) {
    global g_CurrentGui, g_PathCache
    try {
        selectedIndex := listBox.Choice
        if (selectedIndex > 0 && selectedIndex <= g_PathCache.Length) {
            entry := g_PathCache[selectedIndex]
            LogInfo("用户选择路径(Enter): " entry.path " [" entry.label "]")
            ExecutePathSwitch(entry)
            CleanupGui(g_CurrentGui)
        }
    }
}

; Escape 键关闭（通过 gui.OnEvent("Escape") 绑定）
GuiEscape(*) {
    global g_CurrentGui
    LogDebug("用户按 Escape 取消选择")
    CleanupGui(g_CurrentGui)
}

; 失焦关闭（通过 gui.OnEvent("LoseFocus") 绑定）
GuiLoseFocus(*) {
    global g_CurrentGui
    LogDebug("GUI 失焦，自动关闭")
    CleanupGui(g_CurrentGui)
}

; 超时关闭（通过 SetTimer 一次性触发）
GuiAutoClose(gui) {
    global g_CurrentGui
    LogDebug("GUI 超时，自动关闭")
    try gui.Destroy()
}

; 清理 GUI 资源（停止定时器、InputHook，销毁 GUI）
; 在所有关闭路径中统一调用，确保资源正确释放
CleanupGui(gui) {
    global g_CurrentGui
    ; 停止超时定时器（如果存在）
    if (IsSet(gui) && gui && gui.HasOwnProp("autoCloseTimer")) {
        try SetTimer(gui.autoCloseTimer, 0)
    }
    ; 停止 InputHook（如果存在）
    if (IsSet(gui) && gui && gui.HasOwnProp("enterHook")) {
        try gui.enterHook.Stop()
    }
    ; 销毁 GUI
    try gui.Destroy()
    ; 清除全局引用
    g_CurrentGui := ""
}
