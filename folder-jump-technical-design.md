# FolderJump 技术设计文档

> 轻量级 Windows 文件管理器路径快速切换工具 — 复刻 Listary Ctrl+G 功能

| 项目 | 信息 |
|------|------|
| 版本 | 0.1.0 |
| 日期 | 2026-04-05 |
| 状态 | 已实现，待继续打磨 |
| 技术栈 | AutoHotkey v2 |
| 目标平台 | Windows 10/11 (x64) |

---

## 1. 概述

### 1.1 目的与范围

FolderJump 是一个轻量级 Windows 后台工具，用于在文件对话框（打开/保存、另存为）中快速跳转到其他已打开的文件夹路径。用户按下 `Ctrl+G` 后，弹出浮动菜单列出当前已收集到的文件夹路径，选择即可让当前文件对话框跳转到目标目录。

**当前范围**：当前版本只在文件对话框中响应 `Ctrl+G`。路径来源可以来自 Explorer、Total Commander、Directory Opus，但热键不会在这些文件管理器主窗口中直接触发。

### 1.2 目标用户

- 经常需要在多个文件夹间切换的开发者、设计师、数据分析师
- 使用 Total Commander / Directory Opus 等第三方文件管理器的高级用户
- 对系统资源占用敏感的低配电脑用户

### 1.3 核心功能

| # | 功能 | 优先级 |
|---|------|--------|
| F1 | 在文件对话框中通过 `Ctrl+G` 触发路径选择菜单 | P0 |
| F2 | 自动检测并列出所有 Windows Explorer 已打开文件夹 | P0 |
| F3 | 在文件对话框中跳转到选中路径 | P0 |
| F4 | 键盘导航（↑↓选择、Enter确认、Esc取消） | P0 |
| F5 | Total Commander 路径获取 | P1 |
| F6 | Directory Opus 路径获取 | P1 |
| F7 | 用户自定义热键 | P2 |
| F8 | 配置界面 / 配置文件 | P2 |
| F9 | 主题切换（深色/浅色） | P3 |

### 1.4 非功能性需求

| 指标 | 目标值 | 说明 |
|------|--------|------|
| 内存占用（空闲） | ≤ 5 MB | 后台运行时的常驻内存 |
| 内存占用（活跃） | ≤ 10 MB | 弹出菜单时的峰值内存 |
| 响应延迟 | ≤ 200 ms | 从按下热键到菜单显示 |
| 路径列表刷新间隔 | 500 ms | 定时检测新窗口 |
| CPU 占用 | ≤ 0.5% | 后台轮询时的平均 CPU |
| 启动时间 | ≤ 1 s | 冷启动到就绪 |

---

## 2. 系统架构

### 2.1 架构图

```
┌─────────────────────────────────────────────────┐
│                  FolderJump (AHK v2)             │
│                                                  │
│  ┌──────────┐    ┌──────────────┐               │
│  │ Hotkey   │───▶│  Context     │               │
│  │ Manager  │    │  Detector    │               │
│  └──────────┘    └──────┬───────┘               │
│                          │                       │
│                          ▼                       │
│                   ┌──────────────┐               │
│                   │  Window      │               │
│                   │  Monitor     │◀── SetTimer   │
│                   │  (500ms)     │    (polling)  │
│                   └──────┬───────┘               │
│                          │                       │
│              ┌───────────┼───────────┐           │
│              ▼           ▼           ▼           │
│      ┌──────────┐ ┌──────────┐ ┌──────────┐     │
│      │ Explorer │ │TotalCmd  │ │  DOpus   │     │
│      │ Adapter  │ │ Adapter  │ │ Adapter  │     │
│      └────┬─────┘ └────┬─────┘ └────┬─────┘     │
│           │             │            │            │
│           └─────────────┼────────────┘            │
│                         ▼                         │
│               ┌──────────────┐                    │
│               │  Path Cache  │                    │
│               │  (Array)     │                    │
│               └──────┬───────┘                    │
│                      │                            │
│                      ▼                            │
│               ┌──────────────┐                    │
│               │ Selection UI │                    │
│               │ (Gui/ListBox)│                    │
│               └──────┬───────┘                    │
│                      │                            │
│                      ▼                            │
│               ┌──────────────┐                    │
│               │ Path Switcher│                    │
│               │ (Navigate)   │                    │
│               └──────────────┘                    │
└──────────────────────────────────────────────────┘
```

### 2.2 数据流

```
用户在文件对话框中按下 Ctrl+G
    │
    ▼
Hotkey Manager 捕获热键
    │
    ▼
Context Detector 判断前景窗口类型
    │
    ├── 文件对话框 → 允许继续执行
    └── 其他窗口 → 忽略（不响应）
    │
    ▼
Window Monitor 触发路径收集（立即刷新，不等定时器）
    │
    ▼
各 Adapter 并行收集路径 → Path Cache 去重合并
    │
    ▼
Selection UI 弹出，显示路径列表
    │
    ▼
用户选择路径 → Path Switcher 执行跳转
    │
    └── 对当前文件对话框应用目标路径
```

### 2.3 组件职责总览

| 组件 | 职责 | 依赖 |
|------|------|------|
| Hotkey Manager | 注册全局热键，触发动作，动态热键重载 | Windows RegisterHotKey API |
| Context Detector | 识别前景窗口是否为受支持文件对话框 | WinGetClass, WinGetTitle, 控件结构 |
| Window Monitor | 定时轮询窗口状态 | SetTimer, Shell.Application COM |
| Tray Manager | 系统托盘图标与右键菜单 | AHK TrayTip / TrayCreate |
| Log Manager | 日志记录与轮转 | 文件 I/O |
| Path Collector | 从各文件管理器提取路径 | 各 Adapter |
| Explorer Adapter | Windows Explorer 路径获取/跳转 | Shell.Application COM |
| TotalCmd Adapter | Total Commander 路径获取/跳转 | WM_COPYDATA / ControlSetText |
| DOpus Adapter | Directory Opus 路径获取 | DOpusRT / 标题解析 |
| Selection UI | 浮动菜单展示与交互 | AHK Gui |
| Path Switcher | 执行路径跳转 | 各 Adapter 的导航方法 |
| Tray Manager | 系统托盘图标与右键菜单 | AHK TraySetIcon / A_TrayMenu |
| Log Manager | 日志记录与轮转 | 文件 I/O |
| Config Manager | 读取/写入用户配置 | INI 文件读写 |

---

## 3. 模块详细设计

### 3.0 系统托盘管理器 (Tray Manager)

**职责**：后台运行时提供托盘图标、右键菜单、退出入口。

**输入**：无（初始化时自动创建）
**输出**：托盘图标及菜单交互

```autohotkey
; 初始化托盘
TrayInit() {
    ; 创建托盘图标（使用应用内置图标或系统图标）
    TraySetIcon("shell32.dll", 3)  ; 使用系统文件夹图标
    
    ; 创建托盘菜单
    TrayMenu := A_TrayMenu
    TrayMenu.Add("显示提示", (*) => TrayTip("FolderJump", "运行中... 按 Ctrl+G 触发"))
    TrayMenu.Add("重新加载配置", (*) => ReloadConfig())
    TrayMenu.Add()  ; 分隔线
    TrayMenu.Add("退出", (*) => ExitApp())
    
    ; 设置托盘提示
    TraySetToolTip("FolderJump`n按 Ctrl+G 触发")
    
    ; 左键单击显示提示
    TrayOnEvent("Click", (*) => TrayTip("FolderJump", "运行中... 按 Ctrl+G 触发", 2000))
}
```

**托盘菜单项**：

| 菜单项 | 功能 | 快捷键 |
|--------|------|--------|
| 显示提示 | 显示运行状态提示 | — |
| 重新加载配置 | 热重载 config.ini | — |
| 退出 | 关闭程序并保存日志 | — |

**托盘行为**：
- 程序启动时自动创建托盘图标（无主窗口）
- 左键单击托盘：显示状态提示（2秒后自动消失）
- 右键单击托盘：显示右键菜单
- 退出前记录日志

---

### 3.0.1 日志模块 (Log Manager)

**职责**：记录运行日志、错误信息，便于调试与问题排查。

**输入**：日志消息、日志级别
**输出**：写入日志文件

```autohotkey
; 日志级别枚举
LOG_DEBUG := 0
LOG_INFO  := 1
LOG_WARN  := 2
LOG_ERROR := 3

; 全局日志配置
g_LogConfig := {
    level: LOG_INFO,           ; 当前日志级别
    maxSize: 1024 * 1024,      ; 单文件最大 1MB
    maxFiles: 3,               ; 保留 3 个轮转文件
    path: A_ScriptDir "\logs"  ; 日志目录
}

; 初始化日志目录
InitLogs() {
    logDir := g_LogConfig.path
    if (!DirExist(logDir))
        DirCreate(logDir)
    LogInfo("FolderJump 启动")
}

; 写日志
LogWrite(level, message) {
    if (level < g_LogConfig.level)
        return
    
    timestamp := FormatTime("yyyy-MM-dd HH:mm:ss")
    levelName := ["DEBUG", "INFO", "WARN", "ERROR"][level + 1]
    logLine := timestamp " [" levelName "] " message "`n"
    
    logFile := g_LogConfig.path "\folder-jump.log"
    FileAppend(logLine, logFile, "UTF-8")
    
    ; 超过最大文件大小则轮转
    try {
        if (FileGetSize(logFile) > g_LogConfig.maxSize) {
            RotateLogs()
        }
    }
}

; 日志轮转
RotateLogs() {
    logDir := g_LogConfig.path
    maxFiles := g_LogConfig.maxFiles
    
    ; 删除最老的备份
    oldLog := logDir "\folder-jump.log." maxFiles
    try {
        if (FileExist(oldLog))
            FileDelete(oldLog)
    }
    
    ; 轮转现有备份
    for i in Range(maxFiles, 1, -1) {
        src := logDir "\folder-jump.log." i
        dst := logDir "\folder-jump.log." (i + 1)
        try {
            if (FileExist(src))
                FileMove(src, dst, true)
        }
    }
    
    ; 复制当前日志为 .1，然后清空当前
    try {
        FileCopy(logDir "\folder-jump.log", logDir "\folder-jump.log.1", true)
        FileDelete(logDir "\folder-jump.log")
    }
}

; 便捷函数
LogDebug(msg)   => LogWrite(LOG_DEBUG, msg)
LogInfo(msg)    => LogWrite(LOG_INFO, msg)
LogWarn(msg)    => LogWrite(LOG_WARN, msg)
LogError(msg)   => LogWrite(LOG_ERROR, msg)
```

**日志格式**：

```
2026-04-03 14:30:25 [INFO] FolderJump 启动
2026-04-03 14:30:26 [DEBUG] 路径缓存刷新: 3 个 Explorer 窗口
2026-04-03 14:30:45 [INFO] 用户选择路径: C:\Users\ZuoQi\Projects
2026-04-03 14:30:45 [DEBUG] 执行跳转: Explorer -> C:\Users\ZuoQi\Projects
2026-04-03 14:31:02 [WARN] 路径不存在: D:\Deleted\Folder
2026-04-03 14:35:12 [ERROR] COM 对象获取失败，降至键盘模拟
2026-04-03 14:40:00 [INFO] 退出程序
```

**日志文件结构**：

```
folder-jump/
├── logs/
│   ├── folder-jump.log      ; 当前日志
│   ├── folder-jump.log.1   ; 最近一次轮转
│   ├── folder-jump.log.2   ; 第二次轮转
│   └── folder-jump.log.3   ; 最老的轮转
```

**配置项**：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `log_level` | `INFO` | 日志级别 (DEBUG/INFO/WARN/ERROR) |
| `log_max_size` | `1048576` | 单文件最大字节数 (1MB) |
| `log_max_files` | `3` | 保留的历史文件数 |

**使用场景记录**：

| 场景 | 记录级别 | 记录内容 |
|------|---------|---------|
| 启动 | INFO | 版本号、配置加载结果、托盘创建 |
| 热键触发 | DEBUG | 捕获热键、上下文检测结果、路径列表大小 |
| 路径收集 | DEBUG | 各 Adapter 获取路径数量、失败原因 |
| 路径跳转 | DEBUG | 目标路径、跳转方式（COM/键盘）、结果 |
| 异常 | ERROR | 完整错误信息、降级处理 |
| 退出 | INFO | 正常退出或异常退出 |

---

### 3.1 Hotkey Manager

**职责**：注册全局热键，检测是否处于受支持文件对话框，执行防抖处理。

**输入**：用户按键事件
**输出**：触发路径选择 UI

**核心逻辑**：

```autohotkey
; 热键注册（AHK v2 语法）
^g:: => OnCtrlG()

OnCtrlG() {
    ; 1. 获取前景窗口
    activeHwnd := WinExist("A")
    if (!activeHwnd)
        return
    
    activeClass := WinGetClass(activeHwnd)
    activeTitle := WinGetTitle(activeHwnd)
    
    ; 2. 上下文判断
    context := DetectContext(activeClass, activeTitle, activeHwnd)
    if (context != "dialog")
        return  ; 非目标窗口，不响应
    
    ; 3. 防抖：300ms 内不重复触发
    static lastTrigger := 0
    if (A_TickCount - lastTrigger < 300)
        return
    lastTrigger := A_TickCount
    
    ; 4. 触发路径收集与 UI 显示
    ShowPathSelector(activeHwnd)
}
```

**上下文检测规则**：

| 窗口类名 | 上下文类型 | 说明 |
|---------|-----------|------|
| `#32770` | dialog | 通用对话框（需进一步判断） |
| 其他 | none | 忽略 |

**对话框子判断**：`#32770` 类需要进一步判断是否为文件对话框：
- 优先检查控件结构，识别地址栏、编辑框、面包屑或典型导航控件
- 再结合窗口标题关键词做兜底判断
- 避免单纯依赖标题，降低不同语言和宿主应用下的误判率

**边缘情况**：
- 热键冲突：用户可能已将 Ctrl+G 绑定到其他程序 → 提供配置项修改热键
- 多显示器：菜单应显示在前景窗口附近，而非主显示器

**动态热键重载**：支持用户修改配置后无需重启程序

```autohotkey
; 重新注册热键（配置变更后调用）
ReloadHotkey() {
    global g_Config
    
    ; 清除旧热键
    try {
        Hotkey(g_Config.hotkey, , "Off")
    }
    
    ; 检查新热键是否已被其他程序占用
    if (IsHotkeyInUse(g_Config.hotkey)) {
        LogWarn("热键已被其他程序占用: " g_Config.hotkey)
        TrayTip("FolderJump", "热键冲突: " g_Config.hotkey " 已被其他程序使用", 3000)
        return false
    }
    
    ; 注册新热键
    Hotkey(g_Config.hotkey, OnCtrlG)
    LogInfo("热键已重载: " g_Config.hotkey)
    return true
}

; 检测热键是否被占用
IsHotkeyInUse(hotkeyStr) {
    ; 尝试注册热键，如果失败说明被占用
    try {
        Hotkey(hotkeyStr, (*) => {}, "On")
        Hotkey(hotkeyStr, , "Off")
        return false
    }
    return true
}

; 配置变更时触发热键重载
ReloadConfig() {
    global g_Config
    
    ; 重新加载配置
    g_Config := LoadConfig()
    
    ; 重载热键
    ReloadHotkey()
    
    LogInfo("配置已重新加载")
    TrayTip("FolderJump", "配置已重新加载", 2000)
}
```

---
### 3.2 Window Monitor

**职责**：定时检测所有打开的文件管理器窗口，收集路径列表。

**输入**：定时器触发（500ms）或手动刷新请求
**输出**：`PathEntry[]` 数组

**轮询策略**：

```autohotkey
; 定时器：每 500ms 刷新一次路径缓存
SetTimer RefreshPaths, 500

RefreshPaths() {
    global g_PathCache := []
    
    ; 1. 收集 Explorer 路径
    explorerPaths := CollectExplorerPaths()
    for p in explorerPaths
        g_PathCache.Push(p)
    
    ; 2. 收集 Total Commander 路径
    if (g_Config.enable_totalcmd) {
        tcPaths := CollectTotalCmdPaths()
        for p in tcPaths
            g_PathCache.Push(p)
    }
    
    ; 3. 收集 Directory Opus 路径
    if (g_Config.enable_dopus) {
        dopusPaths := CollectDOpusPaths()
        for p in dopusPaths
            g_PathCache.Push(p)
    }
    
    ; 4. 去重（相同路径只保留最新时间戳）
    g_PathCache := DeduplicatePaths(g_PathCache)
}
```

**性能优化**：
- 路径缓存仅在热键触发时强制刷新，定时器更新作为后备
- 使用 `A_TickCount` 做时间戳，避免 DateTime 开销
- 去重使用 Map 结构（O(n)），而非嵌套循环（O(n²)）

---

### 3.3 Explorer Adapter

**职责**：获取 Windows Explorer 已打开窗口的路径，并支持导航跳转。

#### 3.3.1 路径获取

**方法**：使用 `Shell.Application` COM 对象枚举所有打开的 Explorer 窗口。

```autohotkey
CollectExplorerPaths() {
    paths := []
    shell := ComObject("Shell.Application")
    
    for window in shell.Windows {
        try {
            ; 跳过非 Explorer 窗口（如 IE）
            if (window.LocationName = "")
                continue
            
            ; 获取文件夹路径
            folder := window.Document.Folder
            if (!IsSet(folder) || !folder)
                continue
            
            path := folder.Self.Path
            if (!path || path = "")
                continue
            
            ; 跳过虚拟文件夹
            if (IsVirtualFolder(path))
                continue
            
            paths.Push({
                path: path,
                source: "explorer",
                label: "Explorer",
                hwnd: window.hwnd,
                timestamp: A_TickCount
            })
        }
    }
    
    return paths
}

IsVirtualFolder(path) {
    ; 虚拟文件夹列表
    virtualPaths := [
        "::{20D04FE0-3AEA-1069-A2D8-08002B30309D}",  ; 此电脑
        "::{031E4825-7B94-4DC3-B131-E946B44C8DD5}",  ; 库
        "::{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}",  ; 网络
        "::{645FF040-5081-101B-9F08-00AA002F954E}"   ; 回收站
    ]
    for vp in virtualPaths {
        if (InStr(path, vp) = 1)
            return true
    }
    return false
}
```

**边缘情况**：
- **权限提升**：如果 Explorer 以管理员权限运行，而 FolderJump 以普通用户运行，COM 调用会失败 → 建议以相同权限运行，或在失败时降级为窗口标题解析
- **窗口标题降级**：COM 失败时，从 `window.LocationName` 提取路径（地址栏文本）
- **多标签窗口**：Windows 11 Explorer 支持多标签，每个标签对应一个独立的 `window` 对象，COM 枚举天然支持



---

### 3.4 Total Commander Adapter

**职责**：获取 Total Commander 双面板路径，支持跳转。

#### 3.4.1 窗口检测

```autohotkey
IsTotalCmdWindow(class) {
    return (class = "TTOTAL_CMD")
}
```

#### 3.4.2 路径获取

**方法一**（优先）：使用 `SendMessage(1074, 17/18)`

Total Commander 内部消息支持获取左右面板的活动和非活动面板句柄。通过发送特定消息获取到句柄后读取路径：

```autohotkey
GetTCPathsViaAPI(hwnd) {
    ; 通过 SendMessage 1074获取左右面板的活动 (17) 和非活动 (18) 路径控件句柄
    activePathHwnd := SendMessage(1074, 17, , , "ahk_id " hwnd)
    inactivePathHwnd := SendMessage(1074, 18, , , "ahk_id " hwnd)
    
    ; 通过坐标分析判断左右，并使用 ControlGetText 读取路径文本
    ...
}
```

**方法二**（兜底）：通过 `WinGetText` 枚举隐藏文本

如果在某些旧版 TC 中控件消息失败，通过获取整个窗口的隐藏文本，寻找包含结尾 `>` 且以驱动器号开头的路径：

```autohotkey
GetTCPathsViaWinGetText(hwnd) {
    ; 通过 WinGetText 获得窗口内部所有的文本（包括隐藏文本）
    ; 寻找以 '>' 结尾并带有路径特征的行作为备用途径
    ...
}
```

> **注意**：TC 面板因为不确定是由哪一侧处于活动状态，需要动态从控件位置推理，并附带了 `panelSide` 和 `panelRole` 信息供后续跳转使用。



---

### 3.5 Directory Opus Adapter

**职责**：获取 Directory Opus 所有标签页的路径，支持跳转。

#### 3.5.1 窗口检测

```autohotkey
IsDOpusWindow(class) {
    return (class = "dopus.lister" || class = "dopus.tab")
}
```

#### 3.5.2 路径获取

**方法一**（主用）：使用 `dopusrt.exe /info` 获取 XML 格式全量路径

```autohotkey
CollectDOpusPathsViaDOpusRT() {
    ; 使用 DOpusRT 输出 XML 临时文件
    RunWait('"' dopusrtPath '" /info "' tempFile '",paths', , "Hide")
    
    ; 使用 Msxml2.DOMDocument.6.0 解析 XML
    ; 检索 active_tab = "1" 和 side = "1" 或 "2"
    ; 获取每个可见页签的详细并构建 Label（区分左/右、可见/隐藏）
    ...
}
```

**方法二**（兜底）：窗口标题正则提取（降级方案）

如果 DOpusRT 执行失败，降级扫描 `ahk_class dopus.lister` 及 `dopus.tab` 的窗口。

```autohotkey
AddDOpusTitlePathEntry(paths, hwnd) {
    ; 获取 DOpus 窗口标题
    title := WinGetTitle("ahk_id " hwnd)
    
    ; 使用 DOpus 独特规则从 title 中清理 " - Directory Opus" 等提取真实路径
    path := ExtractPathFromDOpusTitle(title)
    ...
}
```

> **建议**：`DOpusRT` 命令是优先的且极其可靠，只要 DOpus 位于标准安装目录中便可执行。



---

### 3.6 Selection UI

**职责**：显示路径选择菜单，处理用户交互。

**设计要求**：
- 轻量级：仅使用 AHK 原生 Gui，无外部依赖
- 键盘友好：↑↓ 导航，Enter 确认，Esc 取消
- 智能定位：在前景窗口下方弹出
- 自动关闭：失焦或超时自动关闭

**UI 规格**：

```
┌─────────────────────────────────────────────┐
│ 🔍 FolderJump                    [×]        │
├─────────────────────────────────────────────┤
│ ▶ C:\Users\ZuoQi\Projects        Explorer   │
│   D:\Data\Reports                Explorer   │
│   C:\Downloads                   TC (左)    │
│   E:\Backup                      TC (右)    │
│   C:\Work\Documents              DOpus      │
├─────────────────────────────────────────────┤
│ ↑↓ 选择  |  Enter 确认  |  Esc 取消        │
└─────────────────────────────────────────────┘
```

**实现**：

```autohotkey
ShowPathSelector(context, activeHwnd) {
    global g_PathCache
    
    if (g_PathCache.Length = 0) {
        TrayTip("FolderJump", "没有打开的文件夹窗口")
        SetTimer(() => TrayTip(), -2000)
        return
    }
    
    ; 获取前景窗口位置
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " activeHwnd)
    
    ; 创建 GUI
    gui := Gui("+AlwaysOnTop +ToolWindow -Caption +Border")
    gui.BackColor := "1E1E2E"  ; 深色背景
    
    ; 标题栏
    gui.Add("Text", "x5 y5 w300 Center cFFFFFF", "FolderJump - 选择目标文件夹")
    
    ; 路径列表（ListBox）
    items := []
    for entry in g_PathCache {
        items.Push(entry.path "  [" entry.label "]")
    }
    
    listHeight := Min(items.Length * 25, 300)  ; 最多显示 12 项
    listBox := gui.Add("ListBox", "x5 y30 w390 h" listHeight " vPathList gPathListHandler", items)
    listBox.Choose(1)
    
    ; 底部提示
    gui.Add("Text", "x5 y+" 5 " w390 Center c888888", "↑↓ 选择  |  Enter 确认  |  Esc 取消")
    
    ; 调整窗口大小
    gui.Show("x" wx " y" (wy + wh + 5) " AutoSize")
    
    ; 绑定事件
    gui.OnEvent("Escape", (*) => {
        LogDebug("用户按 Escape 取消选择")
        gui.Destroy()
    })
    
    ; 失焦自动关闭
    gui.OnEvent("LoseFocus", (*) => {
        LogDebug("GUI 失焦，自动关闭")
        gui.Destroy()
    })
    
    ; 超时自动关闭（10 秒）
    autoCloseTimer := ObjBindMethod(gui, "Destroy")
    SetTimer(autoCloseTimer, -10000)
}

; ListBox 键盘事件处理器（g 标签方式）
PathListHandler(GuiCtrlObj, GuiEvent) {
    global g_PathCache, g_CurrentGui
    
    if (GuiEvent = "DoubleClick" || (GuiEvent = "Normal" && A_GuiEvent = "Enter")) {
        selectedIndex := GuiCtrlObj.Choice
        if (selectedIndex && g_PathCache[selectedIndex]) {
            entry := g_PathCache[selectedIndex]
            LogInfo("用户选择路径: " entry.path " [" entry.label "]")
            g_CurrentGui.Destroy()
            ExecutePathSwitch(entry)
        }
    }
}

ConfirmSelection(gui, listBox) {
    selectedIndex := listBox.Choice
    if (!selectedIndex)
        return
    
    global g_PathCache
    entry := g_PathCache[selectedIndex]
    LogInfo("用户选择路径: " entry.path " [" entry.label "]")
    gui.Destroy()
    
    ; 执行跳转
    ExecutePathSwitch(entry)
}

**主题支持**：

| 元素 | 深色主题 | 浅色主题 |
|------|---------|---------|
| 背景 | `#1E1E2E` | `#FFFFFF` |
| 文字 | `#FFFFFF` | `#333333` |
| 选中项背景 | `#3B82F6` | `#3B82F6` |
| 选中项文字 | `#FFFFFF` | `#FFFFFF` |
| 提示文字 | `#888888` | `#999999` |
| 边框 | `#333333` | `#CCCCCC` |

---

### 3.7 Path Switcher

**职责**：把选中的路径应用到当前文件对话框。

**输入**：选中的 `PathEntry` 对象
**输出**：跳转执行结果

```autohotkey
ExecutePathSwitch(entry, targetHwnd := 0) {
    if (!targetHwnd)
        targetHwnd := WinExist("A")
    if (!targetHwnd)
        return

    activeClass := WinGetClass(targetHwnd)

    ; 针对对话框调用对应的跳转函数
    if (activeClass = "#32770") {
        SwitchFileDialog(targetHwnd, entry.path)
    }
    else {
        SwitchFileDialogFallback(targetHwnd, entry.path)
    }
}
```

#### 文件对话框跳转

主要面向另存为、打开等 `#32770` 窗口，支持四层备选方案。

**方法一**（首选）：基于 `Edit1` 控件的超快无感替换
```autohotkey
TryNavigateFileDialogFast(hwnd, targetPath) {
    ; 这是最接近 Listary 体验的方式。
    ; 1. 给目标路径加上反斜杠，避免跳到对应文件。
    ; 2. 获取 Edit1 输入框并保存用户之前输入的文件名（如果是另存为操作）。
    ; 3. 直接通过 ControlSetText 将目标路径填入 Edit1 并发送 Enter 触发对话框内部跳转。
    ; 4. 毫秒级恢复之前保存的 Edit1 文件名，全程对用户肉眼无感。
    ...
}
```

**方法二**（次优）：基于智能分析直接向地址类型控件投递
```autohotkey
TryNavigateFileDialogByControl(hwnd, targetPath) {
    ; 遍历寻找类似地址栏的控件 （"breadcrumb" 或 "toolbarwindow32"）
    ; 或备用普通的编辑控件，填入并投递。
    ...
}
```

**方法三**（方案三）：借助快捷键切入地址栏
```autohotkey
TryNavigateFileDialogByShortcut(hwnd, targetPath) {
    ; 依次模拟对话框热键（Ctrl+L, Alt+D），聚焦到对话框的原生地址栏。
    ; 获取焦点后投递并确认。
    ...
}
```

**方法四**（最后兜底）：通用按键模拟
```autohotkey
SwitchFileDialogFallback(hwnd, targetPath) {
    ; Alt+D -> Ctrl+A -> Ctrl+V 黏贴路径 -> Enter，成功率极高但有可见交互。
    ...
}
```

---

### 3.8 Config Manager

**职责**：管理用户配置，支持热键自定义、开关控制等。

**配置文件格式**（INI）：

```ini
[general]
hotkey=^g
poll_interval=500
auto_close_timeout=10
theme=dark

[adapters]
enable_explorer=1
enable_totalcmd=1
enable_dopus=1

[ui]
show_source_label=1
max_items=12
sort_by=recent
position=below_window
```

**加载逻辑**：

```autohotkey
LoadConfig() {
    configPath := A_ScriptDir "\config.ini"
    
    g_Config := {
        hotkey: IniRead(configPath, "general", "hotkey", "^g"),
        poll_interval: IniRead(configPath, "general", "poll_interval", 500),
        auto_close_timeout: IniRead(configPath, "general", "auto_close_timeout", 10),
        theme: IniRead(configPath, "general", "theme", "dark"),
        enable_explorer: IniRead(configPath, "adapters", "enable_explorer", 1),
        enable_totalcmd: IniRead(configPath, "adapters", "enable_totalcmd", 1),
        enable_dopus: IniRead(configPath, "adapters", "enable_dopus", 1),
        show_source_label: IniRead(configPath, "ui", "show_source_label", 1),
        max_items: IniRead(configPath, "ui", "max_items", 12),
        sort_by: IniRead(configPath, "ui", "sort_by", "recent"),
        position: IniRead(configPath, "ui", "position", "below_window")
    }
    
    return g_Config
}
```

---

## 4. 数据结构

### 4.1 PathEntry

```
PathEntry := {
    path: string,        ; 完整文件系统路径，如 "C:\Users\ZuoQi\Projects"
    source: string,      ; 来源标识: "explorer" | "totalcmd" | "dopus"
    label: string,       ; 显示标签，如 "Explorer", "TC (active)", "DOpus"
    hwnd: integer,       ; 所属窗口句柄（用于跳转时定位）
    panel: string,       ; 面板标识（仅 TC 使用）: "left" | "right"
    timestamp: integer   ; 最后检测时间戳（A_TickCount），用于去重和排序
}
```

### 4.2 全局状态

```
g_Config := { ... }           ; 用户配置
g_PathCache := []             ; PathEntry 数组
g_CurrentGui := ""            ; 当前打开的 GUI 对象（用于强制关闭）
g_IsRefreshing := false       ; 刷新锁（防止并发刷新）
```

---

## 5. 集成点详述

### 5.1 Windows Explorer

| 集成方式 | 技术 | 可靠性 |
|---------|------|--------|
| 路径获取 | `Shell.Application` COM 枚举 `Windows` 集合 | 高 |
| 路径获取（降级） | 窗口标题解析 | 中 |
| 路径跳转 | `window.Navigate(path)` COM 方法 | 高 |
| 路径跳转（降级） | Alt+D → 粘贴 → Enter | 中 |

**COM 对象**：
- `Shell.Application` — 系统内置，无需额外安装
- `window.Document.Folder.Self.Path` — 获取路径
- `window.Navigate(path)` — 导航

### 5.2 Total Commander

| 集成方式 | 技术 | 可靠性 |
|---------|------|--------|
| 路径获取 | 内部窗口消息读取当前面板路径 | 高 |
| 路径获取（补充） | 路径控件文本分析 | 中 |
| 路径跳转 | 当前版本不作为热键直接触发目标 | — |
| 路径跳转（内部能力） | 面板切换 + 路径写入 | 中 |

**当前实现说明**：
- 当前会收集活动面板和非活动面板的路径
- UI 标签显示为 `TC (active)` / `TC (inactive)`
- 左右侧语义仍未完全稳定，因此不再展示 `left/right`

### 5.3 Directory Opus

| 集成方式 | 技术 | 可靠性 |
|---------|------|--------|
| 路径获取 | `DOpusRT /info ...,paths` | 高 |
| 路径获取（降级） | 窗口标题解析 | 中 |
| 路径跳转 | 当前版本不作为热键直接触发目标 | — |

**DOpusRT 命令**：
```
dopusrt.exe /cmd Go "C:\Target\Path"
```

---

## 6. 错误处理

### 6.1 错误场景与处理策略

| 场景 | 概率 | 处理策略 |
|------|------|---------|
| 没有打开的文件夹窗口 | 中 | 显示提示 "没有打开的文件夹窗口"，2s 后自动消失 |
| 目标路径不存在 | 低 | 跳转后验证地址栏，不匹配则提示 "路径不存在" |
| 权限不足（UAC） | 低 | 捕获 COM 异常，降级为键盘模拟方式 |
| COM 对象不可用 | 极低 | 所有 COM 调用包裹 try-catch，失败时降级 |
| 文件管理器未安装 | 中 | 配置中默认关闭，用户手动开启 |
| 热键被其他程序占用 | 低 | 启动时检测热键冲突，提示用户修改 |
| AHK 脚本被杀毒软件拦截 | 低 | 提供编译为 .exe 的方案，添加数字签名 |

### 6.2 降级策略

```
COM 方法（优先）
    │ 失败
    ▼
键盘模拟方法（降级）
    │ 失败
    ▼
提示用户 "跳转失败，请手动操作"
```

---

## 7. 配置

### 7.1 配置项总览

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `hotkey` | `^g` | 触发热键（AHK 格式） |
| `poll_interval` | `500` | 路径刷新间隔（ms） |
| `auto_close_timeout` | `10` | 菜单自动关闭时间（s） |
| `theme` | `dark` | UI 主题（dark/light） |
| `enable_explorer` | `1` | 启用 Explorer 支持 |
| `enable_totalcmd` | `1` | 启用 Total Commander 支持 |
| `enable_dopus` | `1` | 启用 Directory Opus 支持 |
| `show_source_label` | `1` | 显示来源标签 |
| `max_items` | `12` | 列表最大显示项数 |
| `sort_by` | `recent` | 排序方式（recent/alphabetical） |
| `position` | `below_window` | 菜单位置（below_window/center/cursor） |

### 7.2 配置热加载

配置文件修改后，下次热键触发时自动重新加载，无需重启程序。

---

## 8. 项目结构

```
folder-jump/
│
├── main.ahk                    # 入口文件
│   ├── #Requires AutoHotkey v2.0
│   ├── #SingleInstance Force
│   ├── 加载配置
│   ├── 注册热键
│   ├── 启动定时器
│   └── 主循环
│
├── lib/
│   ├── hotkey_manager.ahk      # 热键注册、上下文检测、防抖
│   ├── window_monitor.ahk      # 定时轮询、路径缓存管理
│   ├── path_collector.ahk      # 路径收集调度器
│   ├── selection_ui.ahk        # 浮动菜单 GUI
│   └── path_switcher.ahk       # 路径跳转执行
│
├── adapters/
│   ├── explorer.ahk            # Windows Explorer 适配器
│   ├── totalcmd.ahk            # Total Commander 适配器
│   └── dopus.ahk               # Directory Opus 适配器
│
├── config.ini                  # 用户配置文件
├── config.ini.example          # 配置模板
├── README.md                   # 使用说明
├── LICENSE                     # MIT License
│
└── build/
    └── build.bat               # 编译为 .exe 的脚本
```

### 8.1 模块依赖关系

```
main.ahk
├── lib/hotkey_manager.ahk
│   └── lib/window_monitor.ahk
│       ├── lib/path_collector.ahk
│       │   ├── adapters/explorer.ahk
│       │   ├── adapters/totalcmd.ahk
│       │   └── adapters/dopus.ahk
│       └── lib/selection_ui.ahk
│           └── lib/path_switcher.ahk
│               ├── adapters/explorer.ahk
│               ├── adapters/totalcmd.ahk
│               └── adapters/dopus.ahk
└── config.ini
```

---

## 9. 开发阶段

### Phase 1: MVP（核心功能）

**目标**：Explorer 支持 + 基本 UI + 热键触发

| 任务 | 预估工时 | 验收标准 |
|------|---------|---------|
| 项目骨架搭建 | 0.5h | 目录结构、配置文件、入口文件 |
| Hotkey Manager | 1h | Ctrl+G 注册、上下文检测、防抖 |
| Explorer Adapter | 2h | 路径获取（COM）、路径跳转（COM+降级） |
| Selection UI | 1.5h | ListBox 展示、键盘导航、自动关闭 |
| Path Switcher | 1h | 对话框跳转、Explorer 导航 |
| 集成测试 | 1h | 端到端流程验证 |

**总计**：~7 小时

### Phase 2: Total Commander 支持

| 任务 | 预估工时 | 验收标准 |
|------|---------|---------|
| TotalCmd Adapter | 2h | 路径获取（ini 文件）、跳转（Ctrl+D） |
| 双面板支持 | 0.5h | 左右面板路径分别显示 |
| 测试 | 0.5h | TC 端到端验证 |

**总计**：~3 小时

### Phase 3: Directory Opus 支持

| 任务 | 预估工时 | 验收标准 |
|------|---------|---------|
| DOpus Adapter | 2h | 路径获取（COM/标题）、跳转（DOpusRT） |
| 多标签支持 | 0.5h | 收集所有标签页路径 |
| 测试 | 0.5h | DOpus 端到端验证 |

**总计**：~3 小时

### Phase 4: 打磨与发布

| 任务 | 预估工时 | 验收标准 |
|------|---------|---------|
| 主题切换 | 1h | 深色/浅色主题 |
| 配置热加载 | 0.5h | 修改 config.ini 即时生效 |
| 编译打包 | 0.5h | 编译为独立 .exe |
| 文档完善 | 1h | README、配置说明、常见问题 |
| 性能优化 | 1h | 内存 < 5MB，CPU < 0.5% |

**总计**：~4 小时

**总工时预估**：~17 小时

---

## 10. 风险与缓解

### 10.1 技术风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| UAC 权限不匹配导致 COM 失败 | 高 | 低 | 降级为键盘模拟；建议用户以相同权限运行 |
| 文件对话框类型多样（现代/旧版） | 中 | 中 | 优先支持最常见的 `#32770` 类对话框；其他类型逐步适配 |
| TC/DOpus 版本差异导致 API 变化 | 中 | 低 | 使用最通用的集成方式（ini 文件、键盘模拟） |
| AHK v2 兼容性问题 | 低 | 低 | 明确标注要求 AHK v2.0+，提供运行时检查 |

### 10.2 性能风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| 频繁 COM 枚举导致 CPU 升高 | 中 | 低 | 500ms 间隔足够大；COM 调用包裹在 try 中 |
| 打开大量窗口导致路径列表过长 | 低 | 低 | 限制 max_items=12，支持滚动 |
| GUI 创建/销毁开销 | 低 | 极低 | AHK Gui 非常轻量，单次创建 < 10ms |

### 10.3 兼容性风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| Windows 11 多标签 Explorer | 中 | 中 | COM 枚举天然支持，每个标签是独立 window 对象 |
| 第三方文件管理器更新后类名变化 | 低 | 低 | 提供配置项自定义窗口类名 |
| 杀毒软件误报 AHK 脚本 | 中 | 低 | 编译为 .exe 并添加数字签名 |

---

## 11. 测试策略

### 11.1 测试矩阵

| 测试场景 | 环境 | 预期结果 |
|---------|------|---------|
| 单个 Explorer 窗口 | Win10 + Explorer | 菜单显示该窗口路径 |
| 多个 Explorer 窗口 | Win11 + 多标签 | 菜单显示所有路径 |
| 文件对话框跳转 | 任意应用 + 打开对话框 | 对话框跳转到目标路径 |
| TC 路径收集 | Total Commander 10+ | 列表显示 active / inactive 两条路径 |
| DOpus 多标签 | Directory Opus 12+ | 当前标签页路径可被稳定收集 |
| 无文件管理器窗口 | 干净桌面 | 提示"没有打开的文件夹窗口" |
| 路径不存在 | 目标路径已删除 | 提示"路径不存在" |
| 热键自定义 | 修改 config.ini | 新热键生效 |

### 11.2 内存测试

```autohotkey
; 监控自身内存占用
GetProcessMemory() {
    for process in WinGetProcessList("ahk_pid " DllCall("GetCurrentProcessId")) {
        ; 使用 PowerShell 获取工作集大小
        return ""
    }
}
```

目标：空闲时 ≤ 5MB，活跃时 ≤ 10MB。

---

## 12. 未来扩展

以下功能不在当前范围内，但架构上预留了扩展点：

| 功能 | 描述 | 实现难度 |
|------|------|---------|
| 模糊搜索 | 在路径列表中实时过滤 | 低（ListBox 自带过滤） |
| 收藏夹 | 保存常用路径 | 中（需要持久化存储） |
| 最近访问历史 | 记录跳转历史 | 低（追加写入日志） |
| XYplorer 支持 | 后续如有需要再补充 | 中 |
| 鼠标悬停预览 | 悬停显示文件夹内容 | 中（需要文件系统读取） |
| 网络路径支持 | UNC 路径跳转 | 低（路径处理兼容） |

---

## 附录 A: AHK v2 环境要求

| 项目 | 要求 |
|------|------|
| AutoHotkey | v2.0+ |
| Windows | 10/11 (x64) |
| 运行时依赖 | 无（纯 AHK 标准库） |
| 编译工具 | Ahk2Exe（AHK 自带） |

## 附录 B: 关键 Windows API 参考

| API | 用途 | 文档 |
|-----|------|------|
| `RegisterHotKey` | 全局热键注册 | WinUser.h |
| `GetForegroundWindow` | 获取前景窗口 | WinUser.h |
| `GetClassName` | 获取窗口类名 | WinUser.h |
| `ShellExecute` | 启动 Explorer | ShellAPI.h |

## 附录 C: 竞品对比

| 功能 | Listary | FolderJump (本方案) | QuickSwitch (AHK) |
|------|---------|---------------------|-------------------|
| Ctrl+G 跳转 | ✅ | ✅ | ✅ |
| 模糊搜索 | ✅ | ❌ (Phase 4 可选) | ❌ |
| Explorer 支持 | ✅ | ✅ | ✅ |
| Total Commander | ✅ | ✅ | ❌ |
| Directory Opus | ✅ | ✅ | ❌ |
| 内存占用 | ~30MB | ~5MB | ~8MB |
| 开源 | ❌ | ✅ | ✅ |
| 可定制热键 | ✅ | ✅ | ❌ |
| 独立运行 | ✅ | ✅ | ✅ |
