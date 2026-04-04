; ============================================================
; Tray Manager — FolderJump
; 系统托盘图标与右键菜单
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"

; 初始化托盘
TrayInit(*) {
    ; 隐藏主窗口（AHK 脚本默认无主窗口，但确保一下）
    A_IconHidden := false

    ; 使用系统文件夹图标
    TraySetIcon("shell32.dll", 3)

    ; 清空默认托盘菜单
    A_TrayMenu.Delete()

    ; 创建托盘菜单
    A_TrayMenu.Add("显示提示", TrayShowTip)
    A_TrayMenu.Add("重新加载配置", TrayReloadConfig)
    A_TrayMenu.Add()  ; 分隔线
    A_TrayMenu.Add("退出", TrayExit)

    ; 设置托盘提示
    A_IconTip := "FolderJump`n按 Ctrl+G 触发"

    ; 左键单击显示提示
    A_TrayMenu.Default := "显示提示"

    LogDebug("托盘管理器已初始化")
}

; 显示状态提示
TrayShowTip(*) {
    TrayTip("FolderJump", "运行中... 按 Ctrl+G 触发", 2000)
}

; 重新加载配置
TrayReloadConfig(*) {
    global g_Config
    try {
        ReloadConfig()
        TrayTip("FolderJump", "配置已重新加载", 2000)
    } catch as err {
        TrayTip("FolderJump", "配置重载失败: " err.Message, 3000)
        LogError("配置重载失败: " err.Message)
    }
}

; 退出程序
TrayExit(*) {
    LogInfo("用户通过托盘退出程序")
    ExitApp()
}
