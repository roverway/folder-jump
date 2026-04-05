# ============================================================
# FolderJump Build Script (PowerShell)
# 使用 Ahk2Exe 将 main.ahk 编译为独立 .exe
# ============================================================

$ErrorActionPreference = "Stop"

# 设置项目名称
$ProjectName = "FolderJump"
$SourceFile = "main.ahk"
$OutputFile = "FolderJump.exe"
$IconFile = ""

Write-Host "[FolderJump] 编译开始..." -ForegroundColor Green

# 查找 Ahk2Exe 编译器
$Ahk2Exe = $null

$CommonPaths = @(
    "$([Environment]::GetFolderPath('ProgramFiles'))\AutoHotkey\Compiler\Ahk2Exe.exe",
    "$([Environment]::GetFolderPath('ProgramFilesX86'))\AutoHotkey\Compiler\Ahk2Exe.exe",
    "$([Environment]::GetFolderPath('ProgramFiles'))\AutoHotkey\v2\Compiler\Ahk2Exe.exe",
    "$([Environment]::GetFolderPath('ProgramFilesX86'))\AutoHotkey\v2\Compiler\Ahk2Exe.exe"
)

foreach ($path in $CommonPaths) {
    if (Test-Path $path) {
        $Ahk2Exe = $path
        break
    }
}

if (-not $Ahk2Exe) {
    $Ahk2Exe = (Get-Command Ahk2Exe.exe -ErrorAction SilentlyContinue).Source
}

if (-not $Ahk2Exe) {
    Write-Host "[错误] 未找到 Ahk2Exe 编译器" -ForegroundColor Red
    Write-Host ""
    Write-Host "请确保已安装 AutoHotkey，Ahk2Exe.exe 应位于以下路径之一："
    Write-Host "  - `$env:ProgramFiles\AutoHotkey\Compiler\Ahk2Exe.exe"
    Write-Host "  - `$env:ProgramFiles(x86)\AutoHotkey\Compiler\Ahk2Exe.exe"
    Write-Host "  - `$env:ProgramFiles\AutoHotkey\v2\Compiler\Ahk2Exe.exe"
    Write-Host ""
    Read-Host "按 Enter 继续"
    exit 1
}

Write-Host "[FolderJump] 编译器: $Ahk2Exe"
Write-Host "[FolderJump] 源文件: $SourceFile"
Write-Host "[FolderJump] 输出文件: $OutputFile"
Write-Host ""

# 执行编译
try {
    $args = @(
        "/in", $SourceFile,
        "/out", $OutputFile,
        "/cp", "0",
        "/x64"
    )
    
    if ($IconFile) {
        $args += "/icon", $IconFile
    }
    
    & $Ahk2Exe $args
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "[FolderJump] 编译成功！" -ForegroundColor Green
        Write-Host "[FolderJump] 输出文件: $(Get-Location)\$OutputFile"
        Write-Host ""
        
        if (Test-Path $OutputFile) {
            $size = (Get-Item $OutputFile).Length
            Write-Host "文件大小: $size 字节"
        }
    } else {
        Write-Host ""
        Write-Host "[FolderJump] 编译失败！" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "[FolderJump] 编译异常: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Read-Host "按 Enter 继续"
