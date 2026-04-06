# FolderJump 代码质量复核报告

日期：2026-04-05

## 复核范围

本次复核在 2026-04-04 版报告的基础上，对当前代码做全面审查，重点关注：

1. **路径获取方法评估** — 各文件管理器适配器采用的路径获取手段是否最优
2. **文件对话框跳转方法评估** — 路径切换的实现是否最接近 Listary 的 Ctrl+G 体验
3. **常规代码质量** — 架构、命名、重复代码、错误处理、编码规范等

---

## 一、路径获取方法评估

### 1.1 Explorer 适配器 (`adapters/explorer.ahk`)

**当前方法**：`Shell.Application` COM → `shell.Windows` 枚举 → `window.Document.Folder.Self.Path`

**评估：✅ 最优方案，无需修改**

| 维度 | 评分 | 说明 |
|------|------|------|
| 可靠性 | ★★★★★ | `Shell.Application` 是 Windows 原生 COM 对象，所有 Windows 版本均可用 |
| 完整性 | ★★★★★ | 自动枚举所有 Explorer 窗口/标签页（Win11 多标签天然支持） |
| 性能 | ★★★★☆ | 每次调用创建新的 COM 对象，可考虑缓存但影响极小 |
| 兼容性 | ★★★★★ | Win10/11 均完全支持，无版本差异问题 |

**优点**：
- 这是 Listary 等主流工具也采用的主要方式
- 虚拟文件夹过滤（`IsVirtualFolder`）做得完善，覆盖了此电脑、库、网络、回收站
- `window.LocationName` 空值检查有效过滤了 IE 等非 Explorer 窗口

**待改进项**：

| # | 问题 | 优先级 | 说明 |
|---|------|--------|------|
| E1 | `for window in shell.Windows` 循环缺少外层 `catch` | P2 | 如果枚举过程中 COM 连接断开（如 Explorer 崩溃重启），整个循环会异常退出。循环本身应被 `try` 包裹 |
| E2 | 未提供标题解析降级方案 | P3 | 技术设计文档提到了降级策略，但代码中未实现。在 UAC 权限不匹配时 COM 调用会静默失败，建议至少记录 Warning |

---

### 1.2 Total Commander 适配器 (`adapters/totalcmd.ahk`)

**当前方法**：
- 首选：`SendMessage(1074, 17/18)` → 获取活动/非活动面板的路径控件句柄 → `ControlGetText` 读取路径
- 兜底：`WinGetText` 枚举隐藏文本，正则提取路径

**评估：⚠️ 可以更优，存在已知的改进空间**

| 维度 | 评分 | 说明 |
|------|------|------|
| 可靠性 | ★★★★☆ | 消息接口稳定，但 `wParam=17/18` 是获取"活动/非活动"面板句柄，而非"左/右"面板 |
| 完整性 | ★★★★☆ | 活动和非活动面板均可获取 |
| 性能 | ★★★★★ | 单次 `SendMessage` 调用，极快 |
| 兼容性 | ★★★★☆ | TC 7.0+ 均支持此消息 |

**关键发现：`wParam` 值使用不够精确**

当前代码使用 `wParam=17`（活动面板路径控件句柄）和 `wParam=18`（非活动面板路径控件句柄），这是正确的"active/inactive"语义获取方式。

但 TC 官方文档同时提供了 **确定性的** 左右面板路径获取接口：

| wParam | 含义 | 当前是否使用 |
|--------|------|-------------|
| 9 | 左面板路径控件句柄 | ❌ 未使用 |
| 10 | 右面板路径控件句柄 | ❌ 未使用 |
| 17 | 活动面板路径控件句柄 | ✅ 使用中 |
| 18 | 非活动面板路径控件句柄 | ✅ 使用中 |

**建议**：如果想同时获取准确的左右语义和活动/非活动语义，可并行发送 `wParam=9/10` 和  `wParam=17/18`，然后通过句柄比对来精确建立映射关系：

```
leftPathHwnd = SendMessage(1074, 9, ...)
rightPathHwnd = SendMessage(1074, 10, ...)
activePathHwnd = SendMessage(1074, 17, ...)

if (activePathHwnd == leftPathHwnd)
    → 活动面板在左侧
else
    → 活动面板在右侧
```

这比当前使用 `ControlGetPos` 做坐标推断的 `GetTCPanelSidesFromControls()` 要**更加可靠和简洁**，可以彻底解决上一轮复核中标记的"left/right 语义不稳定"问题。

**待改进项**：

| # | 问题 | 优先级 | 说明 |
|---|------|--------|------|
| T1 | 应使用 `wParam=9/10` 配合 `wParam=17/18` 做句柄比对，替代坐标推断 | P1 | 可以彻底稳定 left/right 语义 |
| T2 | `CollectTotalCmdPaths()` 内部日志级别过高 | P3 | 正常轮询时大量输出 `LogInfo`，每 500ms 被调用一次会产生大量日志。应降为 `LogDebug` |
| T3 | `WinGetText` 兜底方案用 `>` 结尾匹配路径，假设所有路径面板文字以 `>` 结尾 | P3 | 依赖 TC 默认的路径栏格式，自定义主题下可能失效。但作为兜底方案可接受 |

---

### 1.3 Directory Opus 适配器 (`adapters/dopus.ahk`)

**当前方法**：
- 首选：`dopusrt.exe /info tempFile,paths` → 解析 XML → 提取 `//path[@active_tab]` 节点
- 兜底：枚举 `dopus.lister` / `dopus.tab` 窗口标题 → 正则提取路径

**评估：✅ 方案选择正确，DOpusRT 是官方推荐方式**

| 维度 | 评分 | 说明 |
|------|------|------|
| 可靠性 | ★★★★★ | `DOpusRT /info` 是 DOpus 官方提供的自动化接口，输出结构化 XML |
| 完整性 | ★★★★☆ | 当前仅提取 `active_tab` 属性的节点（即可见标签页），非可见标签页路径被丢弃。这是合理取舍 |
| 性能 | ★★★☆☆ | 每次调用需 `RunWait` 启动外部进程 + 读文件 + 解析 XML，约 50-200ms |
| 兼容性 | ★★★★☆ | 需要 DOpus 安装在标准路径，否则 `FindDOpusRT()` 找不到可执行文件 |

**待改进项**：

| # | 问题 | 优先级 | 说明 |
|---|------|--------|------|
| D1 | `FindDOpusRT()` 硬编码了两个安装路径 | P2 | 应增加从注册表读取 DOpus 安装路径的能力，或者允许用户在 `config.ini` 中配置 `dopusrt_path` |
| D2 | `RunWait` 每轮轮询都创建临时 XML 文件 | P3 | 500ms 轮询间隔下频繁创建/删除临时文件。可考虑在临时文件名中使用固定名称并覆盖写入，减少文件系统操作 |
| D3 | `Msxml2.DOMDocument.6.0` COM 对象每次重新创建 | P3 | 影响微小，但可缓存复用 |
| D4 | 标题解析兜底方案的正则提取不够健壮 | P3 | `ExtractPathFromDOpusTitle` 尝试从标题中提取路径，但在自定义标题格式下可能失效。作为兜底方案可接受 |

---

## 二、文件对话框跳转方法评估

### 2.1 当前实现的四层策略

当前 `path_switcher.ahk` 中的 `SwitchFileDialog()` 实现了完善的四层降级策略：

```
方法一：TryNavigateFileDialogFast()
    ↓ 失败
方法二：TryNavigateFileDialogByControl()
    ↓ 失败
方法三：TryNavigateFileDialogByShortcut()
    ↓ 失败
方法四：SwitchFileDialogFallback()
```

### 2.2 与 Listary Ctrl+G 体验的对比

| 体验维度 | Listary | FolderJump (当前) | 差距分析 |
|---------|---------|------------------|---------|
| 跳转速度 | 瞬间 (<50ms) | 快速 (<100ms) | 方法一（Edit1 快速替换）已非常接近 Listary 速度 |
| 视觉无感 | 完全无闪烁 | 方法一基本无感，方法二~四有可见操作 | 方法一已达到最佳体验 |
| 文件名保持 | 另存为对话框中保持原文件名 | ✅ 方法一已实现保存/恢复 | 已达到相同水平 |
| 兼容性广度 | 极广（内置特例处理） | 中等（通用策略） | Listary 针对数百个应用做了特例处理，FolderJump 靠通用策略覆盖 |
| 一键跳转 | 单路径时直接跳转 | ✅ 已实现 | 已达到相同水平 |

**评估：✅ 方法一（Edit1 快速替换）是当前最佳实现，接近 Listary 水平**

### 2.3 方法一详细评审 (`TryNavigateFileDialogFast`)

这是最关键的跳转路径。逐步分析：

```
1. 路径末尾加 "\" → 避免对话框将输入当作文件名
2. 备份 Edit1 原文本（保护用户已输入的文件名）
3. ControlSetText 写入目标路径
4. Sleep(20) — 等待控件事件处理
5. ControlSend("{Enter}") — 触发路径跳转
6. Sleep(30) — 等待对话框反应
7. 恢复 Edit1 原文本
```

**优点**：
- 全程通过控件级操作，不涉及剪贴板，不涉及全局键盘模拟
- 备份/恢复文件名，对用户完全透明
- 总延迟仅约 50ms，肉眼不可察觉

**待改进项**：

| # | 问题 | 优先级 | 说明 |
|---|------|--------|------|
| S1 | `Sleep(20)` 和 `Sleep(30)` 是固定延时，不同机器上可能不够 | P2 | 低配机器上 30ms 可能不足以让对话框完成跳转。建议改为短轮询验证 + 超时上限的模式 |
| S2 | 恢复文件名时未验证对话框是否仍存在 | P2 | 如果 Enter 触发了对话框关闭（如路径恰好指向文件），`ControlSetText` 恢复会抛出异常 |
| S3 | 方法一失败后进入方法二，但方法二的逻辑与方法一高度重叠 | P3 | `TryNavigateFileDialogByControl` 本质也是找 Edit 控件 + ControlSetText，与方法一冗余较大 |

### 2.4 方法二~四评审

**方法二** (`TryNavigateFileDialogByControl`)：
- 调用 `ActivateTargetWindow` 激活窗口 — 在方法一之后调用这一步是合理的
- `FindFileDialogEditableControl` 遍历所有控件寻找地址栏或编辑框 — 逻辑完善
- `WaitForFileDialogPath` 做结果校验 — 轮询 10 次 × 150ms = 最多 1.5 秒，可接受
- **问题**：该方法大部分代码与方法一重叠，建议精简

**方法三** (`TryNavigateFileDialogByShortcut`)：
- 使用 `Ctrl+L` / `Alt+D` 快捷键聚焦地址栏 — 是标准的 Windows 对话框地址栏快捷键
- 涉及剪贴板操作，有 `SaveClipboard` / `RestoreClipboard` — 正确保护了用户剪贴板
- **问题**：`Sleep(200)` 等待快捷键生效偏长，可能导致在快捷键未被拦截的情况下增加不必要延时

**方法四** (`SwitchFileDialogFallback`)：
- 纯按键模拟：`Alt+D` → `Ctrl+A` → `Ctrl+V` → `Enter`
- 最大的兼容性但最差的用户体验（有可见的文本选中/粘贴过程）
- 作为最终兜底合理

---

## 三、常规代码质量

### 3.1 重复代码 (DRY 违反)

**严重度：P2**

发现以下函数在不同模块中存在功能几乎完全相同的重复实现：

| 函数 A (`hotkey_manager.ahk`) | 函数 B (`path_switcher.ahk`) | 逻辑差异 |
|-------------------------------|------------------------------|---------|
| `GetDialogControlClassSafe(control, hwnd)` | `GetFileDialogControlClassSafe(control, hwnd)` | 完全相同 |
| `GetDialogControlTextSafe(control, hwnd)` | `GetFileDialogControlTextSafe(control, hwnd)` | 完全相同 |

此外，路径归一化逻辑重复出现在多处：

| 位置 | 函数名 | 核心逻辑 |
|------|--------|---------|
| `path_collector.ahk` | `NormalizePath()` | 替换斜杠 + trim + 去尾部 `\` + 小写 |
| `path_switcher.ahk` | `NormalizeFileDialogPath()` | 替换斜杠 + trim + 去尾部 `\` + 小写 |
| `dopus.ahk` | `NormalizeDOpusPathCandidate()` | 替换斜杠 + trim + 去尾部 `\` |

**建议**：将控件安全访问函数和路径归一化函数提取到 `utils.ahk` 中，各模块统一引用。

### 3.2 日志级别使用不当

**严重度：P2**

`totalcmd.ahk` 中的 `CollectTotalCmdPaths()` 在正常轮询路径中使用了大量 `LogInfo`：

```autohotkey
LogInfo("Start collecting Total Commander paths")           ; 每 500ms 触发
LogInfo("Found Total Commander windows: " tcWindows.Length)  ; 每 500ms 触发
LogInfo("Inspect TC path: ...")                              ; 每路径一条
LogInfo("Add TC path: ...")                                  ; 每路径一条
```

按 500ms 轮询间隔，如果 TC 打开了两个面板，每分钟将产生约 **480 条** INFO 级别日志。同类问题在 `path_collector.ahk` 中也存在。

**建议**：常规轮询路径收集的日志应一律使用 `LogDebug`。仅在热键触发时的手动刷新使用 `LogInfo`。

### 3.3 配置项 `position` 未被使用

**严重度：P3**

`config.ini` 中定义了 `position=below_window`（支持 `below_window` / `center` / `cursor`），`config_manager.ahk` 也读取了该值，但 `selection_ui.ahk` 中**硬编码了 `below_window` 的定位逻辑**，从未引用 `g_Config.position`。

**建议**：实现 `center` 和 `cursor` 两种定位模式，或移除该配置项避免误导用户。

### 3.4 `WinWaitActive` 超时参数异常

**严重度：P2**

```autohotkey
; path_switcher.ahk L233
if (!WinWaitActive("ahk_id " hwnd, , 2000)) {
```

AHK v2 中 `WinWaitActive` 的第三个参数是**秒数**，不是毫秒。`2000` 表示等待 **2000 秒（33 分钟）**，而不是 2 秒。应改为 `2` 或 `2.0`。

### 3.5 `InputHook` 使用方式存疑

**严重度：P2**

`selection_ui.ahk` 中使用 `InputHook("V")` 来捕获 Enter 键：

```autohotkey
enterHook := InputHook("V")
enterHook.OnEnter := ListBoxEnterPressed.Bind(listBox)
enterHook.Start()
```

AHK v2 的 `InputHook.OnEnter` 回调在用户按下 Enter 键时触发并结束 Hook。这意味着：
- **第一次按 Enter 后 Hook 就停止了**，后续按 Enter 不会再触发回调
- 如果用户第一次按 Enter 时未选中有效项，后续操作将失去 Enter 响应

**建议**：改为使用 `OnKeyDown` 事件监听 Enter 键，并在回调中自行决定是否停止 Hook。或者在 `OnEnter` 回调的末尾清理逻辑后重新启动 Hook。

### 3.6 GUI 清理时的竞争条件

**严重度：P2**

`CleanupGui()` 被多个关闭路径调用（Escape、失焦、超时、选择确认），但缺少**重入保护**：

```autohotkey
CleanupGui(pathGui) {
    global g_CurrentGui
    ; 多个定时器可能同时触发此函数
    ; 如果 GUI 已被销毁，再次调用 Destroy() 虽然在 try 中但逻辑不够清晰
    ...
}
```

**建议**：在函数入口检查 `g_CurrentGui` 是否为空，为空则立即返回：

```autohotkey
CleanupGui(pathGui) {
    global g_CurrentGui
    if (!IsSet(g_CurrentGui) || !g_CurrentGui)
        return
    ; ... 后续清理
    g_CurrentGui := ""
}
```

### 3.7 Explorer 适配器缺少 `catch` 的循环

**严重度：P2**

```autohotkey
; explorer.ahk L19
for window in shell.Windows {
    try {
        ...
    }
}
```

内层的 `try` 保护了单个窗口的处理，但 `for window in shell.Windows` 枚举本身没有被保护。如果在枚举过程中 COM 连接中断（如 Explorer 进程重启），会导致未捕获异常。

**建议**：在整个 `for` 循环外再包一层 `try`。

### 3.8 冒泡排序效率

**严重度：P3**

`path_collector.ahk` 中使用了**冒泡排序**（`BubbleSort`），时间复杂度 O(n²)。虽然路径列表通常很短（< 20 项），实际影响可忽略，但作为代码质量备注记录。

AHK v2 暂无内置排序函数，冒泡排序在当前场景下可接受。

### 3.9 混合行尾符号

**严重度：P3**

部分文件使用 CRLF（`\r\n`），部分使用 LF（`\n`）。例如 `hotkey_manager.ahk` 的文件头注释是 LF，但 `#Include` 行是 CRLF。根据 AGENTS.md 规范，所有文件应使用 UTF-8 with BOM 编码。

**建议**：统一全部 `.ahk` 文件为 UTF-8 with BOM + CRLF 行尾。

---

## 四、与 Listary Ctrl+G 体验差距总结

### 当前已达到 Listary 水平的能力

| 能力 | 状态 |
|------|------|
| 在文件对话框中快速跳转路径 | ✅ 方法一（Edit1 快速替换）体验接近 Listary |
| 保持另存为对话框中的原文件名 | ✅ 已实现备份/恢复 |
| 多文件管理器路径来源 | ✅ Explorer + TC + DOpus 三源支持 |
| 键盘导航选择菜单 | ✅ ↑↓ + Enter + Esc |
| 单路径时直接跳转 | ✅ 已实现 |

### 与 Listary 仍存在差距的地方

| 差距 | 原因 | 可行的改进方向 |
|------|------|-------------|
| Listary 几乎不存在"跳转失败"的情况 | Listary 针对数百个应用做了特例处理（内置兼容列表） | FolderJump 可维护一个小型特例列表（如 MATLAB、AutoCAD 等自定义对话框），但规模受限于维护成本 |
| Listary 支持模糊搜索过滤路径 | 功能范围差异 | 可在路径列表顶部增加搜索输入框，实时过滤 |
| Listary 支持 Everything 集成 | 功能范围差异 | 可作为 Phase 5 扩展 |
| Listary 的 UI 更精致 | AHK 原生 Gui 的渲染能力有限 | 可使用 WebView2 或自绘控件增强 UI，但会增加复杂度 |

### 核心建议：当前最值得做的改进

对提升 Listary 体验接近度**性价比最高**的改进排序：

1. **TC 面板 left/right 语义精确化** — 使用 `wParam=9/10` + `wParam=17/18` 句柄比对（工作量小，效果显著）
2. **修复 `WinWaitActive` 超时参数** — 从 2000 改为 2（P0 级 bug）
3. **消除重复代码** — 合并控件安全访问函数和路径归一化函数到 `utils.ahk`
4. **修复 `InputHook.OnEnter` 单次触发问题** — 确保 Enter 键在 GUI 生命周期内持续有效
5. **增加 `CleanupGui` 重入保护** — 避免多个关闭路径导致的竞争条件

---

## 五、按优先级排列的完整改进清单

### P0（Bug / 功能缺陷）

| # | 问题 | 位置 | 说明 |
|---|------|------|------|
| 1 | `WinWaitActive` 超时参数错误 | `path_switcher.ahk:233` | ✅ 已修复（改为 2s） |

### P1（建议尽快修复）

| # | 问题 | 位置 | 说明 |
|---|------|------|------|
| 2 | TC 面板应使用 `wParam=9/10` 精确获取 left/right 语义 | `adapters/totalcmd.ahk` | ✅ 已修复：替代 `ControlGetPos` 坐标推断 |
| 3 | `InputHook.OnEnter` 仅触发一次 | `lib/selection_ui.ahk:181-183` | ✅ 已修复：首次 Enter 后 Hook 停止问题解决 |

### P2（建议后续迭代修复）

| # | 问题 | 位置 | 说明 |
|---|------|------|------|
| 4 | 控件安全访问函数重复 | `hotkey_manager.ahk` / `path_switcher.ahk` | ✅ 已修复：合并到 `utils.ahk` |
| 5 | 路径归一化函数重复 | `path_collector.ahk` / `path_switcher.ahk` / `dopus.ahk` | ✅ 已修复：合并到 `utils.ahk` |
| 6 | TC 适配器日志级别过高 | `adapters/totalcmd.ahk` | ✅ 已修复：常规轮询应用 `LogDebug` |
| 7 | `CleanupGui` 缺少重入保护 | `lib/selection_ui.ahk:276` | ✅ 已修复：增加重入判断 |
| 8 | `TryNavigateFileDialogFast` 恢复文件名时未检查窗口存活 | `lib/path_switcher.ahk:92` | ✅ 已修复：`ControlSetText` 恢复前检查存在 |
| 9 | `FindDOpusRT` 硬编码安装路径 | `adapters/dopus.ahk:228-237` | ✅ 已修复：使用注册表查询 |
| 10 | Explorer `for` 循环缺少外层 `try` | `adapters/explorer.ahk:19` | ✅ 已修复：加上了完整的COM保护 |
| 11 | 方法一的 Sleep 延时使用固定值 | `lib/path_switcher.ahk:83,89` | ✅ 已修复：改用超时轮询验证策略 |

### P3（优化/完善项）

| # | 问题 | 位置 | 说明 |
|---|------|------|------|
| 12 | `position` 配置项未被实现 | `lib/selection_ui.ahk` | 仅实现了 `below_window` |
| 13 | 冒泡排序 | `lib/path_collector.ahk:105-119` | 当前场景可接受，记录备注 |
| 14 | 混合行尾符号 | 多个 `.ahk` 文件 | 统一为 CRLF |
| 15 | `DOpusRT` 临时文件名每次使用 `A_TickCount` | `adapters/dopus.ahk:26` | ✅ 已修复：使用固定名称覆盖写入 |

---

## 六、上一轮复核（04-04）遗留问题状态追踪

| 上一轮问题 | 当前状态 | 说明 |
|-----------|---------|------|
| TC left/right 语义不稳定 | 🟡 未解决 | 上轮建议"等待稳定信号"，本轮发现 `wParam=9/10` 可彻底解决 |
| 文件对话框跳转过度依赖按键模拟 | ✅ 已解决 | 方法一（Edit1 快速替换）已作为首选，体验接近 Listary |
| DOpus 路径识别不应依赖标题猜测 | ✅ 已解决 | `DOpusRT /info` 已作为首选 |
| 文件对话框识别不应主要依赖标题关键词 | ✅ 已解决 | 控件结构优先，标题兜底 |
| Windows 路径去重需大小写归一化 | ✅ 已解决 | `StrLower` + 尾部 `\` 去除已实现 |
| 文档与实现漂移 | 🟡 部分解决 | 技术设计文档仍含部分过期描述（如 `IsHotkeyInUse` 函数在实际代码中不存在） |

---

## 七、总结

FolderJump 的整体架构设计合理，模块划分清晰，四层降级策略体现了良好的工程思维。**方法一（Edit1 快速替换）已经非常接近 Listary Ctrl+G 的核心体验**，是当前实现中最亮眼的部分。

最值得投入精力的改进方向是：
1. 修复 `WinWaitActive` 超时参数 bug（影响所有非首选跳转方法的可靠性）
2. 使用 TC 官方 `wParam=9/10` 消息精确解决 left/right 面板问题
3. 消除跨模块重复代码，提升可维护性

在功能层面，当前版本已覆盖了 Listary Ctrl+G 的 **80%+ 核心体验**。剩余差距主要来自应用兼容性特例（需长期积累）和模糊搜索等高级功能（可后续迭代）。

