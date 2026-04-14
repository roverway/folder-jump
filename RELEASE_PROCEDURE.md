# v1.0.4 发布步骤 — 完整操作指南

## 第一步：本地操作 — 创建正式版本标签

```powershell
# 1. 删除临时测试标签
git tag -d v1.0.4-test
git push origin :v1.0.4-test

# 2. 创建正式版本标签（指向当前 HEAD）
git tag v1.0.4

# 3. 添加带注释的标签（可选，但推荐）
git tag -a v1.0.4 -m "Release v1.0.4: FolderJump GitHub Actions CI/CD 修复"

# 4. 推送标签到远程
git push origin v1.0.4

# 5. 验证
git tag -l | grep v1.0.4
git log --oneline -1
```

---

## 第二步：在 GitHub 上创建 Release

### 方法 A：使用 GitHub Web 界面（推荐，更直观）

1. 打开仓库的 Releases 页面：  
   `https://github.com/你的用户名/folder-jump/releases`

2. 点击 **"Draft a new release"** 按钮

3. 填写表单：
   - **Tag version**: 选择 `v1.0.4` （下拉菜单中选择）
   - **Release title**: `v1.0.4 - GitHub Actions 自动打包修复`
   - **Description**: 复制下方的 Release Notes 内容

4. 在 **Description** 框中粘贴以下内容：

```markdown
# v1.0.4 Release Notes

**发布日期**: 2026-04-07  
**重点**: 完全修复 GitHub Actions 自动打包流程

## 📋 概述

v1.0.4 主要关注于修复 GitHub Actions 自动打包流程。自 commit `259ff38` 之后，后续的所有提交几乎都只针对 CI/CD 自动打包问题，应用功能保持不变。本版本已完全重构编译和打包流程，现已稳定运行。

**对于最终用户**：此版本的核心功能与 v1.0.0 相同，但编译产物现在通过更可靠的自动化流程生成。

## 🔧 技术改进

### CI/CD 自动打包流程修复 (6 大问题解决)

1. **动态文件检测** - ZIP 包内部结构自适应
2. **编译参数优化** - PowerShell 数组参数正确化
3. **版本依赖更新** - AutoHotkey v2.0.23、Ahk2Exe 1.1.37.02a2
4. **PowerShell 脚本优化** - 简化复杂管道处理
5. **数组处理修正** - 使用 .FullName 获取完整路径
6. **结果验证改进** - 直接验证输出文件而非依赖退出码

## 📝 提交历史

- `e329fca` - 使用正确的AutoHotkey和Ahk2Exe发布版本URL
- `c62677a` - 修复PowerShell编译步骤的语法错误
- `cba93e9` - 修复PowerShell数组处理
- `70eb4f7` - 移除不可靠的LASTEXITCODE检查

完整技术分析见: `docs/build-script-fix-report.md`

## ✅ 向后兼容

- 与 v1.0.3 完全兼容
- 无需更新 config.ini
- 已知问题：无

## 📥 安装

从本页面下载 `FolderJump.exe` 或本地编译：
```
cd build && .\build.bat
```
```

5. 选择 **"This is a pre-release"**（如果不是正式稳定版）或保持未选中

6. 点击 **"Publish release"**

---

### 方法 B：使用 GitHub CLI（命令行，速度快）

如果已安装 GitHub CLI：

```powershell
# 生成 Release 的内容（可选，直接 piping）
$releaseNotes = @"
# v1.0.4 Release Notes

**发布日期**: 2026-04-07  
**重点**: 完全修复 GitHub Actions 自动打包流程

## 🔧 技术改进

自 v1.0.3 以来，修复了 6 个 CI/CD 中的关键问题：

1. 动态文件检测 - ZIP 包内部结构自适应
2. 编译参数优化 - PowerShell 数组参数正确化  
3. 版本依赖更新 - AutoHotkey v2.0.23、Ahk2Exe 1.1.37.02a2
4. PowerShell 脚本优化 - 简化复杂管道处理
5. 数组处理修正 - 使用 .FullName 获取完整路径
6. 结果验证改进 - 直接验证输出文件

完整技术分析见: `docs/build-script-fix-report.md`

## ✅ 向后兼容
- 与 v1.0.3 完全兼容
- 无需更新 config.ini

"@

# 创建 Release
gh release create v1.0.4 --title "v1.0.4 - GitHub Actions 自动打包修复" --notes $releaseNotes
```

---

## 第三步：验证发布

1. 访问：`https://github.com/你的用户名/folder-jump/releases/tag/v1.0.4`

2. 检查：
   - ✅ 标签是否正确显示
   - ✅ Release Notes 是否完整
   - ✅ 下载链接是否可用

---

## 完整操作清单

- [ ] 删除 v1.0.4-test 标签（本地和远程）
- [ ] 创建 v1.0.4 标签
- [ ] 推送 v1.0.4 标签到 GitHub
- [ ] 在 GitHub 创建 Release
- [ ] 粘贴 Release Notes
- [ ] 发布 Release
- [ ] 验证页面显示正确
- [ ] 可选：在项目 README 中更新最新版本号

---

## 额外建议

### 更新 README.md（可选）

如果 README.md 中有版本号，也可以更新：

```markdown
## 下载

最新版本：**v1.0.4**  
[下载 FolderJump.exe](https://github.com/你的用户名/folder-jump/releases/download/v1.0.4/FolderJump.exe)
```

### 后续维护

- 保存 `RELEASE_NOTES_v1.0.4.md` 文档供将来参考
- 所有 commit 历史完整保留，便于未来维护者理解演进过程
- `docs/build-script-fix-report.md` 作为技术参考文档

---

**所有步骤完成后，v1.0.4 版本就正式发布了！** 🎉
