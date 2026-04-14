# FolderJump v1.0.4 Release Notes

**发布日期**: 2026-04-07  
**标签**: v1.0.4  
**对比**: [259ff38...v1.0.4](https://github.com/你的用户名/folder-jump/compare/259ff38...v1.0.4)

---

## 📋 概述

v1.0.4 主要关注于**修复 GitHub Actions 自动打包流程**。从 commit `259ff38` 开始，后续的所有提交几乎都只针对 CI/CD 自动打包问题，应用功能保持不变。本版本完全重构了编译和打包流程，现已稳定运行。

**对于最终用户**：此版本的核心功能与 v1.0.0 相同，但编译产物现在通过更可靠的自动化流程生成。

---

## 🔧 技术改进

### CI/CD 自动打包流程修复

本版本对 GitHub Actions 工作流进行了深度优化，解决了 6 个关键问题：

#### 1. **动态文件检测**
- **问题**：ZIP 包内部结构不确定，硬编码路径导致编译工具找不到
- **修复**：实现递归文件查找，自动定位 `AutoHotkey64.exe` 和 `Ahk2Exe.exe`，无论 ZIP 内部结构如何

#### 2. **编译参数优化**  
- **问题**：PowerShell 数组参数构建错误
- **修复**：纠正参数顺序和格式，确保 Ahk2Exe 接收正确的参数

#### 3. **版本依赖更新**
- **问题**：下载链接指向已删除的版本（AutoHotkey v2.0.18、Ahk2Exe 1.1.37.02）
- **修复**：更新至最新稳定版本（AutoHotkey v2.0.23、Ahk2Exe 1.1.37.02a2）

#### 4. **PowerShell 脚本优化**
- **问题**：复杂的管道处理导致语法错误
- **修复**：简化脚本逻辑，提高可读性和可维护性

#### 5. **数组处理修正**
- **问题**：PowerShell 数组索引返回字符串首字符而非整个对象
- **修复**：使用 `@()` 强制转换为数组，通过 `.FullName` 属性获取完整路径

#### 6. **结果验证改进**（最终关键修复）
- **问题**：依赖不可靠的 `$LASTEXITCODE`，尽管编译成功但仍报错
- **修复**：改为直接验证输出文件是否存在，更加健壮

---

## ✅ 提交历史

本版本沿用从 commit `259ff38` 开始的 CI 修复历史，以下提交均围绕 GitHub Actions 自动打包问题展开：

```
259ff38 - fix(build): 优化 AHK v2 打包脚本，修复 UTF-8 编码乱码及引号错误，添加 build.bat.example 并配置 .gitignore
60b79ff - feat(ci): 添加 GitHub Actions 自动发布流程及 AHK 编译器指令
26c5fa0 - fix(ci): 修正 GitHub Actions 路径和参数名错误
717c9b6 - fix(ci): 移除 main.ahk 中的无效指令，并在 GH Action 中添加 /cp 65001 参数
970a782 - refactor(ci): 重构自动化发布流程，弃用不稳定的三方 Action
e329fca - fix(ci): 使用正确的AutoHotkey和Ahk2Exe发布版本URL
c62677a - fix(ci): 修复PowerShell编译步骤的语法错误，简化引号处理
cba93e9 - fix(ci): 修复PowerShell数组处理，使用FullName属性获取完整路径
70eb4f7 - fix(ci): 移除不可靠的LASTEXITCODE检查，直接验证输出文件存在
```

完整历史可在本仓库的 `docs/build-script-fix-report.md` 中查看详细技术分析。

---

## 📦 安装

从 [Releases](https://github.com/你的用户名/folder-jump/releases) 页面下载 `FolderJump.exe`，或使用本地编译：

```powershell
cd build
.\build.bat
```

---

## 🙏 致谢

感谢所有使用 FolderJump 的用户，您的反馈和使用体验激励我们不断改进！

---

## 📝 其他说明

- **向后兼容**：与 v1.0.3 完全兼容
- **配置文件**：无需更新 `config.ini`
- **已知问题**：无
- **后续计划**：继续优化文件适配器性能

---

**下载**: [FolderJump.exe](https://github.com/你的用户名/folder-jump/releases/download/v1.0.4/FolderJump.exe)
