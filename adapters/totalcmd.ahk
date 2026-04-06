; ============================================================
; Total Commander 适配器 - FolderJump
; 负责获取与跳转 Total Commander 面板路径
; ============================================================

#Include "%A_ScriptDir%\lib\log_manager.ahk"
#Include "%A_ScriptDir%\lib\utils.ahk"

global g_TC_WMCOPYDATA_Result := ""

CollectTotalCmdPaths() {
    paths := []

    LogDebug("Start collecting Total Commander paths")

    try {
        tcWindows := WinGetList("ahk_class TTOTAL_CMD")
        LogDebug("Found Total Commander windows: " tcWindows.Length)

        for hwnd in tcWindows {
            try {
                expectedPanelCount := 0
                panelPaths := GetTCPathsViaWM_COPYDATA(hwnd, &expectedPanelCount)
                
                ; 无论 API 获取到多少个，如果没达标可视面板数量，再用 WinGetText 兜底补充
                if (panelPaths.Length < expectedPanelCount) {
                    fallbackPaths := GetTCPathsViaWinGetText(hwnd)
                    for fp in fallbackPaths {
                        hasMatched := false
                        for pp in panelPaths {
                            if (pp.path == fp.path) {
                                hasMatched := true
                                break
                            }
                        }
                        if (!hasMatched) {
                            panelPaths.Push(fp)
                        }
                    }
                }

                for panelPath in panelPaths {
                    LogDebug("Inspect TC path: " panelPath.path " [" panelPath.panelRole "/" panelPath.panelSide "]")
                    if (!(panelPath.path && DirExist(panelPath.path))) {
                        LogDebug("Skip invalid TC path: " panelPath.path)
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
                    LogDebug("Add TC path: " panelPath.path " [" label "]")
                }
            } catch as innerErr {
                LogWarn("Failed to process TC window: " innerErr.Message)
            }
        }
    } catch as err {
        LogWarn("Failed to collect Total Commander paths: " err.Message)
    }

    LogDebug("Collected Total Commander paths: " paths.Length)
    return paths
}

GetTCPathsViaWM_COPYDATA(hwnd, &expectedCount) {
    global g_TC_WMCOPYDATA_Result
    paths := []
    expectedCount := 0

    try {
        ; 注册监听，仅在接收时用
        OnMessage(0x004A, ReceiveTC_WM_COPYDATA)

        QueryTC := (cmd) => (
            g_TC_WMCOPYDATA_Result := "",
            cmdStr := cmd,
            cbData := StrPut(cmdStr, "CP0"),
            StrBuf := Buffer(cbData),
            StrPut(cmdStr, StrBuf, "CP0"),
            CopyDataStruct := Buffer(3 * A_PtrSize),
            NumPut("Ptr", Ord("G") + 256 * Ord("W"), CopyDataStruct, 0), ; GW
            NumPut("UInt", cbData, CopyDataStruct, A_PtrSize),
            NumPut("Ptr", StrBuf.Ptr, CopyDataStruct, 2 * A_PtrSize),
            SendMessage(0x004A, A_ScriptHwnd, CopyDataStruct.Ptr, , "ahk_id " hwnd),
            g_TC_WMCOPYDATA_Result
        )

        leftVisible := IsTCPanelVisible(hwnd, 9)
        rightVisible := IsTCPanelVisible(hwnd, 10)
        
        if (leftVisible)
            expectedCount++
        if (rightVisible)
            expectedCount++

        ; LP=左面板, RP=右面板, SP=活动面板
        leftPath := NormalizeTCPathText(QueryTC("LP"))
        rightPath := NormalizeTCPathText(QueryTC("RP"))
        activePath := NormalizeTCPathText(QueryTC("SP"))

        LogDebug("TC Left Path: " leftPath " (Visible: " leftVisible ")")
        LogDebug("TC Right Path: " rightPath " (Visible: " rightVisible ")")
        LogDebug("TC Active Path: " activePath)

        added := Map()
        
        if (leftVisible && leftPath && RegExMatch(leftPath, "^[A-Za-z]:") && !added.Has(leftPath)) {
            paths.Push({
                path: leftPath,
                panelRole: (leftPath == activePath) ? "active" : "inactive",
                panelSide: "left"
            })
            added[leftPath] := true
        }

        if (rightVisible && rightPath && RegExMatch(rightPath, "^[A-Za-z]:") && !added.Has(rightPath)) {
            paths.Push({
                path: rightPath,
                panelRole: (rightPath == activePath) ? "active" : "inactive",
                panelSide: "right"
            })
            added[rightPath] := true
        }

    } catch as err {
        LogWarn("TC WM_COPYDATA path collection failed: " err.Message)
    }

    return paths
}

IsTCPanelVisible(tcHwnd, pathWparam) {
    try {
        ctrlHwnd := SendMessage(1074, pathWparam, , , "ahk_id " tcHwnd)
        if (ctrlHwnd && ctrlHwnd > 0) {
            if (ControlGetVisible(ctrlHwnd)) {
                ControlGetPos(, , &w, , ctrlHwnd)
                if (IsSet(w) && w > 0) {
                    return true
                }
            }
        }
    } catch {
        ; 忽略可能的句柄无效等错误
    }
    return false
}

ReceiveTC_WM_COPYDATA(wParam, lParam, msg, hwnd) {
    global g_TC_WMCOPYDATA_Result
    
    try {
        cbData := NumGet(lParam, A_PtrSize, "UInt")
        lpData := NumGet(lParam, 2 * A_PtrSize, "Ptr")
        
        ; 使用 UTF-16 解析返回的字符串
        g_TC_WMCOPYDATA_Result := StrGet(lpData, "UTF-16")
    }
    return 1
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

        LogDebug("TC WinGetText length: " StrLen(allText))

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
