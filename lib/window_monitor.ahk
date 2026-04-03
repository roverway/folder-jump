; ============================================================
; Window Monitor — FolderJump
; 定时轮询窗口状态，维护路径缓存
; ============================================================

#IncludeOnce "%A_ScriptDir%\lib\log_manager.ahk"
#IncludeOnce "%A_ScriptDir%\lib\path_collector.ahk"

; 全局路径缓存
g_PathCache := []

; 刷新锁（防止并发刷新）
g_IsRefreshing := false

; 初始化窗口监控定时器
; 启动后每 poll_interval 毫秒自动刷新路径缓存
; 定时器由 SetTimer 驱动，在后台持续运行
InitWindowMonitor() {
    global g_Config
    interval := g_Config.poll_interval
    SetTimer(RefreshPaths, interval)
    LogDebug("窗口监控定时器已启动，间隔: " interval "ms")
}

; 停止窗口监控定时器
; 在程序退出或需要暂停监控时调用
StopWindowMonitor() {
    SetTimer(RefreshPaths, 0)
    LogDebug("窗口监控定时器已停止")
}

; 刷新路径缓存（定时器触发或手动调用）
; 从所有启用的文件管理器（Explorer/TC/DOpus）收集路径
; 使用 g_IsRefreshing 防止并发刷新（AHK 单线程，但定时器可能在热键回调期间触发）
; 注意: g_IsRefreshing 是简单的布尔标记，在 AHK 中赋值是原子操作，无需额外锁
RefreshPaths() {
    global g_PathCache, g_IsRefreshing

    ; 防止并发刷新
    if (g_IsRefreshing)
        return
    g_IsRefreshing := true

    try {
        g_PathCache := CollectAllPaths()
    } catch as err {
        LogError("路径刷新异常: " err.Message)
        g_PathCache := []
    }

    g_IsRefreshing := false
}
