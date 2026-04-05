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
