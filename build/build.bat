@echo off
REM ============================================================
REM FolderJump Build Script
REM 使用 Ahk2Exe 将 main.ahk 编译为独立 .exe
REM ============================================================

setlocal

REM 设置项目名称
set PROJECT_NAME=FolderJump

REM 设置源文件
set SOURCE_FILE=main.ahk

REM 设置输出文件
set OUTPUT_FILE=FolderJump.exe

REM 设置图标文件（可选，使用系统文件夹图标）
set ICON_FILE=

REM 查找 Ahk2Exe 编译器
REM Ahk2Exe 通常随 AutoHotkey 安装一起提供
set AHK2EXE=

REM 检查常见安装路径
if exist "%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe" (
    set AHK2EXE=%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe
    goto :found_compiler
)

if exist "%ProgramFiles(x86)%\AutoHotkey\Compiler\Ahk2Exe.exe" (
    set AHK2EXE=%ProgramFiles(x86)%\AutoHotkey\Compiler\Ahk2Exe.exe
    goto :found_compiler
)

REM 检查 AHK v2 安装路径
if exist "%ProgramFiles%\AutoHotkey\v2\Compiler\Ahk2Exe.exe" (
    set AHK2EXE=%ProgramFiles%\AutoHotkey\v2\Compiler\Ahk2Exe.exe
    goto :found_compiler
)

if exist "%ProgramFiles(x86)%\AutoHotkey\v2\Compiler\Ahk2Exe.exe" (
    set AHK2EXE=%ProgramFiles(x86)%\AutoHotkey\v2\Compiler\Ahk2Exe.exe
    goto :found_compiler
)

REM 检查 PATH 中是否有 Ahk2Exe
where Ahk2Exe.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set AHK2EXE=Ahk2Exe.exe
    goto :found_compiler
)

echo [错误] 未找到 Ahk2Exe 编译器
echo.
echo 请确保已安装 AutoHotkey，并且 Ahk2Exe.exe 位于以下路径之一：
echo   - %%ProgramFiles%%\AutoHotkey\Compiler\Ahk2Exe.exe
echo   - %%ProgramFiles(x86)%%\AutoHotkey\Compiler\Ahk2Exe.exe
echo   - %%ProgramFiles%%\AutoHotkey\v2\Compiler\Ahk2Exe.exe
echo.
echo 或者将 Ahk2Exe.exe 所在目录添加到系统 PATH 环境变量中。
echo.
pause
exit /b 1

:found_compiler
echo [FolderJump] 编译开始...
echo [FolderJump] 编译器: %AHK2EXE%
echo [FolderJump] 源文件: %SOURCE_FILE%
echo [FolderJump] 输出文件: %OUTPUT_FILE%
echo.

REM 执行编译
if defined ICON_FILE (
    "%AHK2EXE%" /in "%SOURCE_FILE%" /out "%OUTPUT_FILE%" /icon "%ICON_FILE%" /cp 0 /x64
) else (
    "%AHK2EXE%" /in "%SOURCE_FILE%" /out "%OUTPUT_FILE%" /cp 0 /x64
)

if %ERRORLEVEL% EQU 0 (
    echo.
    echo [FolderJump] 编译成功！
    echo [FolderJump] 输出文件: %CD%\%OUTPUT_FILE%
    echo.
    echo 文件大小:
    for %%A in ("%OUTPUT_FILE%") do echo   %%~zA 字节
) else (
    echo.
    echo [FolderJump] 编译失败！请检查错误信息。
    exit /b 1
)

echo.
pause
