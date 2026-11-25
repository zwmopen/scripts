Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

Function DecodeBasicPercent(strVal)
    Dim s
    s = CStr(strVal)
    s = Replace(s, "%20", " ")
    s = Replace(s, "%2B", "+")
    s = Replace(s, "%2D", "-")
    s = Replace(s, "%5F", "_")
    s = Replace(s, "%2F", "/")
    s = Replace(s, "%3A", ":")
    DecodeBasicPercent = s
End Function

Function QueryValue(url, key)
    Dim cleanUrl, hashPos, re, matches, val
    cleanUrl = CStr(url)
    hashPos = InStr(cleanUrl, "#")
    If hashPos > 0 Then
        cleanUrl = Left(cleanUrl, hashPos - 1)
    End If
    Set re = New RegExp
    re.IgnoreCase = True
    re.Global = False
    re.Pattern = "[?&]" & key & "=([^&#]+)"
    Set matches = re.Execute(cleanUrl)
    If matches.Count > 0 Then
        val = DecodeBasicPercent(matches(0).SubMatches(0))
        Do While Len(val) > 0 And Right(val, 1) = "/"
            val = Left(val, Len(val) - 1)
        Loop
        QueryValue = Trim(val)
    Else
        QueryValue = ""
    End If
End Function

Function ResolveScript(scriptName)
    Dim baseDir, c1, c2, c3, c4
    Dim wWorkPkg, wHelper, wTools, wRunData
    baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
    wHelper = "GPT" & ChrW(&H4F5C) & ChrW(&H54C1) & ChrW(&H52A9) & ChrW(&H624B)
    wTools = ChrW(&H5DE5) & ChrW(&H5177) & ChrW(&H811A) & ChrW(&H672C)
    wRunData = "D:\AICode\" & ChrW(&H8FD0) & ChrW(&H884C) & ChrW(&H6570) & ChrW(&H636E) & "\chatgpt-work-package"

    c1 = baseDir & "\" & scriptName
    c2 = baseDir & "\" & wHelper & "\" & scriptName
    c3 = baseDir & "\" & wHelper & "\" & wTools & "\" & scriptName
    c4 = wRunData & "\" & scriptName

    If fso.FileExists(c1) Then
        ResolveScript = c1
    ElseIf fso.FileExists(c2) Then
        ResolveScript = c2
    ElseIf fso.FileExists(c3) Then
        ResolveScript = c3
    ElseIf fso.FileExists(c4) Then
        ResolveScript = c4
    Else
        ResolveScript = c1
    End If
End Function

Sub LogLaunch(baseDir, msg)
    On Error Resume Next
    Dim logPath, logFile, ts
    logPath = baseDir & "\workpkg_launch.log"
    If fso.FileExists(logPath) Then
        If fso.GetFile(logPath).Size > 262144 Then
            fso.DeleteFile logPath, True
        End If
    End If
    ts = Year(Now) & "-" & Right("0" & Month(Now), 2) & "-" & Right("0" & Day(Now), 2) & " " & Right("0" & Hour(Now), 2) & ":" & Right("0" & Minute(Now), 2) & ":" & Right("0" & Second(Now), 2)
    Set logFile = fso.OpenTextFile(logPath, 8, True, 0)
    logFile.WriteLine "[" & ts & "] " & msg
    logFile.Close
    On Error GoTo 0
End Sub

Dim isConfigure, isCenter, isDiagnose, protocolUrl, baseDir
Dim scriptPath, command, batchId, expectedCount, targetDest, forceFlag

isConfigure = False
isCenter = False
isDiagnose = False
protocolUrl = ""
baseDir = fso.GetParentFolderName(WScript.ScriptFullName)

If WScript.Arguments.Count > 0 Then
    protocolUrl = CStr(WScript.Arguments(0))
    isConfigure = InStr(1, LCase(protocolUrl), "configure", vbTextCompare) > 0
    isCenter = InStr(1, LCase(protocolUrl), "center", vbTextCompare) > 0
    isDiagnose = InStr(1, LCase(protocolUrl), "diagnose", vbTextCompare) > 0
End If

If isConfigure Then
    scriptPath = ResolveScript("work_package_center.ps1")
    command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34) & " -InitialTab Settings"
ElseIf isCenter Then
    scriptPath = ResolveScript("work_package_center.ps1")
    command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34) & " -InitialTab Tasks"
ElseIf isDiagnose Then
    scriptPath = ResolveScript("make_work_package.ps1")
    command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34) & " -Diagnose"
Else
    scriptPath = ResolveScript("make_work_package.ps1")
    command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34)
    batchId = QueryValue(protocolUrl, "batch")
    expectedCount = QueryValue(protocolUrl, "expected")
    targetDest = QueryValue(protocolUrl, "target")
    forceFlag = QueryValue(protocolUrl, "force")
    If batchId <> "" Then
        command = command & " -BatchId " & Chr(34) & batchId & Chr(34)
    End If
    If expectedCount <> "" And IsNumeric(expectedCount) Then
        command = command & " -ExpectedImageCount " & CStr(CLng(expectedCount))
    End If
    If targetDest <> "" Then
        command = command & " -TargetDestination " & Chr(34) & targetDest & Chr(34)
    End If
    If forceFlag = "1" Or LCase(forceFlag) = "true" Then
        command = command & " -AllowDuplicate"
    End If
End If

LogLaunch baseDir, "url=" & protocolUrl & " | cmd=" & command
shell.Run command, 0, False
