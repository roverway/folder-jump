; ============================================================
; Selection UI — FolderJump
; 浮动菜单 GUI（键盘导航、自动关闭、按来源分组显示）
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

; 来源名称映射（source 字符串 → 用户可读的文件管理器完整名称）
GetSourceDisplayName(source) {
    names := Map(
        "explorer", "Windows Explorer",
        "totalcmd", "Total Commander",
        "dopus",    "Directory Opus",
        "xyplorer", "XYplorer"
    )
    return names.Has(source) ? names[source] : source
}

; 智能截断长路径
; 参数:
;   fullPath  - 完整路径
;   maxLength - 显示的最大字符数（默认 55）
; 返回:
;   截断后的路径（保留末尾文件夹和开头部分）
TruncatePathForDisplay(fullPath, maxLength := 55) {
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

; 按来源分组，构建供 ListBox 显示的并行数组集合
; 返回:
;   result.items[]         — ListBox 显示字符串（含分组标题行和路径行）
;   result.selectableMap[] — 与 items 等长；分组标题行值为 -1，路径行值为 g_PathCache 中的 1-based 索引
;   result.fullPaths[]     — 与 items 等长；分组标题行值为 ""，路径行值为完整路径
;   result.firstSelectable — 第一个可选路径行在 items 中的 1-based 索引
BuildGroupedItems(pathCache, maxItems) {
    ; 按首次出现顺序收集各来源分组
    groups     := Map()   ; source → 该来源在 pathCache 中的索引数组
    groupOrder := []      ; 来源首次出现顺序

    count := Min(pathCache.Length, maxItems)
    Loop count {
        entry := pathCache[A_Index]
        src   := entry.source
        if (!groups.Has(src)) {
            groups[src] := []
            groupOrder.Push(src)
        }
        groups[src].Push(A_Index)
    }

    ; 构建并行数组
    items         := []
    selectableMap := []
    fullPaths     := []
    firstSelectable := 0

    for src in groupOrder {
        indices := groups[src]
        srcName := GetSourceDisplayName(src)

        ; 插入分组标题行（格式: "  ── Windows Explorer (2)"）
        header := "  ── " srcName " (" indices.Length ")"
        items.Push(header)
        selectableMap.Push(-1)
        fullPaths.Push("")

        ; 插入各路径行（4 空格缩进，与标题行形成层级感）
        for cacheIdx in indices {
            entry       := pathCache[cacheIdx]
            displayPath := "    " TruncatePathForDisplay(entry.path, 55)
            items.Push(displayPath)
            selectableMap.Push(cacheIdx)
            fullPaths.Push(entry.path)
            ; 记录第一个可选行的位置
            if (firstSelectable = 0)
                firstSelectable := items.Length
        }
    }

    return {items: items, selectableMap: selectableMap, fullPaths: fullPaths, firstSelectable: firstSelectable}
}

; 显示路径选择器
; 参数:
;   context    - 当前窗口类型（"explorer", "dialog", "totalcmd", "dopus", "xyplorer"）
;   activeHwnd - 前景窗口句柄，用于定位弹出位置
; 行为:
;   创建 500px 宽的浮动 ListBox 菜单，按来源分组显示所有已打开的文件夹路径
;   支持键盘导航（↑↓ 选择并自动跳过分组标题行、Enter 确认、Esc 取消）
;   自动关闭（失焦、超时）；用户选择后调用 ExecutePathSwitch 执行跳转
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
        ; 获取失败时使用屏幕中心
        wx := A_ScreenWidth  // 2 - 250
        wy := A_ScreenHeight // 2 - 150
        ww := 500
        wh := 300
    }

    ; 选择主题
    themeName := g_Config.theme
    theme := g_Themes.HasOwnProp(themeName) ? g_Themes.%themeName% : g_Themes.dark

    ; 创建 GUI（固定宽度 500px）
    pathGui := Gui("+AlwaysOnTop +ToolWindow -Caption +Border")
    pathGui.BackColor := theme.bg
    pathGui.SetFont("s11 q5", "Segoe UI")  ; 11pt，ClearType 渲染，可读性最佳

    ; 标题栏
    titleColor := theme.text
    pathGui.Add("Text", "x5 y5 w490 Center c" titleColor, "FolderJump - 选择目标文件夹")

    ; 按来源分组构建显示列表（含分组标题行）
    grouped         := BuildGroupedItems(g_PathCache, g_Config.max_items)
    items           := grouped.items
    selectableMap   := grouped.selectableMap
    fullPaths       := grouped.fullPaths
    firstSelectable := grouped.firstSelectable

    ; 根据 DPI 计算每行高度，11pt 字体约 27px
    dpiScale      := IsSet(A_ScreenDPI) ? (A_ScreenDPI / 96) : 1
    itemHeight    := Round(27 * dpiScale)
    maxListHeight := Round(400 * dpiScale)

    ; 路径列表
    listHeight := Min(items.Length * itemHeight, maxListHeight)
    listBox := pathGui.Add("ListBox", "x5 y30 w490 h" listHeight " vPathList", items)

    ; 选中第一个可选路径行（跳过最开头的分组标题行）
    if (firstSelectable > 0)
        listBox.Choose(firstSelectable)

    ; 完整路径预览区域（显示当前选中行的未截断路径）
    textColor   := theme.text
    initPreview := (firstSelectable > 0) ? fullPaths[firstSelectable] : ""
    previewBox  := pathGui.Add("Text", "x5 y+" 5 " w490 h20 c" textColor, initPreview)
    previewBox.Value := initPreview

    ; 底部操作提示
    hintColor := theme.hint
    pathGui.Add("Text", "x5 y+" 3 " w490 Center c" hintColor, "↑↓ 选择  |  Enter 确认  |  Esc 取消")

    ; 计算弹出位置（优先紧贴活动窗口正下方）
    popupX      := wx
    popupY      := wy + wh + 5
    totalHeight := listHeight + 80 + 6  ; 列表 + 标题 + 预览 + 提示 + 间距

    ; 防止超出屏幕底部
    if (popupY + totalHeight > A_ScreenHeight) {
        popupY := wy - totalHeight - 10
        if (popupY < 0)
            popupY := 10
    }
    ; 防止超出屏幕右侧
    if (popupX + 500 > A_ScreenWidth)
        popupX := A_ScreenWidth - 510

    ; 显示窗口
    pathGui.Show("x" popupX " y" popupY)

    ; 保存 GUI 引用和辅助数据（供事件处理函数使用）
    g_CurrentGui              := pathGui
    pathGui.targetHwnd        := activeHwnd
    pathGui.selectableMap     := selectableMap
    pathGui.fullPaths         := fullPaths
    pathGui.previewBox        := previewBox
    pathGui.lastValidIndex    := firstSelectable  ; 最近一次落在可选行的 displayItems 索引
    pathGui.selectedIndex     := firstSelectable

    ; 绑定事件
    pathGui.OnEvent("Escape", GuiEscape)
    listBox.OnEvent("DoubleClick", ListBoxConfirm)
    listBox.OnEvent("Change", ListBoxChange)

    ; 超时自动关闭
    timeout     := g_Config.auto_close_timeout * 1000
    autoCloseFn := GuiAutoClose.Bind(pathGui)
    SetTimer(autoCloseFn, -timeout)
    pathGui.autoCloseTimer := autoCloseFn

    ; 失焦检测定时器（每 200ms 检查一次）
    focusCheckFn := CheckFocusClose.Bind(pathGui)
    SetTimer(focusCheckFn, 200)
    pathGui.focusCheckTimer := focusCheckFn

    ; 使用 InputHook 捕获 Enter 键，防止原始按键泄漏到目标窗口
    enterHook := InputHook("V")
    enterHook.KeyOpt("{Enter}", "NS")  ; N=Notify, S=Suppress
    enterHook.OnKeyDown := ListBoxEnterPressed.Bind(listBox)
    enterHook.Start()
    pathGui.enterHook := enterHook
}

; ListBox 确认事件（双击时触发）
; 通过 selectableMap 还原真实 g_PathCache 索引，支持分组标题行存在时的正确跳转
ListBoxConfirm(GuiCtrlObj, *) {
    global g_CurrentGui, g_PathCache
    selectedIndex := GuiCtrlObj.Value
    if (selectedIndex > 0 && g_CurrentGui.HasOwnProp("selectableMap")) {
        cacheIdx := g_CurrentGui.selectableMap[selectedIndex]
        ; 分组标题行的 cacheIdx 为 -1，需跳过
        if (cacheIdx > 0 && cacheIdx <= g_PathCache.Length) {
            entry      := g_PathCache[cacheIdx]
            targetHwnd := g_CurrentGui.HasOwnProp("targetHwnd") ? g_CurrentGui.targetHwnd : 0
            LogInfo("用户选择路径(双击): " entry.path " [" entry.label "]")
            CleanupGui(g_CurrentGui)
            ExecutePathSwitch(entry, targetHwnd)
            return
        }
    }
    CleanupGui(g_CurrentGui)
}

; ListBox 变更事件（键盘 ↑↓ 导航时触发）
; 自动跳过分组标题行，同时更新底部完整路径预览
ListBoxChange(GuiCtrlObj, *) {
    global g_CurrentGui
    if (!IsSet(g_CurrentGui) || !g_CurrentGui)
        return

    selectedIndex := GuiCtrlObj.Value
    if (selectedIndex <= 0)
        return

    selectableMap := g_CurrentGui.selectableMap

    ; 当前选中的是分组标题行（selectableMap 值为 -1），需要自动跳转到相邻的可选行
    if (selectableMap[selectedIndex] = -1) {
        lastValid := g_CurrentGui.lastValidIndex

        if (selectedIndex > lastValid) {
            ; 用户向下移动：找当前位置之后最近的可选行
            nextIdx := selectedIndex + 1
            while (nextIdx <= selectableMap.Length && selectableMap[nextIdx] = -1)
                nextIdx++
            GuiCtrlObj.Choose(nextIdx <= selectableMap.Length ? nextIdx : lastValid)
        } else {
            ; 用户向上移动：找当前位置之前最近的可选行
            prevIdx := selectedIndex - 1
            while (prevIdx >= 1 && selectableMap[prevIdx] = -1)
                prevIdx--
            GuiCtrlObj.Choose(prevIdx >= 1 ? prevIdx : lastValid)
        }
        return  ; Choose() 会再次触发 Change 事件，由下方正常逻辑处理
    }

    ; 正常可选行：更新状态和底部完整路径预览
    g_CurrentGui.lastValidIndex := selectedIndex
    g_CurrentGui.selectedIndex  := selectedIndex

    if (g_CurrentGui.HasOwnProp("fullPaths") &&
        g_CurrentGui.HasOwnProp("previewBox") &&
        selectedIndex <= g_CurrentGui.fullPaths.Length) {
        fullPath := g_CurrentGui.fullPaths[selectedIndex]
        if (fullPath != "")
            g_CurrentGui.previewBox.Value := fullPath
    }
}

; Enter 键确认（通过 InputHook 捕获）
; 通过 selectableMap 还原真实 g_PathCache 索引，执行路径跳转并关闭 GUI
ListBoxEnterPressed(listBox, hook, vk, sc, *) {
    global g_CurrentGui, g_PathCache
    if (vk = 13) {
        try {
            selectedIndex := listBox.Value
            if (selectedIndex > 0 && g_CurrentGui.HasOwnProp("selectableMap")) {
                cacheIdx := g_CurrentGui.selectableMap[selectedIndex]
                ; 分组标题行的 cacheIdx 为 -1，需跳过
                if (cacheIdx > 0 && cacheIdx <= g_PathCache.Length) {
                    entry      := g_PathCache[cacheIdx]
                    targetHwnd := g_CurrentGui.HasOwnProp("targetHwnd") ? g_CurrentGui.targetHwnd : 0
                    LogInfo("用户选择路径(Enter): " entry.path " [" entry.label "]")

                    ; 先清理 GUI，释放 InputHook 并恢复目标窗口焦点
                    CleanupGui(g_CurrentGui)

                    ; 等待用户松开 Enter，杜绝回车残留事件导致目标对话框关闭
                    KeyWait("Enter")

                    ExecutePathSwitch(entry, targetHwnd)
                }
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

; 失焦检测定时器回调（每 200ms 触发一次）
CheckFocusClose(pathGui) {
    global g_CurrentGui
    try {
        ; 检查 GUI 是否还存在
        if (!WinExist("ahk_id " pathGui.Hwnd)) {
            SetTimer(pathGui.focusCheckTimer, 0)
            return
        }
        ; 检查 GUI 是否失去焦点（不是当前活动窗口）
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
