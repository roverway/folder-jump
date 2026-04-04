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

    tempFile := A_Temp "\folderjump-dopus-paths-" A_TickCount ".xml"

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
                pathText := NormalizeDOpusPathCandidate(node.text)
                if (!(pathText && DirExist(pathText)))
                    continue

                listerAttr := node.getAttribute("lister")
                hwnd := ParseDOpusListerHandle(listerAttr)
                side := node.getAttribute("side")
                activeTab := node.getAttribute("active_tab")
                label := BuildDOpusLabel(side, activeTab)

                paths.Push({
                    path: pathText,
                    source: "dopus",
                    label: label,
                    hwnd: hwnd,
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

BuildDOpusLabel(side, activeTab) {
    sideLabel := ""
    if (side = "0")
        sideLabel := "left"
    else if (side = "1")
        sideLabel := "right"

    if (sideLabel != "")
        return "DOpus (" sideLabel ")"

    if (activeTab != "")
        return "DOpus (active)"

    return "DOpus"
}

ExtractPathFromDOpusTitle(title) {
    title := Trim(title, " `t`r`n")
    if (!title)
        return ""

    title := RegExReplace(title, "\s+-\s+Directory Opus$")
    title := RegExReplace(title, "\s+-\s+Opus$")
    title := Trim(title)

    candidate := NormalizeDOpusPathCandidate(title)
    if (candidate && DirExist(candidate))
        return candidate

    if (RegExMatch(title, "i)([A-Z]:\\[^<>:\x22|?*\r\n]+)", &match)) {
        candidate := NormalizeDOpusPathCandidate(match[1])
        if (candidate && DirExist(candidate))
            return candidate
    }

    if (RegExMatch(title, "(\\\\[^\\\/:*?\x22<>|\r\n]+\\[^<>:\x22|?*\r\n]+)", &uncMatch)) {
        candidate := NormalizeDOpusPathCandidate(uncMatch[1])
        if (candidate && DirExist(candidate))
            return candidate
    }

    return ""
}

NormalizeDOpusPathCandidate(path) {
    path := Trim(path, " `t`r`n")
    path := StrReplace(path, "/", "\")

    if (StrLen(path) > 3 && SubStr(path, -1) = "\")
        path := SubStr(path, 1, -1)

    return path
}

NavigateDOpus(hwnd, targetPath) {
    try {
        dopusrtPath := FindDOpusRT()
        if (dopusrtPath) {
            Run('"' dopusrtPath '" /cmd Go "' targetPath '"', , "Hide")
            LogDebug("DOpusRT navigation succeeded: " targetPath)
            return true
        }
    } catch as err {
        LogWarn("DOpusRT navigation failed, falling back to keyboard: " err.Message)
    }

    savedClipboard := SaveClipboard()

    try {
        WinActivate("ahk_id " hwnd)
        if (!WinWaitActive("ahk_id " hwnd, , 1000)) {
            RestoreClipboard(savedClipboard)
            return false
        }

        Send("^l")
        Sleep(50)

        A_Clipboard := targetPath
        Sleep(50)
        Send("^v")
        Sleep(50)
        Send("{Enter}")

        LogDebug("DOpus keyboard navigation succeeded: " targetPath)
        RestoreClipboard(savedClipboard)
        return true
    } catch as err {
        LogError("DOpus navigation failed: " err.Message)
        RestoreClipboard(savedClipboard)
        return false
    }
}

FindDOpusRT() {
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
