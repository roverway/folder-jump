; ============================================================
; Window Monitor - FolderJump
; Refresh cached paths on a timer
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\path_collector.ahk"

InitWindowMonitor() {
    global g_Config
    interval := g_Config.poll_interval
    SetTimer(RefreshPaths, interval)
    LogDebug("Window monitor timer started: interval=" interval "ms")
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
