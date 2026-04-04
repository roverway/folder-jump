; ============================================================
; Log Manager — FolderJump
; 日志记录与轮转模块
; ============================================================

; 日志级别常量
LOG_DEBUG := 0
LOG_INFO  := 1
LOG_WARN  := 2
LOG_ERROR := 3

; 全局日志配置
g_LogConfig := {
    level: LOG_INFO,
    maxSize: 1024 * 1024,      ; 1MB
    maxFiles: 3,
    path: A_ScriptDir "\logs"
}

; 初始化日志目录
InitLogs() {
    global g_LogConfig
    logDir := g_LogConfig.path
    if (!DirExist(logDir))
        DirCreate(logDir)
    LogInfo("FolderJump 启动")
}

; 写日志
LogWrite(level, message) {
    global g_LogConfig
    if (level < g_LogConfig.level)
        return

    levelNames := ["DEBUG", "INFO", "WARN", "ERROR"]
    ; 边界检查：确保 level 在有效范围内
    if (level < 0 || level > 3)
        levelName := "UNKNOWN"
    else
        levelName := levelNames[level + 1]
    timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    logLine := timestamp " [" levelName "] " message "`n"

    logFile := g_LogConfig.path "\folder-jump.log"
    try {
        FileAppend(logLine, logFile, "UTF-8")
    } catch as err {
        ; 日志写入失败时静默处理，避免递归错误
        return
    }

    ; 检查是否需要轮转
    try {
        if (FileGetSize(logFile) > g_LogConfig.maxSize) {
            RotateLogs()
        }
    }
}

; 日志轮转
RotateLogs() {
    global g_LogConfig
    logDir := g_LogConfig.path
    maxFiles := g_LogConfig.maxFiles

    ; 删除最老的备份
    oldLog := logDir "\folder-jump.log." maxFiles
    try {
        if (FileExist(oldLog))
            FileDelete(oldLog)
    }

    ; 轮转现有备份（从大到小）
    Loop maxFiles - 1 {
        i := maxFiles - A_Index
        src := logDir "\folder-jump.log." i
        dst := logDir "\folder-jump.log." (i + 1)
        try {
            if (FileExist(src))
                FileMove(src, dst, true)
        }
    }

    ; 复制当前日志为 .1，然后清空当前日志
    try {
        FileCopy(logDir "\folder-jump.log", logDir "\folder-jump.log.1", true)
        FileDelete(logDir "\folder-jump.log")
    }
}

; 便捷函数
LogDebug(msg) => LogWrite(LOG_DEBUG, msg)
LogInfo(msg)  => LogWrite(LOG_INFO, msg)
LogWarn(msg)  => LogWrite(LOG_WARN, msg)
LogError(msg) => LogWrite(LOG_ERROR, msg)
