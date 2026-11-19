#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()

; ============================================================
; DualPlay - run several Roblox instances at once
;   Unlock Next Instance - closes Roblox's single-instance lock
;     (via Microsoft Sysinternals Handle) on every running instance,
;     so the next launch doesn't kick an existing one. Each new
;     instance makes its own lock, so unlock again before each
;     launch. Roblox's files are never modified and nothing is
;     injected into its process.
;   Quick Swap - a hotkey (F9 by default, set with the Key button)
;     moves real focus to the next Roblox window, in launch order.
;   Close an Instance - ends one chosen instance without touching
;     the others.
; ============================================================

; ---------- Auto-elevate: closing another process's handles needs admin ----------
if !A_IsAdmin {
    try {
        if A_IsCompiled
            Run('*RunAs "' A_ScriptFullPath '"')
        else
            Run('*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"')
    }
    ExitApp()
}

; ---------- Config ----------
HandleExePath  := A_ScriptDir "\tools\handle64.exe"
HandleZipUrl   := "https://download.sysinternals.com/files/Handle.zip"
RobloxExeName  := "RobloxPlayerBeta.exe"
SettingsDir    := A_AppData "\DualPlay"
SettingsFile   := SettingsDir "\settings.ini"
LogFile        := SettingsDir "\unlock.log"
DefaultSwapKey := "F9"

; ---------- State ----------
armed       := false
wins        := []   ; Roblox main windows, in launch order
swapKey     := ""
settingsGui := 0
closeGui    := 0

; ---------- GUI ----------
MyGui := Gui("+AlwaysOnTop +ToolWindow", "DualPlay")
MyGui.SetFont("s10")
btnUnlock  := MyGui.AddButton("w260 h32", "Unlock Next Instance")
btnArm     := MyGui.AddButton("w210 h32", "Arm Quick Swap: OFF")
btnSwapKey := MyGui.AddButton("x+6 w44 h32", "Key")
btnClose   := MyGui.AddButton("xm w260 h32", "Close an Instance...")
statusText := MyGui.AddText("xm w260 h20", "Roblox instances running: 0")
helpText   := MyGui.AddText("w260 h48", "")
btnUnlock.OnEvent("Click", UnlockInstances)
btnArm.OnEvent("Click", ToggleArmed)
btnSwapKey.OnEvent("Click", OpenSettings)
btnClose.OnEvent("Click", OpenCloseDialog)
MyGui.OnEvent("Close", (*) => ExitApp())

if !RegisterSwapKey(LoadSwapKey())
    RegisterSwapKey(DefaultSwapKey)
UpdateHelpText()
MyGui.Show()
UpdateStatus()
SetTimer(UpdateStatus, 1000)

; ---------- Helpers ----------
GetRobloxPIDs() {
    global RobloxExeName
    pids := []
    for process in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name='" RobloxExeName "'")
        pids.Push(process.ProcessId)
    return pids
}

SafeDelete(path) {
    try FileDelete(path)
}

LogLine(text) {
    global LogFile, SettingsDir
    try {
        DirCreate(SettingsDir)
        FileAppend(FormatTime(, "HH:mm:ss") "  " text "`n", LogFile)
    }
}

GetMainWindowForPid(pid) {
    try {
        for hwnd in WinGetList("ahk_pid " pid) {
            if WinGetTitle("ahk_id " hwnd) != ""
                return hwnd
        }
    }
    return 0
}

; Every running instance, oldest first - this order is the Quick
; Swap order and the numbering in the Close dialog.
GetInstances() {
    global RobloxExeName
    list := []
    for p in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId, CreationDate FROM Win32_Process WHERE Name='" RobloxExeName "'")
        list.Push({pid: p.ProcessId, created: String(p.CreationDate), hwnd: GetMainWindowForPid(p.ProcessId)})
    i := 2
    while (i <= list.Length) {
        cur := list[i]
        j := i - 1
        while (j >= 1 && StrCompare(list[j].created, cur.created) > 0) {
            list[j + 1] := list[j]
            j--
        }
        list[j + 1] := cur
        i++
    }
    return list
}

HotkeyText(k) {
    mods := ""
    while (StrLen(k) > 1 && InStr("^!+#", SubStr(k, 1, 1))) {
        c := SubStr(k, 1, 1)
        mods .= (c = "^") ? "Ctrl+" : (c = "!") ? "Alt+" : (c = "+") ? "Shift+" : "Win+"
        k := SubStr(k, 2)
    }
    return mods . (StrLen(k) = 1 ? StrUpper(k) : k)
}

UpdateHelpText() {
    global swapKey
    helpText.Text := "Launch Roblox, click Unlock, launch the next.`nUnlock again before every launch.`n" HotkeyText(swapKey) " swaps to the next window."
}

; ---------- First-run: fetch Sysinternals Handle from Microsoft ----------
; Not bundled - Sysinternals' license doesn't allow redistributing it,
; so it's downloaded once from Microsoft's own server and its
; Microsoft signature is checked before it's ever run.
EnsureHandleTool() {
    global HandleExePath, HandleZipUrl
    if FileExist(HandleExePath)
        return true

    msg := "DualPlay uses Microsoft's free Sysinternals Handle tool to release Roblox's single-instance lock. "
        . "It isn't bundled with DualPlay, so it has to be downloaded once from Microsoft:`n`n"
        . HandleZipUrl "`n`n"
        . "By downloading it you agree to the Sysinternals license terms. Download now?"
    if MsgBox(msg, "DualPlay - one-time setup", "YesNo Icon?") != "Yes"
        return false

    toolsDir := A_ScriptDir "\tools"
    zip := A_Temp "\dualplay_handle.zip"
    try {
        DirCreate(toolsDir)
        Download(HandleZipUrl, zip)
    } catch {
        MsgBox("Couldn't download Handle. Check your internet connection and try again.", "DualPlay", "Icon!")
        return false
    }

    q(s) => "'" StrReplace(s, "'", "''") "'"
    ps := "Expand-Archive -LiteralPath " q(zip) " -DestinationPath " q(toolsDir) " -Force; "
        . "$s = Get-AuthenticodeSignature -LiteralPath " q(HandleExePath) "; "
        . "if ($s.Status -eq 'Valid' -and $s.SignerCertificate.Subject -like '*Microsoft*') { exit 0 } "
        . "else { Remove-Item -LiteralPath " q(HandleExePath) " -Force -ErrorAction SilentlyContinue; exit 1 }"
    code := RunWait('powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "' ps '"', , "Hide")
    SafeDelete(zip)

    if (code != 0 || !FileExist(HandleExePath)) {
        MsgBox("Handle was downloaded but couldn't be verified as signed by Microsoft, so it wasn't used. Try again later.", "DualPlay", "Icon!")
        return false
    }
    return true
}

FindSingletonHandles(pid) {
    global HandleExePath
    tempOut := A_Temp "\dualplay_scan_" pid ".txt"
    tempBat := A_Temp "\dualplay_scan_" pid ".bat"
    SafeDelete(tempOut)
    SafeDelete(tempBat)
    FileAppend('"' HandleExePath '" -accepteula -p ' pid ' -a > "' tempOut '" 2>&1' "`r`n", tempBat)
    RunWait(tempBat, , "Hide")

    ids := []
    if FileExist(tempOut) {
        for line in StrSplit(FileRead(tempOut), "`n") {
            ; Log the real named lock objects, so if a match misses we
            ; can still see what Roblox actually named them.
            if RegExMatch(line, "i)BaseNamedObjects[^\r\n]*(roblox|singleton)")
                LogLine("    PID " pid " obj: " Trim(line, " `t`r"))
            ; Close the single-instance guards: the legacy ROBLOX_singleton
            ; event/mutex AND the per-version RobloxPlayerBeta.exe.mtx that
            ; current Roblox clients actually hold. Only Mutant/Event objects
            ; - never the .shm Section, which backs shared memory the running
            ; client needs to keep working.
            if RegExMatch(line, "i)^\s*([0-9A-Fa-f]+):\s+(?:Mutant|Event)\b[^\r\n]*(?:singleton|RobloxPlayerBeta\.exe\.mtx)", &m)
                ids.Push(m[1])
        }
    } else {
        LogLine("    PID " pid " scan produced no output")
    }
    SafeDelete(tempOut)
    SafeDelete(tempBat)
    return ids
}

; ---------- Unlock every running instance ----------
; Returns {running, unlocked, stillLocked}, or 0 if the Handle tool
; isn't available. A running instance can re-create its lock right
; after it's closed, so this closes, re-scans, and repeats, then does
; a final verify. Writes a fresh unlock.log each time for diagnosis.
UnlockAll() {
    global HandleExePath, LogFile
    SafeDelete(LogFile)
    LogLine("=== Launch / auto-unlock requested ===")
    if !EnsureHandleTool() {
        LogLine("Handle tool not available (missing or download declined).")
        return 0
    }
    pids := GetRobloxPIDs()
    pidStr := ""
    for p in pids
        pidStr .= (pidStr = "" ? "" : ", ") p
    LogLine("Running Roblox PIDs: " (pids.Length ? pidStr : "none"))

    everClosed := 0
    Loop 3 {
        pass := A_Index
        closeBat := A_Temp "\dualplay_close.bat"
        SafeDelete(closeBat)
        pending := 0
        for pid in pids {
            ids := FindSingletonHandles(pid)
            if ids.Length = 0
                continue
            LogLine("Pass " pass ": PID " pid " -> " ids.Length " lock handle(s)")
            for id in ids
                FileAppend('"' HandleExePath '" -accepteula -c ' id ' -p ' pid ' -y' "`r`n", closeBat)
            pending++
        }
        if pending = 0 {
            SafeDelete(closeBat)
            break
        }
        RunWait(closeBat, , "Hide")
        SafeDelete(closeBat)
        everClosed := Max(everClosed, pending)
    }

    stillLocked := 0
    for pid in pids {
        if FindSingletonHandles(pid).Length {
            stillLocked++
            LogLine("STILL LOCKED after retries: PID " pid)
        }
    }
    LogLine("Done. closed on up to " everClosed " instance(s); stillLocked=" stillLocked)
    return {running: pids.Length, unlocked: everClosed, stillLocked: stillLocked}
}

; ---------- Unlock button ----------
UnlockInstances(*) {
    r := UnlockAll()
    if !r
        return   ; Handle tool missing or its download was declined.
    if r.running = 0
        MsgBox("No Roblox process found. Launch your first instance, then click Unlock.", "DualPlay", "Iconi")
    else if r.stillLocked > 0
        MsgBox("Closed what I could, but " r.stillLocked " instance(s) still hold a lock - launching another may kick one. Click Unlock again, or wait until any loading instance reaches its game window.", "DualPlay", "Icon!")
    else if r.unlocked = 0
        MsgBox(r.running " instance(s) running, nothing left to unlock. Launch your next one now.", "DualPlay", "Iconi")
    else
        MsgBox("Unlocked. " r.running " instance(s) running - launch your next one now.", "DualPlay", "Iconi")
}

; ---------- Quick swap ----------
RefreshWindows() {
    global wins
    newWins := []
    for inst in GetInstances() {
        if inst.hwnd
            newWins.Push(inst.hwnd)
    }
    wins := newWins
}

ToggleArmed(*) {
    global armed, wins
    if !armed {
        RefreshWindows()
        if wins.Length < 2 {
            MsgBox("Found " wins.Length " Roblox window(s) - need at least 2 loaded to their game window before arming Quick Swap.", "DualPlay", "Iconi")
            return
        }
        armed := true
        btnArm.Text := "Arm Quick Swap: ON (" wins.Length ")"
    } else {
        armed := false
        btnArm.Text := "Arm Quick Swap: OFF"
    }
}

FastActivate(hwnd) {
    ; Direct SetForegroundWindow call - skips AHK's WinActivate overhead
    ; (retry loops / "wait until active" polling) for minimum latency.
    ; Windows blocks background SetForegroundWindow calls after real
    ; user input lands on the CURRENTLY focused window. Attaching our
    ; thread to whichever thread owns foreground focus right now
    ; borrows its permission to switch away without being blocked.
    curHwnd   := DllCall("GetForegroundWindow", "ptr")
    curThread := DllCall("GetWindowThreadProcessId", "ptr", curHwnd, "ptr", 0, "uint")
    myThread  := DllCall("GetCurrentThreadId", "uint")
    linked := false
    if (curThread && curThread != myThread)
        linked := DllCall("AttachThreadInput", "uint", myThread, "uint", curThread, "int", true)
    DllCall("SetForegroundWindow", "ptr", hwnd)
    DllCall("BringWindowToTop", "ptr", hwnd)
    if linked
        DllCall("AttachThreadInput", "uint", myThread, "uint", curThread, "int", false)
}

SwapNext(*) {
    global armed, wins
    if !armed
        return
    live := []
    for w in wins {
        if WinExist("ahk_id " w)
            live.Push(w)
    }
    wins := live
    if wins.Length < 2 {
        ToggleArmed()
        return
    }
    ; Go to whichever window comes after the one currently focused,
    ; so a manual click into any window is respected.
    cur := WinExist("A")
    next := 1
    for i, w in wins {
        if (w = cur) {
            next := Mod(i, wins.Length) + 1
            break
        }
    }
    FastActivate(wins[next])
}

; ---------- Swap hotkey (configurable) ----------
LoadSwapKey() {
    global SettingsFile, DefaultSwapKey
    key := IniRead(SettingsFile, "Hotkeys", "QuickSwap", DefaultSwapKey)
    return key != "" ? key : DefaultSwapKey
}

RegisterSwapKey(newKey) {
    global swapKey
    try Hotkey(newKey, SwapNext, "On")
    catch
        return false
    if (swapKey != "" && swapKey != newKey)
        try Hotkey(swapKey, "Off")
    swapKey := newKey
    return true
}

OpenSettings(*) {
    global settingsGui, swapKey
    if settingsGui {
        settingsGui.Show()
        return
    }
    ; Turn the swap key off while this window is open, so the box
    ; can capture it (and pressing it here doesn't swap windows).
    try Hotkey(swapKey, "Off")

    settingsGui := Gui("+AlwaysOnTop +ToolWindow +Owner" MyGui.Hwnd, "Keybind")
    settingsGui.SetFont("s10")
    settingsGui.AddText("y+8 w54", "Keybind")
    hk := settingsGui.AddHotkey("x+4 yp-3 w150", swapKey)
    btnSave := settingsGui.AddButton("x+6 yp-1 w60", "Save")
    btnSave.OnEvent("Click", (*) => SaveSettings(hk.Value))
    settingsGui.OnEvent("Close", (*) => CloseSettings())
    settingsGui.Show()
}

SaveSettings(newKey) {
    global settingsGui, SettingsDir, SettingsFile
    if (newKey = "") {
        MsgBox("Click the box and press a key first.", "DualPlay", "Icon! Owner" settingsGui.Hwnd)
        return
    }
    if !RegisterSwapKey(newKey) {
        MsgBox("That key can't be used as a hotkey - try a different one.", "DualPlay", "Icon! Owner" settingsGui.Hwnd)
        return
    }
    try {
        DirCreate(SettingsDir)
        IniWrite(newKey, SettingsFile, "Hotkeys", "QuickSwap")
    }
    UpdateHelpText()
    DestroySettings()
}

CloseSettings() {
    global swapKey
    try Hotkey(swapKey, "On")
    DestroySettings()
}

DestroySettings() {
    global settingsGui
    if settingsGui {
        settingsGui.Destroy()
        settingsGui := 0
    }
}

; ---------- Close one instance ----------
; Force-ends just the chosen process. Closing a Roblox window with
; its own X sometimes takes the other instances down with it; ending
; one process directly skips Roblox's own shutdown path entirely.
OpenCloseDialog(*) {
    global closeGui
    DestroyCloseDialog()
    insts := GetInstances()
    if insts.Length = 0 {
        MsgBox("No Roblox instances are running.", "DualPlay", "Iconi")
        return
    }
    items := []
    for i, inst in insts
        items.Push("Instance " i "   (PID " inst.pid ")" (inst.hwnd ? "" : "   - still loading"))

    closeGui := Gui("+AlwaysOnTop +ToolWindow +Owner" MyGui.Hwnd, "Close an Instance")
    closeGui.SetFont("s10")
    closeGui.AddText("w280", "Click an instance to switch to it, so you can see which account it is before closing. Numbers match the Quick Swap order.")
    lb := closeGui.AddListBox("w280 r" Min(insts.Length, 6), items)
    lb.OnEvent("Change", (*) => PreviewInstance(lb, insts))
    btnEnd    := closeGui.AddButton("w135", "Close Selected")
    btnCancel := closeGui.AddButton("x+10 w135", "Cancel")
    btnEnd.OnEvent("Click", (*) => CloseSelectedInstance(lb, insts))
    btnCancel.OnEvent("Click", (*) => DestroyCloseDialog())
    closeGui.OnEvent("Close", (*) => DestroyCloseDialog())
    closeGui.Show()
    ; Select and switch to the first one right away, so you're already
    ; looking at Instance 1 the moment the dialog opens.
    lb.Choose(1)
    PreviewInstance(lb, insts)
}

PreviewInstance(lb, insts) {
    ; WinActivate (AHK's robust activate, with its own focus-steal
    ; dance) rather than the latency-optimized FastActivate - from a
    ; dialog, reliability matters more than speed.
    if (lb.Value && insts[lb.Value].hwnd && WinExist("ahk_id " insts[lb.Value].hwnd))
        try WinActivate("ahk_id " insts[lb.Value].hwnd)
}

CloseSelectedInstance(lb, insts) {
    global closeGui, RobloxExeName
    if !lb.Value {
        MsgBox("Select an instance first.", "DualPlay", "Icon! Owner" closeGui.Hwnd)
        return
    }
    n := lb.Value
    inst := insts[n]
    prompt := "Close Instance " n " (PID " inst.pid ")?`n`nOnly that Roblox window ends - the others keep running. Anything that game hadn't saved yet may be lost."
    if MsgBox(prompt, "DualPlay", "YesNo Icon? Owner" closeGui.Hwnd) != "Yes"
        return
    ; Guard against the PID having been reused by something else.
    name := ""
    try name := ProcessGetName(inst.pid)
    if (name = RobloxExeName)
        RunWait('taskkill /PID ' inst.pid ' /F', , "Hide")
    DestroyCloseDialog()
    UpdateStatus()
}

DestroyCloseDialog() {
    global closeGui
    if closeGui {
        closeGui.Destroy()
        closeGui := 0
    }
}

; ---------- Status line (also keeps the swap list current) ----------
UpdateStatus() {
    global armed, wins
    statusText.Text := "Roblox instances running: " GetRobloxPIDs().Length
    if armed {
        RefreshWindows()
        if wins.Length < 2
            ToggleArmed()
        else
            btnArm.Text := "Arm Quick Swap: ON (" wins.Length ")"
    }
}
