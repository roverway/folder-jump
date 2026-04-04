; ============================================================
; Path Collector - FolderJump
; Collect, deduplicate, and sort paths from enabled adapters
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\adapters\explorer.ahk"
#Include "%A_ScriptDir%\adapters\totalcmd.ahk"
#Include "%A_ScriptDir%\adapters\dopus.ahk"

CollectAllPaths() {
    global g_Config
    allPaths := []

    LogInfo("Adapter state - Explorer: " g_Config.enable_explorer ", TC: " g_Config.enable_totalcmd ", DOpus: " g_Config.enable_dopus)

    if (g_Config.enable_explorer) {
        LogInfo("Start collecting Explorer paths")
        explorerPaths := CollectExplorerPaths()
        for pathEntry in explorerPaths
            allPaths.Push(pathEntry)
    }

    if (g_Config.enable_totalcmd) {
        LogInfo("Start collecting Total Commander paths")
        tcPaths := CollectTotalCmdPaths()
        LogInfo("Collected Total Commander paths: " tcPaths.Length)
        for pathEntry in tcPaths
            allPaths.Push(pathEntry)
    } else {
        LogInfo("Total Commander adapter disabled")
    }

    if (g_Config.enable_dopus) {
        LogInfo("Start collecting Directory Opus paths")
        dopusPaths := CollectDOpusPaths()
        for pathEntry in dopusPaths
            allPaths.Push(pathEntry)
    }

    allPaths := DeduplicatePaths(allPaths)
    allPaths := SortPaths(allPaths)

    LogDebug("Finished collecting paths: totalUnique=" allPaths.Length)
    return allPaths
}

DeduplicatePaths(paths) {
    pathMap := Map()

    for entry in paths {
        normalized := NormalizePath(entry.path)
        if (!pathMap.Has(normalized) || entry.timestamp > pathMap[normalized].timestamp)
            pathMap[normalized] := entry
    }

    result := []
    for _, entry in pathMap
        result.Push(entry)

    return result
}

NormalizePath(path) {
    path := StrReplace(path, "/", "\")
    path := Trim(path, " `t`r`n")

    if (StrLen(path) > 3 && SubStr(path, -1) = "\")
        path := SubStr(path, 1, -1)

    return StrLower(path)
}

SortPaths(paths) {
    global g_Config

    if (paths.Length <= 1)
        return paths

    sorted := []
    for pathEntry in paths
        sorted.Push(pathEntry)

    if (g_Config.sort_by = "alphabetical")
        return BubbleSort(sorted, ComparePathEntriesByName)

    return BubbleSort(sorted, ComparePathEntriesByTimestamp)
}

ComparePathEntriesByName(a, b) {
    normalizedA := NormalizePath(a.path)
    normalizedB := NormalizePath(b.path)

    if (normalizedA < normalizedB)
        return -1
    if (normalizedA > normalizedB)
        return 1
    return 0
}

ComparePathEntriesByTimestamp(a, b) {
    return b.timestamp - a.timestamp
}

BubbleSort(arr, compareFn) {
    n := arr.Length
    Loop n - 1 {
        i := A_Index
        Loop n - i {
            j := A_Index
            if (compareFn(arr[j], arr[j + 1]) > 0) {
                temp := arr[j]
                arr[j] := arr[j + 1]
                arr[j + 1] := temp
            }
        }
    }

    return arr
}
