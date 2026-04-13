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
    entryMap      := []
    firstSelectable := 0

    for groupIdx, src in groupOrder {
        ; 方向A：在不同分组间插入空白分隔行增加呼吸感
        if (groupIdx > 1) {
            items.Push(" ")
            selectableMap.Push(-1)
            fullPaths.Push("")
            entryMap.Push("")
        }

        indices := groups[src]
        srcName := GetSourceDisplayName(src)

        ; 插入分组标题行（方向D：右侧数字通过中点对齐）
        baseTxt := " ▸ " srcName " "
        countTxt := " (" indices.Length ")"
        
        ; 估算填充长度，目标长度约75~80，因 Segoe UI 比例字体可能略有偏差
        padCount := 75 - StrLen(baseTxt) - StrLen(countTxt)
        if (padCount < 3)
            padCount := 3
        
        padStr := ""
        Loop padCount
            padStr .= "·"

        header := baseTxt padStr countTxt
        items.Push(header)
        selectableMap.Push(-1)
        fullPaths.Push("")
        entryMap.Push("")

        ; 插入各路径行（方向A：树状结构模拟）
        totalCount := indices.Length
        for i, cacheIdx in indices {
            entry       := pathCache[cacheIdx]
            
            ; 末尾项用 └─，中间项用 ├─
            prefix := (i = totalCount) ? " └─  " : " ├─  "
            
            displayPath := prefix TruncatePathForDisplay(entry.path, 52)
            items.Push(displayPath)
            selectableMap.Push(cacheIdx)
            fullPaths.Push(entry.path)
            entryMap.Push(entry)
            
            ; 记录第一个可选行的位置
            if (firstSelectable = 0)
                firstSelectable := items.Length
        }
    }

    return {items: items, selectableMap: selectableMap, fullPaths: fullPaths, entryMap: entryMap, firstSelectable: firstSelectable}
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
        ; 如果首次缓存为空，再次刷新一次路径列表
        try {
            RefreshPaths()
        } catch {
            LogWarn("RefreshPaths failed during hotkey selection")
        }
        if (g_PathCache.Length = 0) {
            TrayTip("FolderJump", "没有打开的文件夹窗口", 2000)
            return
        }
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
    entryMap        := grouped.entryMap
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
    pathGui.entryMap          := entryMap
    pathGui.previewBox        := previewBox
    pathGui.lastValidIndex    := firstSelectable  ; 最近一次落在可选行的 displayItems 索引
    pathGui.selectedIndex     := firstSelectable

    ; 绑定事件
    pathGui.OnEvent("Escape", GuiEscape.Bind(pathGui))
    listBox.OnEvent("DoubleClick", ListBoxConfirm.Bind(pathGui))
    listBox.OnEvent("Change", ListBoxChange.Bind(pathGui))

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
    enterHook.OnKeyDown := ListBoxEnterPressed.Bind(listBox, pathGui)
    enterHook.Start()
    pathGui.enterHook := enterHook
}

; ListBox 确认事件（双击时触发）
; 通过 selectableMap 还原真实 g_PathCache 索引，支持分组标题行存在时的正确跳转
ListBoxConfirm(pathGui, GuiCtrlObj, *) {
    selectedIndex := GuiCtrlObj.Value
    if (selectedIndex > 0 && pathGui.HasOwnProp("entryMap")) {
        entry := pathGui.entryMap[selectedIndex]
        if (IsObject(entry)) {
            targetHwnd := pathGui.HasOwnProp("targetHwnd") ? pathGui.targetHwnd : 0
            LogInfo("用户选择路径(双击): " entry.path " [" entry.label "]")
                    ; 关闭 GUI 前先记录目标窗口的父窗口，用于模态对话框场景的恢复
            ownerHwnd := DllCall("GetWindow", "Ptr", targetHwnd, "UInt", 4, "Ptr")  ; GW_OWNER=4
            LogDebug("Target hwnd=" targetHwnd ", owner hwnd=" ownerHwnd)
            CleanupGui(pathGui)
            ; 等待目标窗口重新获得焦点（模态对话框在 GUI 关闭后需要时间恢复）
            Sleep(150)
            ; 验证目标窗口是否仍然存在
            if (WinExist("ahk_id " targetHwnd)) {
                LogDebug("Target window still exists after GUI close, proceeding")
                ExecutePathSwitch(entry, targetHwnd)
            } else if (ownerHwnd && WinExist("ahk_id " ownerHwnd)) {
                ; 模态对话框被父窗口重新激活后可能重建，尝试在父窗口下寻找同类对话框
                LogWarn("Target hwnd gone, trying to find modal dialog under owner: " ownerHwnd)
                newDialogHwnd := FindModalDialogUnderOwner(ownerHwnd)
                if (newDialogHwnd) {
                    LogInfo("Found new dialog hwnd=" newDialogHwnd ", retrying switch")
                    ExecutePathSwitch(entry, newDialogHwnd)
                } else {
                    LogWarn("No modal dialog found under owner, aborting")
                    TrayTip("FolderJump", "目标窗口已关闭，跳转取消", 2000)
                }
            } else {
                LogWarn("Target window no longer exists and no owner found: ahk_id " targetHwnd)
                TrayTip("FolderJump", "目标窗口已关闭，跳转取消", 2000)
            }
            return
        }
    }
    CleanupGui(pathGui)
}

; ListBox 变更事件（键盘 ↑↓ 导航时触发）
; 自动跳过分组标题行，同时更新底部完整路径预览
ListBoxChange(pathGui, GuiCtrlObj, *) {
    if (!IsSet(pathGui) || !pathGui)
        return

    selectedIndex := GuiCtrlObj.Value
    if (selectedIndex <= 0)
        return

    selectableMap := pathGui.selectableMap

    ; 当前选中的是分组标题行（selectableMap 值为 -1），需要自动跳转到相邻的可选行
    if (selectableMap[selectedIndex] = -1) {
        lastValid := pathGui.lastValidIndex

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
    pathGui.lastValidIndex := selectedIndex
    pathGui.selectedIndex  := selectedIndex

    if (pathGui.HasOwnProp("fullPaths") &&
        pathGui.HasOwnProp("previewBox") &&
        selectedIndex <= pathGui.fullPaths.Length) {
        fullPath := pathGui.fullPaths[selectedIndex]
        if (fullPath != "")
            pathGui.previewBox.Value := fullPath
    }
}

; Enter 键确认（通过 InputHook 捕获）
; 通过 selectableMap 还原真实路径对象，执行路径跳转并关闭 GUI
ListBoxEnterPressed(listBox, pathGui, hook, vk, sc, *) {
    if (vk = 13) {
        try {
            selectedIndex := listBox.Value
            if (selectedIndex > 0 && pathGui.HasOwnProp("entryMap")) {
                entry := pathGui.entryMap[selectedIndex]
                if (IsObject(entry)) {
                    targetHwnd := pathGui.HasOwnProp("targetHwnd") ? pathGui.targetHwnd : 0
                    LogInfo("用户选择路径(Enter): " entry.path " [" entry.label "]")

                    ; 先清理 GUI，释放 InputHook 并恢复目标窗口焦点
                    ownerHwnd := DllCall("GetWindow", "Ptr", targetHwnd, "UInt", 4, "Ptr")
                    CleanupGui(pathGui)

                    ; 等待用户松开 Enter，杜绝回车残留事件导致目标对话框关闭
                    KeyWait("Enter")

                    ; 确保 InputHook 停止，避免重复触发或干扰目标窗口
                    if (pathGui.HasOwnProp("enterHook")) {
                        try pathGui.enterHook.Stop()
                    }

                    ; 等待目标窗口重新获得焦点（模态对话框在 GUI 关闭后需要时间恢复）
                    Sleep(150)

                    ; 验证目标窗口仍然存在，避免模态对话框被父窗口销毁的情况
                    if (WinExist("ahk_id " targetHwnd)) {
                        ExecutePathSwitch(entry, targetHwnd)
                    } else if (ownerHwnd && WinExist("ahk_id " ownerHwnd)) {
                        LogWarn("Target hwnd gone (Enter), trying owner: " ownerHwnd)
                        newDialogHwnd := FindModalDialogUnderOwner(ownerHwnd)
                        if (newDialogHwnd)
                            ExecutePathSwitch(entry, newDialogHwnd)
                        else
                            TrayTip("FolderJump", "目标窗口已关闭，跳转取消", 2000)
                    } else {
                        LogWarn("Target window no longer exists after GUI close: ahk_id " targetHwnd)
                        TrayTip("FolderJump", "目标窗口已关闭，跳转取消", 2000)
                    }
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

; 在指定父窗口下寻找模态对话框（#32770 类）
; 用于处理模态对话框 hwnd 在 FolderJump GUI 关闭后被重建的情况
FindModalDialogUnderOwner(ownerHwnd) {
    ; 枚举所有 #32770 窗口，找到 owner 匹配的那个
    foundHwnd := 0
    hwnd := 0
    Loop {
        hwnd := DllCall("FindWindowEx", "Ptr", 0, "Ptr", hwnd, "Str", "#32770", "Ptr", 0, "Ptr")
        if (!hwnd)
            break
        owner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")  ; GW_OWNER=4
        if (owner = ownerHwnd) {
            foundHwnd := hwnd
            break
        }
    }
    return foundHwnd
}


; 在所有关闭路径中统一调用，确保资源正确释放
CleanupGui(pathGui) {
    global g_CurrentGui
    if (!IsSet(g_CurrentGui) || !g_CurrentGui)
        return
    if (!IsSet(pathGui) || !pathGui)
        return
    if (g_CurrentGui != pathGui)
        return

    ; 先清除全局引用，避免重入和竞态
    g_CurrentGui := ""

    ; 停止超时定时器（如果存在）
    if (pathGui.HasOwnProp("autoCloseTimer")) {
        try SetTimer(pathGui.autoCloseTimer, 0)
    }
    ; 停止焦点检测定时器（如果存在）
    if (pathGui.HasOwnProp("focusCheckTimer")) {
        try SetTimer(pathGui.focusCheckTimer, 0)
    }
    ; 停止 InputHook（如果存在）
    if (pathGui.HasOwnProp("enterHook")) {
        try pathGui.enterHook.Stop()
    }
    ; 销毁 GUI
    try pathGui.Destroy()
}
