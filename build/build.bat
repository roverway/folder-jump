@echo off
REM ============================================================
REM FolderJump Build Script
REM Using Ahk2Exe to compile main.ahk into standalone .exe
REM ============================================================

setlocal enabledelayedexpansion

REM Set project name
set PROJECT_NAME=FolderJump

REM Set source file
set SOURCE_FILE=main.ahk

REM Set output file
set OUTPUT_FILE=FolderJump.exe

REM Set icon file (optional)
set ICON_FILE=

REM Locate Ahk2Exe compiler for AutoHotkey v2
set AHK2EXE=

REM Check Scoop installation first
if exist "d:\Personal\00_software\scoop\apps\autohotkey\current\Compiler\Ahk2Exe.exe" (
    set "AHK2EXE=d:\Personal\00_software\scoop\apps\autohotkey\current\Compiler\Ahk2Exe.exe"
    goto :found_compiler
)

REM Check standard Windows installation paths
if exist "%ProgramFiles%\AutoHotkey\v2\Compiler\Ahk2Exe.exe" (
    set "AHK2EXE=%ProgramFiles%\AutoHotkey\v2\Compiler\Ahk2Exe.exe"
    goto :found_compiler
)

if exist "%ProgramFiles(x86)%\AutoHotkey\v2\Compiler\Ahk2Exe.exe" (
    set "AHK2EXE=%ProgramFiles(x86)%\AutoHotkey\v2\Compiler\Ahk2Exe.exe"
    goto :found_compiler
)

REM Check if Ahk2Exe is in PATH
where Ahk2Exe.exe >nul 2>nul
if !ERRORLEVEL! EQU 0 (
    set AHK2EXE=Ahk2Exe.exe
    goto :found_compiler
)

echo [ERROR] Ahk2Exe compiler not found
echo.
echo Please ensure AutoHotkey v2.0+ is installed and Ahk2Exe is available at:
echo   - d:\Personal\00_software\scoop\apps\autohotkey\current\Compiler\Ahk2Exe.exe
echo   - %%ProgramFiles%%\AutoHotkey\v2\Compiler\Ahk2Exe.exe
echo   - %%ProgramFiles(x86)%%\AutoHotkey\v2\Compiler\Ahk2Exe.exe
echo.
echo Or add Ahk2Exe.exe directory to system PATH.
echo.
echo You may need to run the install-ahk2exe.ahk script first.
echo.
pause
exit /b 1

:found_compiler
echo [FolderJump] Build started...
echo [FolderJump] Compiler: !AHK2EXE!
echo [FolderJump] Source: !SOURCE_FILE!
echo [FolderJump] Output: !OUTPUT_FILE!
echo.

REM Execute compilation using Ahk2Exe
if defined ICON_FILE (
    "!AHK2EXE!" /in "!SOURCE_FILE!" /out "!OUTPUT_FILE!" /icon "!ICON_FILE!" /cp 0
) else (
    "!AHK2EXE!" /in "!SOURCE_FILE!" /out "!OUTPUT_FILE!" /cp 0
)

if !ERRORLEVEL! EQU 0 (
    echo.
    echo [FolderJump] Build succeeded!
    echo [FolderJump] Output: %cd%\!OUTPUT_FILE!
    echo.
) else (
    echo.
    echo [FolderJump] Build failed! Check error messages above.
    exit /b 1
)

echo.
pause
