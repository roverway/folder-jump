# AGENTS.md — FolderJump

> AutoHotkey v2 Windows 路径切换工具。复刻 Listary 的 Ctrl+G 功能。

## AI 交互与代码生成规则
1. **强制中文注释**：所有代码行内注释、函数说明、模块文件头注释、git commit内容等都必须使用**简体中文**。
2. **禁止翻译文档**：绝对不允许将现有的中文文档（如 README.md, AGENTS.md）或中文注释翻译成英文。
3. 代码逻辑（变量、函数、类名）使用英文，但注释必须保留中文。
4. 所有文件编码都使用UTF-8 with BOM

## 快速命令

| 操作 | 命令 |
|------|------|
| 运行 | `AutoHotkey64.exe main.ahk`（或双击 `main.ahk` 如果已关联 .ahk 文件）|
| 编译为 .exe | `build\build.bat`（使用 Ahk2Exe，随 AHK 安装包提供）|
| 测试 | 手动测试 — 打开多个 Explorer 窗口，按 `Ctrl+G`，验证弹窗和导航功能 |
| 代码检查/格式化 | 未配置 — 请遵循下方代码风格指南 |
| 日志 | `logs\folder-jump.log`（自动轮转，最多 3 个备份，每个 1MB）|

### 手动测试清单
1. 打开 2 个或更多指向不同文件夹的 Explorer 窗口
2. 聚焦其中一个窗口，按 `Ctrl+G`
3. 验证弹窗中列出了所有打开的文件夹路径
4. 使用 ↑↓ + Enter 选择路径 → 验证导航成功
5. 按 Esc → 验证弹窗关闭
6. 在文件对话框（打开/保存）中测试 → 验证路径切换

## 项目结构

```
folder-jump/
├── main.ahk                    # 入口点 — 初始化序列，#Include 所有模块
├── config.ini.example          # 配置模板（复制为 config.ini）
├── lib/
│   ├── log_manager.ahk         # 带轮转功能的日志模块（无依赖）
│   ├── utils.ahk               # 通用工具函数（剪贴板保存/恢复）
│   ├── config_manager.ahk      # INI 配置文件加载（#Include log_manager）
│   ├── tray_manager.ahk        # 系统托盘图标和菜单（#Include log_manager）
│   ├── hotkey_manager.ahk      # 热键注册、上下文检测、防抖（#Include log_manager）
│   ├── window_monitor.ahk      # 基于定时器的路径缓存刷新（#Include log_manager, path_collector）
│   ├── path_collector.ahk      # 聚合所有适配器的路径（#Include log_manager, adapters/*）
│   ├── selection_ui.ahk        # 浮动 GUI 菜单（#Include log_manager, path_switcher）
│   └── path_switcher.ahk       # 路径导航执行（#Include log_manager, utils, adapters/*）
├── adapters/
│   ├── explorer.ahk            # Windows Explorer COM 适配器（#Include log_manager, utils）
│   ├── totalcmd.ahk            # Total Commander 双面板适配器（#Include log_manager, utils）
│   └── dopus.ahk               # Directory Opus 多标签适配器（#Include log_manager, utils）
├── build/
│   └── build.bat               # Ahk2Exe 编译脚本
└── logs/
    └── folder-jump.log         # 运行时日志（自动创建）
```

### 模块依赖顺序
```
main.ahk
  → log_manager（无依赖）
  → utils（无依赖）
  → config_manager（→ log_manager）
  → tray_manager（→ log_manager）
  → hotkey_manager（→ log_manager）
  → window_monitor（→ log_manager, path_collector）
  → selection_ui（→ log_manager, path_switcher）
    → path_switcher（→ log_manager, utils, adapters/*）
    → path_collector（→ log_manager, adapters/*）
      → adapters/explorer（→ log_manager, utils）
      → adapters/totalcmd（→ log_manager, utils）
      → adapters/dopus（→ log_manager, utils）
```

**规则**：`main.ahk` 按依赖顺序 #Include 模块。每个模块 #Include 自己的依赖。禁止添加循环 include。

## 代码风格

### 语言版本
- **仅限 AutoHotkey v2.0+**。禁止使用 v1 语法。
- 文件头：`#Requires AutoHotkey v2.0`（仅 main.ahk — 模块通过 #Include 继承）

### 文件结构
每个 `.ahk` 文件必须以以下内容开头：
```autohotkey
; ============================================================
; 模块名称 — FolderJump
; 模块职责描述（中文）
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"  ; 如果需要
```

### 命名规范
| 元素 | 规范 | 示例 |
|------|------|------|
| 全局变量 | `g_` 前缀 + PascalCase | `g_Config`, `g_PathCache` |
| 常量 | UPPER_SNAKE_CASE | `LOG_DEBUG`, `LOG_INFO` |
| 函数 | PascalCase | `CollectExplorerPaths()`, `DetectContext()` |
| 局部变量 | camelCase | `activeHwnd`, `targetPath` |
| 对象属性 | camelCase | `entry.path`, `entry.timestamp` |

### 函数规范
- 单行函数使用 `=>` 表达式语法：`LogDebug(msg) => LogWrite(LOG_DEBUG, msg)`
- 多行函数使用 `{}` 块语法
- 在函数内部访问全局变量必须使用 `global` 关键字
- 热键回调必须接受 `*`（可变参数）参数：`OnCtrlG(*) { ... }`
- COM 调用和文件 I/O 必须用 `try/catch` 包裹：
  ```autohotkey
  try {
      shell := ComObject("Shell.Application")
  } catch as err {
      LogError("COM 对象获取失败: " err.Message)
      return
  }
  ```

### 缩进与格式化
- **4 个空格**缩进（禁止使用 Tab）
- 左大括号 `{` 与函数/if/循环在同一行
- 单行 if/return 如果只有一条语句则不使用大括号：
  ```autohotkey
  if (!activeHwnd)
      return
  ```
- 多行对象：每行一个属性，缩进 4 个空格
- 字符串拼接：使用空格分隔，禁止使用 `.` 操作符：`"text " var " more"`

### 错误处理
- **禁止**使用 `@` 或静默失败来抑制错误
- 所有 COM 操作必须用 `try/catch as err` 包裹
- 所有文件操作必须用 `try` 包裹（日志可能在只读介质上）
- 使用适当的日志级别：`LogError` 表示失败，`LogWarn` 表示降级模式，`LogDebug` 表示流程跟踪
- 回退链：COM → 键盘模拟 → 用户通知

### 全局状态
所有全局变量在 `main.ahk` 中声明。模块通过 `global` 关键字访问：
```autohotkey
; main.ahk
g_Config := {}
g_PathCache := []

; 在任何模块函数中：
SomeFunction() {
    global g_Config, g_PathCache
    ; ... 使用它们
}
```

### 注释规范
- 模块级注释使用中文（职责描述）
- 代码行内注释使用中文解释逻辑
- 错误消息：TrayTip 使用中文，日志条目使用英文
- 主要部分之间使用分隔线（`; ===...`）

### 添加新适配器
1. 在 `adapters/` 下创建 `adapters/<name>.ahk`
2. 实现：`Collect<Name>Paths()` 返回 `PathEntry[]`，`Navigate<Name>(hwnd, targetPath)`
3. 包含 `#Include "%A_ScriptDir%\lib\log_manager.ahk"` 和 `#Include "%A_ScriptDir%\lib\utils.ahk"`
4. 在 `path_collector.ahk` 的 `CollectAllPaths()` 中注册
5. 在 `path_switcher.ahk` 的 `ExecutePathSwitch()` 中添加跳转逻辑
6. 在 `config.ini.example` 的 `[adapters]` 下添加配置开关
7. 在 `hotkey_manager.ahk` 的 `DetectContext()` 中添加上下文检测

### PathEntry 对象结构
```autohotkey
{
    path: string,        ; 完整文件系统路径
    source: string,     ; "explorer" | "totalcmd" | "dopus"
    label: string,      ; 显示标签，例如 "Explorer", "TC (左)"
    hwnd: integer,      ; 窗口句柄（不可用时为 0）
    panel: string,      ; "left" | "right"（仅 TC，可选）
    timestamp: integer  ; 收集时的 A_TickCount
}
```
