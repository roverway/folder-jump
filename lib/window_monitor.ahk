; ============================================================
; 窗口监控模块 - FolderJump
; 负责定时刷新路径缓存
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\path_collector.ahk"

InitWindowMonitor() {
    global g_Config
    interval := g_Config.poll_interval
    SetTimer(RefreshPaths, interval)
    LogDebug("Window monitor timer started: interval=" interval "ms")
    RefreshPaths()
}

StopWindowMonitor() {
    SetTimer(RefreshPaths, 0)
    LogDebug("Window monitor timer stopped")
}

RefreshPaths() {
    global g_PathCache, g_IsRefreshing

    if (g_IsRefreshing)
        return

    g_IsRefreshing := true

    try {
        g_PathCache := CollectAllPaths()
    } catch as err {
        LogError("Path refresh failed: " err.Message)
        g_PathCache := []
    }

    g_IsRefreshing := false
}
