; ============================================================
; Directory Opus 适配器 - FolderJump
; 负责获取与跳转 Directory Opus 路径
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\utils.ahk"

CollectDOpusPaths() {
    paths := CollectDOpusPathsViaDOpusRT()
    if (paths.Length > 0)
        return paths

    LogWarn("Falling back to DOpus title parsing")
    return CollectDOpusPathsFromTitles()
}

CollectDOpusPathsViaDOpusRT() {
    paths := []
    dopusrtPath := FindDOpusRT()
    if (!dopusrtPath) {
        LogWarn("DOpusRT not found")
        return paths
    }

    tempFile := A_Temp "\folderjump-dopus-paths.xml"

    try {
        RunWait('"' dopusrtPath '" /info "' tempFile '",paths', , "Hide")
        if (!FileExist(tempFile)) {
            LogWarn("DOpusRT did not produce a paths file")
            return paths
        }

        xml := ComObject("Msxml2.DOMDocument.6.0")
        xml.async := false
        if (!xml.load(tempFile)) {
            LogWarn("Failed to parse DOpusRT XML output")
            return paths
        }

        for node in xml.selectNodes("//path[@active_tab]") {
            try {
                pathText := NormalizePathString(node.text)
                if (!(pathText && DirExist(pathText)))
                    continue

                listerAttr := node.getAttribute("lister")
                hwnd := ParseDOpusListerHandle(listerAttr)
                side := node.getAttribute("side")
                activeTab := node.getAttribute("active_tab")
                ; side 表示该tab所在的窗格，activeTab 表示该tab是否为当前可见tab以及位于哪一侧
                sideName := GetDOpusPaneName(side)
                activeSideName := GetDOpusPaneName(activeTab)
                ; activeTab 属性存在表示该tab是当前可见的
                isVisibleTab := activeTab != ""
                label := BuildDOpusLabel(sideName, activeSideName, isVisibleTab)

                paths.Push({
                    path: pathText,
                    source: "dopus",
                    label: label,
                    hwnd: hwnd,
                    panel: sideName,
                    panelSide: sideName,
                    isVisibleTab: isVisibleTab,
                    timestamp: A_TickCount
                })
                LogInfo("Add DOpus path via DOpusRT: " pathText " [" label "]")
            } catch as innerErr {
                LogWarn("Failed to parse DOpusRT path entry: " innerErr.Message)
            }
        }
    } catch as err {
        LogWarn("DOpusRT path collection failed: " err.Message)
    }

    try {
        if (FileExist(tempFile))
            FileDelete(tempFile)
    }

    return paths
}

CollectDOpusPathsFromTitles() {
    paths := []
    seenHwnd := Map()

    try {
        for hwnd in WinGetList("ahk_class dopus.lister") {
            if (seenHwnd.Has(hwnd))
                continue
            seenHwnd[hwnd] := true
            AddDOpusTitlePathEntry(paths, hwnd)
        }
    } catch as err {
        LogWarn("Failed to collect DOpus lister paths from titles: " err.Message)
    }

    try {
        for hwnd in WinGetList("ahk_class dopus.tab") {
            if (seenHwnd.Has(hwnd))
                continue
            seenHwnd[hwnd] := true
            AddDOpusTitlePathEntry(paths, hwnd)
        }
    } catch as err {
        LogWarn("Failed to collect DOpus tab paths from titles: " err.Message)
    }

    return paths
}

AddDOpusTitlePathEntry(paths, hwnd) {
    title := ""
    try title := WinGetTitle("ahk_id " hwnd)

    path := ExtractPathFromDOpusTitle(title)
    if (!(path && DirExist(path))) {
        LogDebug("Skip DOpus title path candidate: hwnd=" hwnd ", title=" title)
        return
    }

    paths.Push({
        path: path,
        source: "dopus",
        label: "DOpus",
        hwnd: hwnd,
        timestamp: A_TickCount
    })
    LogInfo("Add DOpus path via title: " path)
}

ParseDOpusListerHandle(listerAttr) {
    if (!listerAttr)
        return 0

    if (SubStr(listerAttr, 1, 2) = "0x")
        return Integer(listerAttr)

    return Integer("0x" listerAttr)
}

GetDOpusPaneName(sideValue) {
    ; DOpus 官方定义：1 = left/top，2 = right/bottom
    normalized := Trim(sideValue, " `t`r`n")
    if (normalized = "1")
        return "左"
    if (normalized = "2")
        return "右"
    return ""
}

BuildDOpusLabel(sideName, activeSideName, isVisibleTab) {
    ; 构建标签：同时表达窗格方向和可见性
    ; sideName: tab所在窗格（来自 side 属性）
    ; activeSideName: 当前可见tab所在窗格（来自 active_tab 属性）
    ; isVisibleTab: 该tab是否为当前可见tab
    labelParts := []

    ; 优先使用 active_tab 信息（表示当前可见tab的位置）
    if (isVisibleTab && activeSideName != "") {
        labelParts.Push(activeSideName)
        labelParts.Push("可见")
    } else if (sideName != "") {
        ; 降级：如果不是可见tab或activeSideName为空，使用side信息
        labelParts.Push(sideName)
    }

    if (labelParts.Length = 0)
        return "DOpus"

    return "DOpus (" JoinDOpusLabelParts(labelParts) ")"
}

JoinDOpusLabelParts(parts) {
    result := ""

    for index, part in parts {
        if (index > 1)
            result .= ", "
        result .= part
    }

    return result
}

ExtractPathFromDOpusTitle(title) {
    title := Trim(title, " `t`r`n")
    if (!title)
        return ""

    title := RegExReplace(title, "\s+-\s+Directory Opus$")
    title := RegExReplace(title, "\s+-\s+Opus$")
    title := Trim(title)

    candidate := NormalizePathString(title)
    if (candidate && DirExist(candidate))
        return candidate

    if (RegExMatch(title, "i)([A-Z]:\\[^<>:\x22|?*\r\n]+)", &match)) {
        candidate := NormalizePathString(match[1])
        if (candidate && DirExist(candidate))
            return candidate
    }

    if (RegExMatch(title, "(\\\\[^\\\/:*?\x22<>|\r\n]+\\[^<>:\x22|?*\r\n]+)", &uncMatch)) {
        candidate := NormalizePathString(uncMatch[1])
        if (candidate && DirExist(candidate))
            return candidate
    }

    return ""
}




FindDOpusRT() {
    try {
        appPath := RegRead("HKLM\SOFTWARE\GPSoftware\Directory Opus", "AppPath")
        if (appPath) {
            dopusrt := appPath "\dopusrt.exe"
            if (FileExist(dopusrt))
                return dopusrt
        }
    } catch {
        ; Registry key not found, continue to fallback
    }

    static candidates := [
        "C:\Program Files\GPSoftware\Directory Opus\dopusrt.exe",
        "C:\Program Files (x86)\GPSoftware\Directory Opus\dopusrt.exe"
    ]

    for path in candidates {
        if (FileExist(path))
            return path
    }

    return ""
}
