; ============================================================
; Total Commander 适配器 - FolderJump
; 负责获取与跳转 Total Commander 面板路径
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\utils.ahk"

CollectTotalCmdPaths() {
    paths := []

    LogInfo("Start collecting Total Commander paths")

    try {
        tcWindows := WinGetList("ahk_class TTOTAL_CMD")
        LogInfo("Found Total Commander windows: " tcWindows.Length)

        for hwnd in tcWindows {
            try {
                panelPaths := GetTCPathsViaAPI(hwnd)
                if (panelPaths.Length = 0)
                    panelPaths := GetTCPathsViaWinGetText(hwnd)

                for panelPath in panelPaths {
                    LogInfo("Inspect TC path: " panelPath.path " [" panelPath.panelRole "/" panelPath.panelSide "]")
                    if (!(panelPath.path && DirExist(panelPath.path))) {
                        LogInfo("Skip invalid TC path: " panelPath.path)
                        continue
                    }

                    label := BuildTCLabel(panelPath)
                    paths.Push({
                        path: panelPath.path,
                        source: "totalcmd",
                        label: label,
                        hwnd: hwnd,
                        panel: panelPath.panelSide,
                        panelRole: panelPath.panelRole,
                        panelSide: panelPath.panelSide,
                        timestamp: A_TickCount
                    })
                    LogInfo("Add TC path: " panelPath.path " [" label "]")
                }
            } catch as innerErr {
                LogWarn("Failed to process TC window: " innerErr.Message)
            }
        }
    } catch as err {
        LogWarn("Failed to collect Total Commander paths: " err.Message)
    }

    LogInfo("Collected Total Commander paths: " paths.Length)
    return paths
}

GetTCPathsViaAPI(hwnd) {
    paths := []

    try {
        activePathHwnd := SendMessage(1074, 17, , , "ahk_id " hwnd)
        inactivePathHwnd := SendMessage(1074, 18, , , "ahk_id " hwnd)
        panelSides := GetTCPanelSidesFromControls(activePathHwnd, inactivePathHwnd)

        LogInfo("TC active path control hwnd: " activePathHwnd)
        LogInfo("TC inactive path control hwnd: " inactivePathHwnd)

        if (activePathHwnd && activePathHwnd > 0) {
            try {
                activePath := NormalizeTCPathText(ControlGetText("ahk_id " activePathHwnd))
                if (activePath && RegExMatch(activePath, "^[A-Za-z]:")) {
                    paths.Push({
                        path: activePath,
                        panelRole: "active",
                        panelSide: panelSides.active
                    })
                }
            } catch as err {
                LogWarn("Failed to read active TC panel path: " err.Message)
            }
        }

        if (inactivePathHwnd && inactivePathHwnd > 0) {
            try {
                inactivePath := NormalizeTCPathText(ControlGetText("ahk_id " inactivePathHwnd))
                if (inactivePath && RegExMatch(inactivePath, "^[A-Za-z]:")) {
                    paths.Push({
                        path: inactivePath,
                        panelRole: "inactive",
                        panelSide: panelSides.inactive
                    })
                }
            } catch as err {
                LogWarn("Failed to read inactive TC panel path: " err.Message)
            }
        }
    } catch as err {
        LogWarn("TC API path collection failed: " err.Message)
    }

    return paths
}

GetTCPanelSidesFromControls(activePathHwnd, inactivePathHwnd) {
    result := {
        active: "",
        inactive: ""
    }

    if (!(activePathHwnd && inactivePathHwnd))
        return result

    try {
        ControlGetPos(&activeX, , , , "ahk_id " activePathHwnd)
        ControlGetPos(&inactiveX, , , , "ahk_id " inactivePathHwnd)

        if (activeX <= inactiveX) {
            result.active := "left"
            result.inactive := "right"
        } else {
            result.active := "right"
            result.inactive := "left"
        }
    } catch as err {
        LogWarn("Failed to infer TC panel sides from control positions: " err.Message)
    }

    return result
}

NormalizeTCPathText(pathText) {
    pathText := RegExReplace(pathText, "[>\r\n]+$")
    return Trim(pathText)
}

BuildTCLabel(panelPath) {
    panelRole := panelPath.panelRole != "" ? panelPath.panelRole : ""
    if (panelRole != "")
        return "TC (" panelRole ")"

    return "TC"
}

GetTCPathsViaWinGetText(hwnd) {
    paths := []

    try {
        oldSetting := A_DetectHiddenText
        DetectHiddenText(true)
        allText := WinGetText("ahk_id " hwnd)
        DetectHiddenText(oldSetting)

        LogInfo("TC WinGetText length: " StrLen(allText))

        panelSides := ["left", "right"]
        index := 1

        for line in StrSplit(allText, "`n", "`r") {
            line := Trim(line)
            if (!(line && SubStr(line, -1) = ">"))
                continue

            path := Trim(SubStr(line, 1, -1))
            if (!(path && RegExMatch(path, "^[A-Za-z]:")))
                continue

            panelSide := index <= panelSides.Length ? panelSides[index] : ""
            paths.Push({
                path: path,
                panelRole: "",
                panelSide: panelSide
            })
            index += 1
        }
    } catch as err {
        LogWarn("TC WinGetText path collection failed: " err.Message)
    }

    return paths
}

NavigateTotalCmd(hwnd, targetPath, panelSide := "", panelRole := "active") {
    LogInfo("Navigate TC: hwnd=" hwnd ", path=" targetPath ", panelSide=" panelSide ", panelRole=" panelRole)

    try {
        if (panelSide = "left" || panelSide = "right") {
            if (NavigateTotalCmdByCommandLine(hwnd, targetPath, panelSide))
                return true
        }
    } catch as err {
        LogWarn("TC command line navigation failed: " err.Message)
    }

    return NavigateTotalCmdByKeyboard(hwnd, targetPath, panelSide, panelRole)
}

NavigateTotalCmdByCommandLine(hwnd, targetPath, panelSide) {
    pid := WinGetPID("ahk_id " hwnd)
    if (!pid)
        return false

    tcExe := ""
    for process in ComObjGet("winmgmts:").ExecQuery("Select * From Win32_Process Where ProcessId = " pid) {
        tcExe := process.ExecutablePath
        break
    }

    if (!(tcExe && FileExist(tcExe)))
        return false

    if (panelSide = "left")
        Run('"' tcExe '" /O /T /L="' targetPath '"', , "Hide")
    else
        Run('"' tcExe '" /O /T /R="' targetPath '"', , "Hide")

    LogInfo("TC command line navigation succeeded: " targetPath " [" panelSide "]")
    return true
}

NavigateTotalCmdByKeyboard(hwnd, targetPath, panelSide, panelRole) {
    savedClipboard := SaveClipboard()

    try {
        WinActivate("ahk_id " hwnd)
        if (!WinWaitActive("ahk_id " hwnd, , 2000)) {
            LogError("Failed to activate Total Commander window")
            RestoreClipboard(savedClipboard)
            return false
        }
        Sleep(200)

        activeSide := GetTCActivePanelSide(hwnd)
        if ((panelSide = "left" || panelSide = "right") && activeSide != "" && panelSide != activeSide) {
            Send("{Tab}")
            Sleep(150)
        } else if (panelRole = "inactive" && activeSide = "") {
            ; Without panel side information, Tab is the safest way to target the inactive pane.
            Send("{Tab}")
            Sleep(150)
        }

        Send("^d")
        Sleep(300)

        A_Clipboard := targetPath
        if (!ClipWait(1))
            LogWarn("Clipboard write timed out while navigating TC")
        Sleep(100)

        Send("^v")
        Sleep(200)
        Send("{Enter}")
        Sleep(300)

        LogInfo("TC keyboard navigation succeeded: " targetPath)
        RestoreClipboard(savedClipboard)
        return true
    } catch as err {
        LogError("TC keyboard navigation failed: " err.Message)
        RestoreClipboard(savedClipboard)
        return false
    }
}

GetTCActivePanelSide(hwnd) {
    try {
        activePathHwnd := SendMessage(1074, 17, , , "ahk_id " hwnd)
        inactivePathHwnd := SendMessage(1074, 18, , , "ahk_id " hwnd)
        return GetTCPanelSidesFromControls(activePathHwnd, inactivePathHwnd).active
    } catch as err {
        LogWarn("Failed to get TC active panel side: " err.Message)
        return ""
    }
}
