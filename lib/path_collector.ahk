; ============================================================
; Path Collector — FolderJump
; 路径收集调度器
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\adapters\explorer.ahk"
#Include "%A_ScriptDir%\adapters\totalcmd.ahk"
#Include "%A_ScriptDir%\adapters\dopus.ahk"

; 收集所有文件管理器路径
CollectAllPaths() {
    global g_Config
    allPaths := []

    ; 1. 收集 Explorer 路径
    if (g_Config.enable_explorer) {
        explorerPaths := CollectExplorerPaths()
        for p in explorerPaths
            allPaths.Push(p)
    }

    ; 2. 收集 Total Commander 路径
    if (g_Config.enable_totalcmd) {
        tcPaths := CollectTotalCmdPaths()
        for p in tcPaths
            allPaths.Push(p)
    }

    ; 3. 收集 Directory Opus 路径
    if (g_Config.enable_dopus) {
        dopusPaths := CollectDOpusPaths()
        for p in dopusPaths
            allPaths.Push(p)
    }

    ; 4. 去重
    allPaths := DeduplicatePaths(allPaths)

    ; 5. 排序
    allPaths := SortPaths(allPaths)

    LogDebug("路径收集完成: 总计 " allPaths.Length " 个唯一路径")
    return allPaths
}

; 去重：相同路径只保留最新时间戳
DeduplicatePaths(paths) {
    pathMap := Map()
    for entry in paths {
        normalized := NormalizePath(entry.path)
        if (!pathMap.Has(normalized) || entry.timestamp > pathMap[normalized].timestamp) {
            pathMap[normalized] := entry
        }
    }

    result := []
    for _, entry in pathMap {
        result.Push(entry)
    }
    return result
}

; 路径标准化（统一大小写和分隔符）
NormalizePath(path) {
    ; 统一反斜杠
    path := StrReplace(path, "/", "\")
    ; 移除末尾的反斜杠（除非是根目录）
    if (StrLen(path) > 3 && SubStr(path, -1) = "\")
        path := SubStr(path, 1, -1)
    return path
}

; 排序路径
SortPaths(paths) {
    global g_Config

    if (paths.Length <= 1)
        return paths

    ; 复制数组
    sorted := []
    for p in paths
        sorted.Push(p)

    if (g_Config.sort_by = "alphabetical") {
        ; 按路径字母排序（冒泡排序）
        return BubbleSort(sorted, (a, b) => CompareStr(a.path, b.path))
    }

    ; 默认按时间戳排序（最近的在前）
    return BubbleSort(sorted, (a, b) => b.timestamp - a.timestamp)
}

; 冒泡排序实现（AHK v2 数组没有内置 Sort 方法）
BubbleSort(arr, compareFn) {
    n := arr.Length
    Loop n - 1 {
        i := A_Index
        Loop n - i {
            j := A_Index
            if (compareFn(arr[j], arr[j + 1]) > 0) {
                ; 交换元素
                temp := arr[j]
                arr[j] := arr[j + 1]
                arr[j + 1] := temp
            }
        }
    }
    return arr
}

; 字符串比较辅助函数
CompareStr(a, b) {
    if (a < b)
        return -1
    if (a > b)
        return 1
    return 0
}