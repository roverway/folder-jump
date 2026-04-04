; ============================================================
; Directory Opus Adapter - FolderJump
; Collect and navigate Directory Opus paths
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\utils.ahk"

CollectDOpusPaths() {
    paths := []
    seenHwnd := Map()

    try {
        for hwnd in WinGetList("ahk_class dopus.lister") {
            if (seenHwnd.Has(hwnd))
                continue
            seenHwnd[hwnd] := true
            AddDOpusPathEntry(paths, hwnd)
        }
    } catch as err {
        LogWarn("Failed to collect Directory Opus lister paths: " err.Message)
    }

    try {
        for hwnd in WinGetList("ahk_class dopus.tab") {
            if (seenHwnd.Has(hwnd))
                continue
            seenHwnd[hwnd] := true
            AddDOpusPathEntry(paths, hwnd)
        }
    } catch as err {
        LogWarn("Failed to collect Directory Opus tab paths: " err.Message)
    }

    LogDebug("Collected Directory Opus paths: " paths.Length)
    return paths
}

AddDOpusPathEntry(paths, hwnd) {
    path := ExtractPathFromDOpusWindow(hwnd)
    if (!(path && DirExist(path))) {
        LogDebug("Skip DOpus window without valid path: hwnd=" hwnd)
        return
    }

    paths.Push({
        path: path,
        source: "dopus",
        label: "DOpus",
        hwnd: hwnd,
        timestamp: A_TickCount
    })
    LogInfo("Add DOpus path: " path)
}

ExtractPathFromDOpusWindow(hwnd) {
    controlPath := ExtractPathFromDOpusControls(hwnd)
    if (controlPath)
        return controlPath

    windowTextPath := ExtractPathFromDOpusWindowText(hwnd)
    if (windowTextPath)
        return windowTextPath

    title := ""
    try title := WinGetTitle("ahk_id " hwnd)

    return ExtractPathFromDOpusTitle(title)
}

ExtractPathFromDOpusControls(hwnd) {
    try {
        controls := WinGetControls("ahk_id " hwnd)
    } catch as err {
        LogWarn("Failed to inspect DOpus controls: " err.Message)
        return ""
    }

    candidates := []
    for control in controls {
        text := GetDOpusControlTextSafe(control, hwnd)
        if (!text)
            continue

        foundPaths := ExtractExistingPathsFromText(text)
        for path in foundPaths
            candidates.Push(path)
    }

    return SelectBestDOpusPath(candidates)
}

ExtractPathFromDOpusWindowText(hwnd) {
    oldSetting := A_DetectHiddenText
    try {
        DetectHiddenText(true)
        allText := WinGetText("ahk_id " hwnd)
    } catch as err {
        LogWarn("Failed to read DOpus window text: " err.Message)
        DetectHiddenText(oldSetting)
        return ""
    }
    DetectHiddenText(oldSetting)

    candidates := ExtractExistingPathsFromText(allText)
    return SelectBestDOpusPath(candidates)
}

ExtractExistingPathsFromText(text) {
    candidates := []
    seen := Map()

    for line in StrSplit(text, "`n", "`r") {
        candidate := ExtractPathCandidate(line)
        if (!(candidate && DirExist(candidate)))
            continue

        normalized := StrLower(candidate)
        if (seen.Has(normalized))
            continue

        seen[normalized] := true
        candidates.Push(candidate)
    }

    return candidates
}

ExtractPathCandidate(text) {
    text := Trim(text, " `t`r`n")
    if (!text)
        return ""

    text := RegExReplace(text, "\s+-\s+Directory Opus$")
    text := RegExReplace(text, "\s+-\s+Opus$")
    text := RegExReplace(text, "[>\r\n]+$")
    text := Trim(text)

    if (RegExMatch(text, "i)([A-Z]:\\[^<>:\x22|?*\r\n]+)", &match))
        return NormalizeDOpusPathCandidate(match[1])

    if (RegExMatch(text, "(\\\\[^\\\/:*?\x22<>|\r\n]+\\[^<>:\x22|?*\r\n]+)", &uncMatch))
        return NormalizeDOpusPathCandidate(uncMatch[1])

    return NormalizeDOpusPathCandidate(text)
}

NormalizeDOpusPathCandidate(path) {
    path := Trim(path, " `t`r`n")
    path := StrReplace(path, "/", "\")

    if (StrLen(path) > 3 && SubStr(path, -1) = "\")
        path := SubStr(path, 1, -1)

    return path
}

SelectBestDOpusPath(candidates) {
    bestPath := ""
    for path in candidates {
        if (!(path && DirExist(path)))
            continue

        if (StrLen(path) > StrLen(bestPath))
            bestPath := path
    }

    return bestPath
}

ExtractPathFromDOpusTitle(title) {
    candidate := ExtractPathCandidate(title)
    if (candidate && DirExist(candidate))
        return candidate
    return ""
}

GetDOpusControlTextSafe(control, hwnd) {
    try {
        return ControlGetText(control, "ahk_id " hwnd)
    } catch {
        return ""
    }
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
