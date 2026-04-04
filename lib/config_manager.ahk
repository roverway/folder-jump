; ============================================================
; Config Manager - FolderJump
; Load and reload INI configuration
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"

LoadConfig() {
    configPath := A_ScriptDir "\config.ini"

    cfg := {
        hotkey: IniRead(configPath, "general", "hotkey", "^g"),
        poll_interval: IniRead(configPath, "general", "poll_interval", 500),
        debounce_ms: IniRead(configPath, "general", "debounce_ms", 300),
        auto_close_timeout: IniRead(configPath, "general", "auto_close_timeout", 10),
        theme: IniRead(configPath, "general", "theme", "dark"),
        enable_explorer: IniRead(configPath, "adapters", "enable_explorer", 1),
        enable_totalcmd: IniRead(configPath, "adapters", "enable_totalcmd", 1),
        enable_dopus: IniRead(configPath, "adapters", "enable_dopus", 1),
        show_source_label: IniRead(configPath, "ui", "show_source_label", 1),
        max_items: IniRead(configPath, "ui", "max_items", 12),
        sort_by: IniRead(configPath, "ui", "sort_by", "recent"),
        position: IniRead(configPath, "ui", "position", "below_window"),
        log_level: IniRead(configPath, "log", "log_level", "INFO"),
        log_max_size: IniRead(configPath, "log", "log_max_size", 1048576),
        log_max_files: IniRead(configPath, "log", "log_max_files", 3)
    }

    cfg.poll_interval := Integer(cfg.poll_interval)
    cfg.debounce_ms := Integer(cfg.debounce_ms)
    cfg.auto_close_timeout := Integer(cfg.auto_close_timeout)
    cfg.enable_explorer := Integer(cfg.enable_explorer)
    cfg.enable_totalcmd := Integer(cfg.enable_totalcmd)
    cfg.enable_dopus := Integer(cfg.enable_dopus)
    cfg.show_source_label := Integer(cfg.show_source_label)
    cfg.max_items := Integer(cfg.max_items)
    cfg.log_max_size := Integer(cfg.log_max_size)
    cfg.log_max_files := Integer(cfg.log_max_files)

    ApplyLogConfig(cfg.log_level, cfg.log_max_size, cfg.log_max_files)

    LogInfo("Configuration loaded: " configPath)
    return cfg
}

ApplyLogConfig(levelStr, maxSize, maxFiles) {
    global g_LogConfig

    levelMap := Map("DEBUG", 0, "INFO", 1, "WARN", 2, "ERROR", 3)
    g_LogConfig.level := levelMap.Has(levelStr) ? levelMap[levelStr] : 1
    g_LogConfig.maxSize := maxSize
    g_LogConfig.maxFiles := maxFiles
}

ReloadConfig() {
    global g_Config
    g_Config := LoadConfig()
    LogInfo("Configuration reloaded")
    return g_Config
}
